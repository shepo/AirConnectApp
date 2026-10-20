import AirBridgeCore
import Darwin
import Foundation
import Observation

/// Runs the bundled airupnp, keeps it running, and turns its log into a speaker list.
@MainActor
@Observable
final class ProcessManager {
    enum State: Equatable {
        case stopped
        case starting
        case running
        case scanning
        /// Crashed; starting again at the given time.
        case restarting(at: Date, exitCode: Int32)
        case failed(String)

        var isActive: Bool {
            switch self {
            case .stopped, .failed: false
            default: true
            }
        }
    }

    private(set) var state: State = .stopped
    private(set) var registry = SpeakerRegistry()
    private(set) var logLines: [String] = []
    private(set) var version: String?

    var settings: BridgeSettings {
        didSet {
            guard settings != oldValue else { return }
            SettingsStore.save(settings)
            if settings.newSpeakersEnabled != oldValue.newSpeakersEnabled {
                editConfig { $0.newSpeakersEnabled = self.settings.newSpeakersEnabled }
            } else if state.isActive {
                restart(reason: "Settings changed")
            }
        }
    }

    var speakers: [Speaker] { registry.speakers }

    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var startedAt = Date()
    @ObservationIgnored private var backoff = Backoff()
    @ObservationIgnored private var restartTask: Task<Void, Never>?
    @ObservationIgnored private var noSpeakerCheck: Task<Void, Never>?
    @ObservationIgnored private var userStopped = true
    @ObservationIgnored private let notifier: Notifier

    private static let maxLogLines = 5000
    private static let noSpeakerGrace: Duration = .seconds(30)

    init(notifier: Notifier) {
        self.notifier = notifier
        settings = SettingsStore.load()
        loadConfig()
    }

    // MARK: Paths

