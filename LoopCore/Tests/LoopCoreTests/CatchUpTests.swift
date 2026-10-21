import XCTest
@testable import LoopCore

/// Gemiste trainingen automatisch noteren, weken afsluiten en achteraf koppelen (20 okt 2026).
/// Testprofiel: start maandag 19 okt, di rustig, do fartlek, zo lange loop.
final class CatchUpTests: XCTestCase {

    private var utc: Calendar {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func coach() -> Coach {
        Coach(input: PlanInput(goal: .faster, goalDistance: 10_000, weeks: 12,
                               startDate: utc.date(from: DateComponents(year: 2026, month: 10, day: 19))!,
                               recentDistance: 5_000, recentTime: 25 * 60,
                               weeklyVolumeKm: 15, longestRunKm: 8,
                               runDays: [.tuesday, .thursday, .sunday], longRunDay: .sunday))
    }

    private func week(_ c: Coach, _ w: Int) throws -> PlanWeek {
        try XCTUnwrap(c.plan(calendar: utc)).weeks[w]
    }

    func testPlanAsExpected() throws {
        let w = try week(coach(), 0)
        XCTAssertEqual(w.workouts.map(\.day), [.tuesday, .thursday, .sunday])
        XCTAssertEqual(w.workout(on: .thursday)?.title, "Fartlek")
        XCTAssertEqual(w.workout(on: .sunday)?.type, .long)
    }

    func testMissedSessionsUntilFriday() throws {
        var c = coach()
        let events = c.catchUp(until: PlanDay(week: 0, day: .friday))
        // Dinsdag rustig: valt weg zonder melding. Donderdag fartlek: schuift naar vrijdag (vandaag).
        XCTAssertEqual(events, [.sessionMoved(title: "Fartlek", to: .friday)])
        XCTAssertEqual(c.state.results.map(\.when), [PlanDay(week: 0, day: .tuesday), PlanDay(week: 0, day: .thursday)])
        XCTAssertTrue(c.state.results.allSatisfy { $0.status == .skipped })
        XCTAssertEqual(c.state.processedThrough, 3)
        XCTAssertEqual(try week(c, 0).workout(on: .friday)?.title, "Fartlek")
    }

    func testCatchUpIsIdempotent() {
        var c = coach()
        _ = c.catchUp(until: PlanDay(week: 0, day: .friday))
        let again = c.catchUp(until: PlanDay(week: 0, day: .friday))
        XCTAssertEqual(again, [])
        XCTAssertEqual(c.state.results.count, 2)
    }

    func testDoneRunIsNotMissed() {
        var c = coach()
        _ = c.record(RunResult(when: PlanDay(week: 0, day: .tuesday), rpe: 3))
        let events = c.catchUp(until: PlanDay(week: 0, day: .wednesday))
        XCTAssertEqual(events, [])
        XCTAssertEqual(c.state.results.count, 1)
        XCTAssertEqual(c.state.results.first?.status, .done)
    }

    func testWeekClosesOnNewWeek() throws {
        var c = coach()
        _ = c.catchUp(until: PlanDay(week: 0, day: .friday))
        let events = c.catchUp(until: PlanDay(week: 1, day: .monday))
        // Vrijdag: de verschoven fartlek is opnieuw gemist en kan niet meer in het verleden: weg.
        // Zondag: lange loop gemist, volgende lange loop groeit niet. Daarna week 1 afgesloten:
        // 3 van 3 gemist, telt niet mee.
        XCTAssertEqual(events, [.sessionDropped(title: "Fartlek"),
                                .longRunNotGrowing(week: 1),
                                .weekNotCounted(week: 0, missed: 3)])
        XCTAssertEqual(c.state.processedThrough, 6)
        XCTAssertTrue(c.state.adjustment(forWeek: 0).freeze)
        XCTAssertTrue(c.state.adjustment(forWeek: 1).freezeLongRun)
    }

    func testLateCatchUpDoesNotMoveIntoThePast() {
        var c = coach()
        // App pas zaterdag geopend: donderdag mag niet naar vrijdag (voorbij) schuiven.
        let events = c.catchUp(until: PlanDay(week: 0, day: .saturday))
        XCTAssertEqual(events, [.sessionDropped(title: "Fartlek")])
    }

    func testLinkingReplacesMissedAndUndoesMove() throws {
        var c = coach()
        _ = c.catchUp(until: PlanDay(week: 0, day: .friday))
        _ = c.recordLinked(RunResult(when: PlanDay(week: 0, day: .thursday), rpe: 7, averagePace: 330))
        XCTAssertFalse(c.state.results.contains { $0.when == PlanDay(week: 0, day: .thursday) && $0.status == .skipped })
        XCTAssertTrue(c.state.results.contains { $0.when == PlanDay(week: 0, day: .thursday) && $0.status == .done })
        XCTAssertNil(c.state.adjustment(forWeek: 0).moves[.thursday])
        XCTAssertEqual(try week(c, 0).workout(on: .thursday)?.title, "Fartlek")
        XCTAssertNil(try week(c, 0).workout(on: .friday))
    }

    func testProcessedThroughSurvivesCodable() throws {
        var c = coach()
        _ = c.catchUp(until: PlanDay(week: 0, day: .friday))
        let back = try JSONDecoder().decode(Coach.self, from: JSONEncoder().encode(c))
        XCTAssertEqual(back.state.processedThrough, 3)
    }

    func testOldStateWithoutFieldStillLoads() throws {
        let data = try JSONEncoder().encode(AdaptationState())
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "processedThrough")
        let old = try JSONSerialization.data(withJSONObject: json)
        XCTAssertNil(try JSONDecoder().decode(AdaptationState.self, from: old).processedThrough)
    }
}
