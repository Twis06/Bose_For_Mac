import Foundation

@main struct ProtocolTests {
    static func main() {
        PresetTests.run()
        let battery = Frame(block: 2, function: 2, op: 3, payload: [100, 0, 0, 0])
        let mode = Frame(block: 31, function: 3, op: 3, payload: [1])
        for split in 0...battery.bytes.count {
            var decoder = FrameDecoder()
            let first = decoder.append(Array(battery.bytes.prefix(split)))
            let second = decoder.append(Array(battery.bytes.dropFirst(split)) + mode.bytes)
            precondition(first + second == [battery, mode], "Fragmented / coalesced frame handling failed")
        }
        var decoder = FrameDecoder()
        precondition(decoder.append([2, 2, 3, 4, 100]).isEmpty)
        precondition(decoder.append([0, 0, 0]) == [battery])
        let eq = EQBand.parse([246, 10, 253, 0, 246, 10, 0, 1, 246, 10, 7, 2])
        precondition(eq.map(\.value) == [-3, 0, 7])
        precondition(eq.first?.minimum == -10)
        precondition(EQBand.parse([246, 10, 11, 0]).isEmpty)
        precondition(EQBand.parse([246, 10, 0]).isEmpty)
        var payload = [UInt8](repeating: 0, count: 48)
        payload[0] = 0; payload[2] = 1; payload[4] = 1
        precondition(ListeningMode.parse(payload)?.name == "Quiet")
        payload[4] = 0
        precondition(ListeningMode.parse(payload)?.name == "Quiet", "Factory presets can have configured=0")
        payload[3] = 1
        precondition(ListeningMode.parse(payload) == nil)
        precondition(ListeningMode.parse([0, 0, 1]) == nil)
        payload[4] = 1; payload[0] = 4
        payload.replaceSubrange(6..<12, with: Array("Travel".utf8))
        precondition(ListeningMode.parse(payload)?.name == "Travel")
        precondition(Frame(block: 1, function: 7, op: 2, payload: [253, 0]).bytes == [1, 7, 2, 2, 253, 0])
        print("Passed: every frame split, batched frames, incomplete frame buffering, signed EQ, malformed payload rejection, actual mode names and write encoding.")
    }
}
