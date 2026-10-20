import XCTest
@testable import AirBridgeCore

final class SpeakerRegistryTests: XCTestCase {
    let kitchen = ConfiguredDevice(udn: "uuid:K", name: "Kitchen+", mac: "5c:aa:fd:01:02:03", enabled: true)
    let lounge = ConfiguredDevice(udn: "uuid:L", name: "Lounge+", mac: "5c:aa:fd:0a:0b:0c", enabled: false)

    func feed(_ registry: inout SpeakerRegistry, _ lines: [String]) {
        for line in lines {
            if let event = LogParser.parse(line) { registry.apply(event) }
        }
    }

    func testConfiguredSpeakersWithNothingLogged() {
        let registry = SpeakerRegistry(configured: [lounge, kitchen])
        let speakers = registry.speakers
        XCTAssertEqual(speakers.map(\.name), ["Kitchen", "Lounge"])
        XCTAssertEqual(speakers.map(\.status), [.notSeen, .notSeen])
        XCTAssertEqual(speakers.map(\.enabled), [true, false])
        XCTAssertEqual(registry.activeCount, 0)
    }

    func testLoggedSpeakerMatchesConfigByMAC() {
        var registry = SpeakerRegistry(configured: [kitchen, lounge])
        feed(&registry, [
            "[14:02:51.010] P:1 [0x600001]: location http://192.168.50.21:1400/xml/device_description.xml",
            "[14:02:51.020] A:2 [0x600001]: adding renderer (Kitchen) with mac 5CAAFD010203",
            "[14:02:51.030] P:1 [0x600001]: location http://192.168.50.21:1400/xml/device_description.xml",
        ])
        let k = registry.speakers.first { $0.udn == "uuid:K" }
        XCTAssertEqual(k?.status, .active)
        XCTAssertEqual(k?.ip, "192.168.50.21")
        XCTAssertEqual(registry.speakers.count, 2)
        XCTAssertEqual(registry.activeCount, 1)
    }

    func testMACInLittleEndianChunks() {
        // 5c:aa:fd:01:02:03 read as uint16 + uint32 on a little-endian Mac.
        var registry = SpeakerRegistry(configured: [kitchen])
        feed(&registry, ["[1] A:2 [0x600001]: adding renderer (Some Other Name) with mac AA5C30201FD"])
        XCTAssertEqual(registry.speakers.map(\.status), [.active])
        XCTAssertEqual(registry.speakers.count, 1)
    }

    func testMACFormsAreUnpadded() {
        let forms = MACAddress.logForms(of: "00:0e:58:01:02:03")
        XCTAssertTrue(forms.contains("E58010203"))     // big-endian chunks: 0x000E, 0x58010203
        XCTAssertTrue(forms.contains("E003020158"))    // little-endian chunks: 0x0E00, 0x03020158
        XCTAssertTrue(forms.contains("000E58010203"))  // plain, padded
    }

    func testFallsBackToNameWithoutMAC() {
        let noMac = ConfiguredDevice(udn: "uuid:O", name: "Office+", mac: nil, enabled: true)
        var registry = SpeakerRegistry(configured: [noMac])
        feed(&registry, ["[1] A:2 [0x600002]: adding renderer (Office) with mac 1234"])
        XCTAssertEqual(registry.speakers.map(\.status), [.active])
    }

    func testUnknownLoggedSpeakerIsListed() {
        var registry = SpeakerRegistry(configured: [kitchen])
        feed(&registry, ["[1] A:2 [0x600003]: adding renderer (Garden) with mac 5CAAFD999999"])
        let garden = registry.speakers.first { $0.name == "Garden" }
        XCTAssertEqual(garden?.status, .active)
        XCTAssertNil(garden?.udn)
        XCTAssertEqual(garden?.id, "mac:5CAAFD999999")
    }

    func testRemovalAndGrouping() {
        var registry = SpeakerRegistry(configured: [kitchen])
        feed(&registry, [
            "[1] A:2 [0x600001]: adding renderer (Kitchen) with mac 5CAAFD010203",
            "[2] U:3 [0x600001]: Sonos Kitchen is now slave",
        ])
        XCTAssertEqual(registry.speakers.map(\.status), [.grouped])
        XCTAssertEqual(registry.activeCount, 0)

        feed(&registry, ["[3] U:3 [0x600001]: Sonos Kitchen is now master"])
        XCTAssertEqual(registry.speakers.map(\.status), [.active])

        feed(&registry, ["[4] U:4 [0x600001]: removing unresponsive player (Kitchen)"])
        XCTAssertEqual(registry.speakers.map(\.status), [.notSeen])
    }

    func testResetLive() {
        var registry = SpeakerRegistry(configured: [kitchen])
        feed(&registry, ["[1] A:2 [0x600001]: adding renderer (Kitchen) with mac 5CAAFD010203"])
        registry.resetLive()
        XCTAssertEqual(registry.speakers.map(\.status), [.notSeen])
    }
}
