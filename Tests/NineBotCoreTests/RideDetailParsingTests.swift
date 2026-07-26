import CoreLocation
import XCTest
@testable import NineBotCore

/// Coverage for `extension NinebotRideDetail` — the shape-agnostic track
/// extraction that turns whatever the travel-detail endpoint returns into a
/// polyline.  Only the two public entry points (`interfaceTrackPoints` and
/// `interfaceTrackCoordinates`) are reachable; everything below them is
/// `private static`, so each shape is exercised through the entry points.
///
/// All fixtures use coordinates around Tokyo (longitude > 137.8347), which sit
/// outside `NinebotCoordinateTransform`'s mainland-China bounding box and are
/// therefore returned unshifted.  That keeps the expected values exact.
final class RideDetailParsingTests: XCTestCase {
    private func detail(_ raw: JSONValue) -> NinebotRideDetail {
        NinebotRideDetail(
            vehicleSN: "SN-TEST",
            rideID: "RIDE-1",
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
            raw: raw
        )
    }

    private func assertCoordinate(
        _ coordinate: CLLocationCoordinate2D,
        latitude: Double,
        longitude: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        // CLLocationCoordinate2D is not Equatable, so the members are compared.
        XCTAssertEqual(coordinate.latitude, latitude, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(coordinate.longitude, longitude, accuracy: 1e-9, file: file, line: line)
    }

    // MARK: - Object arrays

    func testObjectArrayWithLatLonKeys() {
        let raw = JSONValue.object([
            "data": .object([
                "trial": .array([
                    .object(["lat": .number(35.5), "lon": .number(139.5)]),
                    .object(["lat": .number(35.6), "lon": .number(139.6)]),
                ])
            ])
        ])

        let coordinates = detail(raw).interfaceTrackCoordinates
        XCTAssertEqual(coordinates.count, 2)
        assertCoordinate(coordinates[0], latitude: 35.5, longitude: 139.5)
        assertCoordinate(coordinates[1], latitude: 35.6, longitude: 139.6)
    }

    func testTrackKeyIsFoundAtAnyNestingDepth() {
        let raw = JSONValue.object([
            "data": .object([
                "detail": .object([
                    "extra": .array([
                        .object([
                            "gps_list": .array([
                                .object(["lat": .number(35.5), "lon": .number(139.5)]),
                                .object(["lat": .number(35.6), "lon": .number(139.6)]),
                            ])
                        ])
                    ])
                ])
            ])
        ])

        XCTAssertEqual(detail(raw).interfaceTrackCoordinates.count, 2)
    }

    func testAlternateLatitudeAndLongitudeKeyNames() {
        let spelledOut = JSONValue.object([
            "track": .array([
                .object(["latitude": .number(35.5), "longitude": .number(139.5)]),
                .object(["latitude": .number(35.6), "longitude": .number(139.6)]),
            ])
        ])
        XCTAssertEqual(detail(spelledOut).interfaceTrackCoordinates.count, 2)

        let xy = JSONValue.object([
            "trace": .array([
                .object(["y": .number(35.5), "x": .number(139.5)]),
                .object(["y": .number(35.6), "x": .number(139.6)]),
            ])
        ])
        let coordinates = detail(xy).interfaceTrackCoordinates
        XCTAssertEqual(coordinates.count, 2)
        assertCoordinate(coordinates[0], latitude: 35.5, longitude: 139.5)

        let gcj = JSONValue.object([
            "trajectory": .array([
                .object(["gcj_lat": .number(35.5), "gcj_lng": .number(139.5)]),
                .object(["gcj_lat": .number(35.6), "gcj_lng": .number(139.6)]),
            ])
        ])
        XCTAssertEqual(detail(gcj).interfaceTrackCoordinates.count, 2)
    }

    func testNumericStringsAreAcceptedAsCoordinates() {
        let raw = JSONValue.object([
            "track": .array([
                .object(["lat": .string("35.5"), "lon": .string("139.5")]),
                .object(["lat": .string("35.6"), "lon": .string("139.6")]),
            ])
        ])

        let coordinates = detail(raw).interfaceTrackCoordinates
        XCTAssertEqual(coordinates.count, 2)
        assertCoordinate(coordinates[0], latitude: 35.5, longitude: 139.5)
    }

    func testCoordinateNestedUnderALocationKey() {
        let raw = JSONValue.object([
            "track": .array([
                .object(["loc": .object(["lat": .number(35.5), "lon": .number(139.5)])]),
                .object(["loc": .object(["lat": .number(35.6), "lon": .number(139.6)])]),
            ])
        ])

        let coordinates = detail(raw).interfaceTrackCoordinates
        XCTAssertEqual(coordinates.count, 2)
        assertCoordinate(coordinates[0], latitude: 35.5, longitude: 139.5)
        assertCoordinate(coordinates[1], latitude: 35.6, longitude: 139.6)
    }

    func testTrackWrappedInAnObjectWithAListKey() {
        let raw = JSONValue.object([
            "track": .object([
                "list": .array([
                    .array([.number(35.5), .number(139.5)]),
                    .array([.number(35.6), .number(139.6)]),
                ])
            ])
        ])

        XCTAssertEqual(detail(raw).interfaceTrackCoordinates.count, 2)
    }

    // MARK: - Number pairs

    func testNumberPairArrays() {
        let raw = JSONValue.object([
            "track": .array([
                .array([.number(35.5), .number(139.5)]),
                .array([.number(35.6), .number(139.6)]),
            ])
        ])

        let coordinates = detail(raw).interfaceTrackCoordinates
        XCTAssertEqual(coordinates.count, 2)
        assertCoordinate(coordinates[0], latitude: 35.5, longitude: 139.5)
        assertCoordinate(coordinates[1], latitude: 35.6, longitude: 139.6)
    }

    func testLongitudeFirstPairsAreSwapped() {
        // |first| > 90 while |second| <= 90 means the pair is [lon, lat].
        let raw = JSONValue.object([
            "track": .array([
                .array([.number(139.5), .number(35.5)]),
                .array([.number(139.6), .number(35.6)]),
            ])
        ])

        let coordinates = detail(raw).interfaceTrackCoordinates
        XCTAssertEqual(coordinates.count, 2)
        assertCoordinate(coordinates[0], latitude: 35.5, longitude: 139.5)
        assertCoordinate(coordinates[1], latitude: 35.6, longitude: 139.6)
    }

    func testPairsCarrySpeedAndAuxiliaryValues() {
        let raw = JSONValue.object([
            "track": .array([
                .array([.number(35.5), .number(139.5), .number(20), .number(90)]),
                .array([.number(35.6), .number(139.6), .number(30), .number(180)]),
            ])
        ])

        let points = detail(raw).interfaceTrackPoints
        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points[0].speedKmh, 20)
        XCTAssertEqual(points[0].auxiliaryValue, 90)
        XCTAssertEqual(points[1].speedKmh, 30)
        XCTAssertEqual(points[1].auxiliaryValue, 180)
    }

