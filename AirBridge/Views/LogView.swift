import AppKit
import Observation
import SwiftUI

struct LogView: View {
    @Environment(ProcessManager.self) private var manager
    @State private var follow = true
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(manager.logLines.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(line.hasPrefix("— AirBridge") ? Color.accentColor : .primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(index)
                        }
                    }
                    .textSelection(.enabled)
                    .padding(8)
                }
                .onChange(of: manager.logLines.count) { _, count in
                    if follow, count > 0 { proxy.scrollTo(count - 1, anchor: .bottom) }
                }
                .onAppear {
                    if !manager.logLines.isEmpty { proxy.scrollTo(manager.logLines.count - 1, anchor: .bottom) }
                }
            }
            Divider()
            HStack {
                Toggle("Follow", isOn: $follow)
                Spacer()
                Text("\(manager.logLines.count) lines").foregroundStyle(.secondary)
                Button("Clear") { manager.clearLog() }
                Button(copied ? "Copied" : "Copy All") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(manager.logLines.joined(separator: "\n"), forType: .string)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        copied = false
                    }
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            }
            .controlSize(.small)
            .padding(8)
        }
        .frame(minWidth: 560, minHeight: 320)
    }
}

/// Opens the log window. Done with AppKit so the window never opens by itself at
/// launch, which a SwiftUI `Window` scene can do in a menu bar app.
@MainActor
@Observable
final class WindowPresenter {
    @ObservationIgnored private let manager: ProcessManager
    @ObservationIgnored private var logWindow: NSWindow?

    init(manager: ProcessManager) {
        self.manager = manager
    }

    func showLog() {
        if logWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 700, height: 420),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "AirBridge Log"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: LogView().environment(manager))
            window.setFrameAutosaveName("AirBridgeLog")
            window.center()
            logWindow = window
        }
        NSApp.activate()
        logWindow?.makeKeyAndOrderFront(nil)
    }
}
