# AirBridge

A macOS menu bar app that makes Sonos (and other UPnP) speakers show up as AirPlay
speakers. It wraps **airupnp** from Philippe's [AirConnect](https://github.com/philippe44/AirConnect),
so you don't need Terminal, Gatekeeper workarounds or manual restarts.

- Menu bar only: the icon shows running / stopped / error
- Runs the bundled airupnp and restarts it if it crashes (backoff 1s → 60s), when
  the network changes and when the Mac wakes
- Lists the speakers it finds, with an on/off switch each. New speakers start
  **off**, so speakers that already do AirPlay 2 don't appear twice
- Settings: start at login, latency (`-l`), log level (`-d`)
- Log viewer with Copy All
- Notifies you if airupnp crashes, or finds no speakers within 30 seconds
- Makes no network connections of its own (no update checks, no analytics); all
  network traffic is airupnp's

Apple Silicon, macOS 14 or later.

## Credit and licences

**AirConnect** is by Philippe (philippe44), philippe_44@outlook.com:
<https://github.com/philippe44/AirConnect>. AirBridge bundles its
`airupnp-macos-arm64-static` binary from release **1.12.4**, unmodified. Version,
commit and checksums are in [`Vendor/AirConnect/VERSION.md`](Vendor/AirConnect/VERSION.md).

