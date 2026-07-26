import Foundation
import XCTest
@testable import NineBotCore

// MARK: - Stub transport

/// Intercepts every request made through a `URLSession` configured with it and
/// answers from an in-memory routing table, so `NinebotServerClient` can be
/// exercised end to end without a server.
final class ServerClientStubURLProtocol: URLProtocol {
    struct Reply {
        var statusCode: Int
        var body: Data

        init(statusCode: Int = 200, body: Data = Data()) {
            self.statusCode = statusCode
            self.body = body
        }

        static func json(_ text: String, statusCode: Int = 200) -> Reply {
            Reply(statusCode: statusCode, body: Data(text.utf8))
        }

        static func text(_ text: String, statusCode: Int = 200) -> Reply {
            Reply(statusCode: statusCode, body: Data(text.utf8))
        }

        static func empty(statusCode: Int = 200) -> Reply {
            Reply(statusCode: statusCode, body: Data())
        }
    }

    private static let lock = NSLock()
    private static var storedHandler: ((URLRequest) -> Reply)?
    private static var recorded: [URLRequest] = []

    static func install(_ handler: @escaping (URLRequest) -> Reply) {
        lock.lock()
        storedHandler = handler
        recorded = []
        lock.unlock()
    }

    static func reset() {
        lock.lock()
        storedHandler = nil
        recorded = []
        lock.unlock()
    }

