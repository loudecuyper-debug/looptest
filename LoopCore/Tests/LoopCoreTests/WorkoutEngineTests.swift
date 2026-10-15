import XCTest
@testable import LoopCore

/// Tests voor de engine achter het lopen, met gesimuleerde loopjes (zonder GPS of stem).
final class WorkoutEngineTests: XCTestCase {

    /// Testprofiel: 5 km in 25:00 (niveau ~38,3).
    let zones = PaceZones(distance: 5_000, time: 1_500)!

    private func fartlek() -> PlannedWorkout {
        QualitySession.fartlek.workout(day: .thursday, progress: 0, weekVolumeKm: 15)
    }

    // MARK: - Volledige workout op doeltempo

    func testFartlekOnTarget() {
        let workout = fartlek()
        let r = EngineSimulator.run(WorkoutEngine(workout: workout, zones: zones), pace: EngineSimulator.onTarget)

        XCTAssertTrue(r.engine.isFinished)
        XCTAssertFalse(r.engine.stoppedEarly)
        XCTAssertEqual(r.engine.blocks.count, 14, "inlopen + 6 × (snel + herstel) + uitlopen")

        // Eerste en laatste cue
        XCTAssertEqual(r.cues.first?.cue.text, "Workout gestart. Inlopen: anderhalve kilometer rustig.")
        XCTAssertEqual(r.cues.last?.cue.kind, .finish)
        XCTAssertTrue(r.cues.last?.cue.text.hasPrefix("Workout klaar.") == true)

        // Elk interval aangekondigd, met het juiste tempo
        let pace = CueText.pace(zones.interval.target)
        XCTAssertTrue(r.texts(.step).contains("Interval 1 van 6: 1 minuut op \(pace)."))
        XCTAssertTrue(r.texts(.step).contains("Interval 6 van 6: 1 minuut op \(pace)."))
        XCTAssertEqual(r.texts(.step).filter { $0.hasPrefix("Interval") }.count, 6)
        XCTAssertTrue(r.texts(.step).contains("Uitlopen: 1 kilometer rustig."))

        // Aftellen: 6 snelle + 6 herstelblokken van 1 minuut, in- en uitlopen op afstand
        XCTAssertEqual(r.texts(.countdown).filter { $0 == "Nog 10 seconden." }.count, 12)
        XCTAssertEqual(r.texts(.countdown).filter { $0 == "Nog 100 meter." }.count, 2)

        // Op doeltempo: geen tempofeedback
        XCTAssertTrue(r.texts(.pace).isEmpty)

        // Tijdsblokken duren exact 1 minuut, afstandsblokken exact hun afstand
        for b in r.engine.blocks {
            switch b.kind {
            case .work, .recovery: XCTAssertEqual(b.duration, 60, accuracy: 0.001)
            case .warmup: XCTAssertEqual(b.distance, 1_500, accuracy: 0.001)
            case .cooldown: XCTAssertEqual(b.distance, 1_000, accuracy: 0.001)
            case .steady: XCTFail("geen rustig blok in een fartlek")
            }
        }

        // Totale afstand klopt met de schatting van het plan
        let planned = workout.estimatedDistance(zones: zones)
        XCTAssertEqual(r.distance, planned, accuracy: planned * 0.01)
    }

    func testResultGoesToCoach() {
        let workout = fartlek()
        let r = EngineSimulator.run(WorkoutEngine(workout: workout, zones: zones), pace: EngineSimulator.onTarget)
        let run = r.engine.completedRun(date: Date(), planDay: PlanDay(week: 0, day: .thursday), workout: workout,
                                        distance: r.distance, duration: r.elapsed)
        XCTAssertEqual(run.status, .done)
        XCTAssertEqual(run.blocks.count, 14)
        XCTAssertEqual(run.workPace ?? 0, zones.interval.target, accuracy: 2)
        XCTAssertEqual(run.coachResult?.status, .done)
        XCTAssertEqual(run.coachResult?.when, PlanDay(week: 0, day: .thursday))
    }

