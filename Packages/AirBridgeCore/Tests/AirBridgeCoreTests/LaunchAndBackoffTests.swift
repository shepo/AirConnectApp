import XCTest
@testable import AirBridgeCore

final class LaunchArgumentsTests: XCTestCase {
    func testDefaults() {
        let args = LaunchArguments.run(settings: BridgeSettings(), configPath: "/c.xml", pidPath: "/p.pid")
        XCTAssertEqual(args, [
            "-Z", "-k",
            "-x", "/c.xml", "-I",
            "-p", "/p.pid",
            "-l", "1000:2000",
            "-d", "all=info",
        ])
    }

    func testNeverUsesDaemonFlag() {
        let args = LaunchArguments.run(settings: BridgeSettings(), configPath: "/c", pidPath: "/p")
        XCTAssertFalse(args.contains("-z")) // not available on macOS
    }

    func testQuietLevelKeepsDiscoveryLogging() {
        var settings = BridgeSettings()
        settings.logLevel = .error
        let args = LaunchArguments.run(settings: settings, configPath: "/c", pidPath: "/p")
        XCTAssertEqual(Array(args.suffix(6)), ["-d", "all=error", "-d", "main=info", "-d", "upnp=info"])
    }

    func testDebugLevelIsPassedThrough() {
        var settings = BridgeSettings()
        settings.logLevel = .debug
        let args = LaunchArguments.run(settings: settings, configPath: "/c", pidPath: "/p")
        XCTAssertEqual(Array(args.suffix(2)), ["-d", "all=debug"])
    }

    func testLatencyIsClamped() {
        var settings = BridgeSettings()
        settings.rtpLatency = -5
        settings.httpLatency = 99_999
        let args = LaunchArguments.run(settings: settings, configPath: "/c", pidPath: "/p")
        XCTAssertEqual(args[args.firstIndex(of: "-l")! + 1], "0:5000")
    }

    func testDiscover() {
        XCTAssertEqual(LaunchArguments.discover(outputPath: "/tmp/s.xml"), ["-Z", "-i", "/tmp/s.xml"])
    }

    func testSettingsCodable() throws {
        var settings = BridgeSettings()
        settings.rtpLatency = 1500
        settings.newSpeakersEnabled = true
        let decoded = try JSONDecoder().decode(BridgeSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded, settings)
    }
}

final class BackoffTests: XCTestCase {
    func testDoublesUpToCap() {
        var backoff = Backoff()
        let delays = (0..<9).map { _ in backoff.delayAfterCrash(runDuration: 1) }
        XCTAssertEqual(delays, [1, 2, 4, 8, 16, 32, 60, 60, 60])
    }

    func testHealthyRunResets() {
        var backoff = Backoff()
        _ = backoff.delayAfterCrash(runDuration: 1)
        _ = backoff.delayAfterCrash(runDuration: 1)
        XCTAssertEqual(backoff.delayAfterCrash(runDuration: 120), 1)
        XCTAssertEqual(backoff.delayAfterCrash(runDuration: 1), 2)
    }

    func testReset() {
        var backoff = Backoff()
        _ = backoff.delayAfterCrash(runDuration: 1)
        backoff.reset()
        XCTAssertEqual(backoff.failures, 0)
        XCTAssertEqual(backoff.delayAfterCrash(runDuration: 1), 1)
    }
}

final class LineBufferTests: XCTestCase {
    func testSplitsAcrossChunks() {
        var buffer = LineBuffer()
        XCTAssertEqual(buffer.append(Data("[1] a:1 hel".utf8)), [])
        XCTAssertEqual(buffer.append(Data("lo\r\nsecond\nthi".utf8)), ["[1] a:1 hello", "second"])
        XCTAssertEqual(buffer.flush(), ["thi"])
        XCTAssertEqual(buffer.flush(), [])
    }

    func testInvalidUTF8DoesNotDropTheLine() {
        var buffer = LineBuffer()
        var data = Data("name ".utf8)
        data.append(0xFF)
        data.append(0x0A)
        XCTAssertEqual(buffer.append(data).count, 1)
    }
}
