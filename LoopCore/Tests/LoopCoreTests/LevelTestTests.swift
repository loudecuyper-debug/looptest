import XCTest
@testable import LoopCore

/// Niveautest uit een gelopen loop en niveau zelf aanpassen (20 okt 2026).
/// Verwachte waarden nagerekend in Python met dezelfde Daniels/Gilbert-formules.
final class LevelTestTests: XCTestCase {

    private var utc: Calendar {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private let current = 38.309   // 5 km in 25:00

    func testShortAllOutCountsHalf() throws {
        // 4,02 km in 18:14 (eerste vrije loop van Louis, 20 okt).
        let measured = try XCTUnwrap(LevelTest.measured(distance: 4_020, time: 18 * 60 + 14))
        XCTAssertEqual(measured, 42.38, accuracy: 0.02)
        XCTAssertTrue(LevelTest.countsHalf(distance: 4_020))
        XCTAssertEqual(LevelTest.suggested(distance: 4_020, time: 18 * 60 + 14, current: current), 40.0)
    }

    func testFiveKmCountsFully() {
        XCTAssertFalse(LevelTest.countsHalf(distance: 5_000))
        XCTAssertEqual(LevelTest.suggested(distance: 5_000, time: 22 * 60 + 57, current: current), 42.0)
        XCTAssertEqual(LevelTest.suggested(distance: 5_000, time: 27 * 60, current: current), 34.5)
    }

    func testShortSlowerRunLowersHalf() {
        // 3 km in 15:00 meet 37,0: de helft van het verschil, naar beneden afgerond.
        XCTAssertEqual(LevelTest.suggested(distance: 3_000, time: 15 * 60, current: current), 37.5)
    }

    func testTooShortGivesNothing() {
        XCTAssertNil(LevelTest.suggested(distance: 1_000, time: 4 * 60, current: current))
    }

    func testRoundDownHalf() {
        XCTAssertEqual(LevelTest.roundDownHalf(40.35), 40.0)
        XCTAssertEqual(LevelTest.roundDownHalf(40.5), 40.5)
        XCTAssertEqual(LevelTest.roundDownHalf(40.99), 40.5)
    }

    func testSetLevelChangesPlanFromWeek() throws {
        let input = PlanInput(goal: .faster, goalDistance: 10_000, weeks: 12,
                              startDate: utc.date(from: DateComponents(year: 2026, month: 10, day: 19))!,
                              recentDistance: 5_000, recentTime: 25 * 60,
                              weeklyVolumeKm: 15, longestRunKm: 8,
                              runDays: [.tuesday, .thursday, .sunday], longRunDay: .sunday)
        var coach = Coach(input: input)
        coach.setLevel(40, fromWeek: 0)
        let plan = try XCTUnwrap(coach.plan(calendar: utc))
        XCTAssertEqual(plan.weeks[0].vdot, 40)
        XCTAssertEqual(plan.weeks[11].vdot, 40)
        XCTAssertEqual(coach.state.levelChanges.last, LevelChange(fromWeek: 0, vdot: 40))

        // Later opnieuw aanpassen vanaf week 3: eerdere weken blijven op 40.
        coach.setLevel(41, fromWeek: 2)
        let again = try XCTUnwrap(coach.plan(calendar: utc))
        XCTAssertEqual(again.weeks[1].vdot, 40)
        XCTAssertEqual(again.weeks[2].vdot, 41)
    }

    func testSetLevelIsClamped() {
        var coach = Coach(input: PlanInput(goal: .faster, goalDistance: 10_000, weeks: 12, startDate: Date(),
                                           recentDistance: 5_000, recentTime: 25 * 60,
                                           weeklyVolumeKm: 15, longestRunKm: 8,
                                           runDays: [.tuesday, .sunday], longRunDay: .sunday))
        coach.setLevel(120, fromWeek: -3)
        XCTAssertEqual(coach.state.levelChanges.last, LevelChange(fromWeek: 0, vdot: 85))
    }

    func testSetLevelSurvivesCodable() throws {
        var coach = Coach(input: PlanInput(goal: .faster, goalDistance: 10_000, weeks: 12, startDate: Date(),
                                           recentDistance: 5_000, recentTime: 25 * 60,
                                           weeklyVolumeKm: 15, longestRunKm: 8,
                                           runDays: [.tuesday, .sunday], longRunDay: .sunday))
        coach.setLevel(40, fromWeek: 0)
        let data = try JSONEncoder().encode(coach)
        let back = try JSONDecoder().decode(Coach.self, from: data)
        XCTAssertEqual(back.state.levelChanges, coach.state.levelChanges)
    }
}