    /// `Contents/Helpers/airupnp`, put there and signed by scripts/embed-airupnp.sh.
    private var helperURL: URL? {
        let url = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/airupnp")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    private var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("AirBridge", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    var configURL: URL { supportDirectory.appendingPathComponent("config.xml") }
    private var pidURL: URL { supportDirectory.appendingPathComponent("airupnp.pid") }

    // MARK: Control

    func start() {
        userStopped = false
        restartTask?.cancel()
        launch()
    }

    func stop() {
        userStopped = true
        restartTask?.cancel()
        noSpeakerCheck?.cancel()
        terminateChild()
        backoff.reset()
        state = .stopped
    }

    func restart(reason: String) {
        append("— AirBridge: restarting (\(reason)) —")
        let wasStopped = userStopped
        terminateChild()
        backoff.reset()
        if !wasStopped { start() }
    }

    /// Stops airupnp and waits for it, for app quit.
    func shutdown() {
        userStopped = true
        restartTask?.cancel()
        noSpeakerCheck?.cancel()
        terminateChild(wait: 2)
        try? FileManager.default.removeItem(at: pidURL)
    }

    func setEnabled(_ enabled: Bool, for speaker: Speaker) {
        guard let udn = speaker.udn else { return }
        editConfig { $0.setEnabled(enabled, udn: udn) }
    }

    /// Runs `airupnp -i` to list every speaker on the network, adds new ones to
    /// the config (on or off per settings), then carries on.
    func rescan() async {
        guard let helperURL else { return fail("The bundled airupnp is missing. Reinstall AirBridge.") }
        let wasRunning = !userStopped
        restartTask?.cancel()
        noSpeakerCheck?.cancel()
        terminateChild(wait: 2)
        state = .scanning
        append("— AirBridge: scanning for speakers —")

        let scanURL = supportDirectory.appendingPathComponent("scan.xml")
        try? FileManager.default.removeItem(at: scanURL)
        let status = await runOnce(helperURL, LaunchArguments.discover(outputPath: scanURL.path), timeout: 30)

        if let data = try? Data(contentsOf: scanURL), let scan = try? DeviceConfig(data: data) {
            var config = currentConfig()
            let added = config.merge(discovered: scan)
            save(config)
            append("— AirBridge: scan found \(scan.devices.count) speaker(s), \(added.count) new —")
        } else {
            append("— AirBridge: scan didn't produce a speaker list (exit \(status)) —")
        }
        try? FileManager.default.removeItem(at: scanURL)

        state = .stopped
        if wasRunning { start() }
    }

    func clearLog() {
        logLines.removeAll()
    }

    // MARK: Config

    private func currentConfig() -> DeviceConfig {
        if let data = try? Data(contentsOf: configURL), let config = try? DeviceConfig(data: data) {
            return config
        }
        return DeviceConfig.empty(newSpeakersEnabled: settings.newSpeakersEnabled)
    }

    private func save(_ config: DeviceConfig) {
        do {
            try config.data.write(to: configURL, options: .atomic)
        } catch {
            append("— AirBridge: couldn't save config: \(error.localizedDescription) —")
        }
        registry.configured = config.devices
    }

    private func loadConfig() {
        registry.configured = currentConfig().devices
    }

    /// airupnp rewrites the config as it scans (`-I`), so edit it only while it's stopped.
    private func editConfig(_ change: (inout DeviceConfig) -> Void) {
        let wasRunning = !userStopped
        restartTask?.cancel()
        terminateChild(wait: 2)
        var config = currentConfig()
        change(&config)
        save(config)
        if wasRunning { start() }
    }

    // MARK: Process

    private func launch() {
        guard let helperURL else { return fail("The bundled airupnp is missing. Reinstall AirBridge.") }
        killLeftover()

        if !FileManager.default.fileExists(atPath: configURL.path) {
            save(DeviceConfig.empty(newSpeakersEnabled: settings.newSpeakersEnabled))
            Task { await self.rescan() }
            return
        }
        loadConfig()

        generation += 1
        let thisGeneration = generation
        registry.resetLive()
        state = .starting

        let process = Process()
        process.executableURL = helperURL
        process.arguments = LaunchArguments.run(settings: settings, configPath: configURL.path, pidPath: pidURL.path)
        process.currentDirectoryURL = supportDirectory
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let reader = LineReader()
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            let lines = data.isEmpty ? reader.flush() : reader.append(data)
            if data.isEmpty { handle.readabilityHandler = nil }
            guard !lines.isEmpty else { return }
            Task { @MainActor in self?.receive(lines, generation: thisGeneration) }
        }
        process.terminationHandler = { [weak self] process in
            let code = process.terminationStatus
            let reason = process.terminationReason
            Task { @MainActor in self?.terminated(code: code, reason: reason, generation: thisGeneration) }
        }

        append("— AirBridge: starting airupnp \(process.arguments!.joined(separator: " ")) —")
        do {
            try process.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            return fail("Couldn't start airupnp: \(error.localizedDescription)")
        }
        self.process = process
        startedAt = Date()
        state = .running
        scheduleNoSpeakerCheck(generation: thisGeneration)
    }

    private func receive(_ lines: [String], generation: Int) {
        for line in lines {
            append(line)
            guard generation == self.generation, let event = LogParser.parse(line) else { continue }
            if case let .started(version) = event { self.version = version }
            registry.apply(event)
        }
    }

