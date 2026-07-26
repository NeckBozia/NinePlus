import XCTest
@testable import NineBotCore

/// Which account a vehicle belongs to. The picker used to group by the
/// displayed Chinese title, so this identity and the on-screen text were the
/// same value.
final class VehicleAccountTests: XCTestCase {

    private func vehicle(sn: String = "SN1", raw: [String: JSONValue]? = nil) -> NinebotVehicleInfo {
        NinebotVehicleInfo(sn: sn, name: "车", model: "M", imageURLString: nil, raw: raw)
    }

    private func account(_ raw: [String: JSONValue]?, boundPhone: String? = nil) -> NinebotVehicleAccount {
        NinebotVehicleAccount(vehicle: vehicle(raw: raw), boundPhone: boundPhone)
    }

    // MARK: - Reading the account out of the payload

    func testPrefersTheEarliestKeyInThePriorityList() {
        // "account" outranks "phone", which outranks "uuid".
        let a = account(["uuid": .string("u"), "phone": .string("p"), "account": .string("a")])
        XCTAssertEqual(a, .identified("a"))

        let b = account(["uuid": .string("u"), "phone": .string("p")])
        XCTAssertEqual(b, .identified("p"))
    }

    func testAcceptsBothSnakeAndCamelKeys() {
        XCTAssertEqual(account(["user_phone": .string("x")]), .identified("x"))
        XCTAssertEqual(account(["userPhone": .string("y")]), .identified("y"))
    }

    func testValueIsTrimmed() {
        XCTAssertEqual(account(["account": .string("  a  ")]), .identified("a"))
    }

    /// A key that is present but blank does not count — it falls through to the
    /// next candidate rather than producing an empty identity.
    func testBlankValueFallsThrough() {
        XCTAssertEqual(account(["account": .string("   "), "phone": .string("p")]), .identified("p"))
        XCTAssertEqual(account(["account": .string("")], boundPhone: "13800138000"), .boundPhone("13800138000"))
    }

    /// A numeric uid works too — `JSONValue.stringValue` renders a whole number
    /// without a decimal point, so `42` reads as "42" rather than "42.0".
    func testNumericIdentifierIsAccepted() {
        XCTAssertEqual(account(["user_id": .number(42)]), .identified("42"))
    }

    // MARK: - Falling back

    func testFallsBackToTheBoundPhone() {
        XCTAssertEqual(account(nil, boundPhone: "13800138000"), .boundPhone("13800138000"))
        XCTAssertEqual(account([:], boundPhone: "13800138000"), .boundPhone("13800138000"))
    }

    func testBlankOrMissingBoundPhoneIsCurrent() {
        XCTAssertEqual(account(nil), .current)
        XCTAssertEqual(account(nil, boundPhone: ""), .current)
        XCTAssertEqual(account(nil, boundPhone: "   "), .current)
    }

    // MARK: - Identity

    func testIdsAreAsciiAndDistinctPerCase() {
        XCTAssertEqual(NinebotVehicleAccount.identified("a").id, "identified:a")
        XCTAssertEqual(NinebotVehicleAccount.boundPhone("a").id, "phone:a")
        XCTAssertEqual(NinebotVehicleAccount.current.id, "current")
        // Same value, different provenance — must not collide.
        XCTAssertNotEqual(
            NinebotVehicleAccount.identified("a").id,
            NinebotVehicleAccount.boundPhone("a").id
        )
    }

    /// Grouping relies on this: two vehicles reporting the same account are the
    /// same group, a third reporting another account is not.
    func testEqualityGroupsVehicles() {
        let first = account(["account": .string("A")])
        let second = NinebotVehicleAccount(vehicle: vehicle(sn: "SN2", raw: ["account": .string("A")]), boundPhone: nil)
        let third = account(["account": .string("B")])

        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first, third)
        XCTAssertEqual(Set([first, second, third]).count, 2)
    }

    func testKeyListIsTheOneTheViewUsedToCarry() {
        XCTAssertEqual(NinebotVehicleAccount.accountKeys.first, "account")
        XCTAssertEqual(NinebotVehicleAccount.accountKeys.count, 17)
        XCTAssertEqual(Set(NinebotVehicleAccount.accountKeys).count, 17)
    }
}
