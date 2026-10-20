import AirBridgeCore
import AppKit
import SwiftUI

/// The panel under the menu bar icon.
struct MenuView: View {
    @Environment(ProcessManager.self) private var manager
    @Environment(WindowPresenter.self) private var windows

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider()
            SpeakerList(compact: true)
            Divider()
            controls
        }
        .padding(12)
        .frame(width: 300)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: manager.state.symbolName)
                .foregroundStyle(statusColor)
                .font(.title3)
            VStack(alignment: .leading, spacing: 1) {
                Text("AirBridge").font(.headline)
                Text(statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
        }
    }

    private var statusLine: String {
        guard manager.state == .running else { return manager.state.title }
        let count = manager.registry.activeCount
        return count == 1 ? "Running · 1 speaker on AirPlay" : "Running · \(count) speakers on AirPlay"
    }

    private var statusColor: Color {
        switch manager.state {
        case .running: .green
        case .starting, .scanning: .secondary
        case .stopped: .secondary
        case .restarting, .failed: .orange
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if manager.state.isActive {
                    Button("Stop") { manager.stop() }
                    Button("Restart") { manager.restart(reason: "Restart from menu") }
                } else {
                    Button("Start") { manager.start() }
                }
                Spacer()
                Button("Log") { windows.showLog() }
                SettingsLink { Text("Settings…") }
                    .simultaneousGesture(TapGesture().onEnded { NSApp.activate() })
            }
            HStack {
                Spacer()
                Button("Quit AirBridge") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .controlSize(.small)
    }
}

/// Speakers with an on/off switch each. Used in the menu and in Settings.
struct SpeakerList: View {
    @Environment(ProcessManager.self) private var manager
    var compact = false
    @State private var scanning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Speakers").font(compact ? .subheadline.weight(.semibold) : .headline)
                Spacer()
                Button(scanning ? "Scanning…" : "Rescan") {
                    scanning = true
                    Task {
                        await manager.rescan()
                        scanning = false
                    }
                }
                .disabled(scanning)
                .controlSize(.small)
            }

            let speakers = manager.speakers.filter { !$0.isSurround }
            let surrounds = manager.speakers.count - speakers.count
            if speakers.isEmpty {
                Text(manager.state == .scanning
                     ? "Looking for speakers on your network…"
                     : "No speakers yet. Press Rescan to look for them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(speakers) { speaker in
                    SpeakerRow(speaker: speaker)
                }
                if surrounds > 0 {
                    Text(surrounds == 1
                         ? "1 surround speaker hidden: it's part of a home cinema set and plays through its main speaker."
                         : "\(surrounds) surround speakers hidden: they're part of a home cinema set and play through its main speaker.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text("Switch on only speakers that can't do AirPlay themselves, or they'll appear twice.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SpeakerRow: View {
    @Environment(ProcessManager.self) private var manager
    let speaker: Speaker

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(speaker.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Toggle(speaker.name, isOn: Binding(
                get: { speaker.enabled },
                set: { manager.setEnabled($0, for: speaker) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
        .disabled(speaker.udn == nil)
        .help(speaker.udn == nil ? "Press Rescan to add this speaker to the list it can be switched from." : "")
    }

    private var detail: String {
        let state: String
        switch speaker.status {
        case .active: state = "On AirPlay"
        case .grouped: state = "In a Sonos group"
        case .notSeen: state = speaker.enabled ? "Not seen yet" : "Off"
        }
        return [state, speaker.ip, speaker.note].compactMap { $0 }.joined(separator: " · ")
    }
}
