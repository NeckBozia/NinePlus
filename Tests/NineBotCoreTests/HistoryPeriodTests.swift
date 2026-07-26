import XCTest
@testable import NineBotCore

/// The history-span buckets, pulled out of the string-producing `periodText`.
final class HistoryPeriodTests: XCTestCase {

    private func period(_ seconds: TimeInterval) -> NinebotHistoryPeriod {
        NinebotHistoryPeriod(seconds: seconds)
    }

    private func periodText(spanSeconds: TimeInterval) -> String? {
        let sn = "SN-PERIOD"
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        func point(at date: Date) -> NinebotVehicleHistoryPoint {
            NinebotVehicleHistoryPoint(sn: sn, state: NinebotVehicleState(updatedAt: date))
        }
        let points = [point(at: base), point(at: base.addingTimeInterval(spanSeconds))]
        return NinebotVehicleHistorySummary(points: points)?.periodText
    }

    // MARK: - Buckets

    func testNoSpanIsJustStarted() {
        XCTAssertEqual(period(0), .justStarted)
        // Points arriving out of order would give a negative span.
        XCTAssertEqual(period(-3_600), .justStarted)
    }

    func testASecondCountsAsASpan() {
        XCTAssertEqual(period(1), .minutes(1.0 / 60))
    }

    /// The hour boundary is inclusive: exactly one hour reads in hours.
    func testHourBoundaryIsInclusive() {
        XCTAssertEqual(period(3_600), .hours(1))
        XCTAssertEqual(period(3_599), .minutes(3_599 / 60))
    }

    /// Likewise the day boundary.
    func testDayBoundaryIsInclusive() {
        XCTAssertEqual(period(86_400), .days(1))
        XCTAssertEqual(period(86_399), .hours(86_399 / 3_600))
    }

    func testDaysAreFractional() {
        XCTAssertEqual(period(86_400 * 2 + 43_200), .days(2.5))
    }

    // MARK: - Wording

    func testWordingPerBucket() {
        XCTAssertEqual(periodText(spanSeconds: 0), "刚刚开始记录")
        XCTAssertEqual(periodText(spanSeconds: 1_800), "30 分钟")
        XCTAssertEqual(periodText(spanSeconds: 7_200), "2 小时")
        XCTAssertEqual(periodText(spanSeconds: 9_000), "2.5 小时")
        XCTAssertEqual(periodText(spanSeconds: 172_800), "2 天")
        XCTAssertEqual(periodText(spanSeconds: 216_000), "2.5 天")
    }

    /// The bucket is chosen from the raw value but the number is then rounded,
    /// so just under a boundary the two disagree: 3599s is still in the minute
    /// bucket yet prints as a round 60, and 86399s prints as a round 24 hours.
    ///
    /// Same quirk as `formatDuration`. Pinned rather than fixed — Android will
    /// need to decide whether to inherit it.
    func testJustUnderABoundaryPrintsTheBoundaryNumber() {
        XCTAssertEqual(periodText(spanSeconds: 3_599), "60 分钟")
        XCTAssertEqual(periodText(spanSeconds: 86_399), "24 小时")
    }
}
