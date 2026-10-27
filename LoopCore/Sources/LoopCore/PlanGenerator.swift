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
/// - Start: in de week waarin het plan gemaakt wordt; loopdagen die al voorbij zijn vallen weg.
///   Is er die week geen loopdag meer over, dan start het plan de maandag erna.
/// - Loopdagen kunnen per week wijzigen (`DaySchedule`, 27 okt): volume, fase en opbouw lopen door,
///   enkel de verdeling over de dagen verandert. Kwaliteitsdagen zelf kiezen kan, anders automatisch.
///
/// Aanpassingen van de coach (`AdaptationState`) worden bij elke berekening toegepast:
/// niveau per week, bevroren weken, verschoven rustweken, verplaatste sessies,
/// dag-overrides, extra loopjes en ziekteperiodes.
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

    public static func generate(_ input: PlanInput, adaptation: AdaptationState = AdaptationState(),
                                calendar: Calendar = PlanCalendar.default) -> TrainingPlan? {
        guard let zones = PaceZones(distance: input.recentDistance, time: input.recentTime) else { return nil }
        let days = Array(Set(input.runDays)).sorted()
        guard days.count >= 2, days.contains(input.longRunDay), input.weeks >= 4 else { return nil }

        let phases = phaseList(weeks: input.weeks)
        let monday = PlanCalendar.planStart(for: input.startDate, runDays: days, calendar: calendar)
        let firstDay = PlanCalendar.firstPlanDay(for: input.startDate, runDays: days, calendar: calendar)
        let startVolume = max(input.weeklyVolumeKm, 5)
        let peakVolume = min(startVolume * 1.6, startVolume + 15)
        let longCap = longRunCapKm(goalDistance: input.goalDistance)

        var volumeTrend = startVolume / volumeGrowth
        var longTrend = min(input.longestRunKm, 0.45 * startVolume + 1) - 1
        var lastLong = longTrend
        var lastProgress = 0.0
        var weeks: [PlanWeek] = []

        for w in 0..<input.weeks {
            let adj = adaptation.adjustment(forWeek: w)
            let schedule = adaptation.daySchedule(forWeek: w)
            let weekDays: [Weekday]
            let longDay: Weekday
            if let schedule, Set(schedule.runDays).count >= 2, schedule.runDays.contains(schedule.longRunDay) {
                weekDays = Array(Set(schedule.runDays)).sorted()
                longDay = schedule.longRunDay
            } else {
                weekDays = days
                longDay = input.longRunDay
            }
            let qualityCount = weekDays.count <= 3 ? 1 : 2
            let qualityDays = pickQualityDays(days: weekDays, longRunDay: longDay, count: qualityCount,
                                              preferred: schedule?.qualityDays ?? input.qualityDays ?? [])
            let weekVdot = adaptation.vdot(forWeek: w, initial: zones.vdot)
            let weekZones = PaceZones(vdot: weekVdot)
            let phase = phases[w]
            let samePhase = phases.indices.filter { phases[$0] == phase }
            let posInPhase = samePhase.firstIndex(of: w) ?? 0
            var progress = Double(posInPhase) / Double(max(1, samePhase.count - 1))
            let isRecovery = phase != .taper && (adj.recovery ?? ((w + 1) % 4 == 0))
            if adj.freeze { progress = lastProgress }
            if !isRecovery { lastProgress = progress }

            // Weekvolume
            let volume: Double
            if phase == .taper {
                volume = roundHalf(peakVolume * 0.6)
            } else if isRecovery {
                volume = roundHalf(volumeTrend * recoveryFactor)
            } else {
                if !adj.freeze { volumeTrend = min(volumeTrend * volumeGrowth, peakVolume) }
                volume = roundHalf(volumeTrend)
            }

            // Lange loop
            var longKm = 0.0
            if phase != .taper {
                if isRecovery {
                    longKm = roundHalf(lastLong * 0.8)
                } else {
                    if !adj.freeze && !adj.freezeLongRun { longTrend = min(longTrend + 1, longCap) }
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
                workouts.append(SimpleRuns.timeTrial(day: longDay, distance: input.goalDistance))
            } else if phase == .peak && !isRecovery && posInPhase == 1 {
                workouts.append(SimpleRuns.progression(day: longDay, km: longKm))
            } else {
                workouts.append(SimpleRuns.long(day: longDay, km: longKm))
            }

            // Rustige loopjes vullen de rest van het volume op.
            let used = workouts.reduce(0.0) { $0 + $1.estimatedDistance(zones: weekZones) / 1000 }
            let easyDays = weekDays.filter { d in !workouts.contains { $0.day == d } }
            if !easyDays.isEmpty {
                let perRun = phase == .taper ? 3 : max(3, roundHalf((volume - used) / Double(easyDays.count)))
                for d in easyDays { workouts.append(SimpleRuns.easy(day: d, km: perRun)) }
            }

            workouts = apply(adj, week: w, to: workouts, sickPeriods: adaptation.sickPeriods)

            // Week 1 begint op de dag dat het plan gemaakt werd: eerdere dagen vallen weg.
            if w == 0 { workouts.removeAll { $0.day < firstDay } }
            // Loopdagen gewijzigd midden in een week: de dagen die toen al voorbij waren vallen weg.
            if let schedule, schedule.fromWeek == w { workouts.removeAll { $0.day < schedule.firstDay } }

            let start = calendar.date(byAdding: .day, value: 7 * w, to: monday) ?? monday
            weeks.append(PlanWeek(number: w + 1, phase: phase, isRecoveryWeek: isRecovery,
                                  startDate: start, workouts: workouts, vdot: weekVdot))
        }
        return TrainingPlan(input: input, zones: zones, weeks: weeks)
    }

    /// Past extra loopjes, verplaatsingen, overrides en ziekteperiodes toe op een week.
    static func apply(_ adj: WeekAdjustment, week: Int, to planned: [PlannedWorkout],
                      sickPeriods: [SickPeriod]) -> [PlannedWorkout] {
        var workouts = planned

        // Extra loopjes op vrije dagen.
        let easyKm = typicalEasyKm(planned)
        for d in adj.extraDays where !workouts.contains(where: { $0.day == d }) {
            workouts.append(SimpleRuns.easy(day: d, km: easyKm, isExtra: true))
        }

        // Verplaatsingen, enkel naar een vrije dag.
        for (from, to) in adj.moves.sorted(by: { $0.key < $1.key }) {
            guard let i = workouts.firstIndex(where: { $0.day == from }),
                  !workouts.contains(where: { $0.day == to }) else { continue }
            workouts[i].day = to
        }

        // Rustige loop toegevoegd door de coach.
        for (d, km) in adj.addedEasy.sorted(by: { $0.key < $1.key })
        where !workouts.contains(where: { $0.day == d }) {
            workouts.append(SimpleRuns.easy(day: d, km: km))
        }

        // Overrides
        for (d, change) in adj.overrides.sorted(by: { $0.key < $1.key }) {
            guard let i = workouts.firstIndex(where: { $0.day == d }) else { continue }
            switch change {
            case .skip:
                workouts.remove(at: i)
            case .easy(let km):
                workouts[i] = SimpleRuns.easy(day: d, km: km, isExtra: workouts[i].isExtra)
            case .shorterLong(let km):
                workouts[i] = SimpleRuns.long(day: d, km: km)
            }
        }

        // Ziek: alles in de periode valt weg.
        workouts.removeAll { w in
            sickPeriods.contains { $0.contains(PlanDay(week: week, day: w.day)) }
        }

        workouts.sort { $0.day < $1.day }
        return workouts
    }

    /// Lengte van een gewone rustige loop in deze week, tussen 3 en 5 km.
    static func typicalEasyKm(_ workouts: [PlannedWorkout]) -> Double {
        let easy = workouts.filter { $0.type == .easy && !$0.isExtra }.map { $0.plainKm ?? 4 }
        let base = easy.isEmpty ? 4 : easy.reduce(0, +) / Double(easy.count)
        return min(max(roundHalf(base), 3), 5)
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

    /// Kiest de kwaliteitsdagen. Eerst de zelf gekozen dagen (`preferred`, in volgorde, enkel loopdagen
    /// en niet de dag van de lange loop), de rest automatisch: zo ver mogelijk van de lange loop en
    /// van elkaar, bij gelijke afstand de vroegste dag.
    public static func pickQualityDays(days: [Weekday], longRunDay: Weekday, count: Int,
                                       preferred: [Weekday] = []) -> [Weekday] {
        var picked: [Weekday] = []
        for d in preferred where picked.count < count && days.contains(d) && d != longRunDay && !picked.contains(d) {
            picked.append(d)
        }
        while picked.count < count {
            let candidates = days.filter { $0 != longRunDay && !picked.contains($0) }
            guard !candidates.isEmpty else { break }
            func score(_ d: Weekday) -> Int {
                ([longRunDay] + picked).map { d.gap(to: $0) }.min() ?? 0
            }
            let best = candidates.max { a, b in
                let sa = score(a), sb = score(b)
                return sa != sb ? sa < sb : a.rawValue > b.rawValue
            }
            guard let best else { break }
            picked.append(best)
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
