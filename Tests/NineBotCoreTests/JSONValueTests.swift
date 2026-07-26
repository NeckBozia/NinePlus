import XCTest
@testable import NineBotCore

/// `JSONValue` absorbs a backend that is inconsistent about types — numbers
/// arriving as strings, flags as 0/1 — so the coercions matter.
final class JSONValueTests: XCTestCase {
    private func decode(_ json: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
    }

    func testDecodesNestedStructures() throws {
        let value = try decode("""
        {
          "battery": 87,
          "name": "scooter",
          "charging": true,
          "missing": null,
          "list": [1, 2, 3],
          "loc": { "lat": 39.9, "lon": 116.4 }
        }
        """)

        XCTAssertEqual(value["battery"]?.intValue, 87)
        XCTAssertEqual(value["name"]?.stringValue, "scooter")
        XCTAssertEqual(value["charging"]?.boolValue, true)
        XCTAssertEqual(value["list"]?.arrayValue?.count, 3)
        XCTAssertEqual(value["loc"]?["lat"]?.doubleValue, 39.9)
        XCTAssertNotNil(value["missing"])
        XCTAssertNil(value["missing"]?.intValue)
        XCTAssertNil(value["absent"])
    }

    func testNumericStringsCoerceToNumbers() throws {
        let value = try decode("""
        { "voltage": "60.5", "cycles": "42" }
        """)
        XCTAssertEqual(value["voltage"]?.doubleValue ?? 0, 60.5, accuracy: 1e-9)
        XCTAssertEqual(value["cycles"]?.intValue, 42)
    }

    func testNumbersCoerceToStrings() throws {
        let value = try decode("""
        { "whole": 42, "fractional": 1.5 }
        """)
        XCTAssertEqual(value["whole"]?.stringValue, "42")
        XCTAssertEqual(value["fractional"]?.stringValue, "1.5")
    }

    func testBooleanLikeValues() throws {
        let value = try decode("""
        { "a": 1, "b": 0, "c": "true", "d": "off", "e": "maybe" }
        """)
        XCTAssertEqual(value["a"]?.boolValue, true)
        XCTAssertEqual(value["b"]?.boolValue, false)
        XCTAssertEqual(value["c"]?.boolValue, true)
        XCTAssertEqual(value["d"]?.boolValue, false)
        XCTAssertNil(value["e"]?.boolValue)
    }

    func testRoundTripsThroughEncoding() throws {
        let original = try decode("""
        { "a": [1, "two", true, null], "b": { "c": 3.5 } }
        """)
        let reencoded = try JSONDecoder().decode(
            JSONValue.self,
            from: JSONEncoder().encode(original)
        )
        XCTAssertEqual(original, reencoded)
    }

    func testTopLevelArray() throws {
        let value = try decode("[{ \"sn\": \"A1\" }, { \"sn\": \"B2\" }]")
        XCTAssertEqual(value.arrayValue?.count, 2)
        XCTAssertEqual(value.arrayValue?.first?["sn"]?.stringValue, "A1")
        XCTAssertNil(value.objectValue)
    }
}
