import Foundation

public enum LogLevel: String, CaseIterable, Codable, Sendable, Identifiable {
    case error, warn, info, debug, sdebug

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .error: "Errors only"
        case .warn: "Warnings"
        case .info: "Info"
        case .debug: "Debug"
        case .sdebug: "Verbose debug"
        }
    }

    var rank: Int { Self.allCases.firstIndex(of: self)! }
}

public struct BridgeSettings: Equatable, Codable, Sendable {
    /// RTP (AirPlay) buffer in ms; airupnp's README recommends 1000 for Sonos.
    public var rtpLatency: Int = 1000
    /// HTTP silence buffer in ms; 2000 for Sonos.
    public var httpLatency: Int = 2000
    public var logLevel: LogLevel = .info
    /// Whether a speaker airupnp hasn't seen before starts switched on.
    public var newSpeakersEnabled: Bool = false

    public init() {}

    public static let latencyRange = 0...5000
}

/// Builds airupnp's command line. Flags checked against `airupnp -h` for v1.12.4.
public enum LaunchArguments {
    /// - `-Z` no interactive console (without it airupnp spins on a missing TTY;
    ///   `-z`, which also daemonises, isn't available on macOS)
    /// - `-k` exit straight away on SIGTERM
    /// - `-x` / `-I` read the config and save it again whenever it scans
    /// - `-p` PID file, so a bridge left behind by a crash can be cleaned up
    /// - `-l rtp:http` latency
    /// - `-d all=<level>`; the speaker list needs `main` and `upnp` at info or more
    public static func run(settings: BridgeSettings, configPath: String, pidPath: String) -> [String] {
        var args = [
            "-Z", "-k",
            "-x", configPath, "-I",
            "-p", pidPath,
            "-l", "\(clamp(settings.rtpLatency)):\(clamp(settings.httpLatency))",
            "-d", "all=\(settings.logLevel.rawValue)",
        ]
        if settings.logLevel.rank < LogLevel.info.rank {
            args += ["-d", "main=info", "-d", "upnp=info"]
        }
        return args
    }

    /// One discovery pass: find speakers, write them to `outputPath`, exit.
    public static func discover(outputPath: String) -> [String] {
        ["-Z", "-i", outputPath]
    }

    private static func clamp(_ value: Int) -> Int {
        min(max(value, BridgeSettings.latencyRange.lowerBound), BridgeSettings.latencyRange.upperBound)
    }
}
