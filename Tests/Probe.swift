import Foundation
import IOBluetooth

@main struct Probe {
    static func main() {
        let transport = BoseBluetooth()
        let devices = BoseBluetooth.devices()
        print("Ultra devices: \(devices.map { "\($0.name ?? "Bose") \($0.addressString ?? "?") (connected: \($0.isConnected()))" })")
        let address: String? = {
            guard let i = CommandLine.arguments.firstIndex(of: "--device"), CommandLine.arguments.count > i + 1 else { return nil }
            return CommandLine.arguments[i + 1].lowercased().replacingOccurrences(of: ":", with: "-")
        }()
        guard let device = devices.first(where: { $0.addressString == address }) ?? devices.first(where: { $0.isConnected() }) ?? (devices.count == 1 ? devices.first : nil) else {
            print("Choose a paired headphone with --device AA:BB:CC:DD:EE:FF"); exit(2)
        }
        var currentMode: UInt8?
        var currentBass: EQBand?
        transport.onFrame = { f in
            if f.block == 31 && f.function == 3 && f.op == 3 { currentMode = f.payload.first }
            if f.block == 1 && f.function == 7 && f.op == 3 { currentBass = EQBand.parse(f.payload).first(where: { $0.id == 0 }) }
            print("[\(f.block).\(f.function)] op=\(f.op): \(f.payload.map { String(format: "%02x", $0) }.joined(separator: " "))") }
        transport.onConnection = { ready, error in
            guard ready else { print(error ?? "Disconnected"); exit(3) }
            print("Connected BMAP")
            let reads: [(UInt8, UInt8)] = [(2,2), (31,3), (1,7), (31,10)]
            for (block, function) in reads {
                transport.request(block, function) { result in print("Read \(block).\(function): \(result)") }
            }
            transport.request(31, 1, op: 5) { result in
                print("Modes: \(result)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    guard CommandLine.arguments.contains("--verify"), let mode = currentMode, let bass = currentBass else { transport.disconnect(); exit(0) }
                    // Reapply current values, then verify readback: no intentional state change.
                    transport.request(31, 3, op: 5, payload: [mode, 0]) { result in
                        guard case .success = result else { print("Mode write failed", result); exit(5) }
                        transport.request(31, 3) { result in
                            guard case .success(let f) = result, f.payload.first == mode else { print("Mode verification failed"); exit(6) }
                            print("PASS: current listening mode write/readback")
                            transport.request(1, 7, op: 2, payload: [UInt8(bitPattern: Int8(bass.value)), bass.id]) { result in
                                guard case .success = result else { print("EQ write failed", result); exit(7) }
                                transport.request(1, 7) { result in
                                    guard case .success(let f) = result, EQBand.parse(f.payload).first(where: { $0.id == bass.id })?.value == bass.value else { print("EQ verification failed"); exit(8) }
                                    print("PASS: current EQ write/readback; original settings retained")
                                    transport.disconnect(); exit(0)
                                }
                            }
                        }
                    }
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            print("After initialization: connected", device.isConnected(), "services", device.services?.count as Any)
            transport.connect(device)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) { print("Probe timeout"); exit(4) }
        RunLoop.main.run()
    }
}
