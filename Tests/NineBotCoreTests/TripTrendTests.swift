import XCTest
@testable import NineBotCore

/// The trend rules used to live inside a 5000-line view file as private code,
/// which made them untestable. These are the first tests they have ever had.
final class TripTrendTests: XCTestCase {
    private let month = "202607"

    private func ride(
        id: String = UUID().uuidString,
        mileage: Double? = nil,
        energy: Double? = nil,
        usedElectricity: Double? = nil,
        speed: Double? = nil
    ) -> NinebotRideRecord {
        NinebotRideRecord(
            id: id,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: Date(timeIntervalSince1970: 1_700_003_600),
            mileage: mileage,
            energy: energy,
            usedElectricity: usedElectricity,
            durationMinutes: 60,
            speed: speed,
            raw: [:]
        )
    }

    private func daily(_ mileages: [Double]) -> [NinebotDailyMileageRecord] {
        mileages.enumerated().map { index, mileage in
            NinebotDailyMileageRecord(
                id: "\(month)-\(index + 1)",
                day: index + 1,
                date: Date(timeIntervalSince1970: 1_700_000_000 + Double(index) * 86_400),
                mileage: mileage
            )
        }
    }

    private func trend(
        rides: [NinebotRideRecord] = [],
        dailyMileages: [NinebotDailyMileageRecord] = [],
        monthMileage: Double? = nil,
        monthEnergy: Double? = nil,
        monthUsedElectricity: Double? = nil,
        recordedRides: [NinebotRecordedRide] = [],
        prediction: NinebotServerPrediction? = nil
    ) -> NinebotTripTrend {
        let state = NinebotVehicleState(
            monthMileage: monthMileage,
            monthEnergy: monthEnergy,
            monthUsedElectricity: monthUsedElectricity,
            rideRecords: rides.isEmpty ? nil : rides,
            dailyMileageRecords: dailyMileages.isEmpty ? nil : dailyMileages,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            serverPrediction: prediction
        )
        return NinebotTripTrend(
            snapshot: NinebotVehicleSnapshot(
                vehicle: NinebotVehicleInfo(sn: "SN-1", name: "车", model: "型号", raw: [:]),
                state: state
            ),
            recordedRides: recordedRides
        )
    }

    private func recordedRide(associatedRideID: String?) -> NinebotRecordedRide {
        NinebotRecordedRide(
            vehicleSN: "SN-1",
            associatedRideID: associatedRideID,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: Date(timeIntervalSince1970: 1_700_001_800),
            distanceMeters: 3_000,
            maxSpeedKmh: 42,
            averageSpeedKmh: 21,
            maxAccelerationG: 0.3,
            points: []
        )
    }

    // MARK: - Aggregates

    func testMonthMileagePrefersTheStateValue() {
        let t = trend(dailyMileages: daily([5, 5, 5]), monthMileage: 99)
        XCTAssertEqual(t.monthMileage, 99)
    }

    func testMonthMileageFallsBackToSummingDailyRecords() {
        let t = trend(dailyMileages: daily([4, 6, 10]))
        XCTAssertEqual(t.monthMileage, 20)
    }

    func testMonthMileageIsNilWithoutAnySource() {
        XCTAssertNil(trend().monthMileage)
    }

    func testAverageDailyMileageDividesByActiveDays() {
        let t = trend(dailyMileages: daily([10, 20, 30]))
        XCTAssertEqual(t.averageDailyMileage ?? 0, 20, accuracy: 1e-9)
    }

    func testAveragesIgnoreNonPositiveSamples() {
        let t = trend(rides: [
            ride(usedElectricity: 10, speed: 20),
            ride(usedElectricity: 0, speed: 0),      // dropped
            ride(usedElectricity: 20, speed: 40),
        ])
        XCTAssertEqual(t.averageUsedElectricity ?? 0, 15, accuracy: 1e-9)
        XCTAssertEqual(t.averageSpeed ?? 0, 30, accuracy: 1e-9)
    }

    func testPeakRideMileageTakesTheMaximum() {
        let t = trend(rides: [ride(mileage: 3), ride(mileage: 11), ride(mileage: 7)])
        XCTAssertEqual(t.peakRideMileage, 11)
    }

    func testEnergyPerKmPrefersMonthTotals() {
        // 400 Wh over 20 km, and monthUsedElectricity wins over monthEnergy.
        let t = trend(monthMileage: 20, monthEnergy: 999, monthUsedElectricity: 400)
        XCTAssertEqual(t.energyPerKm ?? 0, 20, accuracy: 1e-9)
    }

