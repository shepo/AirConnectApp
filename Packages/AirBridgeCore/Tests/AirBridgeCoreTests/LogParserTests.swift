import XCTest
@testable import AirBridgeCore

/// Lines are real airupnp v1.12.4 output where we have it (the first three are
/// from a Mac Studio run) and otherwise built from the binary's own format
/// strings: `"%s %s:%d [%p]: adding renderer (%s) with mac %hX%X"` and friends.
final class LogParserTests: XCTestCase {
    func testStartLine() {
        XCTAssertEqual(
            LogParser.parse("[14:02:43.173] main:1407 Starting airupnp version: v1.12.4 (Sep 26 2026 @ 20:05:30)"),
            .started(version: "v1.12.4")
        )
    }

    func testLinesWithNothingToReport() {
        XCTAssertNil(LogParser.parse("[14:02:43.174] main:1414 no config file, using defaults"))
        XCTAssertNil(LogParser.parse("WARNING: /Users/me/airconnect/airupnp-macos-arm64 is loading libcrypto in an unsafe way"))
        XCTAssertNil(LogParser.parse(""))
        XCTAssertNil(LogParser.parse("[14:03:10.002] MRThread:900 [0x600003a1c000]: uPNP playing"))
    }

    func testBinding() {
        XCTAssertEqual(
            LogParser.parse("[14:02:43.174] Start:1112 Binding to iface 192.168.50.77:0 [en0]"),
            .bound(ip: "192.168.50.77", interface: "en0")
        )
    }

    func testSpeakerAdded() {
        XCTAssertEqual(
            LogParser.parse("[14:02:51.020] AddMRDevice:1170 [0x600003a1c000]: adding renderer (Kitchen) with mac 5CAAFD123456"),
            .speakerAdded(handle: "0x600003a1c000", name: "Kitchen", mac: "5CAAFD123456")
        )
    }

    func testSpeakerAddedNameWithSpacesAndBrackets() {
        XCTAssertEqual(
            LogParser.parse("[14:02:51.020] AddMRDevice:1170 [0x600003a1c0f0]: adding renderer (Living Room (Beam)) with mac e5aafd12"),
            .speakerAdded(handle: "0x600003a1c0f0", name: "Living Room (Beam)", mac: "E5AAFD12")
        )
    }

    func testSpeakerRemoved() {
        XCTAssertEqual(
            LogParser.parse("[15:10:02.500] UpdateThread:640 [0x600003a1c000]: removing unresponsive player (Kitchen)"),
            .speakerRemoved(handle: "0x600003a1c000")
        )
        XCTAssertEqual(
            LogParser.parse("[15:10:02.501] MasterHandler:700 [0x600003a1c000]: device has been removed"),
            .speakerRemoved(handle: "0x600003a1c000")
        )
    }

    func testSonosGrouping() {
        XCTAssertEqual(
            LogParser.parse("[14:02:52.100] AddMRDevice:1150 [0x600003a1d000] skipping Sonos slave Bathroom"),
            .speakerGrouped(handle: "0x600003a1d000", name: "Bathroom")
        )
        XCTAssertEqual(
            LogParser.parse("[14:05:00.000] UpdateThread:600 [0x600003a1d000]: Sonos Bathroom is now slave"),
            .speakerGrouped(handle: "0x600003a1d000", name: "Bathroom")
        )
        XCTAssertEqual(
            LogParser.parse("[14:06:00.000] UpdateThread:610 [0x600003a1d000]: Sonos Bathroom is now master"),
            .speakerUngrouped(handle: "0x600003a1d000", name: "Bathroom")
        )
    }

    func testAddressOnAPlayerLine() {
        XCTAssertEqual(
            LogParser.parse("[14:02:51.010] ProcessQueue:300 [0x600003a1c000]: location http://192.168.50.21:1400/xml/device_description.xml"),
            .speakerAddress(handle: "0x600003a1c000", ip: "192.168.50.21")
        )
    }

    func testIPChange() {
        XCTAssertEqual(
            LogParser.parse("[16:00:00.000] UpdateThread:500 IP change detected 192.168.50.80"),
            .ipChanged("192.168.50.80")
        )
    }

    func testLineWithoutTimestampPrefix() {
        XCTAssertEqual(
            LogParser.parse("[0x600003a1c000]: adding renderer (Office) with mac 1234"),
            .speakerAdded(handle: "0x600003a1c000", name: "Office", mac: "1234")
        )
    }

    func testHandleIsCaseInsensitive() {
        XCTAssertEqual(
            LogParser.parse("[14:02:51.020] f:1 [0x6000ABC]: device has been removed"),
            .speakerRemoved(handle: "0x6000abc")
        )
    }
}
