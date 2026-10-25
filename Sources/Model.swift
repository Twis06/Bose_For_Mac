import Foundation
import IOBluetooth

final class BoseModel {
    let bluetooth = BoseBluetooth()
    var changed: (() -> Void)?
    var name = "Bose Bar"
    var status = "Connect your QC Ultra in Bluetooth Settings."
    var battery: Int?
    var mode: UInt8?
    var modes: [ListeningMode] = []
    var bands: [EQBand] = []
    var audio: [UInt8]?
    var busy = false
    let isDemo: Bool
    var ready: Bool { isDemo || bluetooth.ready }
    private var eqTransaction: EQTransaction?
    private var interruptedEQ = false
    private(set) var previousEQ: [EQBand]?
    var currentPreset: EQPreset? { EQPreset.all.first(where: { $0.matches(bands) }) }
    private var refreshing = false
    private var generation = 0
    private var supportsAudio: Bool?
    private var lastRefresh = Date.distantPast
    private var timer: Timer?
    var log: ((String) -> Void)?

    init(demo: Bool = false) {
        isDemo = demo
        if demo {
            name = "Bose QC Ultra"
            status = "Connected"
            battery = 80
            mode = 0
            modes = [.init(id: 0, name: "Quiet"), .init(id: 1, name: "Aware"), .init(id: 2, name: "Immersion"), .init(id: 3, name: "Focus")]
            bands = [EQBand(id: 0, minimum: -10, maximum: 10, value: -6), EQBand(id: 1, minimum: -10, maximum: 10, value: 4), EQBand(id: 2, minimum: -10, maximum: 10, value: 2)]
        }
        bluetooth.onFrame = { [weak self] in self?.receive($0) }
        bluetooth.onConnection = { [weak self] ready, error in
            guard let self else { return }
            self.busy = false
            self.refreshing = false
            self.status = ready ? "Connected" : (self.interruptedEQ
                ? "EQ was interrupted. Reconnect and check all three bands; some values may have changed."
                : (error ?? "Disconnected"))
            if ready { self.refresh(discover: true) }
            else { self.clearValues() }
            self.changed?()
            self.log?(self.status)
        }
    }

    func start() {
        guard !isDemo else { changed?(); return }
        connect()
        timer = Timer.scheduledTimer(withTimeInterval: 90, repeats: true) { [weak self] _ in
            guard let self, !self.busy, !self.refreshing else { return }
            if self.ready { self.bluetooth.request(2, 2) }
            else if UserDefaults.standard.string(forKey: "preferredDevice") != nil || BoseBluetooth.devices().contains(where: { $0.isConnected() }) { self.connect() }
        }
        timer?.tolerance = 15
    }

    func connect(_ selected: IOBluetoothDevice? = nil) {
        guard !isDemo else { return }
        eqTransaction?.cancel(); eqTransaction = nil
        generation += 1
        bluetooth.disconnect()
        clearValues()
        let devices = BoseBluetooth.devices()
        let preferred = UserDefaults.standard.string(forKey: "preferredDevice")
        guard let device = selected ?? devices.first(where: { $0.addressString == preferred }) ?? devices.first(where: { $0.isConnected() }) ?? (devices.count == 1 ? devices.first : nil) else {
            status = "Connect your QC Ultra in Bluetooth Settings."
            busy = false
            changed?()
            return
        }
        interruptedEQ = false
        UserDefaults.standard.set(device.addressString, forKey: "preferredDevice")
        name = device.name ?? "Bose QC Ultra"
        status = "Connecting…"
        busy = true
        changed?()
        bluetooth.connect(device)
    }

    func sleep() {
        guard !isDemo else { return }
        eqTransaction?.cancel(); eqTransaction = nil
        generation += 1
        bluetooth.disconnect()
        clearValues()
        busy = false
        status = "Sleeping"
        changed?()
    }

    private func clearValues() { battery = nil; mode = nil; modes = []; bands = []; audio = nil; supportsAudio = nil; previousEQ = nil }

    func refresh(discover: Bool = false) {
        guard !isDemo, ready, !refreshing, !busy else { return }
        guard discover || Date().timeIntervalSince(lastRefresh) > 5 else { return }
        refreshing = true
        lastRefresh = Date()
        let epoch = generation
        var reads: [(UInt8, UInt8, UInt8)] = [(2, 2, 1), (31, 3, 1), (1, 7, 1)]
        if supportsAudio != false { reads.append((31, 10, 1)) }
        if discover { reads.append((31, 1, 5)) }
        var remaining = reads.count
        for (b, f, op) in reads {
            bluetooth.request(b, f, op: op) { [weak self] result in
                guard let self, self.generation == epoch else { return }
                if b == 31 && f == 10 {
                    if case .failure = result { self.supportsAudio = false }
                    else { self.supportsAudio = self.audio != nil }
                }
                remaining -= 1
                if remaining == 0 { self.refreshing = false; self.changed?() }
            }
        }
    }

