import XCTest
@testable import LoopCore

final class PlanGeneratorTests: XCTestCase {

    private var utc: Calendar {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        utc.date(from: DateComponents(year: y, month: m, day: d))!
    }

    /// Testprofiel Louis: 5 km in 25:00, ~15 km per week, langste loop 8 km.
    private func input(days: [Weekday] = [.tuesday, .thursday, .sunday],
                       longRunDay: Weekday = .sunday,
                       start: Date? = nil) -> PlanInput {
        PlanInput(goal: .faster, goalDistance: 10_000, weeks: 12,
                  startDate: start ?? date(2026, 10, 19),
                  recentDistance: 5_000, recentTime: 25 * 60,
                  weeklyVolumeKm: 15, longestRunKm: 8,
                  runDays: days, longRunDay: longRunDay)
    }

    private func plan(days: [Weekday] = [.tuesday, .thursday, .sunday]) throws -> TrainingPlan {
        try XCTUnwrap(PlanGenerator.generate(input(days: days), calendar: utc))
    }

    // MARK: - Structuur

    func testPhasesAndRecoveryWeeks() throws {
        let p = try plan()
        XCTAssertEqual(p.weeks.count, 12)
        XCTAssertEqual(p.weeks.map(\.phase),
                       [.base, .base, .base, .base, .build, .build, .build, .build, .peak, .peak, .peak, .taper])
        XCTAssertEqual(p.weeks.filter(\.isRecoveryWeek).map(\.number), [4, 8])
    }

    func testStartsOnMonday() throws {
        let p = try plan()
        XCTAssertEqual(p.weeks[0].startDate, date(2026, 10, 19))
        XCTAssertEqual(p.weeks[1].startDate, date(2026, 10, 26))
        XCTAssertEqual(p.weeks[0].date(for: .sunday, calendar: utc), date(2026, 10, 25))
    }

    // MARK: - Start midden in de week

    func testPlanCalendarHelpers() {
        XCTAssertEqual(PlanCalendar.monday(of: date(2026, 10, 25), calendar: utc), date(2026, 10, 19))
        XCTAssertEqual(PlanCalendar.monday(of: date(2026, 10, 19), calendar: utc), date(2026, 10, 19))
        XCTAssertEqual(PlanCalendar.weekday(of: date(2026, 10, 20), calendar: utc), .tuesday)
        XCTAssertEqual(PlanCalendar.weekday(of: date(2026, 10, 25), calendar: utc), .sunday)
    }

    func testStartsThisWeekOnPlanDay() throws {
        // Gemaakt op dinsdag 20 okt om 13:55: de training van vandaag hoort er nog bij.
        let made = utc.date(byAdding: .minute, value: 13 * 60 + 55, to: date(2026, 10, 20))!
        let p = try XCTUnwrap(PlanGenerator.generate(input(start: made), calendar: utc))
        XCTAssertEqual(p.weeks.count, 12)
        XCTAssertEqual(p.weeks[0].startDate, date(2026, 10, 19))
        XCTAssertEqual(p.weeks[0].workouts.map(\.day), [.tuesday, .thursday, .sunday])
        XCTAssertEqual(p.weeks[1].startDate, date(2026, 10, 26))
        XCTAssertEqual(p.weeks[11].date(for: .sunday, calendar: utc), date(2027, 1, 10))
    }

    func testPassedDaysInFirstWeekDropOut() throws {
        // Gemaakt op woensdag: dinsdag is voorbij, enkel donderdag en zondag blijven in week 1.
        let p = try XCTUnwrap(PlanGenerator.generate(input(start: date(2026, 10, 21)), calendar: utc))
        let reference = try plan()
        XCTAssertEqual(p.weeks[0].startDate, date(2026, 10, 19))
        XCTAssertEqual(p.weeks[0].workouts.map(\.day), [.thursday, .sunday])
        XCTAssertEqual(p.weeks[0].workouts, reference.weeks[0].workouts.filter { $0.day >= .wednesday })
        for w in 1..<12 {
            XCTAssertEqual(p.weeks[w].workouts, reference.weeks[w].workouts, "week \(w + 1)")
        }
    }