    // MARK: - Tempofeedback

    func testWorkTooFast() {
        let r = EngineSimulator.run(WorkoutEngine(workout: fartlek(), zones: zones)) { step in
            guard let step else { return 360 }
            return step.kind == .work ? step.targetPace - 15 : step.targetPace
        }
        let pace = r.cues.filter { $0.cue.kind == .pace }
        XCTAssertEqual(pace.count, 12, "twee keer per snel blok van 1 minuut")
        XCTAssertTrue(pace.allSatisfy { $0.cue.text.hasPrefix("Iets rustiger. Je loopt ") })
        for (a, b) in zip(pace, pace.dropFirst()) {
            XCTAssertGreaterThanOrEqual(b.time - a.time, 30, "hooguit om de 30 seconden")
        }
    }

    func testWorkTooSlow() {
        let r = EngineSimulator.run(WorkoutEngine(workout: fartlek(), zones: zones)) { step in
            guard let step else { return 360 }
            return step.kind == .work ? step.targetPace + 15 : step.targetPace
        }
        XCTAssertFalse(r.texts(.pace).isEmpty)
        XCTAssertTrue(r.texts(.pace).allSatisfy { $0.hasPrefix("Iets sneller. Je loopt ") })
    }

    func testSmallDeviationStaysQuiet() {
        // 3 s/km sneller dan het mikpunt valt nog binnen de zone.
        let r = EngineSimulator.run(WorkoutEngine(workout: fartlek(), zones: zones)) { step in
            guard let step else { return 360 }
            return step.kind == .work ? step.targetPace - 3 : step.targetPace
        }
        XCTAssertTrue(r.texts(.pace).isEmpty)
    }

    func testEasyTooFast() {
        let easy = SimpleRuns.easy(day: .tuesday, km: 6)
        let r = EngineSimulator.run(WorkoutEngine(workout: easy, zones: zones)) { _ in
            self.zones.easy.fast - 20
        }
        let pace = r.cues.filter { $0.cue.kind == .pace }
        XCTAssertGreaterThanOrEqual(pace.count, 10)
        XCTAssertTrue(pace.allSatisfy { $0.cue.text.hasPrefix("Rustiger. Je loopt ") })
        for (a, b) in zip(pace, pace.dropFirst()) {
            XCTAssertGreaterThanOrEqual(b.time - a.time, 120, "hooguit om de 2 minuten")
        }
    }

    func testEasySlowIsFine() {
        let easy = SimpleRuns.easy(day: .tuesday, km: 4)
        let r = EngineSimulator.run(WorkoutEngine(workout: easy, zones: zones)) { _ in
            self.zones.easy.slow + 30
        }
        XCTAssertTrue(r.texts(.pace).isEmpty, "trager dan rustig: geen opmerking")
        XCTAssertEqual(r.engine.paceStatus(nil), .unknown)
    }

    func testProgressionOnPace() {
        let run = SimpleRuns.progression(day: .sunday, km: 8)
        let r = EngineSimulator.run(WorkoutEngine(workout: run, zones: zones), pace: EngineSimulator.onTarget)
        XCTAssertEqual(r.cues.first?.cue.text,
                       "Workout gestart. Lange loop met versnelling: 6 kilometer rustig, rond \(CueText.pace(zones.easy.target)) per kilometer.")
        XCTAssertTrue(r.texts(.step).contains("Versnelling: 2 kilometer op \(CueText.pace(zones.marathon.target))."))
        XCTAssertEqual(r.texts(.onPace).count, 1)
        XCTAssertTrue(r.texts(.onPace).first?.hasPrefix("Op tempo, ") == true)
    }

    func testPaceStatus() {
        var e = WorkoutEngine(workout: fartlek(), zones: zones)
        _ = e.start()
        _ = e.skipStep(elapsed: 10, distance: 30)   // naar interval 1
        let target = zones.interval.target
        XCTAssertEqual(e.paceStatus(target), .onPace)
        XCTAssertEqual(e.paceStatus(target - 20), .tooFast)
        XCTAssertEqual(e.paceStatus(target + 20), .tooSlow)
        XCTAssertEqual(e.label(for: e.currentStep!), "SNEL · 1 VAN 6")
    }