- AirConnect's own code is MIT licensed: [`Vendor/AirConnect/LICENSE`](Vendor/AirConnect/LICENSE).
- The airupnp binary also contains third-party code (libupnp, ALAC, FLAC, FAAC,
  OpenSSL, mDNS). Its licence terms (`airupnp -t`) are the **GNU GPL v3 or later**:
  [`Vendor/AirConnect/COPYING`](Vendor/AirConnect/COPYING). The corresponding source
  is upstream at tag [`1.12.4`](https://github.com/philippe44/AirConnect/tree/1.12.4).
- AirBridge runs airupnp as a separate program and doesn't link to it. AirBridge's
  own code is MIT licensed ([`LICENSE`](LICENSE)).

**Anyone redistributing AirBridge must** ship both licence files (the app carries
them in `Contents/Resources/AirConnect/`), keep the credit above, and point to the
AirConnect source. AirBridge isn't affiliated with or endorsed by AirConnect,
Sonos or Apple.

## Build

You need Xcode 16 or later. The Xcode project is generated from `project.yml` with
[XcodeGen](https://github.com/yonaskolb/XcodeGen) and committed, so you can open it
directly.

```bash
open AirBridge.xcodeproj
```

1. Add your team so Xcode can sign. Create `Config/Signing.local.xcconfig` (ignored
   by git):
   ```
   DEVELOPMENT_TEAM = ABCDE12345
   ```
2. Pick the **AirBridge** scheme, then Run (⌘R). The icon appears in the menu bar.

Tests (log parser, config editing, launch arguments, backoff):

```bash
xcodebuild test -project AirBridge.xcodeproj -scheme AirBridge -destination 'platform=macOS,arch=arm64'
# or just the logic:
swift test --package-path Packages/AirBridgeCore
```

If you change `project.yml`, run `brew install xcodegen && xcodegen generate` and
commit the project. CI fails on `main` if the two don't match.

### First run

- macOS asks to **find devices on your local network**: allow it, or no speakers are
  found. You can change it later in System Settings › Privacy & Security › Local Network.
- With the macOS firewall on, it asks once whether `airupnp` may accept incoming
  connections: allow it. AirPlay connects to it.
- AirBridge runs a quick scan, and every speaker it finds starts switched **off**.
  Open the menu and switch on the ones that can't do AirPlay themselves. Each one
  then appears in AirPlay with a `+` (e.g. "Kitchen+").

### Which Sonos speakers to switch on

Only the ones without AirPlay 2: Play:1, Play:3, Play:5 (1st gen), Connect,
Connect:Amp and Playbar. One, Five, Play:5 (2nd gen), Era, Move, Roam, Beam, Arc, Ray,
Playbase, Amp (2018 on), Port and IKEA Symfonisk already do AirPlay 2; bridging them
just lists them twice.

## How it works

```
AirBridge.app/Contents/
  MacOS/AirBridge               SwiftUI menu bar app (LSUIElement)
  Helpers/airupnp               AirConnect 1.12.4, re-signed with the app
  Resources/AirConnect/         LICENSE.txt, COPYING.txt, VERSION.md
~/Library/Application Support/AirBridge/
  config.xml                    airupnp's config: one <device> per speaker, <enabled> 0/1
  airupnp.pid                   lets AirBridge clean up after itself if it crashed
```

AirBridge starts:

```
airupnp -Z -k -x config.xml -I -p airupnp.pid -l 1000:2000 -d all=info
```

| Flag | Why |
|---|---|
| `-Z` | No interactive console. Without it airupnp spins on a missing terminal. (`-z`, which also daemonises, doesn't exist on macOS.) |
| `-k` | Exit straight away on SIGTERM, so Stop and Quit are clean |
| `-x config.xml -I` | Use AirBridge's config, and save newly found speakers into it |
| `-p` | PID file |
| `-l rtp:http` | Latency in ms; 1000:2000 is AirConnect's advice for Sonos |
| `-d all=<level>` | Log level. `main` and `upnp` stay at `info` or above, since the speaker list is read from them |

Speaker switches edit `<enabled>` in `config.xml` while airupnp is stopped, then
start it again. **Rescan** runs `airupnp -Z -i scan.xml` (find speakers, save, exit)
and adds any new ones to the config.

The code is small: `AirBridge/` holds the app (`ProcessManager`, `NetworkMonitor`,
`Notifier`, `LoginItem`, views), and `Packages/AirBridgeCore` holds the tested logic
(`LogParser`, `SpeakerRegistry`, `DeviceConfig`, `LaunchArguments`, `Backoff`).

## Signing and notarising

### Entitlements

**None.** AirBridge is not sandboxed and needs no hardened-runtime exceptions:

- **No App Sandbox.** A sandboxed app's child processes inherit the sandbox, which
  breaks airupnp's UPnP multicast discovery and its writes outside the container.
  AirBridge is distributed with Developer ID, not through the Mac App Store, so the
  sandbox isn't required.
- **Hardened runtime on both the app and `airupnp`.** Notarisation requires it.
  airupnp is a static build (links only `libSystem`; OpenSSL is built in) and uses no
  JIT, unsigned memory or third-party libraries. So it needs no
  `com.apple.security.cs.*` exceptions, and it runs under the hardened runtime as is
  (CI checks this on every push).
- **Local Network.** This is a privacy permission, not an entitlement.
  `Info.plist` carries `NSLocalNetworkUsageDescription` and `NSBonjourServices`
  (`_raop._tcp`, `_airplay._tcp`). The permission is granted to AirBridge, and its
  child airupnp is covered by it.

### How the helper is signed

The **Embed and sign airupnp** build phase (`scripts/embed-airupnp.sh`) runs before
Xcode signs the app:

1. Copies `Vendor/AirConnect/airupnp-macos-arm64-static` to `Contents/Helpers/airupnp`
   with mode `755`, and clears extended attributes (including any quarantine flag).
2. Signs it with the app's identity:
   `codesign --force --options runtime --timestamp --sign "Developer ID Application: …"`
   (Debug builds skip the timestamp).
3. Xcode then signs the app, which seals the helper inside the app's signature.

The helper lives in `Contents/Helpers`, not `Contents/Resources`. codesign treats
anything in `Resources` as data, and notarisation then rejects an unsigned Mach-O.

### One-time setup

1. In the Apple Developer site, create a **Developer ID Application** certificate and
   install it in your login keychain (Xcode › Settings › Accounts › Manage
   Certificates › + › Developer ID Application).
2. Create an app-specific password at <https://account.apple.com> (Sign-In and
   Security › App-Specific Passwords).
3. Store notarisation credentials in the keychain:
   ```bash
   xcrun notarytool store-credentials AirBridge \
     --apple-id you@example.com --team-id ABCDE12345
   ```

### Release

```bash
TEAM_ID=ABCDE12345 scripts/release.sh
```

`scripts/release.sh` does the following:

1. `xcodebuild` Release with `CODE_SIGN_IDENTITY="Developer ID Application"` and the
   hardened runtime.
2. Checks with `codesign --verify --deep --strict` that both the app and
   `Contents/Helpers/airupnp` carry the Developer ID authority, the `runtime` flag and
   a secure timestamp.
3. `xcrun notarytool submit … --keychain-profile AirBridge --wait`
4. `xcrun stapler staple AirBridge.app`, then
   `spctl --assess --type execute -vv AirBridge.app` (should say *Notarized Developer ID*).
5. Zips it to `build/release/AirBridge-<version>.zip` and prints its SHA-256.

To publish, bump `CFBundleShortVersionString` / `CFBundleVersion` in `project.yml`,
run `xcodegen generate`, commit, tag `v<version>`, then create a GitHub release with
the zip. In the release notes, say which AirConnect version is bundled and link its
source.

If notarisation fails, `xcrun notarytool log <submission-id> --keychain-profile AirBridge`
lists each problem.

## Updating AirConnect

```bash
scripts/update-airconnect.sh 1.12.5
```

This downloads the release, replaces the binary and `LICENSE`, and prints the
checksums and commit for `VERSION.md`. Then:

1. Check `airupnp -h` for changed flags.
2. Run the tests.
3. Try it with your speakers.

Use the `-static` build: the plain `airupnp-macos-arm64` aborts on current macOS
("loading libcrypto in an unsafe way").

## Troubleshooting

- **No speakers:**
  - Check System Settings › Privacy & Security › Local Network › AirBridge is on.
  - Check the Mac and the speakers are on the same network.
  - Then press Rescan.
- **A speaker appears twice in AirPlay:** switch it off in AirBridge; it already
  supports AirPlay 2.
- **Sound drops out:** raise both latency values in Settings, e.g. 1500 / 3000.
- **Grouped Sonos:** only the group's main speaker is bridged. AirBridge shows the
  others as "In a Sonos group".
- **Anything else:** open the log from the menu, then Copy All, and include it in an issue.
