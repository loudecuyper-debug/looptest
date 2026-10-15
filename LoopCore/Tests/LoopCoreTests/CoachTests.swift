import XCTest
@testable import LoopCore

/// De vier scenario's uit de Python-simulatie (15 okt 2026) plus "Niet 100%".
final class CoachTests: XCTestCase {

    private var utc: Calendar {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func input() -> PlanInput {
        PlanInput(goal: .faster, goalDistance: 10_000, weeks: 12,
                  startDate: utc.date(from: DateComponents(year: 2026, month: 10, day: 19))!,
                  recentDistance: 5_000, recentTime: 25 * 60,
                  weeklyVolumeKm: 15, longestRunKm: 8,
                  runDays: [.tuesday, .thursday, .sunday], longRunDay: .sunday)
    }

    private func plan(_ coach: Coach) throws -> TrainingPlan {
        try XCTUnwrap(coach.plan(calendar: utc))
    }

    private func km(_ week: PlanWeek) -> Double {
        week.estimatedDistance(zones: week.zones) / 1000
    }

    // MARK: - Scenario A: fitter dan gedacht en beter wordend

    func testScenarioA_FitterThanExpected() throws {
        var coach = Coach(input: input())
        var suggestionWeeks: [Int] = []
        var testEvent: CoachEvent?

        for w in 0..<12 {
            let week = try plan(coach).weeks[w]
            let truth = PaceZones(vdot: 39 + 2 * Double(w) / 11)
            for wo in week.workouts {
                var r = RunResult(when: PlanDay(week: w, day: wo.day), rpe: wo.type.isQuality ? 7 : nil)
                if wo.type == .test {
                    r.workDuration = truth.predictedTime(distance: 10_000)
                } else if wo.type.isQuality {
                    r.workPace = truth.pace(for: wo.mainTarget)
                }
                for e in coach.record(r) {
                    if case .levelSuggestion(let s) = e {
                        XCTAssertTrue(s.faster)
                        suggestionWeeks.append(w)
                        coach.accept(s)
                    }
                    if case .testResult = e { testEvent = e }
                }
            }
            _ = coach.finishWeek(w)
        }

        XCTAssertEqual(suggestionWeeks, [1, 3, 6, 9])
        guard case .testResult(_, let newVdot, let predicted)? = testEvent else {
            return XCTFail("geen tijdrit verwerkt")
        }
        XCTAssertEqual(newVdot, 41.0, accuracy: 0.05)
        XCTAssertEqual(predicted, 48 * 60 + 58, accuracy: 3)

        // Tempo's in de piek liggen sneller dan in het originele plan.
        let p = try plan(coach)
        let original = try XCTUnwrap(PlanGenerator.generate(input(), calendar: utc))
        XCTAssertLessThan(p.weeks[10].zones.racePace(distance: 10_000),
                          original.weeks[10].zones.racePace(distance: 10_000) - 10)
    }

    func testNoSuggestionInTaper() throws {
        var coach = Coach(input: input())
        let taper = try plan(coach).weeks[11]
        let q = try XCTUnwrap(taper.workouts.first { $0.type == .interval })
        for _ in 0..<2 {
            let events = coach.record(RunResult(when: PlanDay(week: 11, day: q.day), rpe: 6,
                                                workPace: taper.zones.pace(for: q.mainTarget) - 10))
            XCTAssertTrue(events.isEmpty)
        }
    }

    func testSlowerSuggestionWhenStoppingEarly() throws {
        var coach = Coach(input: input())
        var events: [CoachEvent] = []
        for w in 0..<2 {
            events = coach.record(RunResult(when: PlanDay(week: w, day: .thursday), status: .stoppedEarly))
        }
        guard case .levelSuggestion(let s)? = events.first else { return XCTFail("geen voorstel") }
        XCTAssertFalse(s.faster)
        XCTAssertEqual(s.newVdot, s.oldVdot - 0.5, accuracy: 0.0001)
        XCTAssertTrue(s.question.hasPrefix("Je loopt trager dan gepland."))
    }

    // MARK: - Scenario B: week 6 di en do gemist

    func testScenarioB_MissedWeek() throws {
        var coach = Coach(input: input())
        let original = try plan(coach)
        var weekSixEvents: [CoachEvent] = []

        for w in 0..<6 {
            for wo in try plan(coach).weeks[w].workouts {
                let skip = w == 5 && wo.day != .sunday
                weekSixEvents += coach.record(RunResult(when: PlanDay(week: w, day: wo.day),
                                                        status: skip ? .skipped : .done))
            }
            let events = coach.finishWeek(w)
            if w == 5 { weekSixEvents += events }
        }

        // Kwaliteit eerst naar vrijdag geschoven, daar ook niet gelopen: week telt niet mee.
        XCTAssertTrue(weekSixEvents.contains(.sessionMoved(title: "Tempo-intervallen", to: .friday)))
        XCTAssertTrue(weekSixEvents.contains(.weekNotCounted(week: 5, missed: 2)))

        let p = try plan(coach)
        XCTAssertEqual(km(p.weeks[6]), 20.4, accuracy: 0.6)
        XCTAssertLessThan(km(p.weeks[6]), km(original.weeks[6]))
        XCTAssertEqual(km(p.weeks[9]), km(original.weeks[9]), accuracy: 0.6)   // terug op schema
    }

    // MARK: - Scenario C: weken 5 en 6 zwaarder dan verwacht

    func testScenarioC_HeavyWeeks() throws {
        var coach = Coach(input: input())
        var events: [Int: [CoachEvent]] = [:]

        for w in 0..<6 {
            for wo in try plan(coach).weeks[w].workouts {
                let rpe = w >= 4 ? Int((Coach.expectedRPE(wo.type) + 2).rounded(.up)) : nil
                _ = coach.record(RunResult(when: PlanDay(week: w, day: wo.day), rpe: rpe))
            }
            events[w] = coach.finishWeek(w)
        }

        XCTAssertEqual(events[4], [.growthPaused(week: 5)])
        XCTAssertEqual(events[5], [.recoveryEarlier(week: 6)])

        let p = try plan(coach)
        XCTAssertTrue(p.weeks[6].isRecoveryWeek)
        XCTAssertFalse(p.weeks[7].isRecoveryWeek)
        XCTAssertEqual(km(p.weeks[5]), 18.9, accuracy: 0.6)
        XCTAssertEqual(km(p.weeks[6]), 14.0, accuracy: 0.6)
        XCTAssertEqual(km(p.weeks[7]), 18.9, accuracy: 0.6)
        // RPE verandert de tempo's niet.
        XCTAssertEqual(p.weeks[7].vdot, p.weeks[0].vdot, accuracy: 0.0001)
    }

    // MARK: - Scenario D: rustige loopjes te snel

    func testScenarioD_EasyRunsTooFast() throws {
        var coach = Coach(input: input())
        var warnings: [Int] = []
        var tips = 0
        for w in 0..<12 {
            let week = try plan(coach).weeks[w]
            for wo in week.workouts where wo.type == .easy {
                let r = RunResult(when: PlanDay(week: w, day: wo.day), averagePace: week.zones.easy.fast - 20)
                for e in coach.record(r) {
                    if e == .easyTooFastWarning { warnings.append(w) }
                    if e == .easyTooFastTip { tips += 1 }
                }
            }
        }
        XCTAssertEqual(warnings, [2, 4, 6, 8, 10])
        XCTAssertEqual(tips, 7)
        XCTAssertEqual(try plan(coach), try XCTUnwrap(PlanGenerator.generate(input(), calendar: utc)))
    }

    // MARK: - Gemiste sessies

    func testSkippedQualityMovesThenDrops() throws {
        var coach = Coach(input: input())
        let first = coach.record(RunResult(when: PlanDay(week: 0, day: .thursday), status: .skipped))
        XCTAssertEqual(first, [.sessionMoved(title: "Fartlek", to: .friday)])
        XCTAssertEqual(try plan(coach).weeks[0].workout(on: .friday)?.type, .fartlek)
        XCTAssertNil(try plan(coach).weeks[0].workout(on: .thursday))

        let second = coach.record(RunResult(when: PlanDay(week: 0, day: .friday), status: .skipped))
        XCTAssertEqual(second, [.sessionDropped(title: "Fartlek")])
    }

    func testSkippedLongRun() throws {
        var coach = Coach(input: input())
        let events = coach.record(RunResult(when: PlanDay(week: 1, day: .sunday), status: .skipped))
        XCTAssertEqual(events, [.longRunNotGrowing(week: 2)])
        XCTAssertTrue(coach.state.adjustment(forWeek: 2).freezeLongRun)
    }

    func testSkippedEasyRunJustDisappears() throws {
        var coach = Coach(input: input())
        XCTAssertTrue(coach.record(RunResult(when: PlanDay(week: 0, day: .tuesday), status: .skipped)).isEmpty)
        _ = coach.record(RunResult(when: PlanDay(week: 0, day: .thursday)))
        _ = coach.record(RunResult(when: PlanDay(week: 0, day: .sunday)))
        XCTAssertTrue(coach.finishWeek(0).isEmpty)   // 1 gemist: telt nog mee
    }

    // MARK: - Pijn

    func testPainMakesNextRunEasyAndSecondPainSuggestsNotFeeling() throws {
        var coach = Coach(input: input())
        let e1 = coach.record(RunResult(when: PlanDay(week: 2, day: .tuesday), pain: true))
        XCTAssertEqual(e1, [.painNextRunEasy])
        let thursday = try XCTUnwrap(try plan(coach).weeks[2].workout(on: .thursday))
        XCTAssertEqual(thursday.type, .easy)
        XCTAssertLessThanOrEqual(try XCTUnwrap(thursday.plainKm), 4.5)

        let e2 = coach.record(RunResult(when: PlanDay(week: 2, day: .thursday), pain: true))
        XCTAssertEqual(e2, [.suggestNotFeeling])
    }

    // MARK: - Niet 100%

    func testSick() throws {
        var coach = Coach(input: input())
        let original = try plan(coach)
        XCTAssertEqual(coach.notFeeling(.sick, at: PlanDay(week: 5, day: .tuesday)), [.notFeelingApplied(.sick)])
        XCTAssertTrue(coach.state.isSick)
        XCTAssertTrue(try plan(coach).weeks[5].workouts.isEmpty)
        XCTAssertTrue(try plan(coach).weeks[6].workouts.isEmpty)   // nog altijd ziek

        XCTAssertEqual(coach.recovered(at: PlanDay(week: 5, day: .saturday)), [.backToPlan])
        let p = try plan(coach)
        XCTAssertNil(p.weeks[5].workout(on: .tuesday))
        XCTAssertNil(p.weeks[5].workout(on: .thursday))
        XCTAssertEqual(p.weeks[5].workout(on: .sunday)?.type, .easy)       // eerste dagen rustig
        XCTAssertEqual(p.weeks[6].workout(on: .thursday)?.type, .interval) // daarna terug normaal
        XCTAssertLessThan(km(p.weeks[6]), km(original.weeks[6]))           // week 6 telde niet mee
    }

    func testPainButton() throws {
        var coach = Coach(input: input())
        _ = coach.notFeeling(.pain, at: PlanDay(week: 2, day: .tuesday))
        let week = try plan(coach).weeks[2]
        XCTAssertEqual(week.workout(on: .tuesday)?.type, .easy)
        XCTAssertEqual(week.workout(on: .thursday)?.type, .easy)
        XCTAssertEqual(week.workout(on: .sunday)?.type, .long)   // buiten de 3 dagen
        XCTAssertLessThanOrEqual(try XCTUnwrap(week.workout(on: .thursday)?.plainKm), 4.5)
    }

    func testNoTime() throws {
        var coach = Coach(input: input())
        let original = try plan(coach).weeks[2]
        _ = coach.notFeeling(.noTime, at: PlanDay(week: 2, day: .monday))
        let week = try plan(coach).weeks[2]
        XCTAssertNil(week.workout(on: .tuesday))
        XCTAssertEqual(week.workout(on: .thursday)?.type, original.workout(on: .thursday)?.type)
        let long = try XCTUnwrap(week.workout(on: .sunday))
        XCTAssertEqual(long.type, .long)
        XCTAssertLessThan(try XCTUnwrap(long.plainKm), try XCTUnwrap(original.workout(on: .sunday)?.plainKm))
    }

    func testTired() throws {
        var coach = Coach(input: input())
        let events = coach.notFeeling(.tired, at: PlanDay(week: 1, day: .thursday))
        XCTAssertEqual(events, [.notFeelingApplied(.tired), .sessionMoved(title: "Tempoloop", to: .friday)])
        let week = try plan(coach).weeks[1]
        XCTAssertEqual(week.workout(on: .thursday)?.type, .easy)
        XCTAssertEqual(week.workout(on: .friday)?.type, .tempo)
    }

    // MARK: - Extra loop en opslag

    func testExtraRunViaCoach() throws {
        var coach = Coach(input: input())
        coach.addExtraRun(PlanDay(week: 5, day: .monday))
        let extra = try XCTUnwrap(try plan(coach).weeks[5].workout(on: .monday))
        XCTAssertTrue(extra.isExtra)
        coach.removeExtraRun(PlanDay(week: 5, day: .monday))
        XCTAssertNil(try plan(coach).weeks[5].workout(on: .monday))
    }

    func testCoachCodableRoundTrip() throws {
        var coach = Coach(input: input())
        _ = coach.record(RunResult(when: PlanDay(week: 0, day: .thursday), status: .skipped))
        _ = coach.notFeeling(.pain, at: PlanDay(week: 1, day: .tuesday))
        coach.addExtraRun(PlanDay(week: 2, day: .monday))
        let data = try JSONEncoder().encode(coach)
        let back = try JSONDecoder().decode(Coach.self, from: data)
        XCTAssertEqual(back, coach)
        XCTAssertEqual(try plan(back), try plan(coach))
    }

    func testPlanDay() {
        let d = PlanDay(week: 1, day: .sunday)
        XCTAssertEqual(d.index, 13)
        XCTAssertEqual(d.adding(days: 1), PlanDay(week: 2, day: .monday))
        XCTAssertLessThan(PlanDay(week: 0, day: .sunday), PlanDay(week: 1, day: .monday))
    }
}
