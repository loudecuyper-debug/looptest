import XCTest
@testable import LoopCore

final class StorageTests: XCTestCase {

    private var tempDirs: [URL] = []

    override func tearDown() {
        for d in tempDirs { try? FileManager.default.removeItem(at: d) }
        tempDirs = []
        super.tearDown()
    }

    private func makeStore() throws -> RunStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("LoopCoreTests-\(UUID().uuidString)")
        tempDirs.append(dir)
        return try RunStore(directory: dir)
    }

    private var utc: Calendar {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(_ m: Int, _ d: Int, hour: Int = 18) -> Date {
        utc.date(from: DateComponents(year: 2026, month: m, day: d, hour: hour))!
    }

    private func input() -> PlanInput {
        PlanInput(goal: .faster, goalDistance: 10_000, weeks: 12, startDate: date(10, 19, hour: 0),
                  recentDistance: 5_000, recentTime: 25 * 60, weeklyVolumeKm: 15, longestRunKm: 8,
                  runDays: [.tuesday, .thursday, .sunday], longRunDay: .sunday)
    }

    /// Een intervaltraining: 1,5 km inlopen, 4× 800 m snel, 1 km uitlopen.
    private func intervalRun(on d: Date, planDay: PlanDay? = PlanDay(week: 4, day: .thursday)) -> CompletedRun {
        var route = RouteTrack()
        for i in 0..<5 { route.append(latitude: 51.2 + Double(i) * 0.001, longitude: 4.4, time: Double(i) * 60) }
        var blocks = [BlockResult(kind: .warmup, target: .zone(.easy), targetPace: 398, distance: 1500, duration: 600)]
        for _ in 0..<4 {
            blocks.append(BlockResult(kind: .work, target: .zone(.interval), targetPace: 290, distance: 800, duration: 228))
            blocks.append(BlockResult(kind: .recovery, target: .zone(.recovery), targetPace: 440, distance: 250, duration: 120))
        }
        blocks.append(BlockResult(kind: .cooldown, target: .zone(.easy), targetPace: 398, distance: 1000, duration: 400))
        return CompletedRun(date: d, planDay: planDay, workout: nil, distance: 6700, duration: 2392,
                            splits: [Split(distance: 1000, duration: 400), Split(distance: 1000, duration: 330),
                                     Split(distance: 1000, duration: 320), Split(distance: 1000, duration: 335),
                                     Split(distance: 1000, duration: 330), Split(distance: 1000, duration: 380),
                                     Split(distance: 700, duration: 297)],
                            blocks: blocks, route: route, rpe: 7, cadence: 172)
    }

    // MARK: - Loopmodel

    func testWorkPaceAndCoachResult() throws {
        let run = intervalRun(on: date(11, 19))
        XCTAssertEqual(try XCTUnwrap(run.workPace), 285, accuracy: 0.01)          // 912 s over 3,2 km
        XCTAssertEqual(try XCTUnwrap(run.workDuration), 912, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(run.averagePace), 2392.0 / 6.7, accuracy: 0.01)
        XCTAssertEqual(run.blocks[1].deviation ?? 0, -5, accuracy: 0.01)
        let r = try XCTUnwrap(run.coachResult)
        XCTAssertEqual(r.when, PlanDay(week: 4, day: .thursday))
        XCTAssertEqual(r.rpe, 7)
        XCTAssertNil(intervalRun(on: date(11, 19), planDay: nil).coachResult)     // vrije loop
    }

    func testManualRun() {
        let run = CompletedRun.manual(date: date(10, 20), planDay: PlanDay(week: 0, day: .tuesday),
                                      workout: nil, distance: 4000, duration: 1600, rpe: 3)
        XCTAssertEqual(run.source, .manual)
        XCTAssertNil(run.workPace)
        XCTAssertEqual(run.summary.title, "Vrije loop")
        XCTAssertEqual(run.coachResult?.status, .done)
    }

    func testTimeTrialRunFeedsCoach() throws {
        var coach = Coach(input: input())
        let trial = try XCTUnwrap(coach.plan(calendar: utc)?.weeks[11].workout(on: .sunday))
        let run = CompletedRun(date: date(1, 10), planDay: PlanDay(week: 11, day: .sunday), workout: trial,
                               distance: 12_500, duration: 3900,
                               blocks: [BlockResult(kind: .work, target: .racePace(10_000), targetPace: 311,
                                                    distance: 10_000, duration: 48 * 60 + 58)])
        let events = coach.record(try XCTUnwrap(run.coachResult))
        guard case .testResult(_, let newVdot, _)? = events.first else { return XCTFail("geen tijdrit") }
        XCTAssertEqual(newVdot, 41.0, accuracy: 0.05)
    }

    // MARK: - Opslag

    func testSaveLoadAndIndex() throws {
        let store = try makeStore()
        let older = intervalRun(on: date(11, 19))
        let newer = CompletedRun(date: date(11, 22), distance: 8000, duration: 3200)
        try store.save(older)
        try store.save(newer)

        XCTAssertEqual(try store.loadRun(id: older.id), older)
        XCTAssertEqual(try store.summaries().map(\.id), [newer.id, older.id])   // nieuwste eerst

        var edited = older
        edited.rpe = 8
        try store.save(edited)
        XCTAssertEqual(try store.summaries().count, 2)
        XCTAssertEqual(try store.loadRun(id: older.id)?.rpe, 8)

        try store.deleteRun(id: older.id)
        XCTAssertNil(try store.loadRun(id: older.id))
        XCTAssertEqual(try store.summaries().map(\.id), [newer.id])
    }

    func testCoachSaveLoad() throws {
        let store = try makeStore()
        XCTAssertNil(try store.loadCoach())
        var coach = Coach(input: input())
        _ = coach.notFeeling(.pain, at: PlanDay(week: 1, day: .tuesday))
        try store.save(coach)
        XCTAssertEqual(try store.loadCoach(), coach)
    }

    // MARK: - Backup

    func testBackupRoundTrip() throws {
        let a = try makeStore()
        try a.save(Coach(input: input()))
        try a.save(intervalRun(on: date(11, 19)))
        try a.save(CompletedRun(date: date(11, 22), distance: 8000, duration: 3200))
        let data = try a.makeBackup(now: date(11, 23))
        XCTAssertEqual(a.lastBackupDate(), date(11, 23))

        let b = try makeStore()
        try b.save(CompletedRun(date: date(1, 1), distance: 1000, duration: 400))   // wordt overschreven
        let restored = try b.restore(from: data)
        XCTAssertEqual(restored.runs.count, 2)
        XCTAssertEqual(try b.summaries(), try a.summaries())
        XCTAssertEqual(try b.allRuns(), try a.allRuns())
        XCTAssertEqual(try b.loadCoach(), try a.loadCoach())
    }

    func testBackupFromTheFutureIsRefused() throws {
        let store = try makeStore()
        let future = Backup(version: 99, createdAt: date(11, 1), coach: nil, runs: [])
        let data = try JSONEncoder().encode(future)
        XCTAssertThrowsError(try store.restore(from: data)) { error in
            XCTAssertEqual(error as? RunStore.StoreError, .backupTooNew)
        }
    }

    func testBackupReminder() throws {
        let store = try makeStore()
        XCTAssertFalse(try store.shouldRemindBackup(now: date(11, 1)))           // nog niets gelopen
        try store.save(CompletedRun(date: date(10, 20), distance: 4000, duration: 1600))
        XCTAssertTrue(try store.shouldRemindBackup(now: date(11, 1)))            // nog nooit backup
        _ = try store.makeBackup(now: date(11, 1))
        XCTAssertFalse(try store.shouldRemindBackup(now: date(11, 11)))
        XCTAssertTrue(try store.shouldRemindBackup(now: date(11, 22)))
    }

    func testBackupFileName() {
        XCTAssertEqual(Backup.fileName(for: date(10, 15), calendar: utc), "LoopApp-backup-2026-10-15.json")
    }

    // MARK: - Statistieken

    func testWeekProgress() throws {
        let plan = try XCTUnwrap(PlanGenerator.generate(input(), calendar: utc))
        let runs = [
            CompletedRun(date: date(10, 20), distance: 4000, duration: 1600).summary,
            CompletedRun(date: date(10, 22), distance: 4500, duration: 1500).summary,
            CompletedRun(date: date(10, 27), distance: 5000, duration: 2000).summary   // volgende week
        ]
        let p = Stats.progress(of: plan.weeks[0], runs: runs, calendar: utc)
        XCTAssertEqual(p.doneKm, 8.5, accuracy: 0.001)
        XCTAssertEqual(p.plannedKm, 15.06, accuracy: 0.3)
        XCTAssertEqual(p.text, "8,5 van 15,1 km")
        XCTAssertEqual(Stats.weeklyVolumes(plan: plan, runs: runs, calendar: utc)[1].doneKm, 5, accuracy: 0.001)
    }

    func testPersonalRecords() {
        let interval = intervalRun(on: date(11, 19))
        var tempo = CompletedRun(date: date(11, 26), distance: 5000, duration: 1550)
        tempo.splits = [300, 305, 310, 315, 320].map { Split(distance: 1000, duration: $0) }
        let manual = CompletedRun.manual(date: date(12, 1), planDay: nil, workout: nil, distance: 12_000, duration: 4800)

        let prs = Stats.personalRecords([interval, tempo, manual])
        XCTAssertEqual(prs.map(\.label), ["1 km", "5 km", "Langste loop"])
        XCTAssertEqual(prs[0].time, 300)              // snelste km uit de tempoloop
        XCTAssertEqual(prs[0].runID, tempo.id)
        XCTAssertEqual(prs[1].time, 1550)             // 5 km: tempoloop (interval: 1695)
        XCTAssertEqual(prs[2].runID, manual.id)       // manueel telt wel voor langste loop
    }

    func testBestTimeWindow() {
        let splits = [400, 330, 320, 335, 330, 380].map { Split(distance: 1000, duration: Double($0)) }
            + [Split(distance: 700, duration: 297)]
        XCTAssertEqual(Stats.bestTime(km: 1, splits: splits), 320)
        XCTAssertEqual(Stats.bestTime(km: 5, splits: splits), 1695)
        XCTAssertNil(Stats.bestTime(km: 10, splits: splits))
    }

    // MARK: - Meldingen van de coach (27 okt)

    func testCoachMessagesSurviveRestart() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try RunStore(directory: dir)
        XCTAssertEqual(store.coachMessages(), [])

        let suggestion = LevelSuggestion(fromWeek: 3, oldVdot: 40, newVdot: 40.5, exampleLabel: "interval",
                                         oldPace: 290, newPace: 287)
        let events: [CoachEvent] = [
            .levelSuggestion(suggestion),
            .testResult(oldVdot: 40, newVdot: 41, predicted10k: 2_950),
            .sessionMoved(title: "Fartlek", to: .friday),
            .sessionDropped(title: "Lange loop"),
            .weekNotCounted(week: 2, missed: 2),
            .notFeelingApplied(.tired),
            .backToPlan,
            .easyTooFastTip
        ]
        let saved = events.map { SavedCoachMessage(created: date(10, 27), event: $0) }
        try store.save(coachMessages: saved)

        let reopened = try RunStore(directory: dir)
        XCTAssertEqual(reopened.coachMessages(), saved)
        XCTAssertEqual(reopened.coachMessages().first?.event, .levelSuggestion(suggestion))
    }

    // MARK: - Verslepen in de kalender

    func testMoveWorkout() throws {
        var coach = Coach(input: input())
        XCTAssertEqual(coach.moveWorkout(at: PlanDay(week: 1, day: .tuesday), to: .wednesday), .moved(warning: nil))
        XCTAssertEqual(try XCTUnwrap(coach.plan(calendar: utc)).weeks[1].workout(on: .wednesday)?.type, .easy)

        guard case .moved(let warning) = coach.moveWorkout(at: PlanDay(week: 1, day: .thursday), to: .saturday) else {
            return XCTFail("niet verplaatst")
        }
        XCTAssertNotNil(warning)                       // zaterdag ligt naast de lange loop
        XCTAssertEqual(try XCTUnwrap(coach.plan(calendar: utc)).weeks[1].workout(on: .saturday)?.type, .tempo)

        XCTAssertEqual(coach.moveWorkout(at: PlanDay(week: 1, day: .saturday), to: .sunday), .dayTaken)
        XCTAssertEqual(coach.moveWorkout(at: PlanDay(week: 1, day: .monday), to: .friday), .nothingToMove)

        _ = coach.record(RunResult(when: PlanDay(week: 2, day: .tuesday)))
        XCTAssertEqual(coach.moveWorkout(at: PlanDay(week: 2, day: .tuesday), to: .monday), .alreadyDone)
    }

    /// Niet naar een voorbije dag; een gemiste training zonder loop mag wel nog vooruit (27 okt).
    func testMoveWorkoutNotToPastDay() throws {
        var coach = Coach(input: input())
        let today = PlanDay(week: 1, day: .wednesday)
        XCTAssertEqual(coach.moveWorkout(at: PlanDay(week: 1, day: .thursday), to: .monday, today: today), .dayPassed)
        XCTAssertEqual(try XCTUnwrap(coach.plan(calendar: utc)).weeks[1].workout(on: .thursday)?.type, .tempo)

        XCTAssertEqual(coach.moveWorkout(at: PlanDay(week: 1, day: .tuesday), to: .wednesday, today: today),
                       .moved(warning: nil))
        let week = try XCTUnwrap(coach.plan(calendar: utc)).weeks[1]
        XCTAssertNil(week.workout(on: .tuesday))
        XCTAssertEqual(week.workout(on: .wednesday)?.type, .easy)
    }

    func testMoveWorkoutTwiceKeepsOneSession() throws {
        var coach = Coach(input: input())
        _ = coach.moveWorkout(at: PlanDay(week: 0, day: .thursday), to: .friday)
        _ = coach.moveWorkout(at: PlanDay(week: 0, day: .friday), to: .wednesday)
        let week = try XCTUnwrap(coach.plan(calendar: utc)).weeks[0]
        XCTAssertEqual(week.workouts.map(\.day), [.tuesday, .wednesday, .sunday])
        XCTAssertEqual(week.workout(on: .wednesday)?.type, .fartlek)
    }

    func testMoveExtraRun() throws {
        var coach = Coach(input: input())
        coach.addExtraRun(PlanDay(week: 3, day: .monday))
        XCTAssertEqual(coach.moveWorkout(at: PlanDay(week: 3, day: .monday), to: .friday), .moved(warning: nil))
        let week = try XCTUnwrap(coach.plan(calendar: utc)).weeks[3]
        XCTAssertNil(week.workout(on: .monday))
        XCTAssertEqual(week.workout(on: .friday)?.isExtra, true)
    }
}
