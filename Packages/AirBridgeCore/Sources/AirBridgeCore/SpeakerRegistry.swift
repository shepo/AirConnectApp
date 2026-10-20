import Foundation

public struct Speaker: Identifiable, Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        /// Bridged: shows in AirPlay with a "+".
        case active
        /// Part of a Sonos group; only the group's master is bridged.
        case grouped
        /// Known from the config but not seen by this run (switched off, asleep or gone).
        case notSeen
    }

    /// The config's udn, or `mac:`/`name:` for a speaker not in the config yet.
    public var id: String
    public var name: String
    public var ip: String?
    public var enabled: Bool
    public var status: Status
    /// Present when the speaker is in config.xml, so it can be switched.
    public var udn: String?
    /// A short ID, set when another speaker has the same name (e.g. a stereo pair).
    public var note: String? = nil
    /// A Sonos with no room name: a surround or sub bonded to a home cinema
    /// speaker. It can't play on its own, so the app doesn't offer it.
    public var isSurround = false
}

/// Combines what config.xml says (which speakers exist, which are on) with what
/// the running airupnp has logged (which are bridged right now, and their IPs).
public struct SpeakerRegistry: Equatable, Sendable {
    struct Live: Equatable, Sendable {
        var name: String
        var mac: String?
        var ip: String?
        var grouped = false
    }

    public var configured: [ConfiguredDevice] = []
    var live: [String: Live] = [:] // by handle

    public init(configured: [ConfiguredDevice] = []) {
        self.configured = configured
    }

    /// Forget everything the last run logged.
    public mutating func resetLive() {
        live = [:]
    }

    public mutating func apply(_ event: LogEvent) {
        switch event {
        case let .speakerAdded(handle, name, mac):
            var entry = live[handle] ?? Live(name: name)
            entry.name = name
            entry.mac = mac
            entry.grouped = false
            live[handle] = entry
        case let .speakerRemoved(handle):
            live[handle] = nil
        case let .speakerGrouped(handle, name):
            if let handle {
                // A handle we haven't added is a slave airupnp skipped; it may share
                // its name with the master (a stereo pair), so don't look it up by name.
                live[handle]?.grouped = true
            } else if let key = live.first(where: { $0.value.name == name })?.key {
                live[key]?.grouped = true
            }
        case let .speakerUngrouped(handle, _):
            live[handle]?.grouped = false
        case let .speakerAddress(handle, ip):
            live[handle]?.ip = ip
        case .started, .bound, .ipChanged:
            break
        }
    }

    public var speakers: [Speaker] {
        var unmatched = live
        var result: [Speaker] = configured.map { device in
            let key = unmatched.first(where: { Self.matches(device, $0.value) })?.key
            let entry = key.flatMap { unmatched.removeValue(forKey: $0) }
            let tidy = Self.tidy(device.name)
            return Speaker(
                id: device.udn,
                name: tidy.name,
                ip: entry?.ip ?? tidy.ip,
                enabled: device.enabled,
                status: entry.map { $0.grouped ? .grouped : .active } ?? .notSeen,
                udn: device.udn,
                isSurround: tidy.isSurround
            )
        }
        for (_, entry) in unmatched {
            let tidy = Self.tidy(entry.name)
            result.append(Speaker(
                id: entry.mac.map { "mac:\($0)" } ?? "name:\(entry.name)",
                name: tidy.name,
                ip: entry.ip ?? tidy.ip,
                enabled: true, // airupnp only adds speakers that are switched on
                status: entry.grouped ? .grouped : .active,
                udn: nil,
                isSurround: tidy.isSurround
            ))
        }
        let counts = Dictionary(grouping: result.filter { !$0.isSurround }, by: \.name).mapValues(\.count)
        for index in result.indices where !result[index].isSurround && counts[result[index].name, default: 0] > 1 {
            result[index].note = Self.shortID(result[index].udn ?? result[index].id)
        }
        return result.sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }

    public var activeCount: Int {
        live.values.filter { !$0.grouped }.count
    }

    /// airupnp names its AirPlay copy "<name>+" by default.
    static func displayName(_ name: String) -> String {
        name.hasSuffix("+") ? String(name.dropLast()) : name
    }

    /// A Sonos without a room name (a home cinema surround or sub) reports itself
    /// as "192.168.50.138 - SYMFONISK Bookshelf - RINCON_347E5CF1497601400";
    /// that becomes "SYMFONISK Bookshelf", its IP, and `isSurround`.
    static func tidy(_ raw: String) -> (name: String, ip: String?, isSurround: Bool) {
        let name = displayName(raw)
        if let m = LogParser.match(#"^(\d{1,3}(?:\.\d{1,3}){3}) - (.+) - RINCON_[0-9A-Fa-f]+$"#, name) {
            return (m[1], m[0], true)
        }
        return (name, nil, false)
    }

    /// "uuid:RINCON_347E5CF1497601400" -> "…601400".
    static func shortID(_ id: String) -> String {
        let tail = id.split(separator: "_").last.map(String.init) ?? id
        return "…" + String(tail.suffix(6))
    }

    static func matches(_ device: ConfiguredDevice, _ entry: Live) -> Bool {
        if let mac = device.mac, let logged = entry.mac {
            return MACAddress.logForms(of: mac).contains(logged.uppercased())
        }
        return displayName(device.name) == entry.name || device.name == entry.name
            || tidy(device.name).name == tidy(entry.name).name
    }
}

enum MACAddress {
    /// airupnp logs a MAC with `%hX%X` over the first two and last four bytes:
    /// unpadded, and in memory order, so on Apple Silicon each chunk's bytes come
    /// out reversed. Returns every form a given `aa:bb:cc:dd:ee:ff` can take.
    static func logForms(of mac: String) -> Set<String> {
        let bytes = mac.split(whereSeparator: { $0 == ":" || $0 == "-" })
            .compactMap { UInt8($0, radix: 16) }
        guard bytes.count == 6 else {
            return [mac.uppercased().filter(\.isHexDigit)]
        }
        func value(_ slice: ArraySlice<UInt8>, littleEndian: Bool) -> UInt64 {
            let ordered = littleEndian ? Array(slice.reversed()) : Array(slice)
            return ordered.reduce(0) { $0 << 8 | UInt64($1) }
        }
        var forms: Set<String> = []
        for littleEndian in [false, true] {
            let head = String(value(bytes[0..<2], littleEndian: littleEndian), radix: 16, uppercase: true)
            let tail = String(value(bytes[2..<6], littleEndian: littleEndian), radix: 16, uppercase: true)
            forms.insert(head + tail)
        }
        forms.insert(bytes.map { String(format: "%02X", $0) }.joined())
        return forms
    }
}