    // MARK: - Splits

    func testSplitsEasyRun() {
        let easy = SimpleRuns.easy(day: .tuesday, km: 5)
        let r = EngineSimulator.run(WorkoutEngine(workout: easy, zones: zones), pace: EngineSimulator.onTarget)
        let full = r.engine.splits.filter { $0.isFullKm }
        XCTAssertEqual(full.count, 5)
        for s in full { XCTAssertEqual(s.duration, zones.easy.target, accuracy: 0.01) }
        XCTAssertEqual(r.texts(.split).count, 5)
        XCTAssertEqual(r.texts(.split).first, "1 kilometer. \(CueText.pace(zones.easy.target)) per kilometer.")
        XCTAssertEqual(r.texts(.countdown), ["Nog 100 meter."])
    }

    func testFreeRun() {
        let r = EngineSimulator.run(WorkoutEngine(freeRunWith: EngineSettings()), stopAtDistance: 3_000) { _ in 330 }
        XCTAssertEqual(r.cues.first?.cue.text, "Vrij lopen gestart. Je hoort elke kilometer je tijd.")
        XCTAssertEqual(r.texts(.split), [
            "1 kilometer. 5 minuten 30 per kilometer.",
            "2 kilometer. 5 minuten 30 per kilometer.",
            "3 kilometer. 5 minuten 30 per kilometer."
        ])
        XCTAssertTrue(r.texts(.finish).first?.hasPrefix("Vrij lopen gestopt. 3 kilometer in ") == true)
        XCTAssertFalse(r.engine.stoppedEarly)
        let run = r.engine.completedRun(date: Date(), planDay: nil, workout: nil, distance: r.distance, duration: r.elapsed)
        XCTAssertEqual(run.status, .done)
        XCTAssertNil(run.coachResult, "vrije loop gaat niet naar de coach")
    }

    // MARK: - Bediening

    func testSkipStep() {
        var e = WorkoutEngine(workout: fartlek(), zones: zones)
        _ = e.start()
        var d = 0.0
        for t in 1...60 {
            d += 1000 / 400
            _ = e.update(elapsed: Double(t), distance: d, pace: 400)
        }
        let u = e.skipStep(elapsed: 60, distance: d)
        XCTAssertEqual(e.blocks.count, 1)
        XCTAssertEqual(e.blocks[0].kind, .warmup)
        XCTAssertEqual(e.blocks[0].duration, 60, accuracy: 0.001)
        XCTAssertEqual(e.currentStep?.kind, .work)
        XCTAssertTrue(u.cues.first?.text.hasPrefix("Interval 1 van 6") == true)
    }

    func testStopEarly() {
        let workout = fartlek()
        let r = EngineSimulator.run(WorkoutEngine(workout: workout, zones: zones), stopAtTime: 300,
                                    pace: EngineSimulator.onTarget)
        XCTAssertTrue(r.engine.isFinished)
        XCTAssertTrue(r.engine.stoppedEarly)
        XCTAssertTrue(r.cues.last?.cue.text.hasPrefix("Workout gestopt.") == true)
        let run = r.engine.completedRun(date: Date(), planDay: PlanDay(week: 0, day: .thursday), workout: workout,
                                        distance: r.distance, duration: r.elapsed)
        XCTAssertEqual(run.coachResult?.status, .stoppedEarly)
    }

    func testStopDuringCooldownCountsAsDone() {
        let workout = fartlek()
        let full = EngineSimulator.run(WorkoutEngine(workout: workout, zones: zones), pace: EngineSimulator.onTarget)
        let r = EngineSimulator.run(WorkoutEngine(workout: workout, zones: zones), stopAtTime: full.elapsed - 60,
                                    pace: EngineSimulator.onTarget)
        XCTAssertTrue(r.engine.isFinished)
        XCTAssertFalse(r.engine.stoppedEarly, "stoppen tijdens het uitlopen telt als gelopen")
        XCTAssertTrue(r.cues.last?.cue.text.hasPrefix("Workout klaar.") == true)
    }

