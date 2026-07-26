import XCTest
@testable import NineBotCore

/// Covers everything in `NinebotSharedStore` except the recorded-ride track
/// storage, which lives in `SharedStoreTrackStorageTests`.
///
/// Each test runs against its own `UserDefaults` suite so the cases stay
/// independent.  The two pieces of state that escape the suite — vehicle image
/// blobs, which fall back to a file in the shared container — are keyed by a
/// per-test UUID serial number and cleaned up in `tearDown`.
final class SharedStoreTests: XCTestCase {
    /// These mirror `NinebotSharedStore.Key`, which is private.  Only the keys
    /// a test has to read or write directly are duplicated here.
    private let serverConfigurationKey = "ninebot.server.configuration"
    private let legacyConfigurationKey = "ninebot.proxy.configuration"

    private var suiteName = ""
    private var store = NinebotSharedStore()
    private var defaults = UserDefaults.standard
    private var imageSerialNumbers: [String] = []

    override func setUp() {
        super.setUp()
        suiteName = "com.nineplus.tests.\(UUID().uuidString)"
        store = NinebotSharedStore(suiteName: suiteName)
        defaults = UserDefaults(suiteName: suiteName) ?? .standard
        imageSerialNumbers = []
    }

    override func tearDown() {
        for sn in imageSerialNumbers {
            if let url = vehicleImageURL(sn: sn) {
                try? FileManager.default.removeItem(at: url)
            }
        }
        imageSerialNumbers = []
        UserDefaults().removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Helpers

    private let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func uniqueSN() -> String {
        "SN-\(UUID().uuidString)"
    }

    private func makeState(
        updatedAt: Date,
        battery: Int? = 80,
        endurance: Double? = 40,
        totalMileage: Double? = 1_234,
        rideRecords: [NinebotRideRecord]? = nil
    ) -> NinebotVehicleState {
        NinebotVehicleState(
            battery: battery,
            endurance: endurance,
            isCharging: false,
            isPoweredOn: true,
            isLocked: true,
            totalMileage: totalMileage,
            rideRecords: rideRecords,
            updatedAt: updatedAt
        )
    }

    private func makeDashboard(sn: String, state: NinebotVehicleState) -> NinebotDashboard {
        NinebotDashboard(
            vehicles: [
                NinebotVehicleSnapshot(
                    vehicle: NinebotVehicleInfo(sn: sn, name: "Test Vehicle", model: "Test Model"),
                    state: state
                )
            ],
            selectedSN: sn,
            updatedAt: state.updatedAt
        )
    }

    /// A ride record whose `stableIdentityKey` is driven purely by `travel_id`,
    /// so the other fields can vary freely without changing the merge key.
    private func makeRideRecord(
        travelID: String,
        mileage: Double,
        startedAt: Date
    ) -> NinebotRideRecord {
        NinebotRideRecord(
            id: UUID().uuidString,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(600),
            mileage: mileage,
            raw: ["travel_id": .string(travelID)]
        )
    }

    /// Mirrors the private `vehicleImageCacheURL(sn:)`.  Used only for cleanup,
    /// so a mismatch degrades to a leftover temp file rather than a failure.
    private func vehicleImageURL(sn: String) -> URL? {
        let baseURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: NinebotAppGroup.identifier
        ) ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first

        return baseURL?
            .appendingPathComponent("VehicleImages", isDirectory: true)
            .appendingPathComponent("\(sn).image")
    }

    // MARK: - Configuration

    func testLoadConfigurationReturnsNilWhenNothingIsStored() {
        XCTAssertNil(store.loadConfiguration())
    }

    func testConfigurationRoundTrips() {
        let configuration = NinebotServerConfiguration(
            baseURLString: "https://example.com",
            bearerToken: "token-1",
            appSessionToken: "session-1"
        )

        store.saveConfiguration(configuration)

        XCTAssertEqual(store.loadConfiguration(), configuration)
    }

