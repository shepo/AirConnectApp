import AppKit
import SwiftUI

@main
struct AirBridgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environment(appDelegate.manager)
                .environment(appDelegate.windows)
        } label: {
            Image(systemName: appDelegate.manager.state.symbolName)
                .accessibilityLabel("AirBridge: \(appDelegate.manager.state.title)")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(appDelegate.manager)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let notifier = Notifier()
    lazy var manager = ProcessManager(notifier: notifier)
    lazy var windows = WindowPresenter(manager: manager)
    private var network: NetworkMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        notifier.requestPermission()

        network = NetworkMonitor { [weak self] reason in
            guard let manager = self?.manager, manager.state.isActive else { return }
            manager.restart(reason: reason)
        }
        network?.start()

        manager.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        network?.stop()
        manager.shutdown()
    }
}

extension ProcessManager.State {
    var symbolName: String {
        switch self {
        case .running: "airplayaudio"
        case .starting, .scanning: "arrow.triangle.2.circlepath"
        case .stopped: "speaker.slash"
        case .restarting, .failed: "exclamationmark.triangle"
        }
    }

    var title: String {
        switch self {
        case .running: "Running"
        case .starting: "Starting…"
        case .scanning: "Looking for speakers…"
        case .stopped: "Stopped"
        case let .restarting(at, _):
            "Crashed, restarting \(at.formatted(.relative(presentation: .numeric)))"
        case let .failed(message): message
        }
    }
}