    func testStartsNextMondayWhenNoRunDayLeft() throws {
        // Loopdagen ma/wo/vr, gemaakt op zaterdag 24 okt: niets meer over, start maandag 26 okt.
        let days: [Weekday] = [.monday, .wednesday, .friday]
        let made = date(2026, 10, 24)
        XCTAssertEqual(PlanCalendar.planStart(for: made, runDays: days, calendar: utc), date(2026, 10, 26))
        XCTAssertEqual(PlanCalendar.firstPlanDay(for: made, runDays: days, calendar: utc), .monday)
        let p = try XCTUnwrap(PlanGenerator.generate(input(days: days, longRunDay: .friday, start: made),
                                                     calendar: utc))
        XCTAssertEqual(p.weeks[0].startDate, date(2026, 10, 26))
        XCTAssertEqual(p.weeks[0].workouts.map(\.day), days)
    }

    func testSundayLongRunKeepsThisWeek() {
        // Gemaakt op zondag met lange loop op zondag: die dag hoort er nog bij.
        let days: [Weekday] = [.tuesday, .thursday, .sunday]
        XCTAssertEqual(PlanCalendar.planStart(for: date(2026, 10, 25), runDays: days, calendar: utc),
                       date(2026, 10, 19))
        XCTAssertEqual(PlanCalendar.firstPlanDay(for: date(2026, 10, 25), runDays: days, calendar: utc), .sunday)
    }

    func testRunsOnChosenDays() throws {
        let p = try plan()
        for week in p.weeks {
            XCTAssertEqual(week.workouts.map(\.day), [.tuesday, .thursday, .sunday], "week \(week.number)")
        }
    }

    func testSessionsMatchPrototype() throws {
        let p = try plan()
        XCTAssertEqual(p.weeks.map { $0.workout(on: .thursday)?.title ?? "-" }, [
            "Fartlek", "Tempoloop", "Fartlek", "Lichte fartlek",
            "Intervallen 800 m", "Tempo-intervallen", "Intervallen 800 m", "Lichte fartlek",
            "10k-specifiek", "Intervallen 1 km", "10k-generale", "Scherp blijven"
        ])
        XCTAssertEqual(p.weeks[9].workout(on: .sunday)?.type, .progression)
        XCTAssertEqual(p.weeks[11].workout(on: .sunday)?.title, "10 km tijdrit")
        XCTAssertEqual(p.weeks[11].workout(on: .sunday)?.type, .test)
    }

    func testWeeklyVolumesMatchPrototype() throws {
        let p = try plan()
        let expected = [15.06, 16.19, 17.59, 13.56, 18.8, 20.55, 21.87, 16.56, 23.82, 23.87, 23.82, 21.82]
        for (week, km) in zip(p.weeks, expected) {
            XCTAssertEqual(week.estimatedDistance(zones: p.zones) / 1000, km, accuracy: 0.6, "week \(week.number)")
        }
    }

    func testLongRunsGrowAndStayUnderCap() throws {
        let p = try plan()
        var last = 0.0
        for week in p.weeks where !week.isRecoveryWeek && week.phase != .taper {
            let km = try XCTUnwrap(week.workout(on: .sunday)).estimatedDistance(zones: p.zones) / 1000
            XCTAssertGreaterThanOrEqual(km, last, "week \(week.number)")
            XCTAssertLessThanOrEqual(km, PlanGenerator.longRunCapKm(goalDistance: 10_000))
            last = km
        }
    }

    func testRecoveryWeeksAreLighter() throws {
        let p = try plan()
        let v = p.weeks.map { $0.estimatedDistance(zones: p.zones) }
        XCTAssertLessThan(v[3], v[2])
        XCTAssertLessThan(v[7], v[6])
    }

    func testVolumeGrowsGradually() throws {
        let p = try plan()
        let v = p.weeks.map { $0.estimatedDistance(zones: p.zones) }
        for i in 1..<v.count where !p.weeks[i - 1].isRecoveryWeek && !p.weeks[i].isRecoveryWeek
            && p.weeks[i].phase != .taper {
            XCTAssertLessThanOrEqual(v[i] / v[i - 1], 1.2, "week \(i + 1)")
        }
    }

    // MARK: - 4 loopdagen

    func testFourDaysAddsSecondQualityOnlyInBuildAndPeak() throws {
        let p = try plan(days: [.tuesday, .thursday, .friday, .sunday])
        for week in p.weeks {
            let quality = week.workouts.filter { $0.type.isQuality && $0.type != .test }.count
            if (week.phase == .build || week.phase == .peak) && !week.isRecoveryWeek {
                XCTAssertEqual(quality, 2, "week \(week.number)")
            } else {
                XCTAssertEqual(quality, 1, "week \(week.number)")
            }
        }
    }