    private func receive(_ frame: Frame) {
        log?("[\(frame.block).\(frame.function)] op \(frame.op): \(frame.payload.map { String(format: "%02x", $0) }.joined(separator: " "))")
        guard frame.op == 3 else { return }
        let p = frame.payload
        switch (frame.block, frame.function) {
        case (2, 2): if let value = p.first, value <= 100 { battery = Int(value) }
        case (31, 3): mode = p.first
        case (31, 6):
            if let value = ListeningMode.parse(p) {
                modes.removeAll { $0.id == value.id }
                modes.append(value)
                modes.sort { $0.id < $1.id }
            }
        case (1, 7): bands = EQBand.parse(p)
        case (31, 10):
            // Exact known format only. Never write a guessed layout on older firmware.
            if p.count == 5, p[0] <= 10, p[2] <= 2 { audio = p }
        default: break
        }
        changed?()
    }

    func setMode(_ id: UInt8) {
        guard modes.contains(where: { $0.id == id }) else { return }
        if isDemo { mode = id; changed?(); return }
        write(31, 3, op: 5, payload: [id, 0], verify: { $0.payload.first == id })
    }

    func setBand(_ id: UInt8, value: Int) {
        guard let band = bands.first(where: { $0.id == id }), (band.minimum...band.maximum).contains(value) else { return }
        if isDemo { if let i = bands.firstIndex(where: { $0.id == id }) { bands[i].value = value }; changed?(); return }
        write(1, 7, payload: [UInt8(bitPattern: Int8(value)), id], verify: {
            EQBand.parse($0.payload).first(where: { $0.id == id })?.value == value
        })
    }

    func applyPreset(_ preset: EQPreset) {
        guard ready, !busy, preset.supports(bands) else { return }
        let target = (0..<3).compactMap { id -> EQBand? in
            guard var band = bands.first(where: { $0.id == UInt8(id) }) else { return nil }
            band.value = preset.values[id]
            return band
        }
        applyEQ(target, undo: false)
    }

    func undoPreset() {
        guard let previousEQ, ready, !busy else { return }
        applyEQ(previousEQ, undo: true)
    }

    private func applyEQ(_ target: [EQBand], undo: Bool) {
        let original = bands
        if isDemo {
            bands = target; previousEQ = undo ? nil : original; changed?(); return
        }
        interruptedEQ = false
        busy = true
        status = undo ? "Restoring EQ…" : "Applying preset…"
        changed?()
        let epoch = generation
        let transaction = EQTransaction(client: bluetooth)
        eqTransaction = transaction
        transaction.apply(target, original: original) { [weak self] result in
            guard let self, self.generation == epoch else { return }
            self.eqTransaction = nil
            switch result {
            case .success:
                self.previousEQ = undo ? nil : original
                self.finish(nil)
            case .failure(let error):
                self.interruptedEQ = !self.bluetooth.ready
                self.finish(error.localizedDescription)
            }
        }
    }

    func setAudio(index: Int, value: UInt8) {
        guard var payload = audio, payload.indices.contains(index) else { return }
        if index == 0 { guard value <= 10 else { return } }
        else if index == 2 { guard value <= 2 else { return } }
        else { guard value <= 1 else { return } }
        payload[index] = value
        write(31, 10, payload: payload, verify: { $0.payload == payload })
    }

    private func write(_ block: UInt8, _ function: UInt8, op: UInt8 = 2, payload: [UInt8], verify: @escaping (Frame) -> Bool) {
        guard ready, !busy else { return }
        busy = true
        status = "Applying…"
        changed?()
        let epoch = generation
        bluetooth.request(block, function, op: op, payload: payload) { [weak self] result in
            guard let self, self.generation == epoch else { return }
            switch result {
            case .failure(let error): self.finish(error.localizedDescription)
            case .success:
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                    guard let self, self.generation == epoch else { return }
                    self.bluetooth.request(block, function) { result in
                        switch result {
                        case .success(let frame):
                            self.finish(verify(frame) ? nil : "Headphones didn’t apply that setting. Try again.")
                        case .failure(let error): self.finish(error.localizedDescription)
                        }
                    }
                }
            }
        }
    }

    private func finish(_ error: String?) {
        busy = false
        status = error ?? "Connected"
        changed?()
    }
}
