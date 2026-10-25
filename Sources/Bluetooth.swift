import Foundation
import IOBluetooth

final class BoseBluetooth: NSObject, IOBluetoothRFCOMMChannelDelegate, BMAPClient {
    var onFrame: ((Frame) -> Void)?
    var onConnection: ((Bool, String?) -> Void)?
    private(set) var device: IOBluetoothDevice?
    private var channel: IOBluetoothRFCOMMChannel?
    private var decoder = FrameDecoder()
    private var deadline: Timer?
    private var connecting = false
    private var receiving = false
    private var openingChannel = false
    private(set) var ready = false
    private struct Request {
        let frame: Frame
        let completion: (Result<Frame, Error>) -> Void
    }
    private var queue: [Request] = []
    private var pending: Request?
    private let writer = DispatchQueue(label: "local.bosebar.write", qos: .userInitiated)
    private var epoch = 0

    static func devices() -> [IOBluetoothDevice] {
        let cached = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        var seen = Set<String>()
        // macOS can return duplicate, stale paired-device objects. Resolve their
        // addresses to live objects before checking connection state.
        let paired = cached.compactMap { entry -> IOBluetoothDevice? in
            guard let address = entry.addressString, seen.insert(address).inserted else { return nil }
            return IOBluetoothDevice(addressString: address)
        }
        return paired.filter {
            let uuid = IOBluetoothSDPUUID(uuid16: 0x1200)
            let pid = $0.getServiceRecord(for: uuid)?.getAttributeDataElement(0x0202)?.getNumberValue()?.intValue
            return [0x4066, 0x4082].contains(pid ?? 0) || ($0.name ?? "").localizedCaseInsensitiveContains("bose")
        }
            .sorted { a, b in
                if a.isConnected() != b.isConnected() { return a.isConnected() }
                return (a.name ?? "") < (b.name ?? "")
            }
    }

    func connect(_ target: IOBluetoothDevice) {
        disconnect()
        device = IOBluetoothDevice(addressString: target.addressString) ?? target
        connecting = true
        // Refresh SDP before opening BMAP, as in upstream's macOS transport.
        let status = device!.performSDPQuery(self)
        if status != kIOReturnSuccess { fail("Bluetooth service discovery failed. Reconnect your headphones."); return }
        armTimeout(1.5) { [weak self] in
            guard let self, self.connecting else { return }
            self.sdpQueryComplete(self.device, status: kIOReturnSuccess)
        }
    }

    @objc func sdpQueryComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        guard connecting, !openingChannel, device == self.device else { return }
        openingChannel = true
        guard status == kIOReturnSuccess else { fail("Couldn’t read headphone services. Reconnect and retry."); return }
        deadline?.invalidate()
        let result = device.openRFCOMMChannelAsync(&channel, withChannelID: 2, delegate: self)
        guard result == kIOReturnSuccess else { fail("Couldn’t open headphone controls (\(result)). Try reconnecting."); return }
        armTimeout(8) { [weak self] in self?.fail("Connection timed out. Close other Bose control apps and retry.") }
    }

    func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        guard connecting, rfcommChannel == channel else { return }
        deadline?.invalidate()
        guard error == kIOReturnSuccess else { fail("Headphone connection failed (\(error)). Retry after reconnecting."); return }
        connecting = false
        ready = true
        onConnection?(true, nil)
    }

    func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        guard rfcommChannel == channel, dataLength > 0, let dataPointer else { return }
        receiving = true
        defer { receiving = false }
        let frames = decoder.append(Array(UnsafeRawBufferPointer(start: dataPointer, count: dataLength)))
        for frame in frames {
            onFrame?(frame)
            if let request = pending,
               frame.block == request.frame.block, frame.function == request.frame.function,
               [3, 4, 6, 7].contains(frame.op) {
                pending = nil
                deadline?.invalidate()
                if frame.op == 4 {
                    request.completion(.failure(BoseError.message("Headphones declined this control (code \(frame.payload.first ?? 0)).")))
                } else { request.completion(.success(frame)) }
                // Do not let another frame in this callback fulfill the next request.
                DispatchQueue.main.async { [weak self] in self?.sendNext() }
            }
        }
    }

    func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        guard rfcommChannel == channel else { return }
        fail("Headphones disconnected. Reconnect, then choose Retry connection.")
    }

    func request(_ block: UInt8, _ function: UInt8, op: UInt8 = 1, payload: [UInt8] = [],
                 completion: @escaping (Result<Frame, Error>) -> Void = { _ in }) {
        guard ready else { completion(.failure(BoseError.message("Headphones aren’t connected."))); return }
        queue.append(Request(frame: Frame(block: block, function: function, op: op, payload: payload), completion: completion))
        sendNext()
    }

    private func sendNext() {
        guard !receiving, pending == nil, !queue.isEmpty, ready, let channel else { return }
        let request = queue.removeFirst()
        pending = request
        let packet = request.frame.bytes
        let writeEpoch = epoch
        writer.async { [weak self] in
            var bytes = packet
            let result = bytes.withUnsafeMutableBytes { channel.writeSync($0.baseAddress, length: UInt16($0.count)) }
            DispatchQueue.main.async {
                guard let self, self.epoch == writeEpoch else { return }
                if result != kIOReturnSuccess { self.fail("Bluetooth write failed. Reconnect and retry.") }
            }
        }
        armTimeout(3) { [weak self] in
            // A timed-out request invalidates the session: a late reply must never
            // acknowledge a later write to the same address.
            self?.fail("Headphones stopped responding. Choose Retry connection.")
        }
    }

    private func armTimeout(_ seconds: TimeInterval, _ action: @escaping () -> Void) {
        deadline?.invalidate()
        let timer = Timer(timeInterval: seconds, repeats: false) { _ in action() }
        RunLoop.main.add(timer, forMode: .common)
        deadline = timer
    }

    func disconnect() {
        epoch += 1
        ready = false
        connecting = false
        openingChannel = false
        deadline?.invalidate()
        deadline = nil
        let old = channel
        channel = nil
        old?.setDelegate(nil)
        old?.close()
        decoder = FrameDecoder()
        let requests = (pending.map { [$0] } ?? []) + queue
        pending = nil
        queue = []
        requests.forEach { $0.completion(.failure(BoseError.message("Connection closed."))) }
    }

    private func fail(_ message: String) {
        disconnect()
        onConnection?(false, message)
    }
}