    func testLoadConfigurationMigratesTheLegacyProxyKey() throws {
        let configuration = NinebotServerConfiguration(
            baseURLString: "10.0.0.2:8080",
            bearerToken: "legacy-token"
        )
        defaults.set(try JSONEncoder().encode(configuration), forKey: legacyConfigurationKey)
        XCTAssertNil(defaults.data(forKey: serverConfigurationKey))

        XCTAssertEqual(store.loadConfiguration(), configuration)

        // Migrated into the current key and the legacy copy dropped.
        XCTAssertNotNil(defaults.data(forKey: serverConfigurationKey))
        XCTAssertNil(defaults.data(forKey: legacyConfigurationKey))

        // A second read is served entirely by the migrated copy.
        XCTAssertEqual(store.loadConfiguration(), configuration)
    }

    func testLoadConfigurationPrefersTheCurrentKeyOverTheLegacyKey() throws {
        let current = NinebotServerConfiguration(baseURLString: "https://current", bearerToken: "current")
        let legacy = NinebotServerConfiguration(baseURLString: "https://legacy", bearerToken: "legacy")

        store.saveConfiguration(current)
        defaults.set(try JSONEncoder().encode(legacy), forKey: legacyConfigurationKey)

        XCTAssertEqual(store.loadConfiguration(), current)
        // Nothing was migrated, so the legacy key is left untouched.
        XCTAssertNotNil(defaults.data(forKey: legacyConfigurationKey))
    }

    func testLoadConfigurationReturnsNilForUndecodableData() {
        defaults.set(Data("not json".utf8), forKey: serverConfigurationKey)

        XCTAssertNil(store.loadConfiguration())
    }

    // MARK: - Login result

    func testLoginResultRoundTripsAndClears() {
        XCTAssertNil(store.loadLoginResult())

        let result = NinebotLoginResult(
            uuid: "uuid-1",
            phone: "13800000000",
            areaCode: "86",
            region: "CN",
            businessUID: "biz-1",
            accountID: 42,
            sessionToken: "session-1"
        )
        store.saveLoginResult(result)
        XCTAssertEqual(store.loadLoginResult(), result)

        store.clearLoginResult()
        XCTAssertNil(store.loadLoginResult())
    }

    func testSaveLoginResultOverwritesThePreviousValue() {
        store.saveLoginResult(NinebotLoginResult(uuid: "first"))
        store.saveLoginResult(NinebotLoginResult(uuid: "second"))

        XCTAssertEqual(store.loadLoginResult()?.uuid, "second")
    }

    // MARK: - Dashboard

    func testDashboardRoundTrips() {
        let sn = uniqueSN()
        let dashboard = makeDashboard(sn: sn, state: makeState(updatedAt: referenceDate))

        let archived = store.saveDashboard(dashboard)

        XCTAssertEqual(store.loadDashboard(), archived)
        XCTAssertEqual(store.loadDashboard()?.vehicles.first?.vehicle.sn, sn)
        XCTAssertEqual(store.loadDashboard()?.selectedSN, sn)
    }

    func testLoadDashboardReturnsNilWhenNothingIsStored() {
        XCTAssertNil(store.loadDashboard())
        XCTAssertEqual(store.storedDashboardByteCount(), 0)
    }

    func testSaveDashboardRecordsTheStoredByteCount() {
        store.saveDashboard(makeDashboard(sn: uniqueSN(), state: makeState(updatedAt: referenceDate)))

        XCTAssertGreaterThan(store.storedDashboardByteCount(), 0)
    }

    func testSaveDashboardClearsTheLastError() {
        store.saveLastError("network down")
        XCTAssertEqual(store.loadLastError(), "network down")

        store.saveDashboard(makeDashboard(sn: uniqueSN(), state: makeState(updatedAt: referenceDate)))

        XCTAssertNil(store.loadLastError())
    }

