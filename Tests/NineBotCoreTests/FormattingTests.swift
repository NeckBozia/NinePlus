import CoreLocation
import XCTest
@testable import NineBotCore

/// These decide decimal places, units, fallback strings and time zone, so both
/// platforms have to agree on them exactly. They were private functions inside
/// a view file and had never been tested.
final class FormattingTests: XCTestCase {

    // MARK: - Fallbacks
    //
    // Every formatter has its own fallback string. They are not
    // interchangeable — the Android side has to reproduce each one.

    func testEachFormatterHasItsOwnFallback() {
        XCTAssertEqual(formatDistance(nil), "-- km")
        XCTAssertEqual(formatDistanceNumber(nil), "--")
        XCTAssertEqual(formatEnergyWh(nil), "-- Wh")
        XCTAssertEqual(formatPercent(nil), "--%")
        XCTAssertEqual(formatSpeed(nil), "-- km/h")
        XCTAssertEqual(formatAccelerationG(nil), "-- G")
        XCTAssertEqual(formatDuration(nil), "--")
        XCTAssertEqual(formatCoordinate(nil), "--")
        XCTAssertEqual(formatNumber(nil, unit: " kWh"), "-- kWh")
    }

    // MARK: - Decimal places

    func testDistanceKeepsOneDecimal() {
        XCTAssertEqual(formatDistance(12.34), "12.3 km")
        XCTAssertEqual(formatDistance(12.0), "12 km")
    }

    func testSpeedKeepsOneDecimal() {
        XCTAssertEqual(formatSpeed(25.67), "25.7 km/h")
    }

    func testEnergyIsWholeNumbers() {
        XCTAssertEqual(formatEnergyWh(1234.6), "1235 Wh")
    }

    func testAccelerationKeepsTwoDecimals() {
        XCTAssertEqual(formatAccelerationG(0.456), "0.46 G")
    }

    func testCoordinateKeepsEightDecimals() {
        // Coordinates need the precision; truncating them moves the pin.
        XCTAssertEqual(formatCoordinate(39.90869123), "39.90869123")
    }

    func testNumberRespectsRequestedDigits() {
        XCTAssertEqual(formatNumber(1.23456, unit: "", maximumFractionDigits: 2), "1.23")
        XCTAssertEqual(formatNumber(1.0, unit: "", maximumFractionDigits: 2, minimumFractionDigits: 2), "1.00")
        XCTAssertEqual(formatNumber(60.5, unit: " V", maximumFractionDigits: 1), "60.5 V")
    }

    // MARK: - Duration

    func testDurationSwitchesToHoursAtSixtyMinutes() {
        XCTAssertEqual(formatDuration(45), "45 分钟")
        XCTAssertEqual(formatDuration(60), "1 小时")
        XCTAssertEqual(formatDuration(260), "4.3 小时")
    }

    func testZeroDurationIsMinutesNotHours() {
        XCTAssertEqual(formatDuration(0), "0 分钟")
    }

    /// Minutes print without decimals, so the hour switch is compared at that
    /// same precision: anything that would print as 60 reads "1 小时" instead.
    func testDurationRollsUpRatherThanPrintingSixtyMinutes() {
        XCTAssertEqual(formatDuration(59.9), "1 小时")
        XCTAssertEqual(formatDuration(59.5), "1 小时")
        XCTAssertEqual(formatDuration(59.4), "59 分钟")
    }

    func testDisplayRoundedMatchesTheFormatterPrecision() {
        XCTAssertEqual(displayRounded(59.9, maximumFractionDigits: 0), 60)
        XCTAssertEqual(displayRounded(59.9, maximumFractionDigits: 1), 59.9, accuracy: 1e-9)
        XCTAssertEqual(displayRounded(23.96, maximumFractionDigits: 1), 24, accuracy: 1e-9)
    }

    // MARK: - Booleans and coordinates

    func testBoolTextUsesSuppliedWordingAndFallsBackToUnknown() {
        XCTAssertEqual(boolText(true, trueText: "已锁", falseText: "未锁"), "已锁")
        XCTAssertEqual(boolText(false, trueText: "已锁", falseText: "未锁"), "未锁")
        XCTAssertEqual(boolText(nil, trueText: "已锁", falseText: "未锁"), "未知")
    }

