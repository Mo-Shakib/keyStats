import XCTest
@testable import KeyStatsCore

final class AppStatsTests: XCTestCase {
    func testInitSetsExpectedDefaults() {
        let stats = AppStats(bundleId: "com.test.app", displayName: "Test App")

        XCTAssertEqual(stats.bundleId, "com.test.app")
        XCTAssertEqual(stats.displayName, "Test App")
        XCTAssertEqual(stats.keyPresses, 0)
        XCTAssertTrue(stats.keyPressCounts.isEmpty)
        XCTAssertEqual(stats.leftClicks, 0)
        XCTAssertEqual(stats.rightClicks, 0)
        XCTAssertEqual(stats.sideBackClicks, 0)
        XCTAssertEqual(stats.sideForwardClicks, 0)
        XCTAssertEqual(stats.scrollDistance, 0)
        XCTAssertEqual(stats.totalClicks, 0)
        XCTAssertFalse(stats.hasActivity)
    }

    func testRecordMethodsAccumulateCorrectly() {
        var stats = AppStats(bundleId: "com.test.app", displayName: "Test App")

        stats.recordKeyPress()
        stats.recordLeftClick()
        stats.recordRightClick()
        stats.recordSideBackClick()
        stats.recordSideForwardClick()

        XCTAssertEqual(stats.keyPresses, 1)
        XCTAssertEqual(stats.leftClicks, 1)
        XCTAssertEqual(stats.rightClicks, 1)
        XCTAssertEqual(stats.sideBackClicks, 1)
        XCTAssertEqual(stats.sideForwardClicks, 1)
        XCTAssertEqual(stats.totalClicks, 4)
        XCTAssertTrue(stats.hasActivity)
    }

    func testAddScrollDistanceUsesAbsoluteValue() {
        var stats = AppStats(bundleId: "com.test.app", displayName: "Test App")

        stats.addScrollDistance(-12.5)
        stats.addScrollDistance(7.5)

        XCTAssertEqual(stats.scrollDistance, 20.0, accuracy: 0.0001)
    }

    func testUpdateDisplayNameIgnoresEmptyName() {
        var stats = AppStats(bundleId: "com.test.app", displayName: "Original")

        stats.updateDisplayName("")

        XCTAssertEqual(stats.displayName, "Original")
    }

    func testUpdateDisplayNameUpdatesWhenNotEmpty() {
        var stats = AppStats(bundleId: "com.test.app", displayName: "Original")

        stats.updateDisplayName("Updated")

        XCTAssertEqual(stats.displayName, "Updated")
    }

    func testCodableRoundTripPreservesFields() throws {
        var original = AppStats(bundleId: "com.test.app", displayName: "Test App")
        original.keyPresses = 12
        original.keyPressCounts = ["A": 8, "LeftCmd+C": 4]
        original.leftClicks = 3
        original.rightClicks = 4
        original.sideBackClicks = 5
        original.sideForwardClicks = 6
        original.scrollDistance = 18.2

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppStats.self, from: data)

