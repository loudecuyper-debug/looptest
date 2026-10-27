import XCTest
@testable import LoopCore

/// Loopdagen wijzigen zonder nieuw plan, en zelf de kwaliteitsdagen kiezen (27 okt 2026).
/// Testprofiel: start maandag 19 okt, di rustig, do fartlek, zo lange loop, 12 weken.
/// Fases: week 0-3 opbouw, 4-7 zwaarder, 8-10 piek, 11 taper. Rustweken: 3 en 7.
final class DayScheduleTests: XCTestCase {

    private var utc: Calendar {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func input(quality: [Weekday]? = nil) -> PlanInput {
        PlanInput(goal: .faster, goalDistance: 10_000, weeks: 12,
                  startDate: utc.date(from: DateComponents(year: 2026, month: 10, day: 19))!,
                  recentDistance: 5_000, recentTime: 25 * 60,
                  weeklyVolumeKm: 15, longestRunKm: 8,
                  runDays: [.tuesday, .thursday, .sunday], longRunDay: .sunday, qualityDays: quality)
    }

    private func week(_ c: Coach, _ w: Int) throws -> PlanWeek {
        try XCTUnwrap(c.plan(calendar: utc)).weeks[w]
    }

    private let four: [Weekday] = [.tuesday, .thursday, .saturday, .sunday]

    // MARK: - Vanaf deze week

    func testChangeFromThisWeekWhenNothingRun() throws {
        var c = Coach(input: input())
        let before = try XCTUnwrap(c.plan(calendar: utc))

        let from = c.changeDays(four, longRunDay: .thursday, qualityDays: [.tuesday],
                                today: PlanDay(week: 1, day: .tuesday))
        XCTAssertEqual(from, 1)

        // Week 0 blijft zoals ze was.
        XCTAssertEqual(try week(c, 0), before.weeks[0])

        // Week 1 (opbouw): kwaliteit op dinsdag, lange loop donderdag, rustig in het weekend.
        let w1 = try week(c, 1)
        XCTAssertEqual(w1.workouts.map(\.day), four)
        XCTAssertEqual(w1.workout(on: .tuesday)?.type.isQuality, true)
        XCTAssertEqual(w1.workout(on: .thursday)?.type, .long)
        XCTAssertEqual(w1.workout(on: .saturday)?.type, .easy)
        XCTAssertEqual(w1.workout(on: .sunday)?.type, .easy)

        // Data, fase en niveau schuiven niet op.
        let after = try XCTUnwrap(c.plan(calendar: utc))
        XCTAssertEqual(after.weeks.map(\.startDate), before.weeks.map(\.startDate))
        XCTAssertEqual(after.weeks.map(\.phase), before.weeks.map(\.phase))
        XCTAssertEqual(after.weeks.map(\.isRecoveryWeek), before.weeks.map(\.isRecoveryWeek))
    }

    func testSecondQualitySessionInBuildPhase() throws {
        var c = Coach(input: input())
        c.changeDays(four, longRunDay: .thursday, qualityDays: [.tuesday], today: PlanDay(week: 1, day: .tuesday))

        // Week 5 (zwaarder, geen rustweek): tweede kwaliteitssessie automatisch op zaterdag
        // (zaterdag en zondag liggen even ver van do en di, dan de vroegste dag).
        let w5 = try week(c, 5)
        XCTAssertEqual(w5.workouts.map(\.day), four)
        XCTAssertEqual(w5.workout(on: .tuesday)?.type.isQuality, true)
        XCTAssertEqual(w5.workout(on: .saturday)?.type.isQuality, true)
        XCTAssertEqual(w5.workout(on: .sunday)?.type, .easy)
    }

    func testChosenSecondQualityDay() throws {
        var c = Coach(input: input())
        c.changeDays(four, longRunDay: .thursday, qualityDays: [.tuesday, .sunday],
                     today: PlanDay(week: 1, day: .tuesday))
        let w5 = try week(c, 5)
        XCTAssertEqual(w5.workout(on: .sunday)?.type.isQuality, true)
        XCTAssertEqual(w5.workout(on: .saturday)?.type, .easy)
        // In de opbouw maar één sessie: enkel de eerste gekozen dag.
        let w2 = try week(c, 2)
        XCTAssertEqual(w2.workout(on: .tuesday)?.type.isQuality, true)
        XCTAssertEqual(w2.workout(on: .sunday)?.type, .easy)
    }

    func testPastDaysOfThisWeekDropOut() throws {
        var c = Coach(input: input())
        let days: [Weekday] = [.monday, .wednesday, .friday, .sunday]
        XCTAssertEqual(c.changeDays(days, longRunDay: .sunday, today: PlanDay(week: 1, day: .thursday)), 1)
        XCTAssertEqual(try week(c, 1).workouts.map(\.day), [.friday, .sunday])
        XCTAssertEqual(try week(c, 2).workouts.map(\.day), days)
    }

    // MARK: - Vanaf volgende week

    func testChangeFromNextWeekWhenAlreadyRun() throws {
        var c = Coach(input: input())
        _ = c.record(RunResult(when: PlanDay(week: 1, day: .tuesday), rpe: 3))
        let before = try week(c, 1)

        XCTAssertEqual(c.changeDays(four, longRunDay: .thursday, today: PlanDay(week: 1, day: .wednesday)), 2)
        XCTAssertEqual(try week(c, 1), before)
        XCTAssertEqual(try week(c, 2).workouts.map(\.day), four)
    }

    func testMissedSessionAlsoCountsAsActivity() throws {
        var c = Coach(input: input())
        _ = c.catchUp(until: PlanDay(week: 1, day: .wednesday))   // dinsdag van week 1 gemist
        XCTAssertEqual(c.changeDays(four, longRunDay: .thursday, today: PlanDay(week: 1, day: .wednesday)), 2)
    }

    // MARK: - Overige regels

    func testMovesFromThatWeekOnAreCleared() throws {
        var c = Coach(input: input())
        XCTAssertEqual(c.moveWorkout(at: PlanDay(week: 2, day: .tuesday), to: .wednesday), .moved(warning: nil))
        XCTAssertFalse(c.state.adjustment(forWeek: 2).moves.isEmpty)
        c.changeDays(four, longRunDay: .thursday, today: PlanDay(week: 1, day: .tuesday))
        XCTAssertTrue(c.state.adjustment(forWeek: 2).moves.isEmpty)
    }

    func testChangeAgainReplacesLaterSchedules() throws {
        var c = Coach(input: input())
        c.changeDays(four, longRunDay: .thursday, today: PlanDay(week: 1, day: .tuesday))
        c.changeDays([.monday, .wednesday, .saturday], longRunDay: .saturday, today: PlanDay(week: 1, day: .tuesday))
        XCTAssertEqual(c.state.daySchedules?.count, 1)
        XCTAssertEqual(try week(c, 3).workouts.map(\.day), [.monday, .wednesday, .saturday])
        XCTAssertEqual(c.days(forWeek: 3).longRunDay, .saturday)
        XCTAssertEqual(c.days(forWeek: 0).runDays, [.tuesday, .thursday, .sunday])
    }

    func testInvalidChoiceIsRefused() {
        var c = Coach(input: input())
        XCTAssertNil(c.changeDays([.tuesday], longRunDay: .tuesday, today: nil))
        XCTAssertNil(c.changeDays(four, longRunDay: .monday, today: nil))
        XCTAssertNil(c.state.daySchedules)
    }

    func testBeforeStartAppliesFromWeekOne() throws {
        var c = Coach(input: input())
        XCTAssertEqual(c.changeDays(four, longRunDay: .thursday, today: nil), 0)
        XCTAssertEqual(try week(c, 0).workouts.map(\.day), four)
    }

    func testRaceDateFollowsNewLongRunDay() throws {
        var c = Coach(input: input())
        c.changeDays(four, longRunDay: .thursday, today: PlanDay(week: 1, day: .tuesday))
        let plan = try XCTUnwrap(c.plan(calendar: utc))
        let last = try XCTUnwrap(plan.weeks.last)
        XCTAssertEqual(last.workout(on: .thursday)?.type, .test)
        XCTAssertEqual(plan.raceDate(calendar: utc), last.date(for: .thursday, calendar: utc))
    }

    func testQualityDayFromPlanInput() throws {
        let c = Coach(input: input(quality: [.tuesday]))
        let w0 = try week(c, 0)
        XCTAssertEqual(w0.workout(on: .tuesday)?.type.isQuality, true)
        XCTAssertEqual(w0.workout(on: .thursday)?.type, .easy)
        // Zonder keuze blijft het zoals voorheen: fartlek op donderdag.
        XCTAssertEqual(try week(Coach(input: input()), 0).workout(on: .thursday)?.title, "Fartlek")
    }

    func testPickQualityDaysIgnoresInvalidPreferences() {
        let picked = PlanGenerator.pickQualityDays(days: [.tuesday, .thursday, .sunday], longRunDay: .sunday,
                                                   count: 1, preferred: [.sunday, .monday])
        XCTAssertEqual(picked, [.thursday])
    }

    func testSchedulesSurviveCodable() throws {
        var c = Coach(input: input(quality: [.thursday]))
        c.changeDays(four, longRunDay: .thursday, qualityDays: [.tuesday], today: PlanDay(week: 1, day: .tuesday))
        let data = try JSONEncoder().encode(c)
        let back = try JSONDecoder().decode(Coach.self, from: data)
        XCTAssertEqual(back, c)
        XCTAssertEqual(back.plan(calendar: utc), c.plan(calendar: utc))
    }

    func testOldDataWithoutNewFieldsLoads() throws {
        let c = Coach(input: input())
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(c)) as? [String: Any])
        var inputJSON = try XCTUnwrap(json["input"] as? [String: Any])
        inputJSON.removeValue(forKey: "qualityDays")
        json["input"] = inputJSON
        var state = try XCTUnwrap(json["state"] as? [String: Any])
        state.removeValue(forKey: "daySchedules")
        json["state"] = state
        let back = try JSONDecoder().decode(Coach.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(back.plan(calendar: utc), c.plan(calendar: utc))
    }
}
