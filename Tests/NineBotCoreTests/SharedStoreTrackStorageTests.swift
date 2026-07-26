import XCTest
@testable import NineBotCore

/// Covers the split between ride summaries (UserDefaults) and track points
/// (one file per ride).  The regression this guards against is a long ride
/// pushing megabytes of coordinates into the defaults plist.
final class SharedStoreTrackStorageTests: XCTestCase {
    /// Mirrors `NinebotSharedStore.Key.recordedRides`, which is private.
    private let recordedRidesKey = "ninebot.recorded.rides"

    private var suiteName = ""
    private var store = NinebotSharedStore()
    private var defaults = UserDefaults.standard

    override func setUp() {
        super.setUp()
        suiteName = "com.nineplus.tests.\(UUID().uuidString)"
        store = NinebotSharedStore(suiteName: suiteName)
        defaults = UserDefaults(suiteName: suiteName) ?? .standard
        removeAllRides()
    }

    override func tearDown() {
        removeAllRides()
        UserDefaults().removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func removeAllRides() {
        for ride in store.loadRecordedRides() {
            store.deleteRecordedRide(id: ride.id)
        }
    }

    private func makeRide(id: String = UUID().uuidString, pointCount: Int) -> NinebotRecordedRide {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let points = (0..<pointCount).map { index in
            NinebotRideTrackPoint(
                date: start.addingTimeInterval(Double(index) * 2),
                // ~50 m apart, well inside the per-segment cap.
                latitude: 39.9 + Double(index) * 0.00045,
                longitude: 116.4,
                speedKmh: 22,
                accelerationG: 0.12,
                horizontalAccuracy: 8
            )
        }

        return NinebotRecordedRide(
            id: id,
            vehicleSN: "SN-TEST",
            startedAt: start,
            endedAt: start.addingTimeInterval(Double(max(pointCount - 1, 0)) * 2),
            distanceMeters: 0,
            maxSpeedKmh: 42,
            averageSpeedKmh: 21,
            maxAccelerationG: 0.4,
            points: points
        )
    }

    // MARK: -

    func testListLoadReturnsSummariesWithoutPoints() {
        let ride = makeRide(pointCount: 300)
        store.upsertRecordedRide(ride)

        let loaded = store.loadRecordedRides()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertTrue(loaded[0].points.isEmpty)
        XCTAssertEqual(loaded[0].trackPointCount, 300)
        XCTAssertFalse(loaded[0].isTrackLoaded)
    }

    func testDetailLoadReturnsTheFullTrack() {
        let ride = makeRide(pointCount: 300)
        store.upsertRecordedRide(ride)

        let detail = store.loadRecordedRide(id: ride.id)
        XCTAssertNotNil(detail)
        XCTAssertEqual(detail?.points.count, 300)
        XCTAssertEqual(detail?.trackPointCount, 300)
        XCTAssertEqual(detail?.isTrackLoaded, true)
    }

    func testDefaultsPayloadStaysSmallForALongRide() {
        // 4000 points is roughly a two-hour ride at 2 s sampling.
        store.upsertRecordedRide(makeRide(pointCount: 4_000))

        let defaultsBytes = defaults.data(forKey: recordedRidesKey)?.count ?? 0
        let trackBytes = store.recordedTrackByteCount()

        XCTAssertGreaterThan(trackBytes, 50_000, "the track itself should be substantial")
        XCTAssertLessThan(defaultsBytes, 4_000, "defaults must hold a summary, not the track")
        XCTAssertLessThan(defaultsBytes, trackBytes / 10)
    }

    func testSummaryDistanceMatchesTheFullRecord() {
        let ride = makeRide(pointCount: 50)
        store.upsertRecordedRide(ride)

        let summary = store.loadRecordedRides().first
        let detail = store.loadRecordedRide(id: ride.id)

        XCTAssertNotNil(summary)
        XCTAssertNotNil(detail)
        XCTAssertEqual(
            summary?.displayDistanceMeters ?? -1,
            detail?.displayDistanceMeters ?? -2,
            accuracy: 0.5
        )
        XCTAssertGreaterThan(summary?.displayDistanceMeters ?? 0, 0)
    }

    /// The important one: re-saving a list of summaries must not wipe the
    /// tracks on disk, because summaries carry no points.
    func testResavingSummariesPreservesTracks() {
        let ride = makeRide(pointCount: 200)
        store.upsertRecordedRide(ride)

        var summaries = store.loadRecordedRides()
        summaries[0].associatedRideID = "travel-42"
        store.saveRecordedRides(summaries)

        let detail = store.loadRecordedRide(id: ride.id)
        XCTAssertEqual(detail?.points.count, 200)
        XCTAssertEqual(detail?.associatedRideID, "travel-42")
    }

    func testUpsertReplacesRatherThanDuplicates() {
        let ride = makeRide(pointCount: 20)
        store.upsertRecordedRide(ride)

        var updated = ride
        updated.maxSpeedKmh = 55
        store.upsertRecordedRide(updated)

        let loaded = store.loadRecordedRides()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].maxSpeedKmh, 55)
    }

    func testDeleteRemovesSummaryAndTrack() {
        let ride = makeRide(pointCount: 100)
        store.upsertRecordedRide(ride)
        XCTAssertGreaterThan(store.recordedTrackByteCount(), 0)

        store.deleteRecordedRide(id: ride.id)

        XCTAssertTrue(store.loadRecordedRides().isEmpty)
        XCTAssertTrue(store.loadTrackPoints(id: ride.id).isEmpty)
        XCTAssertNil(store.loadRecordedRide(id: ride.id))
        XCTAssertEqual(store.recordedTrackByteCount(), 0)
    }

    func testRidesAreSortedNewestFirst() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        for offset in [0.0, 7_200.0, 3_600.0] {
            var ride = makeRide(pointCount: 5)
            ride.startedAt = base.addingTimeInterval(offset)
            store.upsertRecordedRide(ride)
        }

        let loaded = store.loadRecordedRides()
        XCTAssertEqual(loaded.count, 3)
        XCTAssertEqual(loaded, loaded.sorted { $0.startedAt > $1.startedAt })
    }

    func testRetentionCapDropsOldestRidesAndTheirTracks() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let rides = (0..<125).map { index -> NinebotRecordedRide in
            var ride = makeRide(pointCount: 3)
            ride.startedAt = base.addingTimeInterval(Double(index) * 60)
            return ride
        }

        store.saveRecordedRides(rides)

        let loaded = store.loadRecordedRides()
        XCTAssertEqual(loaded.count, 120)

        // The five oldest are gone, tracks included.
        let dropped = rides.sorted { $0.startedAt > $1.startedAt }.suffix(5)
        for ride in dropped {
            XCTAssertNil(store.loadRecordedRide(id: ride.id))
            XCTAssertTrue(store.loadTrackPoints(id: ride.id).isEmpty)
        }
    }

    /// Records written before the split still have their points inline; the
    /// first read must move them onto disk and shrink the defaults payload.
    func testLegacyInlineRecordsAreMigratedOnFirstRead() throws {
        let legacy = makeRide(pointCount: 500)
        let encoded = try JSONEncoder().encode([legacy])
        defaults.set(encoded, forKey: recordedRidesKey)

        let inlineBytes = encoded.count
        let migrated = store.loadRecordedRides()

        XCTAssertEqual(migrated.count, 1)
        XCTAssertTrue(migrated[0].points.isEmpty)
        XCTAssertEqual(migrated[0].trackPointCount, 500)

        let afterBytes = defaults.data(forKey: recordedRidesKey)?.count ?? 0
        XCTAssertLessThan(afterBytes, inlineBytes / 10)

        // And the track survived the move.
        XCTAssertEqual(store.loadRecordedRide(id: legacy.id)?.points.count, 500)
    }
}
