import XCTest
@testable import AirBridgeCore

/// Output of the bundled airupnp v1.12.4 (`-Z -i … -d all=info`) on a real
/// network: two Sonos 27.1 speakers, a stereo-paired Kitchen, a grouped speaker
/// and two SYMFONISK Bookshelf speakers without a room name.
final class RealLogTests: XCTestCase {
    static let log = """
    [15:37:09.560] main:1407 Starting airupnp version: v1.12.4 (Sep 26 2026 @ 20:05:30)
    [15:37:09.560] main:1414 no config file, using defaults
    [15:37:09.561] Start:1112 Binding to iface 192.168.50.77:0 [en0]
    [15:37:09.561] bind_socket:702 socket binding 7 on port 54457
    [15:37:09.561] Start:1151 Starting pico HTTP server on port 54457
    [15:37:09.728] AddMRDevice:993 [0x148028000]: Sonos stream presented as 'broadcast' (firmware 27.1)
    [15:37:09.728] AddMRDevice:1021 [0x148028000]: creating MAC
    [15:37:09.728] AddMRDevice:1038 [0x148028000]: adding renderer (Living Room Beam) with mac BBBBF1AC394C
    [15:37:09.744] MasterHandler:641 [0x148028000]: subscribe success
    [15:37:09.889] AddMRDevice:993 [0x14802a0d8]: Sonos stream presented as 'broadcast' (firmware 17.2.7)
    [15:37:09.889] AddMRDevice:1021 [0x14802a0d8]: creating MAC
    [15:37:09.889] AddMRDevice:1038 [0x14802a0d8]: adding renderer (Kitchen) with mac BBBBC5F24BEE
    [15:37:09.904] MasterHandler:641 [0x14802a0d8]: subscribe success
    [15:37:09.936] AddMRDevice:993 [0x14802c1b0]: Sonos stream presented as 'broadcast' (firmware 27.1)
    [15:37:09.937] AddMRDevice:1021 [0x14802c1b0]: creating MAC
    [15:37:09.937] AddMRDevice:1038 [0x14802c1b0]: adding renderer (Sonos Roam SL) with mac BBBBF818A121
    [15:37:09.942] MasterHandler:641 [0x14802c1b0]: subscribe success
    [15:37:10.036] GetMaster:128 [0x14802e288]: Master not discovered yet, assigning to self
    [15:37:10.036] GetMaster:138 [0x14802e288]: not in any zone group, treating as standalone
    [15:37:10.063] AddMRDevice:993 [0x14802e288]: Sonos stream presented as 'broadcast' (firmware 17.2.7)
    [15:37:10.063] AddMRDevice:1021 [0x14802e288]: creating MAC
    [15:37:10.063] AddMRDevice:1038 [0x14802e288]: adding renderer (192.168.50.138 - SYMFONISK Bookshelf - RINCON_347E5CF1497601400) with mac BBBBD9DF591F
    [15:37:10.084] MasterHandler:643 [0x14802e288]: subscribe fail, re-trying 1
    [15:37:10.116] AddMRDevice:993 [0x148030360]: Sonos stream presented as 'broadcast' (firmware 27.1)
    [15:37:10.116] AddMRDevice:1021 [0x148030360]: creating MAC
    [15:37:10.116] AddMRDevice:1036 [0x148030360] skipping Sonos slave Sonos Alexa
    [15:37:10.202] MasterHandler:647 [0x14802e288]: subscribe fail, volume feedback will not work
    [15:37:10.218] AddMRDevice:1038 [0x148032438]: adding renderer (192.168.50.154 - SYMFONISK Bookshelf - RINCON_347E5CF148CE01400) with mac BBBBAC55BEB9
    [15:37:10.281] AddMRDevice:993 [0x148034510]: Sonos stream presented as 'broadcast' (firmware 17.2.7)
    [15:37:10.282] AddMRDevice:1021 [0x148034510]: creating MAC
    [15:37:10.282] AddMRDevice:1036 [0x148034510] skipping Sonos slave Kitchen
    [15:37:10.348] MasterHandler:641 [0x148034510]: subscribe success
    """