    func testSaveDashboardWritesAHistorySnapshot() {
        let sn = uniqueSN()
        let state = makeState(updatedAt: referenceDate, battery: 73, endurance: 31, totalMileage: 4_321)

        store.saveDashboard(makeDashboard(sn: sn, state: state))

        let history = store.loadHistory(sn: sn)
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(store.historyCount(sn: sn), 1)

        let point = history.first
        XCTAssertEqual(point?.sn, sn)
        XCTAssertEqual(point?.battery, 73)
        XCTAssertEqual(point?.endurance, 31)
        XCTAssertEqual(point?.totalMileage, 4_321)
        XCTAssertEqual(point?.isCharging, false)
        XCTAssertEqual(point?.isPoweredOn, true)
        XCTAssertEqual(point?.isLocked, true)
        XCTAssertEqual(point?.date, referenceDate)
    }

    // MARK: - History append rules

    func testHistoryIsEmptyForAnUnknownSerialNumber() {
        XCTAssertTrue(store.loadHistory(sn: uniqueSN()).isEmpty)
        XCTAssertEqual(store.historyCount(sn: uniqueSN()), 0)
    }

    func testHistorySkipsIdenticalPointsWithinSixtySeconds() {
        let sn = uniqueSN()
        store.saveDashboard(makeDashboard(sn: sn, state: makeState(updatedAt: referenceDate)))
        store.saveDashboard(
            makeDashboard(sn: sn, state: makeState(updatedAt: referenceDate.addingTimeInterval(30)))
        )

        XCTAssertEqual(store.historyCount(sn: sn), 1)
    }

    func testHistorySkipsIdenticalPointsWithinFiveMinutes() {
        let sn = uniqueSN()
        store.saveDashboard(makeDashboard(sn: sn, state: makeState(updatedAt: referenceDate)))
        store.saveDashboard(
            makeDashboard(sn: sn, state: makeState(updatedAt: referenceDate.addingTimeInterval(120)))
        )

        XCTAssertEqual(store.historyCount(sn: sn), 1)
    }

    func testHistoryAppendsIdenticalPointsPastFiveMinutes() {
        let sn = uniqueSN()
        store.saveDashboard(makeDashboard(sn: sn, state: makeState(updatedAt: referenceDate)))
        store.saveDashboard(
            makeDashboard(sn: sn, state: makeState(updatedAt: referenceDate.addingTimeInterval(600)))
        )

        XCTAssertEqual(store.historyCount(sn: sn), 2)
    }

