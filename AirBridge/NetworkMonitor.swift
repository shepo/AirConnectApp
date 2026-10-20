import AppKit
import Network

/// Calls `onChange` (debounced) when the network comes back or changes, and
/// when the Mac wakes, so airupnp can be restarted on the new network.
@MainActor
final class NetworkMonitor {
    private let monitor = NWPathMonitor()
    private var lastSignature: String?
    private var pending: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?
    private let onChange: @MainActor (String) -> Void

    init(onChange: @escaping @MainActor (String) -> Void) {
        self.onChange = onChange
    }

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            let signature = Self.signature(of: path)
            let usable = path.status == .satisfied
            Task { @MainActor in self?.pathChanged(signature: signature, usable: usable) }
        }
        monitor.start(queue: DispatchQueue(label: "AirBridge.NetworkMonitor"))

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.schedule("Mac woke from sleep", after: .seconds(5)) }
        }
    }

    func stop() {
        monitor.cancel()
        pending?.cancel()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }

    private func pathChanged(signature: String, usable: Bool) {
        defer { lastSignature = signature }
        // The first update just describes the network at launch.
        guard let lastSignature, lastSignature != signature, usable else { return }
        schedule("Network changed", after: .seconds(3))
    }

    /// Wi-Fi tends to report several changes while it reconnects; act once it settles.
    private func schedule(_ reason: String, after delay: Duration) {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.onChange(reason)
        }
    }

    private nonisolated static func signature(of path: NWPath) -> String {
        let interfaces = path.availableInterfaces.map(\.name).sorted().joined(separator: ",")
        return "\(path.status)|\(interfaces)"
    }
}
