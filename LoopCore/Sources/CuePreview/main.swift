import Foundation
import LoopCore

// Cue-preview: wat de stem zegt tijdens een paar gesimuleerde loopjes.
// Verschijnt als Markdown in de Summary van de LoopCore-workflow in GitHub Actions.

let zones = PaceZones(distance: 5_000, time: 1_500)!   // testprofiel: 5 km in 25:00

func section(_ title: String, _ note: String, _ engine: WorkoutEngine,
             stopAtDistance: Double? = nil, pace: (EngineStep?) -> Double) {
    let r = EngineSimulator.run(engine, stopAtDistance: stopAtDistance, pace: pace)
    print("## \(title)\n")
    print("_\(note)_\n")
    print("| Tijd | Soort | Wat de stem zegt |")
    print("|---|---|---|")
    for c in r.cues {
        print("| \(TimeText.clock(c.time)) | \(c.cue.kind.rawValue) | \(c.cue.text) |")
    }
    print("")
    let blocks = r.engine.blocks.map { b -> String in
        let pace = b.pace.map { TimeText.clock($0) } ?? "-"
        return "\(b.kind.rawValue) \(TimeText.distance(b.distance)) in \(TimeText.clock(b.duration)) (\(pace), doel \(TimeText.clock(b.targetPace)))"
    }
    print("Blokken: " + blocks.joined(separator: " · ") + "\n")
    print("Totaal: \(TimeText.distance(r.distance)) in \(TimeText.clock(r.elapsed))\(r.engine.stoppedEarly ? ", vroeger gestopt" : "")\n")
}

func faster(by seconds: Double) -> (EngineStep?) -> Double {
    { step in
        guard let step else { return 360 }
        return step.kind == .work ? step.targetPace - seconds : step.targetPace
    }
}

print("# Cue-preview\n")
print("Niveau \(String(format: "%.1f", zones.vdot)), standaardinstellingen (blok, aftellen, tempo, splits aan; intervallen te gaan uit).\n")

section("Fartlek (week 1), op doeltempo",
        "Zo klinkt een normale kwaliteitssessie.",
        WorkoutEngine(workout: QualitySession.fartlek.workout(day: .thursday, progress: 0, weekVolumeKm: 15), zones: zones),
        pace: EngineSimulator.onTarget)

section("Fartlek, snelle blokken 15 s/km te snel",
        "Tempofeedback in snelle blokken: na 20 s in het blok, als het 15 s aanhoudt, hooguit om de 30 s.",
        WorkoutEngine(workout: QualitySession.fartlek.workout(day: .thursday, progress: 0, weekVolumeKm: 15), zones: zones),
        pace: faster(by: 15))

var remaining = EngineSettings()
remaining.remaining = true
section("Intervallen 800 m, met \"intervallen te gaan\" aan",
        "Afstandsblokken: aftellen met \"Nog 100 meter\".",
        WorkoutEngine(workout: QualitySession.interval800.workout(day: .thursday, progress: 0, weekVolumeKm: 18),
                      zones: zones, settings: remaining),
        pace: EngineSimulator.onTarget)

section("10k-specifiek, op doeltempo",
        "Lange snelle blokken: halverwege één keer \"Op tempo\".",
        WorkoutEngine(workout: QualitySession.tenKSpecific.workout(day: .thursday, progress: 0, weekVolumeKm: 22), zones: zones),
        pace: EngineSimulator.onTarget)

section("Lange loop met versnelling (8 km)",
        "Rustig deel en 2 km op duurtempo.",
        WorkoutEngine(workout: SimpleRuns.progression(day: .sunday, km: 8), zones: zones),
        pace: EngineSimulator.onTarget)

section("Rustige loop (5 km), 20 s/km te snel",
        "In rustige blokken enkel een opmerking als het te snel gaat, hooguit om de 2 minuten.",
        WorkoutEngine(workout: SimpleRuns.easy(day: .tuesday, km: 5), zones: zones),
        pace: { _ in zones.easy.fast - 20 })

section("Vrij lopen, gestopt na 3 km",
        "Enkel de tijd per kilometer.",
        WorkoutEngine(freeRunWith: EngineSettings()),
        stopAtDistance: 3_000,
        pace: { _ in 330 })
