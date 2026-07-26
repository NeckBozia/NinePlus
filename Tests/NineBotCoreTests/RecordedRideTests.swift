import XCTest
@testable import NineBotCore

final class RecordedRideTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func point(
        offsetSeconds: TimeInterval,
        latitude: Double,
        longitude: Double,
        accuracy: Double? = 10
    ) -> NinebotRideTrackPoint {
        NinebotRideTrackPoint(
            date: start.addingTimeInterval(offsetSeconds),
            latitude: latitude,
            longitude: longitude,
            speedKmh: 20,
            accelerationG: 0.1,
            horizontalAccuracy: accuracy
        )
    }

    private func ride(points: [NinebotRideTrackPoint], distanceMeters: Double = 0) -> NinebotRecordedRide {
        NinebotRecordedRide(
            id: UUID().uuidString,
            vehicleSN: "SN-TEST",
            startedAt: start,
            endedAt: start.addingTimeInterval(600),
            distanceMeters: distanceMeters,
            maxSpeedKmh: 42,
            averageSpeedKmh: 21,
            maxAccelerationG: 0.4,
            points: points
        )
    }

    // MARK: - Distance recalculation

    func testDistanceSumsConsecutiveSegments() {
        // ~100 m apart in latitude (0.0009° ≈ 100 m).
        let points = [
            point(offsetSeconds: 0, latitude: 39.9000, longitude: 116.4),
            point(offsetSeconds: 5, latitude: 39.9009, longitude: 116.4),
            point(offsetSeconds: 10, latitude: 39.9018, longitude: 116.4),
        ]
        let distance = NinebotRecordedRide.recalculatedDistanceMeters(from: points)
        XCTAssertEqual(distance, 200, accuracy: 20)
    }

    func testSinglePointHasNoDistance() {
        let distance = NinebotRecordedRide.recalculatedDistanceMeters(
            from: [point(offsetSeconds: 0, latitude: 39.9, longitude: 116.4)]
        )
        XCTAssertEqual(distance, 0)
    }

    func testPointsWithPoorAccuracyAreDropped() {
        let points = [
            point(offsetSeconds: 0, latitude: 39.9000, longitude: 116.4),
            point(offsetSeconds: 5, latitude: 39.9009, longitude: 116.4, accuracy: 500),
            point(offsetSeconds: 10, latitude: 39.9018, longitude: 116.4),
        ]
        // The middle point is discarded, leaving one ~200 m segment.
        let distance = NinebotRecordedRide.recalculatedDistanceMeters(from: points)
        XCTAssertEqual(distance, 200, accuracy: 20)
    }

    func testSegmentsWithLongTimeGapsAreIgnored() {
        let points = [
            point(offsetSeconds: 0, latitude: 39.9000, longitude: 116.4),
            point(offsetSeconds: 120, latitude: 39.9009, longitude: 116.4),
        ]
        // 120 s exceeds the 30 s cap, so the segment does not count.
        XCTAssertEqual(NinebotRecordedRide.recalculatedDistanceMeters(from: points), 0)
    }

    func testImplausiblyLongSegmentsAreIgnored() {
        let points = [
            point(offsetSeconds: 0, latitude: 39.9000, longitude: 116.4),
            point(offsetSeconds: 5, latitude: 39.9500, longitude: 116.4),
        ]
        // ~5.5 km in 5 s — beyond the 300 m per-segment cap.
        XCTAssertEqual(NinebotRecordedRide.recalculatedDistanceMeters(from: points), 0)
    }

    func testUnorderedPointsAreSortedBeforeMeasuring() {
        let ordered = [
            point(offsetSeconds: 0, latitude: 39.9000, longitude: 116.4),
            point(offsetSeconds: 5, latitude: 39.9009, longitude: 116.4),
            point(offsetSeconds: 10, latitude: 39.9018, longitude: 116.4),
        ]
        let shuffled = [ordered[2], ordered[0], ordered[1]]
        XCTAssertEqual(
            NinebotRecordedRide.recalculatedDistanceMeters(from: shuffled),
            NinebotRecordedRide.recalculatedDistanceMeters(from: ordered),
            accuracy: 0.001
        )
    }

    // MARK: - Summary / track split

    func testSummaryDropsPointsButKeepsTheCount() {
        let points = (0..<5).map {
            point(offsetSeconds: Double($0) * 5, latitude: 39.9 + Double($0) * 0.0009, longitude: 116.4)
        }
        let summary = ride(points: points).trackSummary()

        XCTAssertTrue(summary.points.isEmpty)
        XCTAssertEqual(summary.trackPointCount, 5)
        XCTAssertFalse(summary.isTrackLoaded)
    }

    func testSummaryFreezesTheRecalculatedDistance() {
        let points = [
            point(offsetSeconds: 0, latitude: 39.9000, longitude: 116.4),
            point(offsetSeconds: 5, latitude: 39.9009, longitude: 116.4),
        ]
        // Stored distance is deliberately wrong; the summary must carry the
        // recalculated one so a list row shows the same number as the detail.
        let full = ride(points: points, distanceMeters: 99_999)
        let summary = full.trackSummary()

        XCTAssertEqual(summary.distanceMeters, full.displayDistanceMeters, accuracy: 0.001)
        XCTAssertEqual(summary.displayDistanceMeters, full.displayDistanceMeters, accuracy: 0.001)
    }

    func testEmptyRideIsConsideredLoaded() {
        let empty = ride(points: [])
        XCTAssertEqual(empty.trackPointCount, 0)
        XCTAssertTrue(empty.isTrackLoaded)
    }

    func testWithTrackRestoresPoints() {
        let points = (0..<3).map {
            point(offsetSeconds: Double($0) * 5, latitude: 39.9 + Double($0) * 0.0009, longitude: 116.4)
        }
        let restored = ride(points: points).trackSummary().withTrack(points)

        XCTAssertEqual(restored.points.count, 3)
        XCTAssertEqual(restored.trackPointCount, 3)
        XCTAssertTrue(restored.isTrackLoaded)
    }

    /// Summarising a summary must be a no-op.  Getting this wrong zeroes the
    /// point count on every re-save, which makes the detail view stop loading
    /// the track even though the file is still on disk.
    func testSummaryIsIdempotent() {
        let points = (0..<7).map {
            point(offsetSeconds: Double($0) * 5, latitude: 39.9 + Double($0) * 0.0009, longitude: 116.4)
        }
        let once = ride(points: points).trackSummary()
        let twice = once.trackSummary()

        XCTAssertEqual(twice.trackPointCount, 7)
        XCTAssertEqual(twice.distanceMeters, once.distanceMeters, accuracy: 0.001)
        XCTAssertFalse(twice.isTrackLoaded)
    }

    func testWithEmptyTrackKeepsTheKnownCount() {
        let points = (0..<4).map {
            point(offsetSeconds: Double($0) * 5, latitude: 39.9 + Double($0) * 0.0009, longitude: 116.4)
        }
        // A failed read must not make a 4-point ride look like a 0-point ride.
        let summary = ride(points: points).trackSummary()
        XCTAssertEqual(summary.withTrack([]).trackPointCount, 4)
    }

    func testDecodingLegacyRecordWithoutPointCount() throws {
        let legacy = """
        {
          "id": "legacy-1",
          "startedAt": 1700000000,
          "endedAt": 1700000600,
          "distanceMeters": 1234.5,
          "maxSpeedKmh": 42,
          "averageSpeedKmh": 21,
          "maxAccelerationG": 0.4,
          "points": []
        }
        """
        let decoded = try JSONDecoder().decode(NinebotRecordedRide.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.id, "legacy-1")
        XCTAssertNil(decoded.pointCount)
        XCTAssertEqual(decoded.trackPointCount, 0)
    }
}