    func testDelayedTicks() {
        // Telefoon in de achtergrond: metingen komen maar om de 30 seconden binnen.
        let workout = fartlek()
        let r = EngineSimulator.run(WorkoutEngine(workout: workout, zones: zones), tick: 30,
                                    pace: EngineSimulator.onTarget)
        XCTAssertTrue(r.engine.isFinished)
        XCTAssertEqual(r.engine.blocks.count, 14)
        for b in r.engine.blocks where b.kind == .work || b.kind == .recovery {
            XCTAssertEqual(b.duration, 60, accuracy: 0.001)
        }
        XCTAssertEqual(r.texts(.step).filter { $0.hasPrefix("Interval") }.count, 6)
    }

    // MARK: - Instellingen

    func testSilentSettings() {
        let r = EngineSimulator.run(WorkoutEngine(workout: fartlek(), zones: zones, settings: .silent)) { step in
            guard let step else { return 360 }
            return step.kind == .work ? step.targetPace - 15 : step.targetPace
        }
        XCTAssertEqual(r.cues.map { $0.cue.kind }, [.start, .finish], "enkel start en einde")
        XCTAssertEqual(r.engine.splits.filter { $0.isFullKm }.count, Int(r.distance / 1000), "splits worden wel bewaard")
    }

    func testRemainingIntervals() {
        var settings = EngineSettings()
        settings.remaining = true
        let r = EngineSimulator.run(WorkoutEngine(workout: fartlek(), zones: zones, settings: settings),
                                    pace: EngineSimulator.onTarget)
        XCTAssertTrue(r.texts(.step).contains("Herstel: 1 minuut rustig. Nog 5 te gaan."))
        XCTAssertTrue(r.texts(.step).contains("Herstel: 1 minuut rustig. Nog 1 te gaan."))
        XCTAssertEqual(r.texts(.step).filter { $0 == "Herstel: 1 minuut rustig." }.count, 1, "na het laatste interval")
    }

    func testTimeTrialLabel() {
        var e = WorkoutEngine(workout: SimpleRuns.timeTrial(day: .sunday, distance: 10_000), zones: zones)
        _ = e.start()
        _ = e.skipStep(elapsed: 5, distance: 10)
        XCTAssertEqual(e.label(for: e.currentStep!), "TIJDRIT")
        XCTAssertEqual(e.remaining(elapsed: 5, distance: 10), .distance(10_000))
    }

    // MARK: - Uitgesproken tekst

    func testCueText() {
        XCTAssertEqual(CueText.pace(290), "4 minuten 50")
        XCTAssertEqual(CueText.pace(300), "5 minuten")
        XCTAssertEqual(CueText.pace(245), "4 minuten 5")
        XCTAssertEqual(CueText.duration(45), "45 seconden")
        XCTAssertEqual(CueText.duration(60), "1 minuut")
        XCTAssertEqual(CueText.duration(90), "1 minuut 30")
        XCTAssertEqual(CueText.duration(120), "2 minuten")
        XCTAssertEqual(CueText.duration(1_764), "29 minuten 24")
        XCTAssertEqual(CueText.duration(3_900), "1 uur 5 minuten")
        XCTAssertEqual(CueText.distance(400), "400 meter")
        XCTAssertEqual(CueText.distance(1_000), "1 kilometer")
        XCTAssertEqual(CueText.distance(1_500), "anderhalve kilometer")
        XCTAssertEqual(CueText.distance(2_500), "2 en een halve kilometer")
        XCTAssertEqual(CueText.distance(4_620), "4,6 kilometer")
        XCTAssertEqual(CueText.distance(10_000), "10 kilometer")
    }
}
