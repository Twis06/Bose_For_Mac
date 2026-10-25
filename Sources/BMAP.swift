import Foundation

// BMAP framing and payload layouts ported from aaronsb/bosectl (MIT).
struct Frame: Equatable {
    let block: UInt8
    let function: UInt8
    let op: UInt8
    let payload: [UInt8]
    var bytes: [UInt8] { [block, function, op & 15, UInt8(payload.count)] + payload }
}

struct FrameDecoder {
    private var buffer: [UInt8] = []
    mutating func append(_ bytes: [UInt8]) -> [Frame] {
        buffer += bytes
        var frames: [Frame] = []
        while buffer.count >= 4 {
            let size = 4 + Int(buffer[3])
            guard buffer.count >= size else { break }
            let op = buffer[2] & 15
            if op <= 7 {
                frames.append(Frame(block: buffer[0], function: buffer[1], op: op,
                                    payload: Array(buffer[4..<size])))
            }
            buffer.removeFirst(size)
        }
        return frames
    }
}

struct EQBand: Equatable {
    let id: UInt8
    let minimum: Int
    let maximum: Int
    var value: Int
    var name: String { [0: "Bass", 1: "Mid", 2: "Treble"][id] ?? "Band \(id)" }
    static func parse(_ p: [UInt8]) -> [EQBand] {
        guard !p.isEmpty, p.count % 4 == 0 else { return [] }
        return stride(from: 0, to: p.count, by: 4).compactMap { i in
            let low = Int(Int8(bitPattern: p[i])), high = Int(Int8(bitPattern: p[i+1]))
            let value = Int(Int8(bitPattern: p[i+2]))
            guard low < high, low >= -20, high <= 20, (low...high).contains(value) else { return nil }
            return EQBand(id: p[i+3], minimum: low, maximum: high, value: value)
        }
    }
}

struct ListeningMode: Equatable {
    let id: UInt8
    let name: String
    static func parse(_ p: [UInt8]) -> ListeningMode? {
        guard p.count >= 38, p[3] == 0 || p[4] != 0 else { return nil }
        let name = String(bytes: p[6..<38].prefix(while: { $0 != 0 }), encoding: .utf8) ?? ""
        let presets: [UInt8: String] = [1: "Quiet", 2: "Aware", 34: "Immersion", 36: "Cinema"]
        let resolved = name.isEmpty ? (presets[p[2]] ?? "Mode \(p[0])") : name
        return ListeningMode(id: p[0], name: resolved)
    }
}

enum BoseError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
