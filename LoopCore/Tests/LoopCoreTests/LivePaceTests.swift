import XCTest
@testable import LoopCore

/// Tempo "nu" op het loopscherm (22 okt 2026).
/// Grenzen nagerekend met een Python-port van `LivePace` (zelfde ruisgenerator).
final class LivePaceTests: XCTestCase {

    /// Vaste ruis, op elk platform dezelfde reeks.
    private struct Noise {
        var state: UInt64
        mutating func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(UInt64(1) << 53)
        }
        mutating func value(_ amplitude: Double) -> Double { (next() * 2 - 1) * amplitude }
    }

    private let sixMinutes = 1000.0 / 360   // 6:00 per km in m/s

    func testSteadyPaceStaysCalm() throws {
        // Doppler met ±0,3 m/s ruis (= ±40 s per km): na het filter blijft het binnen ±30 s.
        var noise = Noise(state: 42)
        var live = LivePace()
        for t in 0..<300 {
            live.addGPS(speed: sixMinutes + noise.value(0.3), speedAccuracy: 0.4, at: Double(t))
            if t >= 10 {
                let p = try XCTUnwrap(live.pace(at: Double(t)))
                XCTAssertGreaterThan(p, 330, "t=\(t)")
                XCTAssertLessThan(p, 390, "t=\(t)")
            }
        }
        XCTAssertEqual(live.source, .gps)
    }

    func testIntervalChangeShowsWithinTenSeconds() throws {
        // Van 6:10 naar 4:50 op t = 100.
        var noise = Noise(state: 3)
        var live = LivePace()
        var at: [Int: Double] = [:]
        for t in 0..<200 {
            let v = t < 100 ? 1000.0 / 370 : 1000.0 / 290
            live.addGPS(speed: v + noise.value(0.2), speedAccuracy: 0.4, at: Double(t))
            at[t] = live.pace(at: Double(t))
        }
        let before = try XCTUnwrap(at[99])
        XCTAssertEqual(before, 370, accuracy: 6)
        XCTAssertLessThan(try XCTUnwrap(at[110]), 310)
        XCTAssertEqual(try XCTUnwrap(at[130]), 290, accuracy: 6)
    }

    func testSingleSpikeIsIgnored() throws {
        var live = LivePace()
        for t in 0..<60 {
            live.addGPS(speed: t == 40 ? 6.0 : sixMinutes, speedAccuracy: 0.4, at: Double(t))
            if t == 41 {
                XCTAssertEqual(try XCTUnwrap(live.pace(at: 41)), 360, accuracy: 2)
            }
        }
    }

    func testHoldThenPedometerTakesOver() throws {
        var live = LivePace()
        for t in 0..<60 { live.addGPS(speed: sixMinutes, speedAccuracy: 0.4, at: Double(t)) }
        var at: [Int: (Double?, LivePace.Source?)] = [:]
        for t in 60..<120 {
            live.addGPS(speed: -1, speedAccuracy: -1, at: Double(t))
            if t % 3 == 0 { live.addPedometer(paceSecondsPerKm: 380, at: Double(t)) }
            at[t] = (live.pace(at: Double(t)), live.source)
        }
        // Eerst 10 s de laatste GPS-waarde vasthouden.
        XCTAssertEqual(try XCTUnwrap(at[70]?.0), 360, accuracy: 0.5)
        XCTAssertEqual(at[70]?.1, .gps)
        // Daarna de pasteller.
        XCTAssertGreaterThan(try XCTUnwrap(at[90]?.0), 370)
        XCTAssertEqual(at[90]?.1, .pedometer)
        XCTAssertEqual(try XCTUnwrap(at[119]?.0), 380, accuracy: 3)
    }

    func testPedometerIgnoredWhileGpsIsGood() throws {
        var live = LivePace()
        for t in 0..<60 {
            live.addGPS(speed: sixMinutes, speedAccuracy: 0.4, at: Double(t))
            live.addPedometer(paceSecondsPerKm: 420, at: Double(t))
        }
        XCTAssertEqual(try XCTUnwrap(live.pace(at: 59)), 360, accuracy: 0.5)
        XCTAssertEqual(live.source, .gps)
    }

    func testBackToGpsAfterPedometer() throws {
        var live = LivePace()
        for t in 0..<20 { live.addPedometer(paceSecondsPerKm: 400, at: Double(t)) }
        XCTAssertEqual(try XCTUnwrap(live.pace(at: 19)), 400, accuracy: 0.5)
        XCTAssertEqual(live.source, .pedometer)
        for t in 20..<60 { live.addGPS(speed: sixMinutes, speedAccuracy: 0.4, at: Double(t)) }
        XCTAssertEqual(try XCTUnwrap(live.pace(at: 59)), 360, accuracy: 2)
        XCTAssertEqual(live.source, .gps)
    }

    func testStaleAfterFifteenSeconds() {
        var live = LivePace()
        for t in 0..<60 { live.addGPS(speed: sixMinutes, speedAccuracy: 0.4, at: Double(t)) }
        XCTAssertNotNil(live.pace(at: 74))
        XCTAssertNil(live.pace(at: 75.1))
    }

    func testStandingStillGivesNoPace() {
        var live = LivePace()
        for t in 0..<60 { live.addGPS(speed: 0.3, speedAccuracy: 0.4, at: Double(t)) }
        XCTAssertNil(live.pace(at: 59))
    }

    func testUnusableSpeedAloneGivesNothing() {
        var live = LivePace()
        for t in 0..<30 { live.addGPS(speed: 2.8, speedAccuracy: 3.0, at: Double(t)) }
        XCTAssertNil(live.pace(at: 29))
        XCTAssertFalse(LivePace.isUsable(speed: -1, speedAccuracy: 0.3))
        XCTAssertFalse(LivePace.isUsable(speed: 2.8, speedAccuracy: -1))
        XCTAssertTrue(LivePace.isUsable(speed: 2.8, speedAccuracy: 1.5))
    }

    func testReset() {
        var live = LivePace()
        for t in 0..<20 { live.addGPS(speed: sixMinutes, speedAccuracy: 0.4, at: Double(t)) }
        live.reset()
        XCTAssertNil(live.pace(at: 20))
        XCTAssertNil(live.source)
    }

    func testMedian() {
        XCTAssertEqual(LivePace.median([3, 1, 2]), 2)
        XCTAssertEqual(LivePace.median([4, 1, 3, 2]), 2.5)
    }
}
