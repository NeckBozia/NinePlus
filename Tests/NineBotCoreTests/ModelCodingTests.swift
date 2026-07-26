import CoreLocation
import XCTest
@testable import NineBotCore

/// Encode/decode round trips plus the backward-compatibility contract: every
/// optional field is decoded with `decodeIfPresent`, so payloads written before
/// a field existed must still decode.
final class ModelCodingTests: XCTestCase {
    /// Dates encode as seconds since 2001-01-01, so this instant appears in the
    /// hand-written JSON fixtures below as 1_700_000_000 - 978_307_200 = 721_692_800.
    private let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func encoded<T: Encodable>(_ value: T) throws -> Data {
        try JSONEncoder().encode(value)
    }

    private func roundTrip<T: Codable & Equatable>(_ value: T, file: StaticString = #filePath, line: UInt = #line) throws {
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(T.self, from: data)
        XCTAssertEqual(decoded, value, file: file, line: line)
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    private func vehicle(sn: String) -> NinebotVehicleInfo {
        NinebotVehicleInfo(
            sn: sn,
            name: "Bike \(sn)",
            model: "Ninebot E",
            imageURLString: "https://example.com/\(sn).png",
            raw: ["vin": .string("VIN-\(sn)"), "auth_date": .number(1_700_000_000)]
        )
    }

    private func state(battery: Int? = 80) -> NinebotVehicleState {
        NinebotVehicleState(
            battery: battery,
            batteryVoltage: 52.5,
            endurance: 42.5,
            isCharging: false,
            isLocked: true,
            totalMileage: 1048.5,
            updatedAt: referenceDate
        )
    }

    // MARK: - Server configuration

    func testServerConfigurationRoundTrip() throws {
        try roundTrip(
            NinebotServerConfiguration(
                baseURLString: "http://192.168.1.10:8000",
                bearerToken: "token",
                appSessionToken: "session"
            )
        )
    }

    func testServerConfigurationDecodesWithoutTheAppSessionToken() throws {
        // appSessionToken was added later; payloads written before it must load.
        let configuration = try decode(
            NinebotServerConfiguration.self,
            #"{"baseURLString":"http://192.168.1.10:8000","bearerToken":"token"}"#
        )
        XCTAssertNil(configuration.appSessionToken)
        XCTAssertEqual(configuration.baseURLString, "http://192.168.1.10:8000")
        XCTAssertTrue(configuration.isUsable)
    }

    func testBaseURLAddsAMissingScheme() {
        let configuration = NinebotServerConfiguration(baseURLString: "192.168.1.10:8000", bearerToken: "t")
        XCTAssertEqual(configuration.baseURL?.absoluteString, "http://192.168.1.10:8000")
    }

    func testBaseURLKeepsAnExplicitScheme() {
        let configuration = NinebotServerConfiguration(baseURLString: "https://example.com", bearerToken: "t")
        XCTAssertEqual(configuration.baseURL?.absoluteString, "https://example.com")
    }

    func testBaseURLTrimsWhitespaceAndTrailingSlashes() {
        let configuration = NinebotServerConfiguration(baseURLString: "  https://example.com/  ", bearerToken: "t")
        XCTAssertEqual(configuration.baseURL?.absoluteString, "https://example.com")
    }

    func testBaseURLIsNilWhenBlank() {
        XCTAssertNil(NinebotServerConfiguration(baseURLString: "", bearerToken: "t").baseURL)
        XCTAssertNil(NinebotServerConfiguration(baseURLString: "   ", bearerToken: "t").baseURL)
        XCTAssertFalse(NinebotServerConfiguration(baseURLString: "  ", bearerToken: "t").isUsable)
    }

    // MARK: - Login result

    func testLoginResultRoundTrip() throws {
        try roundTrip(
            NinebotLoginResult(
                uuid: "u-1",
                phone: "13800000000",
                areaCode: "86",
                region: "CN",
                businessUID: "b-1",
                accountID: 42,
                sessionToken: "s-1"
            )
        )
    }

    func testLoginResultDecodesAnEmptyObject() throws {
        // Every field is optional, so a server that returns {} must not throw.
        let result = try decode(NinebotLoginResult.self, "{}")
        XCTAssertNil(result.uuid)
        XCTAssertNil(result.phone)
        XCTAssertNil(result.areaCode)
        XCTAssertNil(result.region)
        XCTAssertNil(result.businessUID)
        XCTAssertNil(result.accountID)
        XCTAssertNil(result.sessionToken)
    }

    func testLoginResultDecodesAPartialPayload() throws {
        let result = try decode(NinebotLoginResult.self, #"{"uuid":"u-1","accountID":7}"#)
        XCTAssertEqual(result.uuid, "u-1")
        XCTAssertEqual(result.accountID, 7)
        XCTAssertNil(result.sessionToken)
    }

    // MARK: - Vehicle info

    func testVehicleInfoRoundTripPreservesRawJSON() throws {
        try roundTrip(vehicle(sn: "SN-1"))
    }

    func testVehicleInfoDecodesWithoutOptionalFields() throws {
        let info = try decode(NinebotVehicleInfo.self, #"{"sn":"SN-1","name":"Bike","model":"E"}"#)
        XCTAssertNil(info.imageURLString)
        XCTAssertNil(info.raw)
        XCTAssertNil(info.vin)
        XCTAssertNil(info.authDate)
        XCTAssertEqual(info.id, "SN-1")
        XCTAssertEqual(info.identifierSummaryText, "SN SN-1")
    }

    func testVehicleInfoIdentifierSummaryIncludesTheVIN() {
        XCTAssertEqual(vehicle(sn: "SN-1").identifierSummaryText, "SN SN-1 · VIN VIN-SN-1")
    }

    func testAuthDateAcceptsSecondsMillisecondsAndStrings() {
        func info(_ value: JSONValue) -> NinebotVehicleInfo {
            NinebotVehicleInfo(sn: "S", name: "N", model: "M", imageURLString: nil, raw: ["auth_date": value])
        }

        XCTAssertEqual(info(.number(1_700_000_000)).authDate, referenceDate)
        XCTAssertEqual(info(.number(1_700_000_000_000)).authDate, referenceDate)
        XCTAssertEqual(info(.string("1700000000")).authDate, referenceDate)
        XCTAssertNil(info(.number(0)).authDate)
        XCTAssertNil(info(.string("not-a-date")).authDate)
    }

    func testImageURLSelectionFollowsTheAppearance() {
        let info = NinebotVehicleInfo(
            sn: "S",
            name: "N",
            model: "M",
            imageURLString: "fallback",
            raw: [
                "v6_light_img_url": .string("light"),
                "v6_dark_img_url": .string("dark"),
            ]
        )
        XCTAssertEqual(info.imageURLString(prefersDarkImage: true), "dark")
        XCTAssertEqual(info.imageURLString(prefersDarkImage: false), "light")
    }

    func testImageURLFallsBackWhenTheAppearanceVariantIsMissing() {
        let lightOnly = NinebotVehicleInfo(
            sn: "S",
            name: "N",
            model: "M",
            imageURLString: "fallback",
            raw: ["img_url": .string("light")]
        )
        XCTAssertEqual(lightOnly.imageURLString(prefersDarkImage: true), "light")

        let none = NinebotVehicleInfo(sn: "S", name: "N", model: "M", imageURLString: "fallback", raw: nil)
        XCTAssertEqual(none.imageURLString(prefersDarkImage: true), "fallback")
        XCTAssertEqual(none.imageURLString(prefersDarkImage: false), "fallback")
    }

    // MARK: - Vehicle state and snapshots

    func testVehicleStateRoundTrip() throws {
        try roundTrip(state())
    }

    func testVehicleStateDecodesALegacyPayloadWithOnlyTheTimestamp() throws {
        // Every field except updatedAt is optional, so the oldest cached states
        // still decode after later fields were introduced.
        let decoded = try decode(NinebotVehicleState.self, #"{"updatedAt":721692800}"#)
        XCTAssertEqual(decoded.updatedAt, referenceDate)
        XCTAssertNil(decoded.battery)
        XCTAssertNil(decoded.serverPrediction)
        XCTAssertNil(decoded.rideRecords)
        XCTAssertNil(decoded.dailyMileageRecords)
        XCTAssertNil(decoded.rawStatus)
        XCTAssertEqual(decoded.batteryText, "--%")
    }

    func testVehicleStateRoundTripWithServerPrediction() throws {
        var value = state()
        value.serverPrediction = NinebotServerPrediction(
            modelVersion: "v1",
            updatedAt: referenceDate,
            batteryPercent: 80,
            batteryChemistry: NinebotBatteryChemistryInfo(
                configured: .lithium,
                effective: "lithium",
                source: "manual",
                nominalVoltage: 48,
                capacityWh: 960,
                capacityAh: 20
            ),
            range: NinebotServerRangePrediction(estimatedRange: 40, kmPerPercent: 0.5, sampleCount: 12),
            charging: NinebotServerChargingPrediction(isCharging: false, remainingMinutes: 0)
        )
        try roundTrip(value)
    }

    func testServerPredictionDecodesWithEmptySubObjects() throws {
        let prediction = try decode(NinebotServerPrediction.self, #"{"range":{},"charging":{}}"#)
        XCTAssertNil(prediction.modelVersion)
        XCTAssertNil(prediction.updatedAt)
        XCTAssertNil(prediction.batteryPercent)
        XCTAssertNil(prediction.batteryChemistry)
        XCTAssertNil(prediction.range.estimatedRange)
        XCTAssertNil(prediction.range.isReady)
        XCTAssertNil(prediction.charging.remainingMinutes)
        XCTAssertNil(prediction.charging.estimatedFullAt)
    }

    func testBatteryChemistryInfoDecodesRawValuesAndDefaultsSpecs() throws {
        let info = try decode(
            NinebotBatteryChemistryInfo.self,
            #"{"configured":"lead_acid","effective":"lead_acid","source":"manual"}"#
        )
        XCTAssertEqual(info.configured, .leadAcid)
        XCTAssertEqual(info.effectiveTitle, "铅酸电池")
        XCTAssertNil(info.nominalVoltage)
        XCTAssertEqual(info.specificationText, "未填写电压与容量")
    }

    func testBatteryChemistrySpecificationText() {
        let info = NinebotBatteryChemistryInfo(
            configured: .lithium,
            effective: "lithium",
            source: "auto",
            nominalVoltage: 48,
            capacityWh: 960,
            capacityAh: nil
        )
        XCTAssertEqual(info.specificationText, "48 V · 960 Wh")
        XCTAssertEqual(info.effectiveTitle, "锂电池")
    }

    func testBatteryChemistryRawValues() {
        XCTAssertEqual(NinebotBatteryChemistry.leadAcid.rawValue, "lead_acid")
        XCTAssertEqual(NinebotBatteryChemistry.lithium.rawValue, "lithium")
        XCTAssertEqual(NinebotBatteryChemistry.auto.rawValue, "auto")
        XCTAssertEqual(NinebotBatteryChemistry.allCases.count, 3)
    }

    func testVehicleSnapshotRoundTrip() throws {
        let snapshot = NinebotVehicleSnapshot(vehicle: vehicle(sn: "SN-1"), state: state())
        XCTAssertEqual(snapshot.id, "SN-1")
        try roundTrip(snapshot)
    }

    // MARK: - Dashboard

    func testDashboardRoundTrip() throws {
        let dashboard = NinebotDashboard(
            vehicles: [
                NinebotVehicleSnapshot(vehicle: vehicle(sn: "SN-1"), state: state()),
                NinebotVehicleSnapshot(vehicle: vehicle(sn: "SN-2"), state: state(battery: 40)),
            ],
            selectedSN: "SN-2",
            updatedAt: referenceDate
        )
        try roundTrip(dashboard)
    }

    func testDashboardDecodesWithoutASelection() throws {
        let dashboard = try decode(
            NinebotDashboard.self,
            #"{"vehicles":[],"updatedAt":721692800}"#
        )
        XCTAssertNil(dashboard.selectedSN)
        XCTAssertTrue(dashboard.vehicles.isEmpty)
        XCTAssertNil(dashboard.primaryVehicle)
        XCTAssertEqual(dashboard.updatedAt, referenceDate)
    }

    func testPrimaryVehiclePrefersTheSelection() {
        let dashboard = NinebotDashboard(
            vehicles: [
                NinebotVehicleSnapshot(vehicle: vehicle(sn: "SN-1"), state: state()),
                NinebotVehicleSnapshot(vehicle: vehicle(sn: "SN-2"), state: state()),
            ],
            selectedSN: "SN-2",
            updatedAt: referenceDate
        )
        XCTAssertEqual(dashboard.primaryVehicle?.id, "SN-2")
    }

    func testPrimaryVehicleFallsBackToTheFirstEntry() {
        var dashboard = NinebotDashboard(
            vehicles: [
                NinebotVehicleSnapshot(vehicle: vehicle(sn: "SN-1"), state: state()),
                NinebotVehicleSnapshot(vehicle: vehicle(sn: "SN-2"), state: state()),
            ],
            selectedSN: nil,
            updatedAt: referenceDate
        )
        XCTAssertEqual(dashboard.primaryVehicle?.id, "SN-1")

        // An unknown selection (a vehicle that was unbound) must not blank out
        // the dashboard.
        dashboard.selectedSN = "SN-GONE"
        XCTAssertEqual(dashboard.primaryVehicle?.id, "SN-1")
    }

    func testEmptyDashboardConstant() {
        XCTAssertTrue(NinebotDashboard.empty.vehicles.isEmpty)
        XCTAssertNil(NinebotDashboard.empty.selectedSN)
        XCTAssertNil(NinebotDashboard.empty.primaryVehicle)
        XCTAssertEqual(NinebotDashboard.empty.updatedAt, .distantPast)
    }

    // MARK: - Ride records and details

    func testRideRecordRoundTripPreservesRawJSON() throws {
        try roundTrip(
            NinebotRideRecord(
                id: "R-1",
                startedAt: referenceDate,
                endedAt: referenceDate.addingTimeInterval(600),
                mileage: 4.5,
                energy: 200,
                usedElectricity: 4,
                durationMinutes: 10,
                speed: 27.5,
                raw: [
                    "travel_id": .string("T-1"),
                    "nested": .object(["list": .array([.number(1), .bool(true), .null])]),
                ]
            )
        )
    }

    func testRideRecordDecodesWithOnlyAnIdentifier() throws {
        let record = try decode(NinebotRideRecord.self, #"{"id":"R-1"}"#)
        XCTAssertEqual(record.id, "R-1")
        XCTAssertNil(record.startedAt)
        XCTAssertNil(record.mileage)
        XCTAssertNil(record.raw)
    }

    func testRideDetailRoundTrip() throws {
        try roundTrip(
            NinebotRideDetail(
                vehicleSN: "SN-1",
                rideID: "R-1",
                fetchedAt: referenceDate,
                raw: .object([
                    "mileage": .number(4.5),
                    "trial": .array([
                        .array([.number(35.5), .number(139.5)]),
                        .array([.number(35.6), .number(139.6)]),
                    ]),
                ]),
                parsedRecord: NinebotRideRecord(id: "R-1", mileage: 4.5)
            )
        )
    }

    func testRideDetailDecodesWithoutAParsedRecord() throws {
        let detail = try decode(
            NinebotRideDetail.self,
            #"{"vehicleSN":"SN-1","rideID":"R-1","fetchedAt":721692800,"raw":{"mileage":4.5}}"#
        )
        XCTAssertNil(detail.parsedRecord)
        XCTAssertEqual(detail.id, "SN-1|R-1")
        XCTAssertEqual(detail.fetchedAt, referenceDate)
        XCTAssertEqual(detail.rawObject?["mileage"]?.doubleValue, 4.5)
    }

    func testRideDetailSurvivesEncodingWithTrackDataIntact() throws {
        let original = NinebotRideDetail(
            vehicleSN: "SN-1",
            rideID: "R-1",
            fetchedAt: referenceDate,
            raw: .object([
                "trial": .array([
                    .array([.number(35.5), .number(139.5)]),
                    .array([.number(35.6), .number(139.6)]),
                ])
            ])
        )
        let decoded = try JSONDecoder().decode(NinebotRideDetail.self, from: encoded(original))
        XCTAssertEqual(decoded.interfaceTrackCoordinates.count, 2)
        XCTAssertEqual(decoded.interfaceTrackCoordinates.first?.latitude, 35.5)
    }

    // MARK: - Small value types

    func testDailyMileageRecordRoundTrip() throws {
        try roundTrip(NinebotDailyMileageRecord(id: "d-1", day: 3, date: referenceDate, mileage: 18.5))
        let withoutDate = try decode(
            NinebotDailyMileageRecord.self,
            #"{"id":"d-1","day":3,"mileage":18.5}"#
        )
        XCTAssertNil(withoutDate.date)
    }

    func testResolvedAddressRoundTrip() throws {
        try roundTrip(
            NinebotResolvedAddress(
                sn: "SN-1",
                address: "河畔花园",
                latitude: 31.25,
                longitude: 121.5,
                updatedAt: referenceDate,
                source: "amap"
            )
        )
        let legacy = try decode(
            NinebotResolvedAddress.self,
            #"{"sn":"SN-1","address":"A","latitude":31.25,"longitude":121.5,"updatedAt":721692800}"#
        )
        XCTAssertNil(legacy.source)
    }

    func testRefreshEventDurationAndRoundTrip() throws {
        let event = NinebotRefreshEvent(
            source: "widget",
            operation: "refresh",
            startedAt: referenceDate,
            endedAt: referenceDate.addingTimeInterval(2.5),
            success: true,
            message: nil
        )
        XCTAssertEqual(event.durationSeconds, 2.5, accuracy: 1e-9)
        try roundTrip(event)

        // A clock that ran backwards must never produce a negative duration.
        let reversed = NinebotRefreshEvent(
            source: "widget",
            operation: "refresh",
            startedAt: referenceDate.addingTimeInterval(2.5),
            endedAt: referenceDate,
            success: false,
            message: "failed"
        )
        XCTAssertEqual(reversed.durationSeconds, 0)
    }

    func testLiveActivityPushTokenRecordRoundTrip() throws {
        let record = NinebotLiveActivityPushTokenRecord(
            activityID: "a-1",
            token: "t-1",
            vehicleSN: "SN-1",
            updatedAt: referenceDate
        )
        XCTAssertEqual(record.id, "a-1")
        try roundTrip(record)

        let withoutSN = try decode(
            NinebotLiveActivityPushTokenRecord.self,
            #"{"activityID":"a-1","token":"t-1","updatedAt":721692800}"#
        )
        XCTAssertNil(withoutSN.vehicleSN)
    }

    func testPendingAppRouteRoundTrip() throws {
        for route in [
            NinebotPendingAppRoute.dashboard,
            .trips,
            .recording,
            .settings,
        ] {
            let data = try JSONEncoder().encode([route])
            XCTAssertEqual(try JSONDecoder().decode([NinebotPendingAppRoute].self, from: data), [route])
        }
        XCTAssertEqual(NinebotPendingAppRoute.recording.rawValue, "recording")
    }

    func testVehicleHealthRoundTrip() throws {
        try roundTrip(
            NinebotVehicleHealth(
                level: .attention,
                title: "电量偏低",
                message: "建议尽快充电",
                systemImage: "battery.25"
            )
        )
        XCTAssertEqual(NinebotVehicleHealthLevel.critical.rawValue, "critical")
    }
}

/// `trackCoordinates` filters and transforms; `sampledTrackCoordinates` thins
/// the result for map rendering.  Coordinates sit outside mainland China so the
/// GCJ-02 transform is a no-op and the expected values stay exact.
final class RecordedRideTrackSamplingTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func point(
        index: Int,
        latitude: Double,
        longitude: Double = 139.5,
        accuracy: Double? = 10
    ) -> NinebotRideTrackPoint {
        NinebotRideTrackPoint(
            date: start.addingTimeInterval(Double(index) * 5),
            latitude: latitude,
            longitude: longitude,
            speedKmh: 20,
            accelerationG: 0.1,
            horizontalAccuracy: accuracy
        )
    }

    private func ride(points: [NinebotRideTrackPoint]) -> NinebotRecordedRide {
        NinebotRecordedRide(
            id: "ride-1",
            vehicleSN: "SN-1",
            startedAt: start,
            endedAt: start.addingTimeInterval(600),
            distanceMeters: 1_000,
            maxSpeedKmh: 42,
            averageSpeedKmh: 21,
            maxAccelerationG: 0.4,
            points: points
        )
    }

    private func line(count: Int, accuracy: Double? = 10) -> [NinebotRideTrackPoint] {
        (0..<count).map { point(index: $0, latitude: 35.5 + Double($0) * 0.0001, accuracy: accuracy) }
    }

    // MARK: - trackCoordinates

    func testTrackCoordinatesFollowTheStoredPoints() {
        let coordinates = ride(points: line(count: 3)).trackCoordinates
        XCTAssertEqual(coordinates.count, 3)
        XCTAssertEqual(coordinates[0].latitude, 35.5, accuracy: 1e-9)
        XCTAssertEqual(coordinates[0].longitude, 139.5, accuracy: 1e-9)
        XCTAssertEqual(coordinates[2].latitude, 35.5002, accuracy: 1e-9)
    }

    func testTrackCoordinatesAreSortedByDate() {
        let ordered = line(count: 3)
        let coordinates = ride(points: [ordered[2], ordered[0], ordered[1]]).trackCoordinates
        XCTAssertEqual(coordinates.map(\.latitude), ordered.map(\.latitude))
    }

    func testTrackCoordinatesDropInaccuratePoints() {
        let points = [
            point(index: 0, latitude: 35.5),
            point(index: 1, latitude: 35.6, accuracy: 500),
            point(index: 2, latitude: 35.7),
        ]
        let coordinates = ride(points: points).trackCoordinates
        XCTAssertEqual(coordinates.count, 2)
        XCTAssertEqual(coordinates.map(\.latitude), [35.5, 35.7])
    }

    func testTrackCoordinatesKeepPointsWithoutAnAccuracyReading() {
        let points = [
            point(index: 0, latitude: 35.5, accuracy: nil),
            point(index: 1, latitude: 35.6, accuracy: nil),
        ]
        XCTAssertEqual(ride(points: points).trackCoordinates.count, 2)
    }

    func testTrackCoordinatesDropOutOfRangePoints() {
        let points = [
            point(index: 0, latitude: 35.5),
            point(index: 1, latitude: 91),
            point(index: 2, latitude: 35.7, longitude: 181),
            point(index: 3, latitude: 35.8),
        ]
        let coordinates = ride(points: points).trackCoordinates
        XCTAssertEqual(coordinates.count, 2)
        XCTAssertEqual(coordinates.map(\.latitude), [35.5, 35.8])
    }

    func testTrackCoordinatesOfASummaryAreEmpty() {
        // A summary has no points, so a map must load the track first.
        let summary = ride(points: line(count: 10)).trackSummary()
        XCTAssertTrue(summary.trackCoordinates.isEmpty)
        XCTAssertTrue(summary.sampledTrackCoordinates().isEmpty)
    }

    // MARK: - sampledTrackCoordinates

    func testSamplingReturnsEverythingBelowTheCap() {
        let recorded = ride(points: line(count: 5))
        let sampled = recorded.sampledTrackCoordinates()
        XCTAssertEqual(sampled.count, 5)
        XCTAssertEqual(sampled.map(\.latitude), recorded.trackCoordinates.map(\.latitude))
    }

    func testSamplingReturnsEverythingExactlyAtTheCap() {
        let sampled = ride(points: line(count: 120)).sampledTrackCoordinates()
        XCTAssertEqual(sampled.count, 120)
    }

    func testSamplingThinsToTheDefaultCap() {
        let recorded = ride(points: line(count: 300))
        let sampled = recorded.sampledTrackCoordinates()
        let full = recorded.trackCoordinates

        XCTAssertEqual(sampled.count, 120)
        XCTAssertEqual(sampled.first?.latitude, full.first?.latitude)
        XCTAssertEqual(sampled.last?.latitude, full.last?.latitude)
    }

    func testSamplingHonoursACustomCap() {
        let recorded = ride(points: line(count: 100))
        let sampled = recorded.sampledTrackCoordinates(maxCount: 10)

        XCTAssertEqual(sampled.count, 10)
        XCTAssertEqual(sampled.first?.latitude, recorded.trackCoordinates.first?.latitude)
        XCTAssertEqual(sampled.last?.latitude, recorded.trackCoordinates.last?.latitude)
    }

    func testSamplingKeepsTheTrackOrder() {
        let sampled = ride(points: line(count: 300)).sampledTrackCoordinates()
        let latitudes = sampled.map(\.latitude)
        XCTAssertEqual(latitudes, latitudes.sorted())
    }

    func testSamplingWithACapBelowTwoReturnsTheWholeTrack() {
        // The guard requires maxCount > 1, otherwise the track is returned as is.
        let recorded = ride(points: line(count: 5))
        XCTAssertEqual(recorded.sampledTrackCoordinates(maxCount: 1).count, 5)
        XCTAssertEqual(recorded.sampledTrackCoordinates(maxCount: 0).count, 5)
    }

    func testSamplingWithACapOfTwoKeepsTheEndpoints() {
        let recorded = ride(points: line(count: 5))
        let sampled = recorded.sampledTrackCoordinates(maxCount: 2)
        XCTAssertEqual(sampled.count, 2)
        XCTAssertEqual(sampled[0].latitude, 35.5, accuracy: 1e-9)
        XCTAssertEqual(sampled[1].latitude, 35.5004, accuracy: 1e-9)
    }

    func testSamplingAnEmptyTrack() {
        XCTAssertTrue(ride(points: []).sampledTrackCoordinates().isEmpty)
    }

    func testSamplingCountsOnlyPointsThatSurviveFiltering() {
        // 200 points, half of them unusable, leaves 100 — below the cap.
        let points = (0..<200).map {
            point(index: $0, latitude: 35.5 + Double($0) * 0.0001, accuracy: $0.isMultiple(of: 2) ? 10 : 500)
        }
        XCTAssertEqual(ride(points: points).sampledTrackCoordinates().count, 100)
    }

    func testMainlandTracksAreShiftedForMapKit() {
        let points = [
            point(index: 0, latitude: 39.90869, longitude: 116.39123),
            point(index: 1, latitude: 39.91869, longitude: 116.40123),
        ]
        let coordinates = ride(points: points).trackCoordinates
        XCTAssertEqual(coordinates.count, 2)
        XCTAssertNotEqual(coordinates[0].latitude, 39.90869)
        XCTAssertLessThan(abs(coordinates[0].latitude - 39.90869), 0.01)
        XCTAssertLessThan(abs(coordinates[0].longitude - 116.39123), 0.01)
    }
}

/// `NinebotVehicleHistoryPoint` snapshots a state for the trend chart; the
/// summary derives the deltas shown above it.
final class VehicleHistoryTests: XCTestCase {
    private func state(
        battery: Int?,
        totalMileage: Double?,
        at seconds: TimeInterval
    ) -> NinebotVehicleState {
        NinebotVehicleState(
            battery: battery,
            endurance: 42.5,
            isCharging: true,
            isPoweredOn: false,
            isLocked: true,
            totalMileage: totalMileage,
            updatedAt: Date(timeIntervalSince1970: seconds)
        )
    }

    private func point(
        battery: Int? = 80,
        totalMileage: Double? = 100,
        at seconds: TimeInterval = 1_700_000_000,
        sn: String = "SN-1"
    ) -> NinebotVehicleHistoryPoint {
        NinebotVehicleHistoryPoint(sn: sn, state: state(battery: battery, totalMileage: totalMileage, at: seconds))
    }

    // MARK: - Point

    func testPointCopiesTheStateAndDerivesAnIdentifier() {
        let value = point(battery: 73, totalMileage: 1234.5, at: 1_700_000_000)

        XCTAssertEqual(value.id, "SN-1-1700000000")
        XCTAssertEqual(value.sn, "SN-1")
        XCTAssertEqual(value.date, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(value.battery, 73)
        XCTAssertEqual(value.endurance, 42.5)
        XCTAssertEqual(value.totalMileage, 1234.5)
        XCTAssertEqual(value.isCharging, true)
        XCTAssertEqual(value.isPoweredOn, false)
        XCTAssertEqual(value.isLocked, true)
    }

    func testPointCarriesMissingReadingsThrough() {
        let value = point(battery: nil, totalMileage: nil)
        XCTAssertNil(value.battery)
        XCTAssertNil(value.totalMileage)
    }

    func testPointRoundTripsThroughCodable() throws {
        let value = point(battery: 73, totalMileage: 1234.5)
        let data = try JSONEncoder().encode(value)
        XCTAssertEqual(try JSONDecoder().decode(NinebotVehicleHistoryPoint.self, from: data), value)
    }

    func testPointDecodesWithoutOptionalReadings() throws {
        let decoded = try JSONDecoder().decode(
            NinebotVehicleHistoryPoint.self,
            from: Data(#"{"id":"SN-1-1","sn":"SN-1","date":721692800}"#.utf8)
        )
        XCTAssertEqual(decoded.id, "SN-1-1")
        XCTAssertNil(decoded.battery)
        XCTAssertNil(decoded.endurance)
        XCTAssertNil(decoded.isCharging)
    }

    // MARK: - Summary

    func testSummaryIsNilWithoutPoints() {
        XCTAssertNil(NinebotVehicleHistorySummary(points: []))
    }

    func testSummaryOfASinglePoint() {
        let only = point(at: 1_700_000_000)
        let summary = NinebotVehicleHistorySummary(points: [only])
        XCTAssertEqual(summary?.sampleCount, 1)
        XCTAssertEqual(summary?.first, only)
        XCTAssertEqual(summary?.latest, only)
        XCTAssertEqual(summary?.batteryDelta, 0)
        XCTAssertEqual(summary?.periodText, "刚刚开始记录")
    }

    func testSummarySortsPointsByDate() {
        let oldest = point(battery: 90, totalMileage: 100, at: 1_700_000_000)
        let middle = point(battery: 80, totalMileage: 130, at: 1_700_003_600)
        let newest = point(battery: 70, totalMileage: 160, at: 1_700_007_200)

        let summary = NinebotVehicleHistorySummary(points: [middle, newest, oldest])
        XCTAssertEqual(summary?.first, oldest)
        XCTAssertEqual(summary?.latest, newest)
        XCTAssertEqual(summary?.sampleCount, 3)
    }

    func testSummaryDeltas() {
        let oldest = point(battery: 90, totalMileage: 100, at: 1_700_000_000)
        let newest = point(battery: 70, totalMileage: 160, at: 1_700_007_200)
        let summary = NinebotVehicleHistorySummary(points: [oldest, newest])

        XCTAssertEqual(summary?.batteryDelta, -20)
        XCTAssertEqual(summary?.mileageDelta ?? 0, 60, accuracy: 1e-9)
        XCTAssertEqual(summary?.batteryDeltaText, "-20%")
        XCTAssertEqual(summary?.mileageDeltaText, "+60 km")
    }

    func testPositiveBatteryDeltaIsSigned() {
        let oldest = point(battery: 40, totalMileage: 100, at: 1_700_000_000)
        let newest = point(battery: 95, totalMileage: 100, at: 1_700_007_200)
        let summary = NinebotVehicleHistorySummary(points: [oldest, newest])

        XCTAssertEqual(summary?.batteryDelta, 55)
        XCTAssertEqual(summary?.batteryDeltaText, "+55%")
        XCTAssertEqual(summary?.mileageDeltaText, "+0 km")
    }

    func testDeltasAreNilWhenAReadingIsMissing() {
        let oldest = point(battery: 90, totalMileage: 100, at: 1_700_000_000)
        let newest = point(battery: nil, totalMileage: nil, at: 1_700_007_200)
        let summary = NinebotVehicleHistorySummary(points: [oldest, newest])

        XCTAssertNil(summary?.batteryDelta)
        XCTAssertNil(summary?.mileageDelta)
        XCTAssertEqual(summary?.batteryDeltaText, "--%")
        XCTAssertEqual(summary?.mileageDeltaText, "-- km")
    }

    func testPeriodTextBuckets() {
        func periodText(spanSeconds: TimeInterval) -> String? {
            let start = point(at: 1_700_000_000)
            let end = point(at: 1_700_000_000 + spanSeconds)
            return NinebotVehicleHistorySummary(points: [start, end])?.periodText
        }

        XCTAssertEqual(periodText(spanSeconds: 0), "刚刚开始记录")

        let minutes = periodText(spanSeconds: 1_800)
        XCTAssertEqual(minutes?.hasSuffix(" 分钟"), true)
        XCTAssertEqual(minutes?.hasPrefix("30"), true)

        let hours = periodText(spanSeconds: 7_200)
        XCTAssertEqual(hours?.hasSuffix(" 小时"), true)
        XCTAssertEqual(hours?.hasPrefix("2"), true)

        let days = periodText(spanSeconds: 172_800)
        XCTAssertEqual(days?.hasSuffix(" 天"), true)
        XCTAssertEqual(days?.hasPrefix("2"), true)
    }
}
