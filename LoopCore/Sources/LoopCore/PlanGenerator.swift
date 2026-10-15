import Foundation

/// Maakt een volledig trainingsplan uit de ingevulde gegevens.
///
/// Regels (versie 1, afgestemd op een snellere 10 km):
/// - Fases: 40% opbouw, 35% zwaarder, rest piek, laatste week taper.
/// - Volume: +8% per week tot max 1,6× startvolume (of +15 km), elke 4e week rustweek (-25%).
/// - Lange loop: +1 km per week, max 42% van het weekvolume en max `longRunCapKm`.
/// - Kwaliteit: 1 sessie per week; met 4+ loopdagen een tweede (tempo) in zwaarder en piek.
/// - Kwaliteitsdagen zo ver mogelijk van de lange loop en van elkaar.
/// - Laatste week: tijdrit over de doelafstand.
public enum PlanGenerator {

    public static let volumeGrowth = 1.08
    public static let recoveryFactor = 0.75
    public static let longRunShare = 0.42

    /// Maximale lange loop per doelafstand.
    public static func longRunCapKm(goalDistance: Double) -> Double {
        switch goalDistance {
        case ..<7_500: return 12
        case ..<15_000: return 14
        case ..<30_000: return 20
        default: return 30
        }
    }

    public static func generate(_ input: PlanInput, calendar: Calendar = PlanCalendar.default) -> TrainingPlan? {
        guard let zones = PaceZones(distance: input.recentDistance, time: input.recentTime) else { return nil }
        let days = Array(Set(input.runDays)).sorted()
        guard days.count >= 2, days.contains(input.longRunDay), input.weeks >= 4 else { return nil }

        let phases = phaseList(weeks: input.weeks)
        let monday = PlanCalendar.nextMonday(onOrAfter: input.startDate, calendar: calendar)
        let startVolume = max(input.weeklyVolumeKm, 5)
        let peakVolume = min(startVolume * 1.6, startVolume + 15)
        let longCap = longRunCapKm(goalDistance: input.goalDistance)

        let qualityCount = days.count <= 3 ? 1 : 2
        let qualityDays = pickQualityDays(days: days, longRunDay: input.longRunDay, count: qualityCount)

        var volumeTrend = startVolume / volumeGrowth
        var longTrend = min(input.longestRunKm, 0.45 * startVolume + 1) - 1
        var lastLong = longTrend
        var weeks: [PlanWeek] = []

        for w in 0..<input.weeks {
            let phase = phases[w]
            let samePhase = phases.indices.filter { phases[$0] == phase }
            let posInPhase = samePhase.firstIndex(of: w) ?? 0
            let progress = Double(posInPhase) / Double(max(1, samePhase.count - 1))
            let isRecovery = phase != .taper && (w + 1) % 4 == 0

            // Weekvolume
            let volume: Double
            if phase == .taper {
                volume = roundHalf(peakVolume * 0.6)
            } else if isRecovery {
                volume = roundHalf(volumeTrend * recoveryFactor)
            } else {
                volumeTrend = min(volumeTrend * volumeGrowth, peakVolume)
                volume = roundHalf(volumeTrend)
            }

            // Lange loop
            var longKm = 0.0
            if phase != .taper {
                if isRecovery {
                    longKm = roundHalf(lastLong * 0.8)
                } else {
                    longTrend = min(longTrend + 1, longCap)
                    longKm = roundHalf(min(longTrend, longRunShare * volume))
                    lastLong = longKm
                }
            }

            // Kwaliteit
            var sessions = [primarySession(phase: phase, isRecovery: isRecovery, weekIndex: w,
                                           posInPhase: posInPhase, progress: progress,
                                           qualityCount: qualityCount)]
            if qualityCount > 1, !isRecovery, phase == .build || phase == .peak {
                sessions.append(sessions[0] == .cruise ? .fartlek : .cruise)
            }

            var workouts: [PlannedWorkout] = []
            for (day, session) in zip(qualityDays, sessions) {
                workouts.append(session.workout(day: day, progress: progress, weekVolumeKm: volume))
            }

            if phase == .taper {
                workouts.append(SimpleRuns.timeTrial(day: input.longRunDay, distance: input.goalDistance))
            } else if phase == .peak && !isRecovery && posInPhase == 1 {
                workouts.append(SimpleRuns.progression(day: input.longRunDay, km: longKm))
            } else {
                workouts.append(SimpleRuns.long(day: input.longRunDay, km: longKm))
            }

            // Rustige loopjes vullen de rest van het volume op.
            let used = workouts.reduce(0.0) { $0 + $1.estimatedDistance(zones: zones) / 1000 }
            let easyDays = days.filter { d in !workouts.contains { $0.day == d } }
            if !easyDays.isEmpty {
                let perRun = phase == .taper ? 3 : max(3, roundHalf((volume - used) / Double(easyDays.count)))
                for d in easyDays { workouts.append(SimpleRuns.easy(day: d, km: perRun)) }
            }
            workouts.sort { $0.day < $1.day }

            let start = calendar.date(byAdding: .day, value: 7 * w, to: monday) ?? monday
            weeks.append(PlanWeek(number: w + 1, phase: phase, isRecoveryWeek: isRecovery,
                                  startDate: start, workouts: workouts))
        }
        return TrainingPlan(input: input, zones: zones, weeks: weeks)
    }

    // MARK: - Hulpfuncties

    /// Fase per week: 40% opbouw, 35% zwaarder, rest piek, laatste week taper.
    public static func phaseList(weeks: Int) -> [Phase] {
        let rest = weeks - 1
        let base = Int((Double(rest) * 0.40).rounded())
        let build = Int((Double(rest) * 0.35).rounded())
        let peak = max(0, rest - base - build)
        return Array(repeating: Phase.base, count: base)
            + Array(repeating: Phase.build, count: build)
            + Array(repeating: Phase.peak, count: peak)
            + [Phase.taper]
    }

    /// Kiest de kwaliteitsdagen: zo ver mogelijk van de lange loop en van elkaar,
    /// bij gelijke afstand de vroegste dag.
    public static func pickQualityDays(days: [Weekday], longRunDay: Weekday, count: Int) -> [Weekday] {
        var picked: [Weekday] = []
        for _ in 0..<count {
            let candidates = days.filter { $0 != longRunDay && !picked.contains($0) }
            guard !candidates.isEmpty else { break }
            func score(_ d: Weekday) -> Int {
                ([longRunDay] + picked).map { d.gap(to: $0) }.min() ?? 0
            }
            let best = candidates.max { a, b in
                let sa = score(a), sb = score(b)
                return sa != sb ? sa < sb : a.rawValue > b.rawValue
            }
            if let best { picked.append(best) }
        }
        return picked
    }

    static func primarySession(phase: Phase, isRecovery: Bool, weekIndex: Int, posInPhase: Int,
                               progress: Double, qualityCount: Int) -> QualitySession {
        if isRecovery { return .fartlekLight }
        let alternate = weekIndex % 2 == 1
        switch phase {
        case .base:
            return alternate ? .tempoSplit : .fartlek
        case .build:
            if qualityCount == 1 { return alternate ? .cruise : .interval800 }
            return progress < 0.5 ? .interval800 : .interval1000
        case .peak:
            return [QualitySession.tenKSpecific, .interval1000, .tenKDressRehearsal][posInPhase % 3]
        case .taper:
            return .sharpen
        }
    }

    /// Afronden op halve kilometers.
    static func roundHalf(_ km: Double) -> Double { (km * 2).rounded() / 2 }
}