    func testImplausibleSpeedsAreDroppedButThePointIsKept() {
        // normalizedSpeed only accepts 0...160.
        let raw = JSONValue.object([
            "track": .array([
                .array([.number(35.5), .number(139.5), .number(999)]),
                .array([.number(35.6), .number(139.6), .number(-3)]),
            ])
        ])

        let points = detail(raw).interfaceTrackPoints
        XCTAssertEqual(points.count, 2)
        XCTAssertNil(points[0].speedKmh)
        XCTAssertNil(points[1].speedKmh)
        XCTAssertNil(points[0].auxiliaryValue)
    }

    func testSpeedAndDirectionFromObjectKeys() {
        let raw = JSONValue.object([
            "track": .array([
                .object([
                    "lat": .number(35.5),
                    "lon": .number(139.5),
                    "speed": .number(20),
                    "direction": .number(90),
                ]),
                .object([
                    "lat": .number(35.6),
                    "lon": .number(139.6),
                    "spd": .number(30),
                    "heading": .number(180),
                ]),
            ])
        ])

        let points = detail(raw).interfaceTrackPoints
        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points[0].speedKmh, 20)
        XCTAssertEqual(points[0].auxiliaryValue, 90)
        XCTAssertEqual(points[1].speedKmh, 30)
        XCTAssertEqual(points[1].auxiliaryValue, 180)
    }

    // MARK: - Strings

    func testSemicolonSeparatedString() {
        let raw = JSONValue.object(["trail": .string("35.5,139.5;35.6,139.6;35.7,139.7")])

        let coordinates = detail(raw).interfaceTrackCoordinates
        XCTAssertEqual(coordinates.count, 3)
        assertCoordinate(coordinates[0], latitude: 35.5, longitude: 139.5)
        assertCoordinate(coordinates[2], latitude: 35.7, longitude: 139.7)
    }

    func testPipeSeparatedStringWithSpaceSeparatedNumbers() {
        let raw = JSONValue.object(["trail": .string("35.5 139.5|35.6 139.6")])

        let coordinates = detail(raw).interfaceTrackCoordinates
        XCTAssertEqual(coordinates.count, 2)
        assertCoordinate(coordinates[1], latitude: 35.6, longitude: 139.6)
    }

    func testNewlineSeparatedString() {
        let raw = JSONValue.object(["trail": .string("35.5,139.5\n35.6,139.6")])
        XCTAssertEqual(detail(raw).interfaceTrackCoordinates.count, 2)
    }

    func testJSONEncodedStringTrack() {
        let raw = JSONValue.object(["gps": .string("[[35.5,139.5],[35.6,139.6]]")])

        let coordinates = detail(raw).interfaceTrackCoordinates
        XCTAssertEqual(coordinates.count, 2)
        assertCoordinate(coordinates[0], latitude: 35.5, longitude: 139.5)
        assertCoordinate(coordinates[1], latitude: 35.6, longitude: 139.6)
    }

    func testJSONEncodedStringOfObjects() {
        let raw = JSONValue.object([
            "gps": .string(#"[{"lat":35.5,"lon":139.5},{"lat":35.6,"lon":139.6}]"#)
        ])

        let coordinates = detail(raw).interfaceTrackCoordinates
        XCTAssertEqual(coordinates.count, 2)
        assertCoordinate(coordinates[0], latitude: 35.5, longitude: 139.5)
    }

    func testAStringHoldingASingleCoordinateYieldsNothing() {
        // Track parsing only accepts candidates with more than one point, so a
        // lone "lat,lon" string is not a track.
        let raw = JSONValue.object(["trail": .string("35.5,139.5")])
        XCTAssertTrue(detail(raw).interfaceTrackCoordinates.isEmpty)
        XCTAssertTrue(detail(raw).interfaceTrackPoints.isEmpty)
    }

    func testArrayOfOneCoordinatePerStringIsNotRecognised() {
        // Documented gap: each element is parsed on its own, and a string that
        // resolves to a single coordinate is discarded, so the whole array is
        // lost.  The same coordinates in one string do parse.
        let perElement = JSONValue.object([
            "track": .array([.string("35.5,139.5"), .string("35.6,139.6")])
        ])
        XCTAssertTrue(detail(perElement).interfaceTrackCoordinates.isEmpty)

        let combined = JSONValue.object([
            "track": .array([.string("35.5,139.5;35.6,139.6")])
        ])
        XCTAssertEqual(detail(combined).interfaceTrackCoordinates.count, 2)
    }

    // MARK: - Deduplication

    func testConsecutiveDuplicatesAreCollapsed() {
        let raw = JSONValue.object([
            "track": .array([
                .array([.number(35.5), .number(139.5)]),
                .array([.number(35.5), .number(139.5)]),
                .array([.number(35.6), .number(139.6)]),
            ])
        ])

        let coordinates = detail(raw).interfaceTrackCoordinates
        XCTAssertEqual(coordinates.count, 2)
        assertCoordinate(coordinates[0], latitude: 35.5, longitude: 139.5)
        assertCoordinate(coordinates[1], latitude: 35.6, longitude: 139.6)
    }

    func testNonConsecutiveDuplicatesAreKept() {
        // Only runs of identical points collapse; revisiting a spot later in
        // the ride is a real part of the track.
        let raw = JSONValue.object([
            "track": .array([
                .array([.number(35.5), .number(139.5)]),
                .array([.number(35.6), .number(139.6)]),
                .array([.number(35.5), .number(139.5)]),
            ])
        ])

        XCTAssertEqual(detail(raw).interfaceTrackCoordinates.count, 3)
    }

    func testDeduplicationComparesToSixDecimalPlaces() {
        // 1e-7 apart rounds to the same key and collapses.
        let raw = JSONValue.object([
            "track": .array([
                .array([.number(35.5), .number(139.5)]),
                .array([.number(35.50000001), .number(139.5)]),
                .array([.number(35.6), .number(139.6)]),
            ])
        ])

        XCTAssertEqual(detail(raw).interfaceTrackCoordinates.count, 2)
    }

    // MARK: - Rejected input

    func testOutOfRangeCoordinatesAreSkipped() {
        let raw = JSONValue.object([
            "track": .array([
                .array([.number(35.5), .number(139.5)]),
                .array([.number(200), .number(300)]),
                .array([.number(35.6), .number(139.6)]),
            ])
        ])

        let coordinates = detail(raw).interfaceTrackCoordinates
        XCTAssertEqual(coordinates.count, 2)
        assertCoordinate(coordinates[0], latitude: 35.5, longitude: 139.5)
        assertCoordinate(coordinates[1], latitude: 35.6, longitude: 139.6)
    }

    func testSinglePointTracksAreIgnored() {
        let nested = JSONValue.object([
            "track": .array([.array([.number(35.5), .number(139.5)])])
        ])
        XCTAssertTrue(detail(nested).interfaceTrackCoordinates.isEmpty)
        XCTAssertTrue(detail(nested).interfaceTrackPoints.isEmpty)

        let flatPair = JSONValue.object([
            "track": .array([.number(35.5), .number(139.5)])
        ])
        XCTAssertTrue(detail(flatPair).interfaceTrackCoordinates.isEmpty)

        let singleObject = JSONValue.object([
            "track": .array([.object(["lat": .number(35.5), "lon": .number(139.5)])])
        ])
        XCTAssertTrue(detail(singleObject).interfaceTrackCoordinates.isEmpty)
    }

    func testPayloadWithoutTrackKeysHasNoCoordinates() {
        let raw = JSONValue.object([
            "mileage": .number(12.3),
            "detail": .object(["speed": .number(20)]),
            "items": .array([.object(["lat": .number(35.5), "lon": .number(139.5)])]),
        ])
        XCTAssertTrue(detail(raw).interfaceTrackCoordinates.isEmpty)
        XCTAssertTrue(detail(raw).interfaceTrackPoints.isEmpty)
    }

    func testNonContainerPayloadsHaveNoCoordinates() {
        XCTAssertTrue(detail(.null).interfaceTrackCoordinates.isEmpty)
        XCTAssertTrue(detail(.number(1)).interfaceTrackCoordinates.isEmpty)
        XCTAssertTrue(detail(.string("hello")).interfaceTrackCoordinates.isEmpty)
        XCTAssertTrue(detail(.array([])).interfaceTrackPoints.isEmpty)
    }

    // MARK: - Candidate selection

    func testTheLongestCandidateWins() {
        let raw = JSONValue.object([
            "track": .array([
                .array([.number(35.5), .number(139.5)]),
                .array([.number(35.6), .number(139.6)]),
            ]),
            "points": .array([
                .array([.number(35.5), .number(139.5)]),
                .array([.number(35.6), .number(139.6)]),
                .array([.number(35.7), .number(139.7)]),
                .array([.number(35.8), .number(139.8)]),
            ]),
        ])

        XCTAssertEqual(detail(raw).interfaceTrackCoordinates.count, 4)
    }

    func testPointsFallBackToCoordinateOnlyParsing() {
        // A JSON string whose coordinates hang off arbitrary object keys is
        // only reachable through the coordinate parser, so interfaceTrackPoints
        // falls back to it and produces points without speed metadata.
        let raw = JSONValue.object([
            "gps": .string(#"{"a":{"lat":35.5,"lon":139.5},"b":{"lat":35.6,"lon":139.6}}"#)
        ])

        let coordinates = detail(raw).interfaceTrackCoordinates
        XCTAssertEqual(coordinates.count, 2)
        // Dictionary iteration order is unspecified, so only the set matters.
        XCTAssertEqual(coordinates.map(\.latitude).sorted(), [35.5, 35.6])

        let points = detail(raw).interfaceTrackPoints
        XCTAssertEqual(points.count, 2)
        XCTAssertTrue(points.allSatisfy { $0.speedKmh == nil })
        XCTAssertTrue(points.allSatisfy { $0.auxiliaryValue == nil })
    }

    // MARK: - Point identifiers

    func testPointIdentifiersEncodeTheIndexAndMicrodegrees() {
        let raw = JSONValue.object([
            "track": .array([
                .object(["lat": .number(35.5), "lon": .number(139.5)]),
                .object(["lat": .number(35.6), "lon": .number(139.6)]),
            ])
        ])

        let points = detail(raw).interfaceTrackPoints
        XCTAssertEqual(points.map(\.id), ["0-35500000-139500000", "1-35600000-139600000"])
    }

    func testIdentifiersKeepTheIndexFromBeforeDeduplication() {
        let raw = JSONValue.object([
            "track": .array([
                .array([.number(35.5), .number(139.5)]),
                .array([.number(35.5), .number(139.5)]),
                .array([.number(35.6), .number(139.6)]),
            ])
        ])

        let points = detail(raw).interfaceTrackPoints
        XCTAssertEqual(points.map(\.id), ["0-35500000-139500000", "2-35600000-139600000"])
    }

    func testPointsAndCoordinatesAgree() {
        let raw = JSONValue.object([
            "track": .array([
                .array([.number(35.5), .number(139.5)]),
                .array([.number(35.6), .number(139.6)]),
                .array([.number(35.7), .number(139.7)]),
            ])
        ])

        let rideDetail = detail(raw)
        let points = rideDetail.interfaceTrackPoints
        let coordinates = rideDetail.interfaceTrackCoordinates
        XCTAssertEqual(points.count, coordinates.count)
        for (point, coordinate) in zip(points, coordinates) {
            assertCoordinate(point.coordinate, latitude: coordinate.latitude, longitude: coordinate.longitude)
        }
    }

    // MARK: - Coordinate transform

    func testMainlandCoordinatesAreShiftedForMapKit() {
        let raw = JSONValue.object([
            "track": .array([
                .array([.number(39.90869), .number(116.39123)]),
                .array([.number(39.91869), .number(116.40123)]),
            ])
        ])

        let coordinates = detail(raw).interfaceTrackCoordinates
        XCTAssertEqual(coordinates.count, 2)
        // GCJ-02 offset in Beijing: a few hundred metres, never zero.
        XCTAssertNotEqual(coordinates[0].latitude, 39.90869)
        XCTAssertNotEqual(coordinates[0].longitude, 116.39123)
        XCTAssertLessThan(abs(coordinates[0].latitude - 39.90869), 0.01)
        XCTAssertLessThan(abs(coordinates[0].longitude - 116.39123), 0.01)
    }

    // MARK: - NinebotInterfaceTrackPoint

    func testInterfaceTrackPointExposesItsCoordinate() {
        let point = NinebotInterfaceTrackPoint(
            id: "p-1",
            latitude: 35.5,
            longitude: 139.5,
            speedKmh: 21,
            auxiliaryValue: 90
        )

        XCTAssertEqual(point.id, "p-1")
        assertCoordinate(point.coordinate, latitude: 35.5, longitude: 139.5)
        XCTAssertEqual(
            point,
            NinebotInterfaceTrackPoint(
                id: "p-1",
                latitude: 35.5,
                longitude: 139.5,
                speedKmh: 21,
                auxiliaryValue: 90
            )
        )
    }

    // MARK: - Detail identity

    func testRideDetailIdentityAndRawObject() {
        let raw = JSONValue.object(["mileage": .number(12.3)])
        let rideDetail = detail(raw)

        XCTAssertEqual(rideDetail.id, "SN-TEST|RIDE-1")
        XCTAssertEqual(rideDetail.rawObject?["mileage"]?.doubleValue, 12.3)
        XCTAssertNil(detail(.array([])).rawObject)
        XCTAssertNil(rideDetail.parsedRecord)
    }
}

/// `NinebotRideRecord.stableIdentityKey` is what `NinebotSharedStore` uses to
/// merge freshly fetched rides with stored ones, so its tiering and formatting
/// are pinned here.
final class RideRecordIdentityTests: XCTestCase {
    private func record(
        id: String = "generated-id",
        startedAt: Date? = nil,
        endedAt: Date? = nil,
        mileage: Double? = nil,
        energy: Double? = nil,
        usedElectricity: Double? = nil,
        durationMinutes: Double? = nil,
        speed: Double? = nil,
        raw: [String: JSONValue]? = nil
    ) -> NinebotRideRecord {
        NinebotRideRecord(
            id: id,
            startedAt: startedAt,
            endedAt: endedAt,
            mileage: mileage,
            energy: energy,
            usedElectricity: usedElectricity,
            durationMinutes: durationMinutes,
            speed: speed,
            raw: raw
        )
    }

    // MARK: - Tier 1: travel id

    func testTravelIdentifierWins() {
        let key = record(raw: ["travel_id": .string("T-1")]).stableIdentityKey
        XCTAssertEqual(key, "travel:travel_id=T-1")
    }

    func testCamelCaseTravelIdentifier() {
        XCTAssertEqual(
            record(raw: ["travelId": .string("T-1")]).stableIdentityKey,
            "travel:travelId=T-1"
        )
    }

    func testNumericTravelIdentifierIsStringified() {
        XCTAssertEqual(
            record(raw: ["travel_id": .number(4321)]).stableIdentityKey,
            "travel:travel_id=4321"
        )
    }

    func testTravelIdentifierBeatsEveryOtherTier() {
        let key = record(
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            raw: [
                "travel_id": .string("T-1"),
                "ride_id": .string("R-1"),
                "start_time": .string("2024-05-01 08:00:00"),
            ]
        ).stableIdentityKey
        XCTAssertEqual(key, "travel:travel_id=T-1")
    }

    // MARK: - Tier 2: explicit identifier

    func testExplicitIdentifierTier() {
        XCTAssertEqual(
            record(raw: ["record_id": .number(42)]).stableIdentityKey,
            "id:record_id=42"
        )
    }

    func testExplicitIdentifierKeyPrecedence() {
        // "ride_id" comes before "id" in the lookup order.
        let key = record(raw: ["id": .string("X"), "ride_id": .string("R")]).stableIdentityKey
        XCTAssertEqual(key, "id:ride_id=R")
    }

    // MARK: - Tier 3: raw timestamps

    func testRawTimestampTierFallsBackToComputedMetrics() {
        let key = record(
            mileage: 12.34,
            usedElectricity: 4,
            raw: ["start_time": .string("2024-05-01 08:00:00")]
        ).stableIdentityKey
        XCTAssertEqual(key, "raw:start=start_time=2024-05-01 08:00:00|end=none|km=1234|used=400")
    }

    func testRawTimestampTierPrefersRawMetrics() {
        let key = record(
            mileage: 12.34,
            usedElectricity: 4,
            raw: [
                "start_time": .string("A"),
                "end_time": .string("B"),
                "mileage": .string("12.5"),
                "used_electricity": .number(3),
            ]
        ).stableIdentityKey
        XCTAssertEqual(key, "raw:start=start_time=A|end=end_time=B|km=mileage=12.5|used=used_electricity=3")
    }

    // MARK: - Tier 4: parsed dates

    func testParsedDateTier() {
        let key = record(
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: Date(timeIntervalSince1970: 1_700_000_600),
            mileage: 12.34,
            usedElectricity: 4
        ).stableIdentityKey
        XCTAssertEqual(key, "start:1700000000|end:1700000600|km:1234|used:400")
    }

    func testParsedDateTierWithoutAnEndDate() {
        let key = record(startedAt: Date(timeIntervalSince1970: 1_700_000_000)).stableIdentityKey
        XCTAssertEqual(key, "start:1700000000|end:none|km:none|used:none")
    }

    // MARK: - Tier 5: fallback

    func testFallbackTierUsesTheGeneratedIdentifier() {
        let key = record(
            id: "abc",
            mileage: 12.34,
            energy: 200,
            usedElectricity: 4,
            durationMinutes: 10,
            speed: 27.6
        ).stableIdentityKey
        XCTAssertEqual(key, "fallback:abc|km:1234|energy:2000|used:400|duration:100|speed:276")
    }

    func testFallbackTierWithNoMetrics() {
        XCTAssertEqual(
            record(id: "abc").stableIdentityKey,
            "fallback:abc|km:none|energy:none|used:none|duration:none|speed:none"
        )
    }

    func testEmptyRawDictionaryFallsThrough() {
        XCTAssertEqual(
            record(id: "abc", raw: [:]).stableIdentityKey,
            "fallback:abc|km:none|energy:none|used:none|duration:none|speed:none"
        )
    }

    // MARK: - Value filtering

    func testBlankRawValuesAreSkipped() {
        let key = record(raw: [
            "travel_id": .string("   "),
            "ride_id": .string("R-9"),
        ]).stableIdentityKey
        XCTAssertEqual(key, "id:ride_id=R-9")
    }

    func testNullRawValuesAreSkipped() {
        let key = record(raw: [
            "travel_id": .null,
            "ride_id": .string("R-9"),
        ]).stableIdentityKey
        XCTAssertEqual(key, "id:ride_id=R-9")
    }

    func testRawValuesAreTrimmed() {
        XCTAssertEqual(
            record(raw: ["travel_id": .string("  T-1  ")]).stableIdentityKey,
            "travel:travel_id=T-1"
        )
    }

    // MARK: - Merge behaviour

    func testTheSameRideKeepsItsKeyAcrossFetches() {
        // The synthesised `id` differs between fetches; the travel id does not.
        let first = record(id: "fetch-1-0", mileage: 12.34, raw: ["travel_id": .string("T-1")])
        let second = record(id: "fetch-2-7", mileage: 12.34, raw: ["travel_id": .string("T-1")])
        XCTAssertEqual(first.stableIdentityKey, second.stableIdentityKey)
    }

    func testDifferentRidesGetDifferentKeys() {
        let first = record(raw: ["travel_id": .string("T-1")])
        let second = record(raw: ["travel_id": .string("T-2")])
        XCTAssertNotEqual(first.stableIdentityKey, second.stableIdentityKey)
    }

    func testKeysFromDifferentTiersDoNotCollide() {
        let keys = [
            record(raw: ["travel_id": .string("1")]).stableIdentityKey,
            record(raw: ["ride_id": .string("1")]).stableIdentityKey,
            record(raw: ["start_time": .string("1")]).stableIdentityKey,
            record(startedAt: Date(timeIntervalSince1970: 1)).stableIdentityKey,
            record(id: "1").stableIdentityKey,
        ]
        XCTAssertEqual(Set(keys).count, keys.count)
    }
}
