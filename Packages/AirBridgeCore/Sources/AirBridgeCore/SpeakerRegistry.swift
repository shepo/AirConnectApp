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
            if let handle, live[handle] != nil {
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
            return Speaker(
                id: device.udn,
                name: Self.displayName(device.name),
                ip: entry?.ip,
                enabled: device.enabled,
                status: entry.map { $0.grouped ? .grouped : .active } ?? .notSeen,
                udn: device.udn
            )
        }
        for (_, entry) in unmatched {
            result.append(Speaker(
                id: entry.mac.map { "mac:\($0)" } ?? "name:\(entry.name)",
                name: entry.name,
                ip: entry.ip,
                enabled: true, // airupnp only adds speakers that are switched on
                status: entry.grouped ? .grouped : .active,
                udn: nil
            ))
        }
        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public var activeCount: Int {
        live.values.filter { !$0.grouped }.count
    }

    /// airupnp names its AirPlay copy "<name>+" by default.
    static func displayName(_ name: String) -> String {
        name.hasSuffix("+") ? String(name.dropLast()) : name
    }

    static func matches(_ device: ConfiguredDevice, _ entry: Live) -> Bool {
        if let mac = device.mac, let logged = entry.mac {
            return MACAddress.logForms(of: mac).contains(logged.uppercased())
        }
        return displayName(device.name) == entry.name || device.name == entry.name
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
