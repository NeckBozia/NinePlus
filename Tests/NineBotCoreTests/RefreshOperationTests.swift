import XCTest
@testable import NineBotCore

/// The diagnostics log's operation field. It used to hold the Chinese loading
/// message, JSON-encoded into `UserDefaults` — so rewording a label changed the
/// persisted format.
final class RefreshOperationTests: XCTestCase {

    private func roundTrip(_ operation: NinebotRefreshOperation) throws -> NinebotRefreshOperation {
        let data = try JSONEncoder().encode(operation)
        return try JSONDecoder().decode(NinebotRefreshOperation.self, from: data)
    }

    private var allCases: [NinebotRefreshOperation] {
        [
            .testConnection, .dashboard, .batteryQuery, .locationQuery, .addressResolve,
            .batteryChemistryUpdate("lead_acid"), .batteryChemistryUpdate(nil),
            .travelMonthSync("202603"), .travelMonthSync(nil),
            .chargingNotificationsEnable, .pushTokenSync, .login,
            .bell, .openBucket, .engineStart, .engineStop,
            .widgetTimeline, .backgroundRefresh,
        ]
    }

    // MARK: - Codes

    /// The whole point: nothing that reaches disk contains a Chinese character.
    func testEveryCodeIsAscii() {
        for operation in allCases {
            XCTAssertTrue(
                operation.code.allSatisfy { $0.isASCII },
                "\(operation) 的 code 不是纯 ASCII：\(operation.code)"
            )
        }
    }

    func testCodesAreDistinct() {
        let codes = allCases.map(\.code)
        XCTAssertEqual(Set(codes).count, codes.count)
    }

    /// These strings are a persisted format. Renaming one silently orphans every
    /// record already on disk, so they are pinned literally.
    func testCodesArePinned() {
        XCTAssertEqual(NinebotRefreshOperation.dashboard.code, "dashboard")
        XCTAssertEqual(NinebotRefreshOperation.backgroundRefresh.code, "background_refresh")
        XCTAssertEqual(NinebotRefreshOperation.widgetTimeline.code, "widget_timeline")
        XCTAssertEqual(NinebotRefreshOperation.engineStop.code, "engine_stop")
        XCTAssertEqual(NinebotRefreshOperation.travelMonthSync("202603").code, "travel_month_sync:202603")
        XCTAssertEqual(NinebotRefreshOperation.travelMonthSync(nil).code, "travel_month_sync")
    }

    // MARK: - Round trip

    func testEveryCaseSurvivesEncoding() throws {
        for operation in allCases {
            XCTAssertEqual(try roundTrip(operation), operation, "\(operation)")
        }
    }

    func testPayloadSurvives() {
        XCTAssertEqual(NinebotRefreshOperation(code: "travel_month_sync:202603"), .travelMonthSync("202603"))
        XCTAssertEqual(NinebotRefreshOperation(code: "battery_chemistry_update:lithium"),
                       .batteryChemistryUpdate("lithium"))
    }

    /// An empty payload reads back as absent rather than as an empty string, so
    /// `travel_month_sync:` and `travel_month_sync` mean the same thing.
    func testEmptyPayloadCollapsesToNil() {
        XCTAssertEqual(NinebotRefreshOperation.travelMonthSync("").code, "travel_month_sync")
    }

    // MARK: - Legacy records

    /// Records written before this enum existed hold the Chinese message. They
    /// must still decode and still display, rather than failing and taking the
    /// whole event off the diagnostics page.
    func testChineseRecordsStillDecode() throws {
        let legacy = try JSONDecoder().decode(
            NinebotRefreshOperation.self,
            from: Data(#""正在刷新车况""#.utf8)
        )
        XCTAssertEqual(legacy, .legacy("正在刷新车况"))
        XCTAssertEqual(try roundTrip(legacy), legacy)
    }

    func testUnknownCodeIsKeptVerbatim() {
        XCTAssertEqual(NinebotRefreshOperation(code: "something_a_newer_build_writes"),
                       .legacy("something_a_newer_build_writes"))
    }

    // MARK: - The event itself

    func testEventRoundTripsWithAnAsciiPayload() throws {
        let event = NinebotRefreshEvent(
            source: .widget,
            operation: .engineStart,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: Date(timeIntervalSince1970: 1_700_000_002),
            success: true,
            message: "车辆名"
        )
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(NinebotRefreshEvent.self, from: data)
        XCTAssertEqual(decoded, event)
        XCTAssertEqual(decoded.durationSeconds, 2)

        // `message` is genuinely free text and stays Chinese; `source` and
        // `operation` are identities and must not be.
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains(#""operation":"engine_start""#), json)
        XCTAssertTrue(json.contains(#""source":"Widget""#), json)
    }

    func testSourceRawValuesArePinned() {
        XCTAssertEqual(NinebotRefreshSource.app.rawValue, "App")
        XCTAssertEqual(NinebotRefreshSource.widget.rawValue, "Widget")
        XCTAssertEqual(NinebotRefreshSource.shortcut.rawValue, "Shortcut")
        XCTAssertEqual(NinebotRefreshSource.background.rawValue, "Background")
        XCTAssertEqual(NinebotRefreshSource.allCases.count, 4)
    }
}
