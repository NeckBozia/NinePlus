import XCTest
@testable import NineBotCore

final class CoordinateTransformTests: XCTestCase {
    func testCoordinatesOutsideMainlandChinaAreLeftUntouched() {
        // Tokyo — outside the transform's bounding box.
        let tokyo = NinebotCoordinateTransform.gcj02Coordinate(latitude: 35.6812, longitude: 139.7671)
        XCTAssertEqual(tokyo.latitude, 35.6812, accuracy: 1e-9)
        XCTAssertEqual(tokyo.longitude, 139.7671, accuracy: 1e-9)

        // London — well west of the box.
        let london = NinebotCoordinateTransform.gcj02Coordinate(latitude: 51.5074, longitude: -0.1278)
        XCTAssertEqual(london.latitude, 51.5074, accuracy: 1e-9)
        XCTAssertEqual(london.longitude, -0.1278, accuracy: 1e-9)
    }

    func testMainlandCoordinatesAreShiftedByAPlausibleAmount() {
        let latitude = 39.90869
        let longitude = 116.39123
        let shifted = NinebotCoordinateTransform.gcj02Coordinate(latitude: latitude, longitude: longitude)

        XCTAssertNotEqual(shifted.latitude, latitude)
        XCTAssertNotEqual(shifted.longitude, longitude)

        // The GCJ-02 offset in Beijing is a few hundred metres, never kilometres.
        let metresPerDegree = 111_000.0
        let latitudeShift = abs(shifted.latitude - latitude) * metresPerDegree
        let longitudeShift = abs(shifted.longitude - longitude) * metresPerDegree * cos(latitude * .pi / 180)

        XCTAssertGreaterThan(latitudeShift, 20)
        XCTAssertLessThan(latitudeShift, 1_000)
        XCTAssertGreaterThan(longitudeShift, 20)
        XCTAssertLessThan(longitudeShift, 1_000)
    }

    func testTransformIsDeterministic() {
        let first = NinebotCoordinateTransform.gcj02Coordinate(latitude: 31.2304, longitude: 121.4737)
        let second = NinebotCoordinateTransform.gcj02Coordinate(latitude: 31.2304, longitude: 121.4737)
        XCTAssertEqual(first, second)
    }

    func testMainlandBoundingBox() {
        XCTAssertTrue(NinebotCoordinateTransform.isInsideMainlandChina(latitude: 39.9, longitude: 116.4))
        XCTAssertTrue(NinebotCoordinateTransform.isInsideMainlandChina(latitude: 22.5, longitude: 114.0))
        XCTAssertFalse(NinebotCoordinateTransform.isInsideMainlandChina(latitude: 35.68, longitude: 139.77))
        XCTAssertFalse(NinebotCoordinateTransform.isInsideMainlandChina(latitude: 0.5, longitude: 116.4))
    }
}