        XCTAssertEqual(decoded.bundleId, original.bundleId)
        XCTAssertEqual(decoded.displayName, original.displayName)
        XCTAssertEqual(decoded.keyPresses, 12)
        XCTAssertEqual(decoded.keyPressCounts, original.keyPressCounts)
        XCTAssertEqual(decoded.leftClicks, 3)
        XCTAssertEqual(decoded.rightClicks, 4)
        XCTAssertEqual(decoded.sideBackClicks, 5)
        XCTAssertEqual(decoded.sideForwardClicks, 6)
        XCTAssertEqual(decoded.scrollDistance, 18.2, accuracy: 0.0001)
    }

    func testDecodeLegacyOtherClicksBackfillsSideBackClicks() throws {
        let json = """
        {
          "bundleId": "com.test.app",
          "displayName": "Test App",
          "keyPresses": 2,
          "leftClicks": 1,
          "rightClicks": 1,
          "otherClicks": 9,
          "scrollDistance": 4.5
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(AppStats.self, from: json)

        XCTAssertEqual(decoded.sideBackClicks, 9)
        XCTAssertTrue(decoded.keyPressCounts.isEmpty)
        XCTAssertEqual(decoded.sideForwardClicks, 0)
        XCTAssertEqual(decoded.totalClicks, 11)
    }

    func testDecodeExplicitSideClicksDoesNotUseLegacyOtherClicks() throws {
        let json = """
        {
          "bundleId": "com.test.app",
          "displayName": "Test App",
          "leftClicks": 1,
          "rightClicks": 1,
          "sideBackClicks": 2,
          "sideForwardClicks": 3,
          "otherClicks": 100,
          "scrollDistance": 0
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(AppStats.self, from: json)

        XCTAssertEqual(decoded.sideBackClicks, 2)
        XCTAssertEqual(decoded.sideForwardClicks, 3)
        XCTAssertEqual(decoded.totalClicks, 7)
    }

    func testDecodeMissingFieldsFallsBackToZeroAndEmpty() throws {
        let json = "{}".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppStats.self, from: json)

        XCTAssertEqual(decoded.bundleId, "")
        XCTAssertEqual(decoded.displayName, "")
        XCTAssertEqual(decoded.keyPresses, 0)
        XCTAssertEqual(decoded.leftClicks, 0)
        XCTAssertEqual(decoded.rightClicks, 0)
        XCTAssertEqual(decoded.sideBackClicks, 0)
        XCTAssertEqual(decoded.sideForwardClicks, 0)
        XCTAssertEqual(decoded.scrollDistance, 0)
        XCTAssertFalse(decoded.hasActivity)
    }

    func testPerAppKeyDistributionKeepsAppsSeparateAndExpandsModifiers() {
        var editor = AppStats(bundleId: "com.test.editor", displayName: "Editor")
        var browser = AppStats(bundleId: "com.test.browser", displayName: "Browser")
        editor.recordKeyPress(keyName: " LeftCmd + C ")
        editor.recordKeyPress(keyName: "LeftCmd+C")
        editor.recordKeyPress(keyName: "RightShift+A")
        browser.recordKeyPress(keyName: "Space")

        XCTAssertEqual(editor.keyPresses, 3)
        XCTAssertEqual(editor.keyPressCounts, ["LeftCmd+C": 2, "RightShift+A": 1])
        XCTAssertEqual(keyboardHeatmapCounts(from: editor.keyPressCounts), [
            "LeftCmd": 2, "C": 2, "RightShift": 1, "A": 1
        ])
        XCTAssertEqual(browser.keyPressCounts, ["Space": 1])
    }

    func testUnnamedKeyPressOnlyUpdatesTotal() {
        var stats = AppStats(bundleId: "com.test.app", displayName: "Test")
        stats.recordKeyPress()
        stats.recordKeyPress(keyName: "  ")

        XCTAssertEqual(stats.keyPresses, 2)
        XCTAssertTrue(stats.keyPressCounts.isEmpty)
    }

    func testLegacyAppStartsShowingNewDistributionWithoutInventingEarlierKeys() throws {
        let json = Data("""
        {"bundleId":"com.test.app","displayName":"Test","keyPresses":152}
        """.utf8)
        var stats = try JSONDecoder().decode(AppStats.self, from: json)
        XCTAssertEqual(stats.keyPressesWithDistribution, 0)

        stats.recordKeyPress(keyName: "LeftCmd+C")
        stats.recordKeyPress(keyName: "A")

        let saved = try JSONEncoder().encode(stats)
        let restored = try JSONDecoder().decode(AppStats.self, from: saved)
        XCTAssertEqual(restored.keyPresses, 154)
        XCTAssertEqual(restored.keyPressesWithDistribution, 2)
        XCTAssertEqual(keyboardHeatmapCounts(from: restored.keyPressCounts), [
            "LeftCmd": 1, "C": 1, "A": 1
        ])
        // A second app must never inherit this app's distribution.
        XCTAssertTrue(AppStats(bundleId: "com.test.other", displayName: "Other").keyPressCounts.isEmpty)
    }

    func testDistributionCoverageIgnoresNegativeCountsAndSaturates() {
        var stats = AppStats(bundleId: "com.test.app", displayName: "Test")
        stats.keyPressCounts = ["A": Int.max, "B": 1, "C": -4]
        XCTAssertEqual(stats.keyPressesWithDistribution, Int.max)
    }
}