    private func terminated(code: Int32, reason: Process.TerminationReason, generation: Int) {
        guard generation == self.generation else { return }
        process = nil
        noSpeakerCheck?.cancel()
        registry.resetLive()
        let how = reason == .uncaughtSignal ? "signal \(code)" : "exit code \(code)"

        if userStopped {
            append("— AirBridge: airupnp stopped (\(how)) —")
            state = .stopped
            return
        }

        let ran = Date().timeIntervalSince(startedAt)
        let delay = backoff.delayAfterCrash(runDuration: ran)
        append("— AirBridge: airupnp ended unexpectedly (\(how)) after \(Int(ran))s; restarting in \(Int(delay))s —")
        state = .restarting(at: Date().addingTimeInterval(delay), exitCode: code)

        if backoff.failures == 1 {
            notifier.post(title: "AirBridge restarted the bridge",
                          body: "airupnp stopped unexpectedly (\(how)). AirBridge is starting it again.")
        } else if backoff.failures == 5 {
            notifier.post(title: "AirBridge keeps crashing",
                          body: "airupnp has stopped 5 times in a row. AirBridge will keep trying every minute. Open the log for details.")
        }

        restartTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.launch()
        }
    }

    private func terminateChild(wait: TimeInterval = 0) {
        generation += 1 // the old process's termination is expected; ignore it
        noSpeakerCheck?.cancel()
        guard let process else { return }
        self.process = nil
        registry.resetLive()
        guard process.isRunning else { return }
        process.terminate() // SIGTERM; -k makes airupnp exit at once
        let pid = process.processIdentifier
        let deadline = Date().addingTimeInterval(max(wait, 0.5))
        while process.isRunning && Date() < deadline {
            usleep(20_000)
        }
        if process.isRunning {
            kill(pid, SIGKILL)
        }
    }

    /// If AirBridge itself crashed, its airupnp may still be running and holding
    /// the ports. Kill it only if the PID file points at our own helper.
    private func killLeftover() {
        guard let helperURL,
              let text = try? String(contentsOf: pidURL, encoding: .utf8),
              let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)),
              pid > 0, kill(pid, 0) == 0
        else { return }
        var buffer = [CChar](repeating: 0, count: 4096) // PROC_PIDPATHINFO_MAXSIZE
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return }
        let path = String(cString: buffer)
        guard URL(fileURLWithPath: path).resolvingSymlinksInPath().path == helperURL.resolvingSymlinksInPath().path else { return }
        append("— AirBridge: stopping an airupnp left over from before (pid \(pid)) —")
        kill(pid, SIGTERM)
        usleep(500_000)
        if kill(pid, 0) == 0 { kill(pid, SIGKILL) }
    }

    private func runOnce(_ url: URL, _ arguments: [String], timeout: TimeInterval) async -> Int32 {
        let process = Process()
        process.executableURL = url
        process.arguments = arguments
        process.currentDirectoryURL = supportDirectory
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let reader = LineReader()
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            let lines = data.isEmpty ? reader.flush() : reader.append(data)
            if data.isEmpty { handle.readabilityHandler = nil }
            guard !lines.isEmpty else { return }
            Task { @MainActor in lines.forEach { self?.append($0) } }
        }
        return await withCheckedContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                pipe.fileHandleForReading.readabilityHandler = nil
                process.terminationHandler = nil
                continuation.resume(returning: -1)
                return
            }
            Task {
                try? await Task.sleep(for: .seconds(timeout))
                if process.isRunning { process.terminate() }
            }
        }
    }

    private func scheduleNoSpeakerCheck(generation: Int) {
        noSpeakerCheck?.cancel()
        noSpeakerCheck = Task { [weak self] in
            try? await Task.sleep(for: Self.noSpeakerGrace)
            guard !Task.isCancelled, let self, generation == self.generation, self.state == .running else { return }
            guard self.registry.activeCount == 0 else { return }
            let configured = self.registry.configured
            if !configured.isEmpty && configured.allSatisfy({ !$0.enabled }) {
                return // every speaker is switched off on purpose
            }
            self.notifier.post(
                title: "No speakers found",
                body: "AirBridge hasn't found any speakers in 30 seconds. Check this Mac is on the same network, and that AirBridge is allowed under System Settings › Privacy & Security › Local Network."
            )
        }
    }

    private func fail(_ message: String) {
        append("— AirBridge: \(message) —")
        state = .failed(message)
    }

    private func append(_ line: String) {
        logLines.append(line)
        if logLines.count > Self.maxLogLines {
            logLines.removeFirst(logLines.count - Self.maxLogLines)
        }
    }
}

/// LineBuffer behind a lock, for the pipe's background callbacks.
private final class LineReader: @unchecked Sendable {
    private var buffer = LineBuffer()
    private let lock = NSLock()

    func append(_ data: Data) -> [String] {
        lock.lock(); defer { lock.unlock() }
        return buffer.append(data)
    }

    func flush() -> [String] {
        lock.lock(); defer { lock.unlock() }
        return buffer.flush()
    }
}

enum SettingsStore {
    private static let key = "bridgeSettings"

    static func load() -> BridgeSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(BridgeSettings.self, from: data)
        else { return BridgeSettings() }
        return settings
    }

    static func save(_ settings: BridgeSettings) {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
