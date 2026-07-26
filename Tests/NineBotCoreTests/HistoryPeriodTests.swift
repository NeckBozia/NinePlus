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

    /// The hour boundary is measured against the printed minute figure, which
    /// carries no decimals — so it flips half a minute early, at 59:30.
    func testHourBoundaryFollowsThePrintedMinuteFigure() {
        XCTAssertEqual(period(3_600), .hours(1))
        // 59:30 prints as 60 minutes, so it reads in hours instead.
        XCTAssertEqual(period(3_570), .hours(3_570 / 3_600))
        // 59:29 still prints as 59.
        XCTAssertEqual(period(3_569), .minutes(3_569 / 60))
    }

    /// Same for the day boundary, against the printed hour figure, which
    /// carries one decimal — so it flips at 23.95 hours.
    func testDayBoundaryFollowsThePrintedHourFigure() {
        XCTAssertEqual(period(86_400), .days(1))
        // 23:57:10 prints as 24.0 hours, so it reads in days instead.
        //
        // The expectation divides in the same order the initialiser does —
        // hours first, then by 24. Collapsing it to `86_230 / 86_400` lands one
        // ULP away and the enum compares its payload exactly.
        XCTAssertEqual(period(86_230), .days((86_230.0 / 3_600) / 24))
        // 23:55 still prints as 23.9.
        XCTAssertEqual(period(86_100), .hours(86_100 / 3_600))
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

    /// The point of picking the bucket at display precision: a span just under
    /// a boundary rolls up to the next unit instead of printing the number that
    /// means that unit. No "60 分钟", no "24 小时".
    func testJustUnderABoundaryRollsUp() {
        XCTAssertEqual(periodText(spanSeconds: 3_599), "1 小时")
        XCTAssertEqual(periodText(spanSeconds: 86_399), "1 天")
    }

    /// The rolled-up value is still the real span, so it can print as a
    /// fraction rather than a flat 1.
    func testRollingUpKeepsTheRealSpan() {
        // 23:55 is under the day boundary and prints its own hour figure.
        XCTAssertEqual(periodText(spanSeconds: 86_100), "23.9 小时")
    }
}
