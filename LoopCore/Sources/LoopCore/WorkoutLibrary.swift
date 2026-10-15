import Foundation

/// Sjablonen voor kwaliteitssessies. `progress` loopt van 0 tot 1 binnen een fase,
/// zodat sessies binnen dezelfde fase stilaan zwaarder worden.
public enum QualitySession: String, Codable, CaseIterable, Sendable {
    case fartlek, fartlekLight, tempoSplit, cruise, interval800, interval1000
    case tenKSpecific, tenKDressRehearsal, sharpen

    static let warmupKm = 1.5
    static let cooldownKm = 1.0

    public func workout(day: Weekday, progress: Double, weekVolumeKm: Double) -> PlannedWorkout {
        let p = min(max(progress, 0), 1)
        // Begrenzing van het zware deel tegenover het weekvolume (in km).
        let capInterval = max(3, 0.20 * weekVolumeKm)
        let capTempo = max(4, 0.25 * weekVolumeKm)

        func lerp(_ a: Double, _ b: Double) -> Int { Int((a + (b - a) * p).rounded()) }
        let wu = WorkoutBlock([WorkoutStep(.warmup, .distance(Self.warmupKm * 1000), .zone(.easy))])
        let cd = WorkoutBlock([WorkoutStep(.cooldown, .distance(Self.cooldownKm * 1000), .zone(.easy))])
        func main(_ reps: Int, _ work: WorkoutStep, _ rest: WorkoutStep) -> [WorkoutBlock] {
            [wu, WorkoutBlock(repeats: reps, [work, rest]), cd]
        }
        func jog(_ seconds: Double) -> WorkoutStep { WorkoutStep(.recovery, .time(seconds), .zone(.recovery)) }

        switch self {
        case .fartlek:
            return PlannedWorkout(day: day, type: .fartlek, title: "Fartlek",
                                  blocks: main(lerp(6, 10), WorkoutStep(.work, .time(60), .zone(.interval)), jog(60)))
        case .fartlekLight:
            return PlannedWorkout(day: day, type: .fartlek, title: "Lichte fartlek",
                                  blocks: main(5, WorkoutStep(.work, .time(60), .zone(.interval)), jog(90)))
        case .tempoSplit:
            let minutes = Double(lerp(6, 10))
            return PlannedWorkout(day: day, type: .tempo, title: "Tempoloop",
                                  blocks: main(2, WorkoutStep(.work, .time(minutes * 60), .zone(.threshold)), jog(120)))
        case .cruise:
            let n = min(lerp(3, 5), Int(capTempo))
            return PlannedWorkout(day: day, type: .tempo, title: "Tempo-intervallen",
                                  blocks: main(n, WorkoutStep(.work, .distance(1000), .zone(.threshold)), jog(60)))
        case .interval800:
            let n = min(lerp(4, 6), Int(capInterval / 0.8))
            return PlannedWorkout(day: day, type: .interval, title: "Intervallen 800 m",
                                  blocks: main(n, WorkoutStep(.work, .distance(800), .zone(.interval)), jog(120)))
        case .interval1000:
            let n = min(lerp(4, 6), Int(capInterval))
            return PlannedWorkout(day: day, type: .interval, title: "Intervallen 1 km",
                                  blocks: main(n, WorkoutStep(.work, .distance(1000), .zone(.interval)), jog(150)))
        case .tenKSpecific:
            let n = max(min(lerp(3, 4), Int(capTempo / 2)), 2)
            return PlannedWorkout(day: day, type: .tempo, title: "10k-specifiek",
                                  blocks: main(n, WorkoutStep(.work, .distance(2000), .racePace(10_000)), jog(120)))
        case .tenKDressRehearsal:
            return PlannedWorkout(day: day, type: .tempo, title: "10k-generale",
                                  blocks: main(2, WorkoutStep(.work, .distance(3000), .racePace(10_000)), jog(180)))
        case .sharpen:
            return PlannedWorkout(day: day, type: .interval, title: "Scherp blijven",
                                  blocks: main(3, WorkoutStep(.work, .distance(1000), .racePace(10_000)), jog(120)))
        }
    }
}

/// Eenvoudige loopjes zonder blokken.
public enum SimpleRuns {
    public static func easy(day: Weekday, km: Double, isExtra: Bool = false) -> PlannedWorkout {
        PlannedWorkout(day: day, type: .easy, title: isExtra ? "Extra rustige loop" : "Rustige loop",
                       blocks: [WorkoutBlock([WorkoutStep(.steady, .distance(km * 1000), .zone(.easy))])],
                       isExtra: isExtra)
    }

    public static func long(day: Weekday, km: Double) -> PlannedWorkout {
        PlannedWorkout(day: day, type: .long, title: "Lange loop",
                       blocks: [WorkoutBlock([WorkoutStep(.steady, .distance(km * 1000), .zone(.easy))])])
    }

    /// Lange loop waarvan de laatste kilometers op duurtempo gaan.
    public static func progression(day: Weekday, km: Double, fastKm: Double = 2) -> PlannedWorkout {
        PlannedWorkout(day: day, type: .progression, title: "Lange loop met versnelling",
                       blocks: [WorkoutBlock([
                           WorkoutStep(.steady, .distance((km - fastKm) * 1000), .zone(.easy)),
                           WorkoutStep(.work, .distance(fastKm * 1000), .zone(.marathon))
                       ])])
    }

    /// Tijdrit over de doelafstand: zo snel als je kan, het voorspelde tempo is de ondergrens.
    public static func timeTrial(day: Weekday, distance: Double) -> PlannedWorkout {
        PlannedWorkout(day: day, type: .test, title: "\(TimeText.distance(distance)) tijdrit",
                       blocks: [
                           WorkoutBlock([WorkoutStep(.warmup, .distance(QualitySession.warmupKm * 1000), .zone(.easy))]),
                           WorkoutBlock([WorkoutStep(.work, .distance(distance), .racePace(distance))]),
                           WorkoutBlock([WorkoutStep(.cooldown, .distance(QualitySession.cooldownKm * 1000), .zone(.easy))])
                       ])
    }
}