    func testHistoryAppendsImmediatelyWhenAValueChanges() {
        let sn = uniqueSN()
        store.saveDashboard(makeDashboard(sn: sn, state: makeState(updatedAt: referenceDate, battery: 80)))
        store.saveDashboard(
            makeDashboard(
                sn: sn,
                state: makeState(updatedAt: referenceDate.addingTimeInterval(30), battery: 79)
            )
        )

        let history = store.loadHistory(sn: sn)
        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history.map(\.battery), [80, 79])
    }

    func testHistoryIsReturnedInChronologicalOrder() {
        let sn = uniqueSN()
        // Written newest-first; `loadHistory` must still hand back oldest-first.
        for offset in [1_200.0, 600.0, 0.0] {
            store.saveDashboard(
                makeDashboard(
                    sn: sn,
                    state: makeState(
                        updatedAt: referenceDate.addingTimeInterval(offset),
                        totalMileage: 1_000 + offset
                    )
                )
            )
        }

        let dates = store.loadHistory(sn: sn).map(\.date)
        XCTAssertEqual(dates, dates.sorted())
    }

    func testHistoryKeepsOnlyTheMostRecent240Points() {
        let sn = uniqueSN()
        let total = 250

        for index in 0..<total {
            let state = makeState(
                updatedAt: referenceDate.addingTimeInterval(Double(index) * 600),
                totalMileage: 1_000 + Double(index)
            )
            store.saveDashboard(makeDashboard(sn: sn, state: state))
        }

        let history = store.loadHistory(sn: sn)
        XCTAssertEqual(history.count, 240)
        // The oldest 10 samples were trimmed off the front.
        XCTAssertEqual(history.first?.totalMileage, 1_000 + Double(total - 240))
        XCTAssertEqual(history.last?.totalMileage, 1_000 + Double(total - 1))
    }

    // MARK: - Interface ride records

    func testInterfaceRideCountIsZeroForAnUnknownSerialNumber() {
        XCTAssertEqual(store.interfaceRideCount(sn: uniqueSN()), 0)
    }

    func testUpsertInterfaceRideRecordsIgnoresAnEmptyBatch() {
        let sn = uniqueSN()
        store.upsertInterfaceRideRecords([], sn: sn)

        XCTAssertEqual(store.interfaceRideCount(sn: sn), 0)
    }

    func testUpsertInterfaceRideRecordsStoresDistinctRides() {
        let sn = uniqueSN()
        store.upsertInterfaceRideRecords(
            [
                makeRideRecord(travelID: "T1", mileage: 1, startedAt: referenceDate),
                makeRideRecord(travelID: "T2", mileage: 2, startedAt: referenceDate.addingTimeInterval(3_600))
            ],
            sn: sn
        )

        XCTAssertEqual(store.interfaceRideCount(sn: sn), 2)
    }

    func testUpsertInterfaceRideRecordsDeduplicatesByStableIdentityKey() {
        let sn = uniqueSN()
        let first = makeRideRecord(travelID: "T1", mileage: 1, startedAt: referenceDate)
        let second = makeRideRecord(travelID: "T1", mileage: 9, startedAt: referenceDate)

        // Different `id`, same `travel_id`, so the same merge key.
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(first.stableIdentityKey, second.stableIdentityKey)

        store.upsertInterfaceRideRecords([first], sn: sn)
        store.upsertInterfaceRideRecords([second], sn: sn)

        XCTAssertEqual(store.interfaceRideCount(sn: sn), 1)
    }

    func testUpsertInterfaceRideRecordsLetsIncomingRidesWinOverStoredOnes() {
        let sn = uniqueSN()
        store.upsertInterfaceRideRecords(
            [makeRideRecord(travelID: "T1", mileage: 1, startedAt: referenceDate)],
            sn: sn
        )
        store.upsertInterfaceRideRecords(
            [makeRideRecord(travelID: "T1", mileage: 9, startedAt: referenceDate)],
            sn: sn
        )

        // Stored rides are surfaced back through the dashboard when the fresh
        // snapshot carries none of its own.
        let archived = store.saveDashboard(makeDashboard(sn: sn, state: makeState(updatedAt: referenceDate)))
        XCTAssertEqual(archived.vehicles.first?.state.rideRecords?.count, 1)
        XCTAssertEqual(archived.vehicles.first?.state.rideRecords?.first?.mileage, 9)
    }

    func testSaveDashboardArchivesTheRidesCarriedBySnapshot() {
        let sn = uniqueSN()
        let state = makeState(
            updatedAt: referenceDate,
            rideRecords: [
                makeRideRecord(travelID: "T1", mileage: 1, startedAt: referenceDate),
                makeRideRecord(travelID: "T2", mileage: 2, startedAt: referenceDate.addingTimeInterval(3_600))
            ]
        )

        store.saveDashboard(makeDashboard(sn: sn, state: state))

        XCTAssertEqual(store.interfaceRideCount(sn: sn), 2)
    }

    func testSaveDashboardRestoresStoredRidesOntoAnEmptySnapshot() {
        let sn = uniqueSN()
        store.upsertInterfaceRideRecords(
            [makeRideRecord(travelID: "T1", mileage: 5, startedAt: referenceDate)],
            sn: sn
        )

        let archived = store.saveDashboard(makeDashboard(sn: sn, state: makeState(updatedAt: referenceDate)))

        XCTAssertEqual(archived.vehicles.first?.state.rides.count, 1)
        XCTAssertEqual(store.loadDashboard()?.vehicles.first?.state.rides.first?.mileage, 5)
    }

    func testInterfaceRideRecordsAreCappedAt500() {
        let sn = uniqueSN()
        let total = 600
        let records = (0..<total).map { index in
            makeRideRecord(
                travelID: "T\(index)",
                mileage: Double(index),
                startedAt: referenceDate.addingTimeInterval(Double(index) * 60)
            )
        }

        store.upsertInterfaceRideRecords(records, sn: sn)

        XCTAssertEqual(store.interfaceRideCount(sn: sn), 500)

        // Records are kept newest-first, so the most recent ride survives.
        let archived = store.saveDashboard(makeDashboard(sn: sn, state: makeState(updatedAt: referenceDate)))
        XCTAssertEqual(archived.vehicles.first?.state.rideRecords?.count, 500)
        XCTAssertEqual(archived.vehicles.first?.state.rideRecords?.first?.mileage, Double(total - 1))
    }

    // MARK: - Pending app route

    func testPendingAppRouteIsConsumedExactlyOnce() {
        XCTAssertNil(store.consumePendingAppRoute())

        store.savePendingAppRoute(.trips)
        XCTAssertEqual(store.consumePendingAppRoute(), .trips)
        XCTAssertNil(store.consumePendingAppRoute())
    }

    func testSavePendingAppRouteOverwritesThePreviousRoute() {
        store.savePendingAppRoute(.dashboard)
        store.savePendingAppRoute(.settings)

        XCTAssertEqual(store.consumePendingAppRoute(), .settings)
    }

    func testConsumePendingAppRouteIgnoresAnUnknownRawValue() {
        store.savePendingAppRoute(.recording)
        defaults.set("not-a-route", forKey: "ninebot.pending.app.route")

        XCTAssertNil(store.consumePendingAppRoute())
    }

    // MARK: - Resolved addresses

    func testResolvedAddressesRoundTrip() {
        XCTAssertTrue(store.loadResolvedAddresses().isEmpty)

        let sn = uniqueSN()
        let address = NinebotResolvedAddress(
            sn: sn,
            address: "Somewhere Street 1",
            latitude: 39.9,
            longitude: 116.4,
            updatedAt: referenceDate,
            source: "test"
        )

        store.saveResolvedAddresses([sn: address])

        XCTAssertEqual(store.loadResolvedAddresses(), [sn: address])
    }

    func testSaveResolvedAddressesReplacesTheWholeMap() {
        let first = NinebotResolvedAddress(
            sn: "A", address: "A street", latitude: 1, longitude: 2, updatedAt: referenceDate
        )
        let second = NinebotResolvedAddress(
            sn: "B", address: "B street", latitude: 3, longitude: 4, updatedAt: referenceDate
        )

        store.saveResolvedAddresses(["A": first])
        store.saveResolvedAddresses(["B": second])

        let loaded = store.loadResolvedAddresses()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertNil(loaded["A"])
        XCTAssertEqual(loaded["B"], second)
    }

    // MARK: - Live Activity push tokens

    func testPushToStartTokenRoundTrips() {
        XCTAssertNil(store.loadChargingLiveActivityPushToStartToken())

        store.saveChargingLiveActivityPushToStartToken("push-to-start")
        XCTAssertEqual(store.loadChargingLiveActivityPushToStartToken(), "push-to-start")
    }

    func testPushToStartTokenTreatsBlankAsMissing() {
        store.saveChargingLiveActivityPushToStartToken("   ")

        XCTAssertNil(store.loadChargingLiveActivityPushToStartToken())
    }

    func testSaveChargingLiveActivityPushTokenStoresTokenAndRecord() {
        store.saveChargingLiveActivityPushToken("token-a", activityID: "A1", vehicleSN: "S1")

        XCTAssertEqual(store.loadChargingLiveActivityPushToken(activityID: "A1"), "token-a")

        let records = store.loadChargingLiveActivityPushTokenRecords()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.activityID, "A1")
        XCTAssertEqual(records.first?.token, "token-a")
        XCTAssertEqual(records.first?.vehicleSN, "S1")
    }

    func testSaveChargingLiveActivityPushTokenTreatsBlankTokenAsMissing() {
        store.saveChargingLiveActivityPushToken("  ", activityID: "A1", vehicleSN: "S1")

        XCTAssertNil(store.loadChargingLiveActivityPushToken(activityID: "A1"))
        // The record itself is still written; only the lookup filters blanks.
        XCTAssertEqual(store.loadChargingLiveActivityPushTokenRecords().count, 1)
    }

    func testSaveChargingLiveActivityPushTokenReplacesTheSameActivity() {
        store.saveChargingLiveActivityPushToken("token-a", activityID: "A1", vehicleSN: "S1")
        store.saveChargingLiveActivityPushToken("token-b", activityID: "A1", vehicleSN: "S1")

        XCTAssertEqual(store.loadChargingLiveActivityPushToken(activityID: "A1"), "token-b")

        let records = store.loadChargingLiveActivityPushTokenRecords()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.token, "token-b")
    }

    func testSaveChargingLiveActivityPushTokenInheritsTheVehicleForAKnownActivity() {
        store.saveChargingLiveActivityPushToken("token-a", activityID: "A1", vehicleSN: "S1")
        store.saveChargingLiveActivityPushToken("token-b", activityID: "A1")

        let records = store.loadChargingLiveActivityPushTokenRecords()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.token, "token-b")
        // The serial number is carried over rather than dropped.
        XCTAssertEqual(records.first?.vehicleSN, "S1")
    }

    func testSaveChargingLiveActivityPushTokenEvictsTheOldActivityForTheSameVehicle() {
        store.saveChargingLiveActivityPushToken("token-a", activityID: "A1", vehicleSN: "S1")
        store.saveChargingLiveActivityPushToken("token-b", activityID: "A2", vehicleSN: "S1")

        XCTAssertNil(store.loadChargingLiveActivityPushToken(activityID: "A1"))
        XCTAssertEqual(store.loadChargingLiveActivityPushToken(activityID: "A2"), "token-b")

        let records = store.loadChargingLiveActivityPushTokenRecords()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.activityID, "A2")
    }

    func testSaveChargingLiveActivityPushTokenKeepsSeparateVehicles() {
        store.saveChargingLiveActivityPushToken("token-a", activityID: "A1", vehicleSN: "S1")
        store.saveChargingLiveActivityPushToken("token-b", activityID: "A2", vehicleSN: "S2")

        XCTAssertEqual(store.loadChargingLiveActivityPushToken(activityID: "A1"), "token-a")
        XCTAssertEqual(store.loadChargingLiveActivityPushToken(activityID: "A2"), "token-b")
        XCTAssertEqual(store.loadChargingLiveActivityPushTokenRecords().count, 2)
    }

    func testSaveChargingLiveActivityPushTokenEvictsOtherUnattributedActivities() {
        store.saveChargingLiveActivityPushToken("token-a", activityID: "A1")
        store.saveChargingLiveActivityPushToken("token-b", activityID: "A2")

        XCTAssertNil(store.loadChargingLiveActivityPushToken(activityID: "A1"))
        XCTAssertEqual(store.loadChargingLiveActivityPushToken(activityID: "A2"), "token-b")

        let records = store.loadChargingLiveActivityPushTokenRecords()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.activityID, "A2")
        XCTAssertNil(records.first?.vehicleSN)
    }

    func testSaveChargingLiveActivityPushTokenTrimsAnEmptyVehicleToNil() {
        store.saveChargingLiveActivityPushToken("token-a", activityID: "A1", vehicleSN: "   ")

        XCTAssertNil(store.loadChargingLiveActivityPushTokenRecords().first?.vehicleSN)
    }

    func testRemoveChargingLiveActivityPushTokenDropsTokenAndRecord() {
        store.saveChargingLiveActivityPushToken("token-a", activityID: "A1", vehicleSN: "S1")
        store.saveChargingLiveActivityPushToken("token-b", activityID: "A2", vehicleSN: "S2")

        store.removeChargingLiveActivityPushToken(activityID: "A1")

        XCTAssertNil(store.loadChargingLiveActivityPushToken(activityID: "A1"))
        XCTAssertEqual(store.loadChargingLiveActivityPushToken(activityID: "A2"), "token-b")

        let records = store.loadChargingLiveActivityPushTokenRecords()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.activityID, "A2")
    }

    func testRemoveAllChargingLiveActivityPushTokensClearsEverything() {
        store.saveChargingLiveActivityPushToken("token-a", activityID: "A1", vehicleSN: "S1")
        store.saveChargingLiveActivityPushToken("token-b", activityID: "A2", vehicleSN: "S2")

        store.removeAllChargingLiveActivityPushTokens()

        XCTAssertTrue(store.loadChargingLiveActivityPushTokenRecords().isEmpty)
        XCTAssertNil(store.loadChargingLiveActivityPushToken(activityID: "A1"))
        XCTAssertNil(store.loadChargingLiveActivityPushToken(activityID: "A2"))
    }

    func testPruneChargingLiveActivityPushTokensKeepsOnlyActiveActivities() {
        store.saveChargingLiveActivityPushToken("token-a", activityID: "A1", vehicleSN: "S1")
        store.saveChargingLiveActivityPushToken("token-b", activityID: "A2", vehicleSN: "S2")
        store.saveChargingLiveActivityPushToken("token-c", activityID: "A3", vehicleSN: "S3")

        store.pruneChargingLiveActivityPushTokens(activeActivityIDs: ["A1", "A3"])

        let activityIDs = Set(store.loadChargingLiveActivityPushTokenRecords().map(\.activityID))
        XCTAssertEqual(activityIDs, ["A1", "A3"])

        XCTAssertEqual(store.loadChargingLiveActivityPushToken(activityID: "A1"), "token-a")
        XCTAssertNil(store.loadChargingLiveActivityPushToken(activityID: "A2"))
        XCTAssertEqual(store.loadChargingLiveActivityPushToken(activityID: "A3"), "token-c")
    }

    func testPruneChargingLiveActivityPushTokensWithNoActiveActivitiesClearsRecords() {
        store.saveChargingLiveActivityPushToken("token-a", activityID: "A1", vehicleSN: "S1")

        store.pruneChargingLiveActivityPushTokens(activeActivityIDs: [])

        XCTAssertTrue(store.loadChargingLiveActivityPushTokenRecords().isEmpty)
        XCTAssertNil(store.loadChargingLiveActivityPushToken(activityID: "A1"))
    }

    func testChargingLiveActivityPushTokenRecordsAreCappedAtTwelve() {
        // Distinct vehicles so none of the replacement rules fire; only the
        // 12-record ceiling can trim the list.
        for index in 0..<15 {
            store.saveChargingLiveActivityPushToken(
                "token-\(index)",
                activityID: "A\(index)",
                vehicleSN: "S\(index)"
            )
        }

        let records = store.loadChargingLiveActivityPushTokenRecords()
        XCTAssertEqual(records.count, 12)
        // The newest write always survives the trim.
        XCTAssertTrue(records.contains { $0.activityID == "A14" })
    }

    // MARK: - Last error

    func testLastErrorRoundTrips() {
        XCTAssertNil(store.loadLastError())

        store.saveLastError("boom")
        XCTAssertEqual(store.loadLastError(), "boom")

        store.saveLastError("still broken")
        XCTAssertEqual(store.loadLastError(), "still broken")
    }

    // MARK: - Refresh events

    func testAppAndWidgetRefreshEventsAreStoredSeparately() {
        XCTAssertNil(store.loadLastAppRefreshEvent())
        XCTAssertNil(store.loadLastWidgetRefreshEvent())

        let appEvent = NinebotRefreshEvent(
            source: "app",
            operation: "refresh",
            startedAt: referenceDate,
            endedAt: referenceDate.addingTimeInterval(2),
            success: true,
            message: nil
        )
        let widgetEvent = NinebotRefreshEvent(
            source: "widget",
            operation: "timeline",
            startedAt: referenceDate,
            endedAt: referenceDate.addingTimeInterval(5),
            success: false,
            message: "timed out"
        )

        store.saveLastAppRefreshEvent(appEvent)
        store.saveLastWidgetRefreshEvent(widgetEvent)

        XCTAssertEqual(store.loadLastAppRefreshEvent(), appEvent)
        XCTAssertEqual(store.loadLastWidgetRefreshEvent(), widgetEvent)
        XCTAssertEqual(store.loadLastAppRefreshEvent()?.durationSeconds, 2)
        XCTAssertEqual(store.loadLastWidgetRefreshEvent()?.durationSeconds, 5)
    }

    func testSaveRefreshEventOverwritesThePreviousEvent() {
        let first = NinebotRefreshEvent(
            source: "app", operation: "first",
            startedAt: referenceDate, endedAt: referenceDate, success: true
        )
        let second = NinebotRefreshEvent(
            source: "app", operation: "second",
            startedAt: referenceDate, endedAt: referenceDate, success: false
        )

        store.saveLastAppRefreshEvent(first)
        store.saveLastAppRefreshEvent(second)

        XCTAssertEqual(store.loadLastAppRefreshEvent(), second)
    }

    // MARK: - Push device token

    func testPushDeviceTokenRoundTrips() {
        XCTAssertNil(store.loadPushDeviceToken())

        store.savePushDeviceToken("device-token")
        XCTAssertEqual(store.loadPushDeviceToken(), "device-token")
    }

    func testPushDeviceTokenTreatsBlankAsMissing() {
        store.savePushDeviceToken("  \n ")

        XCTAssertNil(store.loadPushDeviceToken())
    }

    // MARK: - Capture privacy protection

    func testCapturePrivacyProtectionDefaultsToFalseAndRoundTrips() {
        XCTAssertFalse(store.loadCapturePrivacyProtectionEnabled())

        store.saveCapturePrivacyProtectionEnabled(true)
        XCTAssertTrue(store.loadCapturePrivacyProtectionEnabled())

        store.saveCapturePrivacyProtectionEnabled(false)
        XCTAssertFalse(store.loadCapturePrivacyProtectionEnabled())
    }

    // MARK: - Vehicle image data

    func testVehicleImageDataRoundTrips() {
        let sn = uniqueSN()
        imageSerialNumbers.append(sn)

        let data = Data(repeating: 0xAB, count: 1_024)
        store.saveVehicleImageData(data, sn: sn)

        XCTAssertEqual(store.loadVehicleImageData(sn: sn), data)
    }

    func testLoadVehicleImageDataIsNilWhenNothingWasSaved() {
        XCTAssertNil(store.loadVehicleImageData(sn: uniqueSN()))
    }

    func testSaveVehicleImageDataIgnoresEmptyData() {
        let sn = uniqueSN()
        imageSerialNumbers.append(sn)

        store.saveVehicleImageData(Data(), sn: sn)

        XCTAssertNil(store.loadVehicleImageData(sn: sn))
    }

    func testSaveVehicleImageDataIgnoresOversizedData() {
        let sn = uniqueSN()
        imageSerialNumbers.append(sn)

        store.saveVehicleImageData(Data(repeating: 0x01, count: 2_500_001), sn: sn)

        XCTAssertNil(store.loadVehicleImageData(sn: sn))
    }

    func testSaveVehicleImageDataAcceptsDataAtTheSizeLimit() {
        let sn = uniqueSN()
        imageSerialNumbers.append(sn)

        store.saveVehicleImageData(Data(repeating: 0x02, count: 2_500_000), sn: sn)

        XCTAssertEqual(store.loadVehicleImageData(sn: sn)?.count, 2_500_000)
    }

    func testSaveVehicleImageDataOverwritesThePreviousImage() {
        let sn = uniqueSN()
        imageSerialNumbers.append(sn)

        store.saveVehicleImageData(Data(repeating: 0x01, count: 16), sn: sn)
        let replacement = Data(repeating: 0x02, count: 32)
        store.saveVehicleImageData(replacement, sn: sn)

        XCTAssertEqual(store.loadVehicleImageData(sn: sn), replacement)
    }

    func testVehicleImagesAreKeyedBySerialNumber() {
        let first = uniqueSN()
        let second = uniqueSN()
        imageSerialNumbers.append(contentsOf: [first, second])

        let firstData = Data(repeating: 0x01, count: 16)
        let secondData = Data(repeating: 0x02, count: 16)
        store.saveVehicleImageData(firstData, sn: first)
        store.saveVehicleImageData(secondData, sn: second)

        XCTAssertEqual(store.loadVehicleImageData(sn: first), firstData)
        XCTAssertEqual(store.loadVehicleImageData(sn: second), secondData)
    }
}
