import XCTest
@testable import LoopCore

final class PaceZonesTests: XCTestCase {

    private func louis() throws -> PaceZones {
        try XCTUnwrap(PaceZones(distance: 5_000, time: 25 * 60))
    }

    /// Daniels-tabel rond VDOT 38: tempo ~5:16, interval ~4:51, snelheid ~4:28 per km.
    func testLouisZonesMatchDaniels() throws {
        let z = try louis()
        XCTAssertEqual(z.threshold.target, 5 * 60 + 17, accuracy: 6)
        XCTAssertEqual(z.interval.target, 4 * 60 + 50, accuracy: 6)
        XCTAssertEqual(z.repetition.target, 4 * 60 + 28, accuracy: 6)
        XCTAssertEqual(z.easy.fast, 6 * 60 + 19, accuracy: 3)
        XCTAssertEqual(z.easy.slow, 6 * 60 + 57, accuracy: 3)
    }

    func testZonesGetFasterInOrder() throws {
        let z = try louis()
        let order: [PaceZone] = [.recovery, .easy, .marathon, .threshold, .interval, .repetition]
        for (a, b) in zip(order, order.dropFirst()) {
            XCTAssertGreaterThan(z.range(for: a).target, z.range(for: b).target,
                                 "\(a.name) moet trager zijn dan \(b.name)")
        }
    }

    func testRangesAreWellFormed() throws {
        let z = try louis()
        for zone in PaceZone.allCases {
            let r = z.range(for: zone)
            XCTAssertLessThan(r.fast, r.slow, zone.name)
        }
    }

    func testTenKRacePaceSitsBetweenThresholdAndInterval() throws {
        let z = try louis()
        let p = z.racePace(distance: 10_000)
        XCTAssertLessThan(p, z.threshold.target)
        XCTAssertGreaterThan(p, z.interval.target)
    }

    func testDeviation() {
        let r = PaceRange(fast: 300, slow: 320)
        XCTAssertEqual(r.deviation(of: 290), -10)
        XCTAssertEqual(r.deviation(of: 310), 0)
        XCTAssertEqual(r.deviation(of: 335), 15)
        XCTAssertTrue(r.contains(325, tolerance: 5))
        XCTAssertFalse(r.contains(326, tolerance: 5))
    }

    func testRangeNormalisesOrder() {
        let r = PaceRange(fast: 320, slow: 300)
        XCTAssertEqual(r.fast, 300)
        XCTAssertEqual(r.slow, 320)
    }

    func testAdjustedMakesFaster() throws {
        let z = try louis()
        let better = z.adjusted(byVdot: 1)
        XCTAssertLessThan(better.threshold.target, z.threshold.target)
        XCTAssertEqual(better.vdot, z.vdot + 1, accuracy: 0.0001)
    }

    func testVdotIsClamped() {
        XCTAssertEqual(PaceZones(vdot: 5).vdot, Vdot.validRange.lowerBound)
        XCTAssertEqual(PaceZones(vdot: 200).vdot, Vdot.validRange.upperBound)
    }

    func testCodableRoundTrip() throws {
        let z = try louis()
        let data = try JSONEncoder().encode(z)
        let back = try JSONDecoder().decode(PaceZones.self, from: data)
        XCTAssertEqual(z, back)
    }

    func testTimeText() {
        XCTAssertEqual(TimeText.clock(316), "5:16")
        XCTAssertEqual(TimeText.clock(59.6), "1:00")
        XCTAssertEqual(TimeText.clock(3725), "1:02:05")
        XCTAssertEqual(TimeText.distance(400), "400 m")
        XCTAssertEqual(TimeText.distance(10_000), "10 km")
        XCTAssertEqual(TimeText.distance(21_097.5), "21,1 km")
    }
}