    func testEnergyPerKmFallsBackToPerRideAverage() {
        let t = trend(rides: [
            ride(mileage: 10, energy: 200),          // 20 Wh/km
            ride(mileage: 10, energy: 300),          // 30 Wh/km
            ride(mileage: 0, energy: 100),           // dropped
        ])
        XCTAssertEqual(t.energyPerKm ?? 0, 25, accuracy: 1e-9)
    }

    func testRecentRidesAreCappedAtEight() {
        let t = trend(rides: (0..<12).map { ride(id: "r\($0)", mileage: 1) })
        XCTAssertEqual(t.rideCount, 12)
        XCTAssertEqual(t.recentRides.count, NinebotTripTrend.recentRideDisplayCount)
        XCTAssertEqual(t.recentRides.count, 8)
    }

    func testDailyRecordsSortChronologically() {
        var records = daily([1, 2, 3])
        records.reverse()
        let t = trend(dailyMileages: records)
        XCTAssertEqual(t.dailyRecords.map(\.day), [1, 2, 3])
        XCTAssertEqual(t.activeDayCount, 3)
    }

    // MARK: - Insight rules

    /// A ride 1.8x the daily average is the boundary — strictly greater fires.
    func testLongRideRuleUsesAStrictRatio() {
        // 3 days totalling 30 km → daily average 10 km. Threshold is 18 km.
        let below = trend(rides: [ride(mileage: 18)], dailyMileages: daily([10, 10, 10]))
        XCTAssertFalse(below.insights.contains(.longRideDominates))

        let above = trend(rides: [ride(mileage: 18.1)], dailyMileages: daily([10, 10, 10]))
        XCTAssertTrue(above.insights.contains(.longRideDominates))
    }

    func testHighAverageElectricityBoundary() {
        XCTAssertFalse(trend(rides: [ride(usedElectricity: 12)]).insights.contains(.highAverageElectricity))
        XCTAssertTrue(trend(rides: [ride(usedElectricity: 12.1)]).insights.contains(.highAverageElectricity))
    }

    func testHighEnergyPerKmBoundary() {
        XCTAssertFalse(trend(monthMileage: 10, monthUsedElectricity: 350).insights.contains(.highEnergyPerKm))
        XCTAssertTrue(trend(monthMileage: 10, monthUsedElectricity: 351).insights.contains(.highEnergyPerKm))
    }

    /// No server prediction means zero samples, so this always fires with the
    /// community server.
    func testFewRangeSamplesFiresWithoutServerPrediction() {
        XCTAssertTrue(trend().insights.contains(.fewRangeSamples))
    }

    func testUnlinkedLocalRidesFiresOnlyForUnlinkedRecords() {
        let linked = trend(recordedRides: [recordedRide(associatedRideID: "travel-1")])
        XCTAssertFalse(linked.insights.contains(.unlinkedLocalRides))

        let unlinked = trend(recordedRides: [recordedRide(associatedRideID: nil)])
        XCTAssertTrue(unlinked.insights.contains(.unlinkedLocalRides))
    }

    func testInsightsAreNeverEmpty() {
        // Enough samples that nothing else fires, so .normal has to appear.
        let prediction = NinebotServerPrediction(
            range: NinebotServerRangePrediction(sampleCount: 9),
            charging: NinebotServerChargingPrediction()
        )
        let t = trend(
            rides: [ride(mileage: 10, energy: 100, usedElectricity: 5, speed: 25)],
            dailyMileages: daily([10, 10]),
            monthMileage: 20,
            monthUsedElectricity: 200,
            prediction: prediction
        )
        XCTAssertEqual(t.insights, [.normal])
    }

    func testInsightsCanStack() {
        let t = trend(
            rides: [ride(mileage: 50, usedElectricity: 30)],
            dailyMileages: daily([5, 5]),
            monthMileage: 10,
            monthUsedElectricity: 600,
            recordedRides: [recordedRide(associatedRideID: nil)]
        )
        // Long ride, high electricity, high Wh/km, few samples, unlinked rides.
        XCTAssertEqual(t.insights.count, 5)
        XCTAssertFalse(t.insights.contains(.normal))
    }

    func testInsightOrderIsStable() {
        let t = trend(
            rides: [ride(mileage: 50, usedElectricity: 30)],
            dailyMileages: daily([5, 5]),
            monthMileage: 10,
            monthUsedElectricity: 600,
            recordedRides: [recordedRide(associatedRideID: nil)]
        )
        XCTAssertEqual(t.insights, [
            .longRideDominates,
            .highAverageElectricity,
            .highEnergyPerKm,
            .fewRangeSamples,
            .unlinkedLocalRides,
        ])
    }
}