    var events: [LogEvent] {
        Self.log.split(separator: "\n").compactMap { LogParser.parse(String($0)) }
    }

    func testEvents() {
        XCTAssertEqual(events, [
            .started(version: "v1.12.4"),
            .bound(ip: "192.168.50.77", interface: "en0"),
            .speakerAdded(handle: "0x148028000", name: "Living Room Beam", mac: "BBBBF1AC394C"),
            .speakerAdded(handle: "0x14802a0d8", name: "Kitchen", mac: "BBBBC5F24BEE"),
            .speakerAdded(handle: "0x14802c1b0", name: "Sonos Roam SL", mac: "BBBBF818A121"),
            .speakerAdded(handle: "0x14802e288",
                          name: "192.168.50.138 - SYMFONISK Bookshelf - RINCON_347E5CF1497601400",
                          mac: "BBBBD9DF591F"),
            .speakerGrouped(handle: "0x148030360", name: "Sonos Alexa"),
            .speakerAdded(handle: "0x148032438",
                          name: "192.168.50.154 - SYMFONISK Bookshelf - RINCON_347E5CF148CE01400",
                          mac: "BBBBAC55BEB9"),
            .speakerGrouped(handle: "0x148034510", name: "Kitchen"),
        ])
    }

    func testRegistryFromRealLog() {
        var registry = SpeakerRegistry(configured: [
            ConfiguredDevice(udn: "uuid:RINCON_KITCHEN_A01400", name: "Kitchen+", mac: "bb:bb:c5:f2:4b:ee", enabled: true),
            ConfiguredDevice(udn: "uuid:RINCON_KITCHEN_B01400", name: "Kitchen+", mac: "bb:bb:00:00:00:01", enabled: false),
            ConfiguredDevice(udn: "uuid:RINCON_347E5CF1497601400",
                             name: "192.168.50.138 - SYMFONISK Bookshelf - RINCON_347E5CF1497601400+",
                             mac: "bb:bb:d9:df:59:1f", enabled: false),
        ])
        events.forEach { registry.apply($0) }
        let speakers = registry.speakers

        // The stereo-pair slave "Kitchen" must not mark the bridged Kitchen as grouped.
        let kitchens = speakers.filter { $0.name == "Kitchen" }
        XCTAssertEqual(kitchens.count, 2)
        XCTAssertEqual(kitchens.first { $0.udn == "uuid:RINCON_KITCHEN_A01400" }?.status, .active)
        XCTAssertEqual(kitchens.first { $0.udn == "uuid:RINCON_KITCHEN_B01400" }?.status, .notSeen)
        XCTAssertEqual(Set(kitchens.compactMap(\.note)), ["…A01400", "…B01400"])

        let symfonisk = speakers.first { $0.udn == "uuid:RINCON_347E5CF1497601400" }
        XCTAssertEqual(symfonisk?.name, "SYMFONISK Bookshelf")
        XCTAssertEqual(symfonisk?.ip, "192.168.50.138")
        XCTAssertEqual(symfonisk?.isSurround, true) // bonded to the Beam
        XCTAssertNil(symfonisk?.note) // two surrounds share a name; no ID needed, they're hidden
        XCTAssertEqual(speakers.filter(\.isSurround).count, 2)
        XCTAssertFalse(speakers.first { $0.name == "Living Room Beam" }!.isSurround)

        // Speakers not in the config are still listed, tidied.
        XCTAssertNotNil(speakers.first { $0.name == "Living Room Beam" && $0.status == .active })
        XCTAssertNotNil(speakers.first { $0.name == "SYMFONISK Bookshelf" && $0.ip == "192.168.50.154" })
        XCTAssertEqual(registry.activeCount, 5)
    }

    func testTidyLeavesNormalNamesAlone() {
        XCTAssertEqual(SpeakerRegistry.tidy("Kitchen+").name, "Kitchen")
        XCTAssertNil(SpeakerRegistry.tidy("Kitchen+").ip)
        XCTAssertFalse(SpeakerRegistry.tidy("Kitchen+").isSurround)
        XCTAssertEqual(SpeakerRegistry.tidy("Sonos Roam SL").name, "Sonos Roam SL")
    }
}
