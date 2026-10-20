import Foundation

/// Something airupnp reported that AirBridge cares about.
///
/// airupnp writes lines like
/// `[14:02:43.174] Start:1112 Binding to iface 192.168.50.77:0 [en0]`, and per-player
/// lines carry the player's pointer as a handle:
/// `[14:02:51.020] AddMRDevice:1170 [0x600003a1c000]: adding renderer (Kitchen) with mac 5CAAFD123456`.
/// The function names and line numbers change between releases, so only the
/// message text is matched.
public enum LogEvent: Equatable, Sendable {
    case started(version: String)
    case bound(ip: String, interface: String)
    case speakerAdded(handle: String, name: String, mac: String)
    case speakerRemoved(handle: String)
    /// A Sonos that joined a group: only the group's master is bridged.
    case speakerGrouped(handle: String?, name: String)
    case speakerUngrouped(handle: String, name: String)
    /// Any other line about a player that mentions an IPv4 address.
    case speakerAddress(handle: String, ip: String)
    case ipChanged(String)
}

public enum LogParser {
    public static func parse(_ line: String) -> LogEvent? {
        let message = stripPrefix(line)
        let (handle, body) = splitHandle(message)

        if let handle {
            if let m = match(#"^adding renderer \((.*)\) with mac ([0-9A-Fa-f]+)\s*$"#, body) {
                return .speakerAdded(handle: handle, name: m[0], mac: m[1].uppercased())
            }
            if match(#"^removing unresponsive player"#, body) != nil
                || match(#"^device has been removed"#, body) != nil {
                return .speakerRemoved(handle: handle)
            }
            if let m = match(#"^skipping Sonos slave (.+?)\s*$"#, body) {
                return .speakerGrouped(handle: handle, name: m[0])
            }
            if let m = match(#"^Sonos (.+) is now slave\s*$"#, body) {
                return .speakerGrouped(handle: handle, name: m[0])
            }
            if let m = match(#"^Sonos (.+) is now master\s*$"#, body) {
                return .speakerUngrouped(handle: handle, name: m[0])
            }
            if let m = match(#"\b((?:25[0-5]|2[0-4]\d|1?\d?\d)(?:\.(?:25[0-5]|2[0-4]\d|1?\d?\d)){3})\b"#, body) {
                return .speakerAddress(handle: handle, ip: m[0])
            }
            return nil
        }

        if let m = match(#"Starting airupnp version: (\S+)"#, body) {
            return .started(version: m[0])
        }
        if let m = match(#"^Binding to iface ([0-9.]+):\d+ \[(.*)\]"#, body) {
            return .bound(ip: m[0], interface: m[1])
        }
        if let m = match(#"^IP change detected (.*?)\s*$"#, body) {
            return .ipChanged(m[0])
        }
        return nil
    }

    /// Drops `[time] function:line ` when present.
    static func stripPrefix(_ line: String) -> String {
        if let m = match(#"^\[[0-9:.]+\]\s+\S+:\d+\s+(.*)$"#, line) {
            return m[0]
        }
        return line.trimmingCharacters(in: .whitespaces)
    }

    /// Splits `[0x6000...]: rest` (or `[0x6000...] rest`) into handle and rest.
    static func splitHandle(_ message: String) -> (String?, String) {
        if let m = match(#"^\[(0x[0-9A-Fa-f]+)\]:?\s*(.*)$"#, message) {
            return (m[0].lowercased(), m[1])
        }
        return (nil, message)
    }

    private static var cache: [String: NSRegularExpression] = [:]
    private static let lock = NSLock()

    /// Capture groups of the first match, or nil.
    static func match(_ pattern: String, _ text: String) -> [String]? {
        lock.lock()
        let regex: NSRegularExpression
        if let cached = cache[pattern] {
            regex = cached
        } else {
            regex = try! NSRegularExpression(pattern: pattern)
            cache[pattern] = regex
        }
        lock.unlock()

        let range = NSRange(text.startIndex..., in: text)
        guard let result = regex.firstMatch(in: text, range: range) else { return nil }
        return (1..<max(result.numberOfRanges, 1)).map { i in
            guard let r = Range(result.range(at: i), in: text) else { return "" }
            return String(text[r])
        }
    }
}
