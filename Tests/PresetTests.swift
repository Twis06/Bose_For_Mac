import Foundation

private final class FakeBMAP: BMAPClient {
    var ready = true
    var values = [0, 0, 0]
    var writes: [[UInt8]] = []
    var failWrite: Int?
    var corruptNextRead = false
    var disconnectAtFailure = false
    func request(_ block: UInt8, _ function: UInt8, op: UInt8, payload: [UInt8], completion: @escaping (Result<Frame, Error>) -> Void) {
        precondition(block == 1 && function == 7)
        if op == 2 {
            writes.append(payload)
            if writes.count == failWrite {
                if disconnectAtFailure { ready = false }
                completion(.failure(BoseError.message("Injected write failure"))); return
            }
            values[Int(payload[1])] = Int(Int8(bitPattern: payload[0]))
        }
        var reading = values
        if op == 1 && corruptNextRead { reading[2] = 9; corruptNextRead = false }
        let bytes: [UInt8] = reading.enumerated().flatMap { [246, 10, UInt8(bitPattern: Int8($0.element)), UInt8($0.offset)] }
        completion(.success(Frame(block: 1, function: 7, op: 3, payload: bytes)))
    }
}

enum PresetTests {
    static func run() {
        let original = (0..<3).map { EQBand(id: UInt8($0), minimum: -10, maximum: 10, value: 0) }
        let preset = EQPreset.all.first(where: { $0.id == "recordingnow-v1" })!
        let target = original.enumerated().map { i, band -> EQBand in var b = band; b.value = preset.values[i]; return b }
        precondition(preset.supports(original))
        precondition(!preset.supports(Array(original.prefix(2))))
        precondition(!preset.matches(original))
        precondition(preset.matches(target))
        precondition(Set(EQPreset.all.map(\.id)).count == EQPreset.all.count)
        for p in EQPreset.all { precondition(p.values.count == 3 && p.values.allSatisfy { (-10...10).contains($0) }) }

        let client = FakeBMAP()
        let transaction = EQTransaction(client: client)
        var passed = false
        transaction.apply(target, original: original) { if case .success = $0 { passed = true } }
        precondition(passed && client.values == [-6, 4, 2])
        precondition(client.writes == [[250, 0], [4, 1], [2, 2]], "Must serialize signed band writes")

        let failure = FakeBMAP(); failure.failWrite = 2
        var failureText = ""
        EQTransactionRetainer.withClient(failure, target: target, original: original) { if case .failure(let e) = $0 { failureText = e.localizedDescription } }
        precondition(failure.values == [0, 0, 0] && failureText.contains("restored"), "Partial writes must restore the previous EQ")

        let mismatch = FakeBMAP(); mismatch.corruptNextRead = true
        failureText = ""
        EQTransactionRetainer.withClient(mismatch, target: target, original: original) { if case .failure(let e) = $0 { failureText = e.localizedDescription } }
        precondition(mismatch.values == [0, 0, 0] && failureText.contains("restored"), "A mismatched readback must not claim success")

        let disconnected = FakeBMAP(); disconnected.failWrite = 2; disconnected.disconnectAtFailure = true
        failureText = ""
        EQTransactionRetainer.withClient(disconnected, target: target, original: original) { if case .failure(let e) = $0 { failureText = e.localizedDescription } }
        precondition(failureText.contains("some values may have changed"), "Disconnected rollback must report partial state")
        print("Passed: preset ranges/matching, serial writes, complete readback, rollback on write failure/mismatch, honest disconnect errors.")
    }
}

private enum EQTransactionRetainer {
    static func withClient(_ client: FakeBMAP, target: [EQBand], original: [EQBand], completion: @escaping (Result<Void, Error>) -> Void) {
        let transaction = EQTransaction(client: client)
        transaction.apply(target, original: original, completion: completion)
        withExtendedLifetime(transaction) {}
    }
}
