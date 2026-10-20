import AirBridgeCore
import AppKit
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            ScrollView { SpeakerList().padding() }
                .tabItem { Label("Speakers", systemImage: "hifispeaker.2") }
            AboutView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 460, height: 420)
        .onAppear { NSApp.activate() }
    }
}

private struct GeneralSettings: View {
    @Environment(ProcessManager.self) private var manager
    @State private var startAtLogin = LoginItem.isEnabled
    @State private var loginError: String?

    var body: some View {
        @Bindable var manager = manager
        Form {
            Section {
                Toggle("Start AirBridge at login", isOn: $startAtLogin)
                    .onChange(of: startAtLogin) { _, enabled in
                        do {
                            try LoginItem.set(enabled)
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                            startAtLogin = LoginItem.isEnabled
                        }
                    }
                if LoginItem.needsApproval {
                    Button("Approve in System Settings…") { LoginItem.openSystemSettings() }
                }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }

            Section {
                Stepper(value: $manager.settings.rtpLatency, in: BridgeSettings.latencyRange, step: 250) {
                    LabeledContent("AirPlay buffer", value: "\(manager.settings.rtpLatency) ms")
                }
                Stepper(value: $manager.settings.httpLatency, in: BridgeSettings.latencyRange, step: 250) {
                    LabeledContent("Speaker buffer", value: "\(manager.settings.httpLatency) ms")
                }
                Button("Reset to Sonos defaults (1000 / 2000 ms)") {
                    manager.settings.rtpLatency = 1000
                    manager.settings.httpLatency = 2000
                }
            } header: {
                Text("Latency")
            } footer: {
                Text("Passed to airupnp as -l. Raise both if the sound drops out. Changing them restarts the bridge.")
            }

            Section {
                Picker("Log level", selection: $manager.settings.logLevel) {
                    ForEach(LogLevel.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Switch new speakers on automatically", isOn: $manager.settings.newSpeakersEnabled)
            } footer: {
                Text("Leave new speakers off if most of yours already support AirPlay 2, so they don't appear twice.")
            }
        }
        .formStyle(.grouped)
        .onAppear { startAtLogin = LoginItem.isEnabled }
    }
}

private struct AboutView: View {
    @Environment(ProcessManager.self) private var manager

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AirBridge \(appVersion)").font(.title2.bold())
            Text("Makes Sonos and other UPnP speakers appear as AirPlay speakers, using AirConnect's airupnp.")

            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    Text("AirConnect by Philippe (philippe44)").font(.headline)
                    Text("Bundled: airupnp \(manager.version ?? "1.12.4") (macOS arm64, static build), redistributed unmodified.")
                    Text("AirConnect's own code is MIT licensed. The airupnp binary includes third-party code and is distributed under the GNU GPL v3 or later. Its source is at the link below.")
                        .foregroundStyle(.secondary)
                    HStack {
                        Link("AirConnect source", destination: URL(string: "https://github.com/philippe44/AirConnect/tree/1.12.4")!)
                        Button("MIT licence") { openBundled("LICENSE.txt") }
                        Button("GPL v3") { openBundled("COPYING.txt") }
                    }
                    .controlSize(.small)
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text("AirBridge itself is MIT licensed and makes no network connections of its own: no update checks, no analytics.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
    }

    private func openBundled(_ name: String) {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("AirConnect/\(name)") else { return }
        NSWorkspace.shared.open(url)
    }
}