    static var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    static var requestedPaths: [String] {
        requests.map { $0.url?.path ?? "" }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let currentRequest = request

        Self.lock.lock()
        Self.recorded.append(currentRequest)
        let handler = Self.storedHandler
        Self.lock.unlock()

        let reply = handler?(currentRequest) ?? Reply(statusCode: 599, body: Data())

        guard let url = currentRequest.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: reply.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !reply.body.isEmpty {
            client?.urlProtocol(self, didLoad: reply.body)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - Tests

final class ServerClientTests: XCTestCase {
    private typealias Reply = ServerClientStubURLProtocol.Reply

    override func setUp() {
        super.setUp()
        ServerClientStubURLProtocol.reset()
    }

    override func tearDown() {
        ServerClientStubURLProtocol.reset()
        super.tearDown()
    }

    // MARK: Helpers

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ServerClientStubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func makeClient(
        baseURLString: String = "https://api.example.com",
        bearerToken: String = "",
        appSessionToken: String? = nil
    ) -> NinebotServerClient {
        NinebotServerClient(
            configuration: NinebotServerConfiguration(
                baseURLString: baseURLString,
                bearerToken: bearerToken,
                appSessionToken: appSessionToken
            ),
            session: makeSession()
        )
    }

    /// Answers by URL path; anything unrouted comes back as an empty 404 so a
    /// wrong request surfaces as a failure instead of hanging.
    private func route(_ routes: [String: Reply]) {
        ServerClientStubURLProtocol.install { request in
            routes[request.url?.path ?? ""] ?? .empty(statusCode: 404)
        }
    }

    private func alwaysReply(_ reply: Reply) {
        ServerClientStubURLProtocol.install { _ in reply }
    }

    private var lastRequest: URLRequest? {
        ServerClientStubURLProtocol.requests.last
    }

    private func captureError(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () async throws -> Void
    ) async -> Error? {
        do {
            try await body()
            XCTFail("expected an error to be thrown", file: file, line: line)
            return nil
        } catch {
            return error
        }
    }

    /// Runs a full `fetchDashboard` against a one-vehicle server whose dashboard
    /// carries the given `state` (and optionally `travel`) object.
    private func singleVehicleSnapshot(
        vehicleJSON: String = #"{"wnumber":"SN1"}"#,
        stateJSON: String,
        travelJSON: String? = nil
    ) async throws -> NinebotVehicleSnapshot {
        var fields = #""state":\#(stateJSON)"#
        if let travelJSON {
            fields += #","travel":\#(travelJSON)"#
        }
        route([
            "/vehicles": .json(#"{"ok":true,"data":[\#(vehicleJSON)]}"#),
            "/vehicles/SN1/dashboard": .json(#"{"ok":true,"data":{\#(fields)}}"#)
        ])
        let dashboard = try await makeClient().fetchDashboard()
        return try XCTUnwrap(dashboard.vehicles.first)
    }

    // MARK: - Envelope unwrapping

    func testEnvelopeSuccessYieldsTheDataPayload() async throws {
        route(["/vehicles/SN1/bell": .json(#"{"ok":true,"data":{"code":0,"msg":"ok"}}"#)])
        let payload = try await makeClient().ringBell(sn: "SN1")
        XCTAssertEqual(payload["code"]?.intValue, 0)
        XCTAssertEqual(payload["msg"]?.stringValue, "ok")
        XCTAssertNil(payload["ok"], "the envelope itself must not leak into the payload")
    }

    func testEnvelopeSuccessWithoutDataYieldsAnEmptyObject() async throws {
        route(["/vehicles/SN1/bell": .json(#"{"ok":true}"#)])
        let payload = try await makeClient().ringBell(sn: "SN1")
        XCTAssertEqual(payload, .object([:]))
    }

    func testEnvelopeFailureThrowsTheServerMessage() async {
        route(["/vehicles/SN1/bell": .json(#"{"ok":false,"error":{"message":"设备离线"}}"#)])
        let client = makeClient()
        let error = await captureError { _ = try await client.ringBell(sn: "SN1") }
        guard let serverError = error as? NinebotServerError,
              case .server(let message) = serverError else {
            XCTFail("expected .server, got \(String(describing: error))")
            return
        }
        XCTAssertEqual(message, "设备离线")
    }

    func testEnvelopeFailureFallsBackToTheErrorCode() async {
        route(["/vehicles/SN1/bell": .json(#"{"ok":false,"error":{"code":"VEHICLE_OFFLINE"}}"#)])
        let client = makeClient()
        let error = await captureError { _ = try await client.ringBell(sn: "SN1") }
        guard let serverError = error as? NinebotServerError,
              case .server(let message) = serverError else {
            XCTFail("expected .server, got \(String(describing: error))")
            return
        }
        XCTAssertEqual(message, "VEHICLE_OFFLINE")
    }

    func testEnvelopeFailureWithoutAnErrorObjectUsesTheGenericMessage() async {
        route(["/vehicles/SN1/bell": .json(#"{"ok":false}"#)])
        let client = makeClient()
        let error = await captureError { _ = try await client.ringBell(sn: "SN1") }
        guard let serverError = error as? NinebotServerError,
              case .server(let message) = serverError else {
            XCTFail("expected .server, got \(String(describing: error))")
            return
        }
        XCTAssertEqual(message, "NinePlus 服务器请求失败")
    }

    func testPayloadWithoutAnOkKeyIsReturnedVerbatim() async throws {
        route(["/vehicles/SN1/bell": .json(#"{"code":0,"data":{"x":1}}"#)])
        let payload = try await makeClient().ringBell(sn: "SN1")
        XCTAssertEqual(payload["code"]?.intValue, 0)
        XCTAssertEqual(payload["data"]?["x"]?.intValue, 1)
    }

    func testTopLevelArrayPayloadIsReturnedVerbatim() async throws {
        route(["/vehicles/SN1/bell": .json(#"[{"a":1},{"a":2}]"#)])
        let payload = try await makeClient().ringBell(sn: "SN1")
        XCTAssertEqual(payload.arrayValue?.count, 2)
    }

    func testEmptyResponseBodyBecomesAnEmptyObject() async throws {
        route(["/vehicles/SN1/buck": .empty(statusCode: 200)])
        let payload = try await makeClient().openBucket(sn: "SN1")
        XCTAssertEqual(payload, .object([:]))
    }

    func testEmptyResponseBodyOnNoContentBecomesAnEmptyObject() async throws {
        route(["/vehicles/SN1/buck": .empty(statusCode: 204)])
        let payload = try await makeClient().openBucket(sn: "SN1")
        XCTAssertEqual(payload, .object([:]))
    }

    // MARK: - HTTP failures

    func testHTTPErrorCarriesTheNestedErrorMessage() async {
        route(["/vehicles/SN1/bell": .json(#"{"error":{"message":"boom"}}"#, statusCode: 500)])
        let client = makeClient()
        let error = await captureError { _ = try await client.ringBell(sn: "SN1") }
        guard let serverError = error as? NinebotServerError,
              case .httpStatus(let code, let message) = serverError else {
            XCTFail("expected .httpStatus, got \(String(describing: error))")
            return
        }
        XCTAssertEqual(code, 500)
        XCTAssertEqual(message, "boom")
    }

    func testHTTPErrorCarriesATopLevelMessage() async {
        route(["/vehicles/SN1/bell": .json(#"{"message":"bad gateway"}"#, statusCode: 502)])
        let client = makeClient()
        let error = await captureError { _ = try await client.ringBell(sn: "SN1") }
        guard let serverError = error as? NinebotServerError,
              case .httpStatus(let code, let message) = serverError else {
            XCTFail("expected .httpStatus, got \(String(describing: error))")
            return
        }
        XCTAssertEqual(code, 502)
        XCTAssertEqual(message, "bad gateway")
    }

    func testHTTPErrorFallsBackToTheRawBodyWhenItIsNotJSON() async {
        route(["/vehicles/SN1/bell": .text("upstream exploded", statusCode: 503)])
        let client = makeClient()
        let error = await captureError { _ = try await client.ringBell(sn: "SN1") }
        guard let serverError = error as? NinebotServerError,
              case .httpStatus(let code, let message) = serverError else {
            XCTFail("expected .httpStatus, got \(String(describing: error))")
            return
        }
        XCTAssertEqual(code, 503)
        XCTAssertEqual(message, "upstream exploded")
    }

    func testHTTPErrorWithAnEmptyBodyHasNoMessage() async {
        route(["/vehicles/SN1/bell": .empty(statusCode: 404)])
        let client = makeClient()
        let error = await captureError { _ = try await client.ringBell(sn: "SN1") }
        guard let serverError = error as? NinebotServerError,
              case .httpStatus(let code, let message) = serverError else {
            XCTFail("expected .httpStatus, got \(String(describing: error))")
            return
        }
        XCTAssertEqual(code, 404)
        XCTAssertEqual(message, "")
    }

    func testHTTPStatusIsCheckedBeforeTheEnvelope() async {
        // A failing envelope delivered with a 5xx must still report the status code.
        route(["/vehicles/SN1/bell": .json(#"{"ok":false,"error":{"message":"nope"}}"#, statusCode: 500)])
        let client = makeClient()
        let error = await captureError { _ = try await client.ringBell(sn: "SN1") }
        guard let serverError = error as? NinebotServerError,
              case .httpStatus(let code, let message) = serverError else {
            XCTFail("expected .httpStatus, got \(String(describing: error))")
            return
        }
        XCTAssertEqual(code, 500)
        XCTAssertEqual(message, "nope")
    }

    // MARK: - Error descriptions

    func testErrorDescriptions() {
        XCTAssertEqual(NinebotServerError.invalidBaseURL.errorDescription, "服务器地址无效")
        XCTAssertEqual(NinebotServerError.invalidResponse.errorDescription, "服务器返回的数据格式无效")
        XCTAssertEqual(NinebotServerError.server("炸了").errorDescription, "炸了")
        XCTAssertEqual(NinebotServerError.httpStatus(404, "").errorDescription, "HTTP 404")
        XCTAssertEqual(NinebotServerError.httpStatus(500, "boom").errorDescription, "HTTP 500: boom")
    }

    // MARK: - URL construction

    func testURLIsBuiltFromABaseWithoutATrailingSlash() async throws {
        alwaysReply(.empty())
        try await makeClient(baseURLString: "https://api.example.com").healthCheck()
        XCTAssertEqual(lastRequest?.url?.absoluteString, "https://api.example.com/healthz")
    }

    func testTrailingSlashesInTheBaseAreIgnored() async throws {
        alwaysReply(.empty())
        try await makeClient(baseURLString: "https://api.example.com/").healthCheck()
        XCTAssertEqual(lastRequest?.url?.absoluteString, "https://api.example.com/healthz")
    }

    func testBaseSubPathIsPreserved() async throws {
        alwaysReply(.empty())
        try await makeClient(baseURLString: "https://api.example.com/nineplus/v1").healthCheck()
        XCTAssertEqual(lastRequest?.url?.absoluteString, "https://api.example.com/nineplus/v1/healthz")
    }

    func testBaseSubPathWithATrailingSlashIsPreserved() async throws {
        alwaysReply(.empty())
        try await makeClient(baseURLString: "https://api.example.com/nineplus/v1/").healthCheck()
        XCTAssertEqual(lastRequest?.url?.absoluteString, "https://api.example.com/nineplus/v1/healthz")
    }

    func testASchemelessBaseDefaultsToHTTP() async throws {
        alwaysReply(.empty())
        try await makeClient(baseURLString: "api.example.com").healthCheck()
        XCTAssertEqual(lastRequest?.url?.absoluteString, "http://api.example.com/healthz")
    }

    func testSurroundingWhitespaceInTheBaseIsTrimmed() async throws {
        alwaysReply(.empty())
        try await makeClient(baseURLString: "  https://api.example.com  ").healthCheck()
        XCTAssertEqual(lastRequest?.url?.absoluteString, "https://api.example.com/healthz")
    }

    func testMultiComponentPathsAreJoined() async throws {
        alwaysReply(.empty())
        _ = try await makeClient().engineStart(sn: "SN1")
        XCTAssertEqual(lastRequest?.url?.path, "/vehicles/SN1/engine/start")
        XCTAssertEqual(lastRequest?.httpMethod, "POST")
    }

    func testAnEmptyBaseURLThrowsBeforeAnyRequest() async {
        alwaysReply(.empty())
        let client = makeClient(baseURLString: "")
        let error = await captureError { try await client.healthCheck() }
        guard let serverError = error as? NinebotServerError,
              case .invalidBaseURL = serverError else {
            XCTFail("expected .invalidBaseURL, got \(String(describing: error))")
            return
        }
        XCTAssertTrue(ServerClientStubURLProtocol.requests.isEmpty)
    }

    func testAWhitespaceOnlyBaseURLThrows() async {
        alwaysReply(.empty())
        let client = makeClient(baseURLString: "   ")
        let error = await captureError { try await client.healthCheck() }
        guard let serverError = error as? NinebotServerError,
              case .invalidBaseURL = serverError else {
            XCTFail("expected .invalidBaseURL, got \(String(describing: error))")
            return
        }
        XCTAssertFalse(NinebotServerConfiguration(baseURLString: "   ", bearerToken: "").isUsable)
    }

    func testQueryItemsAreAppended() async throws {
        route(["/vehicles/SN1/travel-sync": .json(#"{"ok":true,"data":{"list":[]}}"#)])
        _ = try await makeClient().syncTravelMonth(sn: "SN1", month: "202401", pageSize: 50)

        let request = try XCTUnwrap(lastRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        let url = try XCTUnwrap(request.url)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.path, "/vehicles/SN1/travel-sync")
        XCTAssertEqual(components.queryItems, [
            URLQueryItem(name: "month", value: "202401"),
            URLQueryItem(name: "page_size", value: "50")
        ])
    }

    // MARK: - Request headers

    func testAuthorizationAndSessionHeadersAreSent() async throws {
        alwaysReply(.empty())
        let client = makeClient(bearerToken: "tok-123", appSessionToken: "sess-456")
        try await client.healthCheck()

        let request = try XCTUnwrap(lastRequest)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok-123")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-NinePlus-Session"), "sess-456")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
    }

    func testTokensAreTrimmedBeforeBeingSent() async throws {
        alwaysReply(.empty())
        let client = makeClient(bearerToken: "  tok-123  ", appSessionToken: "  sess-456  ")
        try await client.healthCheck()

        let request = try XCTUnwrap(lastRequest)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok-123")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-NinePlus-Session"), "sess-456")
    }

    func testNoAuthHeadersWhenTokensAreAbsent() async throws {
        alwaysReply(.empty())
        try await makeClient(bearerToken: "", appSessionToken: nil).healthCheck()

        let request = try XCTUnwrap(lastRequest)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(request.value(forHTTPHeaderField: "X-NinePlus-Session"))
    }

    func testNoAuthHeadersWhenTokensAreBlank() async throws {
        alwaysReply(.empty())
        try await makeClient(bearerToken: "   ", appSessionToken: "  ").healthCheck()

        let request = try XCTUnwrap(lastRequest)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(request.value(forHTTPHeaderField: "X-NinePlus-Session"))
    }

    func testPostWithABodySetsTheContentType() async throws {
        route(["/accounts/login": .json(#"{"ok":true,"data":{}}"#)])
        _ = try await makeClient().login(account: "a", password: "b")

        let request = try XCTUnwrap(lastRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/accounts/login")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    // MARK: - login

    func testLoginParsesSnakeCaseFields() async throws {
        route(["/accounts/login": .json(#"""
        {"ok":true,"data":{
          "uuid":"u-1",
          "phone":"13800000000",
          "area_code":"86",
          "region":"CN",
          "business_uid":"biz-9",
          "account_id":4242,
          "session_token":"tok-abc"
        }}
        """#)])

        let result = try await makeClient().login(account: "user", password: "pass")
        XCTAssertEqual(result, NinebotLoginResult(
            uuid: "u-1",
            phone: "13800000000",
            areaCode: "86",
            region: "CN",
            businessUID: "biz-9",
            accountID: 4242,
            sessionToken: "tok-abc"
        ))
    }

    func testLoginAcceptsCamelCaseSessionTokenAndPlainID() async throws {
        route(["/accounts/login": .json(#"{"ok":true,"data":{"id":7,"sessionToken":"tok-camel"}}"#)])
        let result = try await makeClient().login(account: "user", password: "pass")
        XCTAssertEqual(result.accountID, 7)
        XCTAssertEqual(result.sessionToken, "tok-camel")
        XCTAssertNil(result.uuid)
    }

    func testLoginPrefersAccountIDOverID() async throws {
        route(["/accounts/login": .json(#"{"ok":true,"data":{"account_id":1,"id":2}}"#)])
        let result = try await makeClient().login(account: "user", password: "pass")
        XCTAssertEqual(result.accountID, 1)
    }

    func testLoginPrefersSnakeCaseSessionToken() async throws {
        route(["/accounts/login": .json(#"{"ok":true,"data":{"session_token":"snake","sessionToken":"camel"}}"#)])
        let result = try await makeClient().login(account: "user", password: "pass")
        XCTAssertEqual(result.sessionToken, "snake")
    }

    func testLoginWithAnEmptyPayloadYieldsAllNilFields() async throws {
        route(["/accounts/login": .json(#"{"ok":true}"#)])
        let result = try await makeClient().login(account: "user", password: "pass")
        XCTAssertEqual(result, NinebotLoginResult())
    }

    func testLoginPropagatesAServerEnvelopeError() async {
        route(["/accounts/login": .json(#"{"ok":false,"error":{"message":"账号或密码错误"}}"#)])
        let client = makeClient()
        let error = await captureError { _ = try await client.login(account: "a", password: "b") }
        guard let serverError = error as? NinebotServerError,
              case .server(let message) = serverError else {
            XCTFail("expected .server, got \(String(describing: error))")
            return
        }
        XCTAssertEqual(message, "账号或密码错误")
    }

    // MARK: - Command endpoints

    func testCommandEndpointPaths() async throws {
        alwaysReply(.json(#"{"ok":true,"data":{}}"#))
        let client = makeClient()

        _ = try await client.ringBell(sn: "SN1")
        XCTAssertEqual(lastRequest?.url?.path, "/vehicles/SN1/bell")

        _ = try await client.openBucket(sn: "SN1")
        XCTAssertEqual(lastRequest?.url?.path, "/vehicles/SN1/buck")

        _ = try await client.engineStop(sn: "SN1")
        XCTAssertEqual(lastRequest?.url?.path, "/vehicles/SN1/engine/stop")

        try await client.registerPushDevice(token: "t", bundleID: "com.example.app", environment: "development")
        XCTAssertEqual(lastRequest?.url?.path, "/devices/register")
        XCTAssertEqual(lastRequest?.httpMethod, "POST")

        try await client.registerLiveActivityToken(
            token: "t",
            tokenKind: "update",
            bundleID: "com.example.app",
            environment: "development"
        )
        XCTAssertEqual(lastRequest?.url?.path, "/live-activities/register")

        try await client.healthCheck()
        XCTAssertEqual(lastRequest?.url?.path, "/healthz")
        XCTAssertEqual(lastRequest?.httpMethod, "GET")
    }

    // MARK: - updateBatteryChemistry

    func testUpdateBatteryChemistryParsesTheReturnedInfo() async throws {
        route(["/vehicles/SN1/prediction-settings": .json(#"""
        {"ok":true,"data":{"battery_chemistry":{
          "configured":"lead_acid",
          "effective":"lead_acid",
          "source":"manual",
          "nominal_voltage":60,
          "capacity_wh":1440,
          "capacity_ah":24
        }}}
        """#)])

        let info = try await makeClient().updateBatteryChemistry(
            sn: "SN1",
            chemistry: .leadAcid,
            nominalVoltage: 60,
            capacityWh: 1440
        )
        let unwrapped = try XCTUnwrap(info)
        XCTAssertEqual(unwrapped.configured, .leadAcid)
        XCTAssertEqual(unwrapped.effective, "lead_acid")
        XCTAssertEqual(unwrapped.source, "manual")
        XCTAssertEqual(unwrapped.nominalVoltage ?? 0, 60, accuracy: 1e-9)
        XCTAssertEqual(unwrapped.capacityWh ?? 0, 1440, accuracy: 1e-9)
        XCTAssertEqual(unwrapped.capacityAh ?? 0, 24, accuracy: 1e-9)
        XCTAssertEqual(lastRequest?.url?.path, "/vehicles/SN1/prediction-settings")
    }

    func testUpdateBatteryChemistryAcceptsTheCamelCaseKey() async throws {
        route(["/vehicles/SN1/prediction-settings": .json(#"""
        {"ok":true,"data":{"batteryChemistry":{"configured":"lithium"}}}
        """#)])

        let info = try await makeClient().updateBatteryChemistry(
            sn: "SN1",
            chemistry: .lithium,
            nominalVoltage: nil,
            capacityWh: nil
        )
        let unwrapped = try XCTUnwrap(info)
        XCTAssertEqual(unwrapped.configured, .lithium)
        // Defaults applied when the server omits them.
        XCTAssertEqual(unwrapped.effective, "unknown")
        XCTAssertEqual(unwrapped.source, "unresolved")
        XCTAssertNil(unwrapped.nominalVoltage)
    }

    func testUpdateBatteryChemistryReturnsNilWhenTheServerOmitsIt() async throws {
        route(["/vehicles/SN1/prediction-settings": .json(#"{"ok":true,"data":{}}"#)])
        let info = try await makeClient().updateBatteryChemistry(
            sn: "SN1",
            chemistry: .auto,
            nominalVoltage: nil,
            capacityWh: nil
        )
        XCTAssertNil(info)
    }

    // MARK: - syncTravelMonth

    func testSyncTravelMonthParsesThePage() async throws {
        route(["/vehicles/SN1/travel-sync": .json(#"""
        {"ok":true,"data":{
          "month":"202312",
          "page":2,
          "page_size":10,
          "total":37,
          "has_more":true,
          "list":[{
            "travel_id":"T1",
            "mileages":4.6,
            "ec":200,
            "used_electricity":4,
            "start_time":"2024-01-15 08:00:00",
            "end_time":"2024-01-15 08:30:00"
          }]
        }}
        """#)])

        let page = try await makeClient().syncTravelMonth(sn: "SN1", month: "202401")
        XCTAssertEqual(page.month, "202312")
        XCTAssertEqual(page.page, 2)
        XCTAssertEqual(page.pageSize, 10)
        XCTAssertEqual(page.total, 37)
        XCTAssertTrue(page.hasMore)
        XCTAssertEqual(page.records.count, 1)

        let record = try XCTUnwrap(page.records.first)
        XCTAssertEqual(record.id, "T1")
        XCTAssertEqual(record.mileage ?? 0, 4.6, accuracy: 1e-9)
        XCTAssertEqual(record.energy ?? 0, 200, accuracy: 1e-9)
        XCTAssertEqual(record.usedElectricity ?? 0, 4, accuracy: 1e-9)
        // Derived from start/end, which are read in Asia/Shanghai (UTC+8).
        XCTAssertEqual(record.durationMinutes ?? 0, 30, accuracy: 1e-9)
        XCTAssertEqual(
            record.startedAt?.timeIntervalSince1970 ?? 0,
            1_705_276_800,
            accuracy: 1
        )
    }

    func testSyncTravelMonthFallsBackToTheRequestedMonthAndDefaults() async throws {
        route(["/vehicles/SN1/travel-sync": .json(#"{"ok":true,"data":{"list":[]}}"#)])
        let page = try await makeClient().syncTravelMonth(sn: "SN1", month: "202401")
        XCTAssertEqual(page.month, "202401")
        XCTAssertEqual(page.page, 1)
        XCTAssertEqual(page.pageSize, 0)
        XCTAssertEqual(page.total, 0)
        XCTAssertFalse(page.hasMore)
        XCTAssertTrue(page.records.isEmpty)
    }

    // MARK: - fetchTravelDetail

    func testFetchTravelDetailWrapsTheRawPayload() async throws {
        route(["/vehicles/SN1/travel/T9": .json(#"""
        {"ok":true,"data":{
          "travel_id":"T9",
          "mileages":3.2,
          "start_time":"2024-01-15 08:00:00",
          "end_time":"2024-01-15 08:20:00"
        }}
        """#)])

        let detail = try await makeClient().fetchTravelDetail(sn: "SN1", travelID: "T9")
        XCTAssertEqual(detail.vehicleSN, "SN1")
        XCTAssertEqual(detail.rideID, "T9")
        XCTAssertEqual(detail.id, "SN1|T9")
        XCTAssertEqual(detail.rawObject?["mileages"]?.doubleValue ?? 0, 3.2, accuracy: 1e-9)

        let record = try XCTUnwrap(detail.parsedRecord)
        XCTAssertEqual(record.id, "T9")
        XCTAssertEqual(record.mileage ?? 0, 3.2, accuracy: 1e-9)
        XCTAssertEqual(record.durationMinutes ?? 0, 20, accuracy: 1e-9)
    }

    // MARK: - fetchDashboard, happy path

    func testFetchDashboardParsesVehicleAndStateFromTheStableStateBranch() async throws {
        route([
            "/vehicles": .json(#"""
            {"ok":true,"data":[{
              "wnumber":"SN1",
              "device_name":"我的九号",
              "vehicle_name_en":"Ninebot E100",
              "vehicle_type":"电动车",
              "v6_light_img_url":"https://img.example.com/e100.png"
            }]}
            """#),
            "/vehicles/SN1/dashboard": .json(#"""
            {"ok":true,"data":{
              "state":{
                "dump_energy":86,
                "precise_estimate_mileage":42.5,
                "charging":0,
                "pwr":1,
                "bms_volt":60500,
                "bat_temp":285,
                "bms_cycle":36,
                "loc":{"lock":1,"lat":39900000,"lon":116400000}
              },
              "travel":{
                "total_mileages":128.4,
                "ec":3.2,
                "used_electricity":2.8,
                "list":[]
              },
              "updated_at":"2024-01-15 10:30:00"
            }}
            """#)
        ])

        let dashboard = try await makeClient().fetchDashboard()
        XCTAssertEqual(dashboard.vehicles.count, 1)
        XCTAssertEqual(dashboard.selectedSN, "SN1")

        let snapshot = try XCTUnwrap(dashboard.primaryVehicle)
        XCTAssertEqual(snapshot.vehicle.sn, "SN1")
        XCTAssertEqual(snapshot.vehicle.name, "我的九号")
        XCTAssertEqual(snapshot.vehicle.model, "Ninebot E100 (电动车)")
        XCTAssertEqual(snapshot.vehicle.imageURLString, "https://img.example.com/e100.png")

        let state = snapshot.state
        XCTAssertEqual(state.battery, 86)
        XCTAssertEqual(state.endurance ?? 0, 42.5, accuracy: 1e-9)
        XCTAssertEqual(state.isCharging, false)
        XCTAssertEqual(state.isPoweredOn, true)
        XCTAssertEqual(state.isLocked, true)
        XCTAssertEqual(state.batteryCycleCount, 36)
        XCTAssertEqual(state.monthMileage ?? 0, 128.4, accuracy: 1e-9)
        XCTAssertEqual(state.monthEnergy ?? 0, 3.2, accuracy: 1e-9)
        XCTAssertEqual(state.monthUsedElectricity ?? 0, 2.8, accuracy: 1e-9)
        // Magnified coordinates are divided back down.
        XCTAssertEqual(state.latitude ?? 0, 39.9, accuracy: 1e-9)
        XCTAssertEqual(state.longitude ?? 0, 116.4, accuracy: 1e-9)
        // 60500 mV and 285 deci-degrees.
        XCTAssertEqual(state.batteryVoltage ?? 0, 60.5, accuracy: 1e-9)
        XCTAssertEqual(state.batteryTemperature ?? 0, 28.5, accuracy: 1e-9)
        // Recomputed from the per-month travel payloads.
        XCTAssertEqual(state.totalMileage ?? 0, 128.4, accuracy: 1e-9)
        XCTAssertNil(state.rideRecords)
        XCTAssertEqual(state.updatedAt.timeIntervalSince1970, 1_705_314_600, accuracy: 1)
        XCTAssertNil(state.serverPrediction)

        // `travel` came inline, so no extra month request was needed.
        XCTAssertEqual(
            ServerClientStubURLProtocol.requestedPaths,
            ["/vehicles", "/vehicles/SN1/dashboard"]
        )
    }

    func testFetchDashboardReadsVehiclesFromAWrappedArray() async throws {
        route([
            "/vehicles": .json(#"""
            {"ok":true,"data":{"vehicles":[{"wnumber":"SN1"},{"junk":true},{"sn":""}]}}
            """#),
            "/vehicles/SN1/dashboard": .json(#"{"ok":true,"data":{"state":{"dump_energy":50}}}"#)
        ])

        let dashboard = try await makeClient().fetchDashboard()
        // Entries without a usable serial number are dropped.
        XCTAssertEqual(dashboard.vehicles.count, 1)
        XCTAssertEqual(dashboard.vehicles.first?.vehicle.sn, "SN1")
    }

    func testFetchDashboardWorksWithoutAnEnvelope() async throws {
        route([
            "/vehicles": .json(#"[{"wnumber":"SN1"}]"#),
            "/vehicles/SN1/dashboard": .json(#"{"state":{"dump_energy":50}}"#)
        ])

        let dashboard = try await makeClient().fetchDashboard()
        XCTAssertEqual(dashboard.vehicles.first?.state.battery, 50)
    }

    func testFetchDashboardDefaultsVehicleNameAndModelToTheSerial() async throws {
        let snapshot = try await singleVehicleSnapshot(
            vehicleJSON: #"{"sn":"SN1"}"#,
            stateJSON: #"{"dump_energy":50}"#
        )
        XCTAssertEqual(snapshot.vehicle.sn, "SN1")
        XCTAssertEqual(snapshot.vehicle.name, "SN1")
        XCTAssertEqual(snapshot.vehicle.model, "SN1")
        XCTAssertNil(snapshot.vehicle.imageURLString)
    }

    func testFetchDashboardBorrowsTheVehicleImageFromTheStatusPayload() async throws {
        let snapshot = try await singleVehicleSnapshot(
            vehicleJSON: #"{"wnumber":"SN1"}"#,
            stateJSON: #"{"dump_energy":50,"img_url":"https://img.example.com/from-status.png"}"#
        )
        XCTAssertEqual(snapshot.vehicle.imageURLString, "https://img.example.com/from-status.png")
    }

    func testFetchDashboardWithNoVehiclesIsEmpty() async throws {
        route(["/vehicles": .json(#"{"ok":true,"data":[]}"#)])
        let dashboard = try await makeClient().fetchDashboard()
        XCTAssertTrue(dashboard.vehicles.isEmpty)
        XCTAssertNil(dashboard.selectedSN)
        XCTAssertNil(dashboard.primaryVehicle)
    }

    func testFetchDashboardSelectionFallsBackToTheFirstVehicle() async throws {
        route([
            "/vehicles": .json(#"{"ok":true,"data":[{"wnumber":"SN1"},{"wnumber":"SN2"}]}"#),
            "/vehicles/SN1/dashboard": .json(#"{"ok":true,"data":{"state":{"dump_energy":10}}}"#),
            "/vehicles/SN2/dashboard": .json(#"{"ok":true,"data":{"state":{"dump_energy":20}}}"#)
        ])
        let client = makeClient()

        let selected = try await client.fetchDashboard(selectedSN: "SN2")
        XCTAssertEqual(selected.selectedSN, "SN2")
        XCTAssertEqual(selected.primaryVehicle?.state.battery, 20)

        let unknown = try await client.fetchDashboard(selectedSN: "SN-does-not-exist")
        XCTAssertEqual(unknown.selectedSN, "SN1")

        let none = try await client.fetchDashboard()
        XCTAssertEqual(none.selectedSN, "SN1")
    }

    // MARK: - fetchDashboard, fallback path

    func testFetchDashboardFallsBackToStatusAndBatteryEndpoints() async throws {
        route([
            "/vehicles": .json(#"{"ok":true,"data":[{"wnumber":"SN1"}]}"#),
            // No usable state/status/battery in the dashboard response.
            "/vehicles/SN1/dashboard": .json(#"{"ok":true,"data":{}}"#),
            "/vehicles/SN1/status": .json(#"""
            {"ok":true,"data":{
              "dump_energy":42,
              "pwr":0,
              "loc":{"lock":0,"lat":31.2304,"lon":121.4737}
            }}
            """#),
            "/vehicles/SN1/battery": .json(#"""
            {"ok":true,"data":{
              "battery_list":[{"bms_volt":605,"bat_temp":30,"bms_cycle":12}],
              "charging_power":0
            }}
            """#)
        ])

        let dashboard = try await makeClient().fetchDashboard()
        let state = try XCTUnwrap(dashboard.vehicles.first?.state)
        XCTAssertEqual(state.battery, 42)
        XCTAssertEqual(state.isPoweredOn, false)
        XCTAssertEqual(state.isLocked, false)
        XCTAssertEqual(state.latitude ?? 0, 31.2304, accuracy: 1e-9)
        XCTAssertEqual(state.longitude ?? 0, 121.4737, accuracy: 1e-9)
        // 605 is a deci-volt reading.
        XCTAssertEqual(state.batteryVoltage ?? 0, 60.5, accuracy: 1e-9)
        XCTAssertEqual(state.batteryTemperature ?? 0, 30, accuracy: 1e-9)
        XCTAssertEqual(state.batteryCycleCount, 12)
        XCTAssertEqual(state.chargingPower ?? -1, 0, accuracy: 1e-9)

        let paths = ServerClientStubURLProtocol.requestedPaths
        XCTAssertTrue(paths.contains("/vehicles/SN1/status"))
        XCTAssertTrue(paths.contains("/vehicles/SN1/battery"))
    }

    func testFetchDashboardFallsBackWhenTheDashboardRequestFails() async throws {
        route([
            "/vehicles": .json(#"{"ok":true,"data":[{"wnumber":"SN1"}]}"#),
            // /dashboard is unrouted, so it answers 404 and the error is swallowed.
            "/vehicles/SN1/status": .json(#"{"ok":true,"data":{"dump_energy":42,"pwr":1}}"#),
            "/vehicles/SN1/battery": .json(#"{"ok":true,"data":{"electricity":42,"bms_volt":60.5}}"#)
        ])

        let dashboard = try await makeClient().fetchDashboard()
        let state = try XCTUnwrap(dashboard.vehicles.first?.state)
        XCTAssertEqual(state.battery, 42)
        XCTAssertEqual(state.isPoweredOn, true)
        XCTAssertEqual(state.batteryVoltage ?? 0, 60.5, accuracy: 1e-9)
    }

    func testFetchDashboardThrowsWhenNoVehicleStatusIsAvailable() async {
        route([
            "/vehicles": .json(#"{"ok":true,"data":[{"wnumber":"SN1"}]}"#),
            "/vehicles/SN1/dashboard": .json(#"{"ok":true,"data":{}}"#),
            "/vehicles/SN1/status": .json(#"{"ok":true,"data":{}}"#),
            "/vehicles/SN1/battery": .json(#"{"ok":true,"data":{}}"#)
        ])
        let client = makeClient()

        let error = await captureError { _ = try await client.fetchDashboard() }
        guard let serverError = error as? NinebotServerError,
              case .server(let message) = serverError else {
            XCTFail("expected .server, got \(String(describing: error))")
            return
        }
        XCTAssertTrue(message.contains("车辆状态"), message)
    }

    func testFetchDashboardThrowsWhenNoBatteryDataIsAvailable() async {
        route([
            "/vehicles": .json(#"{"ok":true,"data":[{"wnumber":"SN1"}]}"#),
            "/vehicles/SN1/dashboard": .json(#"{"ok":true,"data":{}}"#),
            "/vehicles/SN1/status": .json(#"{"ok":true,"data":{"dump_energy":42}}"#),
            "/vehicles/SN1/battery": .json(#"{"ok":true,"data":{}}"#)
        ])
        let client = makeClient()

        let error = await captureError { _ = try await client.fetchDashboard() }
        guard let serverError = error as? NinebotServerError,
              case .server(let message) = serverError else {
            XCTFail("expected .server, got \(String(describing: error))")
            return
        }
        XCTAssertTrue(message.contains("电池数据"), message)
    }

    func testFetchDashboardPropagatesAFailingVehiclesRequest() async {
        route(["/vehicles": .json(#"{"error":{"message":"unauthorized"}}"#, statusCode: 401)])
        let client = makeClient()

        let error = await captureError { _ = try await client.fetchDashboard() }
        guard let serverError = error as? NinebotServerError,
              case .httpStatus(let code, let message) = serverError else {
            XCTFail("expected .httpStatus, got \(String(describing: error))")
            return
        }
        XCTAssertEqual(code, 401)
        XCTAssertEqual(message, "unauthorized")
    }

    // MARK: - Coordinate normalisation

    func testMagnifiedCoordinatesAreNormalised() async throws {
        let snapshot = try await singleVehicleSnapshot(
            stateJSON: #"{"dump_energy":50,"loc":{"lat":39900000,"lon":116400000}}"#
        )
        XCTAssertEqual(snapshot.state.latitude ?? 0, 39.9, accuracy: 1e-9)
        XCTAssertEqual(snapshot.state.longitude ?? 0, 116.4, accuracy: 1e-9)
    }

    func testTenMillionScaledCoordinatesAreNormalised() async throws {
        let snapshot = try await singleVehicleSnapshot(
            stateJSON: #"{"dump_energy":50,"loc":{"lat":399000000,"lon":1164000000}}"#
        )
        XCTAssertEqual(snapshot.state.latitude ?? 0, 39.9, accuracy: 1e-9)
        XCTAssertEqual(snapshot.state.longitude ?? 0, 116.4, accuracy: 1e-9)
    }

    func testAlreadyValidCoordinatesArePassedThrough() async throws {
        let snapshot = try await singleVehicleSnapshot(
            stateJSON: #"{"dump_energy":50,"loc":{"lat":-31.2304,"lon":-121.4737}}"#
        )
        XCTAssertEqual(snapshot.state.latitude ?? 0, -31.2304, accuracy: 1e-9)
        XCTAssertEqual(snapshot.state.longitude ?? 0, -121.4737, accuracy: 1e-9)
    }

    func testUnnormalisableCoordinatesBecomeNil() async throws {
        let snapshot = try await singleVehicleSnapshot(
            stateJSON: #"{"dump_energy":50,"loc":{"lat":10000000000,"lon":10000000000}}"#
        )
        XCTAssertNil(snapshot.state.latitude)
        XCTAssertNil(snapshot.state.longitude)
    }

    func testLocationInfoIsUsedWhenLocIsMissing() async throws {
        let snapshot = try await singleVehicleSnapshot(
            stateJSON: #"""
            {"dump_energy":50,"locationInfo":{"lat":39.9,"lon":116.4,"locationDesc":"陆家嘴"}}
            """#
        )
        XCTAssertEqual(snapshot.state.latitude ?? 0, 39.9, accuracy: 1e-9)
        XCTAssertEqual(snapshot.state.longitude ?? 0, 116.4, accuracy: 1e-9)
        XCTAssertEqual(snapshot.state.locationDescription, "陆家嘴")
        XCTAssertNil(snapshot.state.isLocked)
    }

    // MARK: - Battery voltage and temperature normalisation

    func testMilliVoltReadingsAreNormalised() async throws {
        let snapshot = try await singleVehicleSnapshot(
            stateJSON: #"{"dump_energy":50,"bms_volt":60500}"#
        )
        XCTAssertEqual(snapshot.state.batteryVoltage ?? 0, 60.5, accuracy: 1e-9)
    }

    func testDeciVoltReadingsAreNormalised() async throws {
        let snapshot = try await singleVehicleSnapshot(
            stateJSON: #"{"dump_energy":50,"battery_voltage":605}"#
        )
        XCTAssertEqual(snapshot.state.batteryVoltage ?? 0, 60.5, accuracy: 1e-9)
    }

    func testPlainVoltReadingsArePassedThrough() async throws {
        let snapshot = try await singleVehicleSnapshot(
            stateJSON: #"{"dump_energy":50,"battery_voltage":60.5}"#
        )
        XCTAssertEqual(snapshot.state.batteryVoltage ?? 0, 60.5, accuracy: 1e-9)
    }

    func testVoltageAtTheScalingBoundaryIsPassedThrough() async throws {
        // 120 is the inclusive upper bound of "already in volts".
        let snapshot = try await singleVehicleSnapshot(
            stateJSON: #"{"dump_energy":50,"battery_voltage":120}"#
        )
        XCTAssertEqual(snapshot.state.batteryVoltage ?? 0, 120, accuracy: 1e-9)
    }

    func testDeciDegreeTemperaturesAreNormalised() async throws {
        let snapshot = try await singleVehicleSnapshot(
            stateJSON: #"{"dump_energy":50,"bat_temp":285}"#
        )
        XCTAssertEqual(snapshot.state.batteryTemperature ?? 0, 28.5, accuracy: 1e-9)
    }

    func testNegativeDeciDegreeTemperaturesAreNormalised() async throws {
        let snapshot = try await singleVehicleSnapshot(
            stateJSON: #"{"dump_energy":50,"bat_temp":-250}"#
        )
        XCTAssertEqual(snapshot.state.batteryTemperature ?? 0, -25, accuracy: 1e-9)
    }

    func testPlainTemperaturesArePassedThrough() async throws {
        let snapshot = try await singleVehicleSnapshot(
            stateJSON: #"{"dump_energy":50,"bat_temp":-12.5}"#
        )
        XCTAssertEqual(snapshot.state.batteryTemperature ?? 0, -12.5, accuracy: 1e-9)
    }

    // MARK: - Server prediction

    func testDashboardPredictionIsParsed() async throws {
        let snapshot = try await singleVehicleSnapshot(
            stateJSON: #"{"dump_energy":50}"#,
            travelJSON: #"{"total_mileages":10}"#
        )
        // Sanity: the helper above carries no prediction.
        XCTAssertNil(snapshot.state.serverPrediction)

        route([
            "/vehicles": .json(#"{"ok":true,"data":[{"wnumber":"SN1"}]}"#),
            "/vehicles/SN1/dashboard": .json(#"""
            {"ok":true,"data":{
              "state":{"dump_energy":50},
              "travel":{"total_mileages":10},
              "prediction":{
                "model_version":"v3",
                "battery_percent":50,
                "range":{
                  "estimated_range_km":42.5,
                  "km_per_percent":0.85,
                  "sample_count":12,
                  "source":"local",
                  "ready":true
                },
                "charging":{
                  "is_charging":false,
                  "remaining_minutes":90,
                  "fast_minutes_per_percent":2.5,
                  "sample_count":7,
                  "ready":false
                }
              }
            }}
            """#)
        ])

        let dashboard = try await makeClient().fetchDashboard()
        let prediction = try XCTUnwrap(dashboard.vehicles.first?.state.serverPrediction)
        XCTAssertEqual(prediction.modelVersion, "v3")
        XCTAssertEqual(prediction.batteryPercent ?? 0, 50, accuracy: 1e-9)
        XCTAssertEqual(prediction.range.estimatedRange ?? 0, 42.5, accuracy: 1e-9)
        XCTAssertEqual(prediction.range.kmPerPercent ?? 0, 0.85, accuracy: 1e-9)
        XCTAssertEqual(prediction.range.sampleCount, 12)
        XCTAssertEqual(prediction.range.source, "local")
        XCTAssertEqual(prediction.range.isReady, true)
        XCTAssertEqual(prediction.charging.isCharging, false)
        XCTAssertEqual(prediction.charging.remainingMinutes ?? 0, 90, accuracy: 1e-9)
        XCTAssertEqual(prediction.charging.fastMinutesPerPercent ?? 0, 2.5, accuracy: 1e-9)
        XCTAssertEqual(prediction.charging.sampleCount, 7)
        XCTAssertEqual(prediction.charging.isReady, false)
    }

    func testPredictionWithNeitherRangeNorChargingIsDropped() async throws {
        route([
            "/vehicles": .json(#"{"ok":true,"data":[{"wnumber":"SN1"}]}"#),
            "/vehicles/SN1/dashboard": .json(#"""
            {"ok":true,"data":{
              "state":{"dump_energy":50},
              "travel":{"total_mileages":10},
              "prediction":{"model_version":"v3"}
            }}
            """#)
        ])
        let dashboard = try await makeClient().fetchDashboard()
        XCTAssertNil(dashboard.vehicles.first?.state.serverPrediction)
    }

    // MARK: - Ride records inside the dashboard

    func testTravelListBecomesRideRecords() async throws {
        let snapshot = try await singleVehicleSnapshot(
            stateJSON: #"{"dump_energy":50}"#,
            travelJSON: #"""
            {"total_mileages":9.2,"list":[
              {"travel_id":"T2","mileages":4.6,"ec":200,"used_electricity":4},
              {"travel_id":"T1","mileages":4.6,"ec":210,"used_electricity":5}
            ]}
            """#
        )
        let state = snapshot.state
        XCTAssertEqual(state.rideRecords?.count, 2)
        XCTAssertEqual(state.rideRecords?.first?.id, "T2")
        // "last" mirrors the first entry of the list.
        XCTAssertEqual(state.lastMileage ?? 0, 4.6, accuracy: 1e-9)
        XCTAssertEqual(state.lastEnergy ?? 0, 200, accuracy: 1e-9)
        XCTAssertEqual(state.lastUsedElectricity ?? 0, 4, accuracy: 1e-9)
        XCTAssertEqual(state.monthMileage ?? 0, 9.2, accuracy: 1e-9)
    }
}
