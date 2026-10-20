import Foundation

/// Restart delays after a crash: 1s, 2s, 4s … capped at 60s. A run that lasted
/// `healthyAfter` seconds counts as healthy and starts the sequence again.
public struct Backoff: Equatable, Sendable {
    public var base: TimeInterval = 1
    public var cap: TimeInterval = 60
    public var healthyAfter: TimeInterval = 60
    public private(set) var failures = 0

    public init() {}

    /// Records a crash after a run of `runDuration` seconds and returns how long
    /// to wait before starting again.
    public mutating func delayAfterCrash(runDuration: TimeInterval) -> TimeInterval {
        if runDuration >= healthyAfter { failures = 0 }
        let delay = min(cap, base * pow(2, Double(failures)))
        failures += 1
        return delay
    }

    public mutating func reset() {
        failures = 0
    }
}

/// Splits a byte stream into lines, holding back a partial last line.
public struct LineBuffer: Sendable {
    private var pending = Data()

    public init() {}

    public mutating func append(_ data: Data) -> [String] {
        pending.append(data)
        var lines: [String] = []
        while let newline = pending.firstIndex(of: 0x0A) {
            let lineData = pending[pending.startIndex..<newline]
            pending.removeSubrange(pending.startIndex...newline)
            lines.append(Self.decode(lineData))
        }
        return lines
    }

    /// Whatever is left once the stream has ended.
    public mutating func flush() -> [String] {
        defer { pending = Data() }
        return pending.isEmpty ? [] : [Self.decode(pending)]
    }

    private static func decode(_ data: Data) -> String {
        var line = String(decoding: data, as: UTF8.self)
        if line.hasSuffix("\r") { line.removeLast() }
        return line
    }
}
