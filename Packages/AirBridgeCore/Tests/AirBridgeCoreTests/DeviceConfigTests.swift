import XCTest
@testable import AirBridgeCore

final class DeviceConfigTests: XCTestCase {
    /// The shape `airupnp -i config.xml` writes (trimmed).
    let sample = """
    <?xml version="1.0"?>
    <airupnp>
    <common>
    <enabled>0</enabled>
    <latency>1000:2000</latency>
    <codec>flac</codec>
    </common>
    <main_log>info</main_log>
    <device>
    <udn>uuid:RINCON_5CAAFD000001</udn>
    <name>Kitchen+</name>
    <mac>5c:aa:fd:00:00:01</mac>
    <enabled>1</enabled>
    </device>
    <device>
    <udn>uuid:RINCON_5CAAFD000002</udn>
    <name>Living Room+</name>
    <mac>5c:aa:fd:00:00:02</mac>
    <enabled>0</enabled>
    </device>
    <device>
    <udn>uuid:RINCON_5CAAFD000003</udn>
    <name>Office+</name>
    </device>
    </airupnp>
    """

    func config() throws -> DeviceConfig {
        try DeviceConfig(data: Data(sample.utf8))
    }

    func testReadsDevices() throws {
        let devices = try config().devices
        XCTAssertEqual(devices.map(\.name), ["Kitchen+", "Living Room+", "Office+"])
        XCTAssertEqual(devices.map(\.enabled), [true, false, false]) // Office inherits <common>
        XCTAssertEqual(devices[0].mac, "5c:aa:fd:00:00:01")
        XCTAssertNil(devices[2].mac)
    }

    func testCommonEnabled() throws {
        var config = try config()
        XCTAssertFalse(config.newSpeakersEnabled)
        config.newSpeakersEnabled = true
        XCTAssertTrue(try DeviceConfig(data: config.data).newSpeakersEnabled)
    }

    func testMissingCommonDefaultsToAirupnpsDefault() throws {
        let config = try DeviceConfig(data: Data("<airupnp></airupnp>".utf8))
        XCTAssertTrue(config.newSpeakersEnabled)
        XCTAssertEqual(config.devices, [])
    }

    func testSetEnabledRoundTripsAndKeepsOtherSettings() throws {
        var config = try config()
        XCTAssertTrue(config.setEnabled(true, udn: "uuid:RINCON_5CAAFD000002"))
        XCTAssertTrue(config.setEnabled(true, udn: "uuid:RINCON_5CAAFD000003"))
        XCTAssertFalse(config.setEnabled(true, udn: "uuid:nope"))

        let reread = try DeviceConfig(data: config.data)
        XCTAssertEqual(reread.devices.map(\.enabled), [true, true, true])
        let text = String(decoding: config.data, as: UTF8.self)
        XCTAssertTrue(text.contains("<codec>flac</codec>"))
        XCTAssertTrue(text.contains("<main_log>info</main_log>"))
    }

    func testCopiesAreIndependent() throws {
        let original = try config()
        var copy = original
        copy.setEnabled(false, udn: "uuid:RINCON_5CAAFD000001")
        XCTAssertTrue(original.devices[0].enabled)
        XCTAssertFalse(copy.devices[0].enabled)
    }

    func testMergeAddsOnlyNewSpeakersUsingTheDefault() throws {
        var config = try config()
        let scan = try DeviceConfig(data: Data("""
        <airupnp><common><enabled>1</enabled></common>
        <device><udn>uuid:RINCON_5CAAFD000001</udn><name>Kitchen+</name><enabled>1</enabled></device>
        <device><udn>uuid:RINCON_5CAAFD000009</udn><name>Garden+</name><mac>5c:aa:fd:00:00:09</mac><enabled>1</enabled></device>
        </airupnp>
        """.utf8))

        XCTAssertEqual(config.merge(discovered: scan), ["uuid:RINCON_5CAAFD000009"])
        let garden = config.devices.first { $0.name == "Garden+" }
        XCTAssertEqual(garden?.enabled, false) // new speakers start off
        XCTAssertEqual(garden?.mac, "5c:aa:fd:00:00:09")
        XCTAssertEqual(config.devices.count, 4)
        XCTAssertEqual(config.merge(discovered: scan), [])
    }

    func testEmptyConfig() throws {
        let config = DeviceConfig.empty(newSpeakersEnabled: false)
        let reread = try DeviceConfig(data: config.data)
        XCTAssertFalse(reread.newSpeakersEnabled)
        XCTAssertEqual(reread.devices, [])
    }

    func testRejectsGarbage() {
        XCTAssertThrowsError(try DeviceConfig(data: Data("not xml".utf8)))
    }
}
