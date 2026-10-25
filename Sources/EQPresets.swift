import Foundation

struct EQPreset: Equatable {
    let id: String
    let name: String
    let values: [Int] // Bass, mid, treble — Bose's slider steps, not parametric filters.
    let detail: String
    let source: URL?
    var summary: String { values.map { $0 > 0 ? "+\($0)" : "\($0)" }.joined(separator: " / ") }
    func matches(_ bands: [EQBand]) -> Bool {
        (0..<3).allSatisfy { id in bands.first(where: { $0.id == UInt8(id) })?.value == values[id] }
    }
    func supports(_ bands: [EQBand]) -> Bool {
        (0..<3).allSatisfy { id in
            guard let band = bands.first(where: { $0.id == UInt8(id) }) else { return false }
            return (band.minimum...band.maximum).contains(values[id])
        }
    }
    static let all: [EQPreset] = [
        .init(id: "flat", name: "Flat", values: [0, 0, 0], detail: "Reset all three bands to zero.", source: nil),
        .init(id: "recordingnow-v1", name: "Vocal clarity", values: [-6, 4, 2], detail: "RecordingNow V1 · pop and vocal-focused listening.", source: URL(string: "https://recordingnow.com/blog/bose-quietcomfort-ultra-review/")),
        .init(id: "recordingnow-v2", name: "Fuller detail", values: [-4, 5, 3], detail: "RecordingNow V2 · a fuller alternative for rock and metal.", source: URL(string: "https://recordingnow.com/blog/bose-quietcomfort-ultra-review/")),
        .init(id: "toms-guide", name: "Everyday balance", values: [-2, 0, 3], detail: "Tom’s Guide · less bass emphasis, more treble presence.", source: URL(string: "https://www.tomsguide.com/audio/headphones/here-are-the-3-settings-you-should-change-for-every-pair-of-bose-headphones")),
        .init(id: "warm", name: "Warm & soft", values: [1, 0, -2], detail: "Bose Bar starting point · a little warmth, softer highs.", source: nil),
        .init(id: "speech", name: "Speech", values: [-3, 3, 0], detail: "Bose Bar starting point · foreground voices in podcasts.", source: nil)
    ]
}

// Transport abstraction keeps preset transactions testable without touching hardware.
protocol BMAPClient: AnyObject {
    var ready: Bool { get }
    func request(_ block: UInt8, _ function: UInt8, op: UInt8, payload: [UInt8],
                 completion: @escaping (Result<Frame, Error>) -> Void)
}

/// Serial multi-band write followed by complete readback. If a write/readback
/// fails, attempt to restore the snapshot and verify it; never claim atomicity.
final class EQTransaction {
    private let client: BMAPClient
    private var cancelled = false
    init(client: BMAPClient) { self.client = client }
    func cancel() { cancelled = true }
    func apply(_ target: [EQBand], original: [EQBand], completion: @escaping (Result<Void, Error>) -> Void) {
        write(target, at: 0) { [weak self] error in
            guard let self, !self.cancelled else { return }
            if let error { self.restore(original, after: error, completion: completion); return }
            self.verify(target) { error in
                guard !self.cancelled else { return }
                if let error { self.restore(original, after: error, completion: completion) }
                else { completion(.success(())) }
            }
        }
    }
    private func write(_ bands: [EQBand], at index: Int, completion: @escaping (Error?) -> Void) {
        guard !cancelled else { return }
        guard index < bands.count else { completion(nil); return }
        let band = bands[index]
        client.request(1, 7, op: 2, payload: [UInt8(bitPattern: Int8(band.value)), band.id]) { [weak self] result in
            guard let self, !self.cancelled else { return }
            switch result {
            case .failure(let error): completion(error)
            case .success: self.write(bands, at: index + 1, completion: completion)
            }
        }
    }
    private func verify(_ expected: [EQBand], completion: @escaping (Error?) -> Void) {
        client.request(1, 7, op: 1, payload: []) { [weak self] result in
            guard let self, !self.cancelled else { return }
            switch result {
            case .failure(let error): completion(error)
            case .success(let frame):
                let actual = EQBand.parse(frame.payload)
                let matches = expected.allSatisfy { band in actual.first(where: { $0.id == band.id })?.value == band.value }
                completion(matches ? nil : BoseError.message("The headphones did not confirm all three EQ values."))
            }
        }
    }
    private func restore(_ original: [EQBand], after cause: Error, completion: @escaping (Result<Void, Error>) -> Void) {
        guard client.ready else {
            completion(.failure(BoseError.message("EQ was interrupted. Reconnect and check all three bands; some values may have changed.")))
            return
        }
        write(original, at: 0) { [weak self] error in
            guard let self, !self.cancelled else { return }
            guard error == nil else {
                completion(.failure(BoseError.message("Couldn’t restore EQ. Refresh and check all three bands."))); return
            }
            self.verify(original) { error in
                guard !self.cancelled else { return }
                completion(.failure(BoseError.message(error == nil
                    ? "Preset wasn’t applied; your previous EQ was restored. \(cause.localizedDescription)"
                    : "Couldn’t verify restored EQ. Refresh and check all three bands.")))
            }
        }
    }
}
