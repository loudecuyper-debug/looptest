import XCTest
@testable import LoopCore

final class VdotTests: XCTestCase {

    func testLouis5kIn25MinutesGivesVdot38() throws {
        let v = try XCTUnwrap(Vdot.from(distance: 5_000, time: 25 * 60))
        XCTAssertEqual(v, 38.3, accuracy: 0.1)
    }

    /// Vergelijken met de gepubliceerde Daniels-tabel (VDOT 50).
    func testMatchesDanielsTableAtVdot50() {
        XCTAssertEqual(Vdot.predictedTime(distance: 5_000, vdot: 50), 19 * 60 + 57, accuracy: 5)
        XCTAssertEqual(Vdot.predictedTime(distance: 10_000, vdot: 50), 41 * 60 + 21, accuracy: 8)
        XCTAssertEqual(Vdot.predictedTime(distance: 42_195, vdot: 50), 3 * 3600 + 10 * 60 + 49, accuracy: 30)
    }

    /// Vergelijken met de gepubliceerde Daniels-tabel (VDOT 30).
    func testMatchesDanielsTableAtVdot30() {
        XCTAssertEqual(Vdot.predictedTime(distance: 5_000, vdot: 30), 30 * 60 + 40, accuracy: 5)
        XCTAssertEqual(Vdot.predictedTime(distance: 10_000, vdot: 30), 63 * 60 + 46, accuracy: 10)
    }

    func testPredictionRoundTrip() throws {
        let v = try XCTUnwrap(Vdot.from(distance: 5_000, time: 1_500))
        XCTAssertEqual(Vdot.predictedTime(distance: 5_000, vdot: v), 1_500, accuracy: 1)
    }

    func testLongerDistanceIsSlowerPace() {
        let v = 38.3
        XCTAssertLessThan(Vdot.predictedPace(distance: 5_000, vdot: v),
                          Vdot.predictedPace(distance: 10_000, vdot: v))
        XCTAssertLessThan(Vdot.predictedPace(distance: 10_000, vdot: v),
                          Vdot.predictedPace(distance: 42_195, vdot: v))
    }

    func testHigherVdotIsFaster() {
        XCTAssertLessThan(Vdot.predictedTime(distance: 10_000, vdot: 42),
                          Vdot.predictedTime(distance: 10_000, vdot: 38))
    }

    func testRejectsNonsense() {
        XCTAssertNil(Vdot.from(distance: 400, time: 90))          // te kort
        XCTAssertNil(Vdot.from(distance: 5_000, time: 0))         // geen tijd
        XCTAssertNil(Vdot.from(distance: 5_000, time: 5 * 60))    // 1:00 per km
        XCTAssertNil(Vdot.from(distance: 5_000, time: 120 * 60))  // 24:00 per km
    }

    func testCooperTest() throws {
        let v = try XCTUnwrap(Vdot.fromCooperTest(distance: 2_400))
        XCTAssertEqual(v, 36.3, accuracy: 0.2)
    }

    func testVelocityIsInverseOfOxygenCost() {
        for v in stride(from: 120.0, through: 400, by: 20) {
            let vo2 = Vdot.oxygenCost(metersPerMinute: v)
            XCTAssertEqual(Vdot.velocity(forOxygenCost: vo2), v, accuracy: 0.001)
        }
    }
}