    func testQualityDaysSpreadOut() {
        let days = PlanGenerator.pickQualityDays(days: [.tuesday, .thursday, .friday, .sunday],
                                                 longRunDay: .sunday, count: 2)
        XCTAssertEqual(days, [.thursday, .tuesday])
        XCTAssertEqual(PlanGenerator.pickQualityDays(days: [.tuesday, .thursday, .sunday],
                                                     longRunDay: .sunday, count: 1), [.thursday])
    }

    // MARK: - Ongeldige input

    func testRejectsInvalidInput() {
        var bad = input()
        bad.longRunDay = .saturday
        XCTAssertNil(PlanGenerator.generate(bad, calendar: utc))

        bad = input(days: [.sunday])
        XCTAssertNil(PlanGenerator.generate(bad, calendar: utc))

        bad = input()
        bad.recentTime = 60
        XCTAssertNil(PlanGenerator.generate(bad, calendar: utc))

        bad = input()
        bad.weeks = 2
        XCTAssertNil(PlanGenerator.generate(bad, calendar: utc))
    }

    func testPhaseListForOtherLengths() {
        XCTAssertEqual(PlanGenerator.phaseList(weeks: 8).last, .taper)
        XCTAssertEqual(PlanGenerator.phaseList(weeks: 8).count, 8)
        XCTAssertEqual(PlanGenerator.phaseList(weeks: 24).count, 24)
        XCTAssertTrue(PlanGenerator.phaseList(weeks: 6).contains(.base))
    }

    func testCodableRoundTrip() throws {
        let p = try plan()
        let data = try JSONEncoder().encode(p)
        let back = try JSONDecoder().decode(TrainingPlan.self, from: data)
        XCTAssertEqual(p, back)
    }

    // MARK: - Tekst

    func testFartlekDescription() throws {
        let p = try plan()
        let w = try XCTUnwrap(p.weeks[0].workout(on: .thursday))
        XCTAssertEqual(WorkoutText.describe(w, zones: p.zones),
                       "1,5 km rustig · 6× (1 min interval @ 4:50 + 1 min herstel) · 1 km rustig")
        XCTAssertEqual(w.flattenedSteps.count, 14)
    }

    func testTenKPaceLabel() throws {
        let p = try plan()
        let w = try XCTUnwrap(p.weeks[8].workout(on: .thursday))
        XCTAssertTrue(WorkoutText.describe(w, zones: p.zones).contains("2 km 10k-tempo @ 5:11"))
    }

    // MARK: - Extra loop

    func testExtraRun() throws {
        let p = try plan()
        let week = p.weeks[5]   // di 5 km rustig, do kwaliteit, zo lange loop
        XCTAssertEqual(ExtraRun.freeDays(in: week), [.monday, .wednesday, .friday, .saturday])
        XCTAssertEqual(ExtraRun.suggestedKm(in: week), 5)

        XCTAssertNotNil(ExtraRun.warning(for: .saturday, in: week))   // voor de lange loop
        XCTAssertNotNil(ExtraRun.warning(for: .wednesday, in: week))  // voor de kwaliteit
        XCTAssertNil(ExtraRun.warning(for: .monday, in: week))
        XCTAssertNil(ExtraRun.warning(for: .friday, in: week))

        let withExtra = ExtraRun.adding(to: week, on: .monday)
        XCTAssertEqual(withExtra.workouts.count, 4)
        XCTAssertEqual(withExtra.workouts.first?.day, .monday)
        XCTAssertEqual(withExtra.workouts.first?.isExtra, true)
        XCTAssertEqual(withExtra.estimatedDistance(zones: p.zones, includeExtra: false),
                       week.estimatedDistance(zones: p.zones), accuracy: 0.001)

        XCTAssertEqual(ExtraRun.adding(to: week, on: .tuesday), week)   // dag al bezet
        XCTAssertEqual(ExtraRun.removing(from: withExtra, on: .monday), week)
    }

    func testSuggestExtraDayAfterThreeWeeks() throws {
        let p = try plan()
        let three = (0..<3).map { ExtraRun.adding(to: p.weeks[$0], on: .monday) }
        XCTAssertTrue(ExtraRun.shouldSuggestExtraDay(recentWeeks: three))
        XCTAssertFalse(ExtraRun.shouldSuggestExtraDay(recentWeeks: Array(three.prefix(2))))
        XCTAssertFalse(ExtraRun.shouldSuggestExtraDay(recentWeeks: [three[0], p.weeks[1], three[2]]))
    }
}