    func testCoordinateTextNeedsBothHalves() {
        XCTAssertEqual(coordinateText(39.9, 116.4), "39.9, 116.4")
        XCTAssertEqual(coordinateText(nil, 116.4), "--")
        XCTAssertEqual(coordinateText(39.9, nil), "--")
        XCTAssertEqual(coordinateText(nil, nil), "--")
    }

    // MARK: - Vehicle coordinate

    private func state(latitude: Double?, longitude: Double?) -> NinebotVehicleState {
        NinebotVehicleState(
            latitude: latitude,
            longitude: longitude,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    func testVehicleCoordinateRejectsMissingOrOutOfRangeValues() {
        XCTAssertNil(vehicleCoordinate(state(latitude: nil, longitude: 116.4)))
        XCTAssertNil(vehicleCoordinate(state(latitude: 39.9, longitude: nil)))
        XCTAssertNil(vehicleCoordinate(state(latitude: 91, longitude: 116.4)))
        XCTAssertNil(vehicleCoordinate(state(latitude: 39.9, longitude: 181)))
    }

    func testVehicleCoordinateAppliesTheGcjShiftInsideChina() {
        let coordinate = vehicleCoordinate(state(latitude: 39.90869, longitude: 116.39123))
        XCTAssertNotNil(coordinate)
        // Shifted, but only by a few hundred metres.
        XCTAssertNotEqual(coordinate?.latitude, 39.90869)
        XCTAssertEqual(coordinate?.latitude ?? 0, 39.90869, accuracy: 0.01)
        XCTAssertEqual(coordinate?.longitude ?? 0, 116.39123, accuracy: 0.01)
    }

    func testVehicleCoordinateLeavesForeignCoordinatesAlone() {
        let tokyo = vehicleCoordinate(state(latitude: 35.6812, longitude: 139.7671))
        XCTAssertEqual(tokyo?.latitude ?? 0, 35.6812, accuracy: 1e-9)
        XCTAssertEqual(tokyo?.longitude ?? 0, 139.7671, accuracy: 1e-9)
    }

    // MARK: - Month arithmetic
    //
    // Months are yyyyMM strings in Asia/Shanghai, not the device time zone.

    private func date(_ iso: String) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.date(from: iso)!
    }

    func testMonthStringUsesShanghaiTime() {
        XCTAssertEqual(tripMonthString(for: date("2026-07-26 12:00:00")), "202607")
        XCTAssertEqual(tripMonthString(for: date("2026-01-01 00:00:00")), "202601")
        XCTAssertEqual(tripMonthString(for: date("2026-12-31 23:59:59")), "202612")
    }

    func testPreviousMonthCrossesYearBoundary() {
        XCTAssertEqual(previousTripMonth(before: "202607"), "202606")
        XCTAssertEqual(previousTripMonth(before: "202601"), "202512")
    }

    func testMonthStringFromRideRecordUsesItsStartDate() {
        let record = NinebotRideRecord(
            id: "r1",
            startedAt: date("2026-03-15 08:00:00"),
            endedAt: date("2026-03-15 09:00:00"),
            raw: [:]
        )
        XCTAssertEqual(tripMonthString(for: record), "202603")
    }

    func testMonthStringIsNilWithoutAnyDate() {
        let record = NinebotRideRecord(id: "r1", raw: [:])
        XCTAssertNil(tripMonthString(for: record))
    }

    // MARK: - Dates

    func testDateAndTimeFormatsAreFixedToShanghai() {
        let d = date("2026-07-26 14:32:10")
        XCTAssertEqual(formatDate(d), "2026-07-26 14:32")
        XCTAssertEqual(formatTime(d), "14:32")
    }

    // MARK: - JSON

    func testFormattedJSONIsPrettyPrinted() throws {
        let value = try JSONDecoder().decode(
            JSONValue.self,
            from: Data("{\"battery\":87}".utf8)
        )
        let text = formattedJSON(value)
        XCTAssertTrue(text.contains("battery"))
        XCTAssertTrue(text.contains("87"))
        // Pretty printed means it spans more than one line.
        XCTAssertTrue(text.contains("\n"))
    }
}
