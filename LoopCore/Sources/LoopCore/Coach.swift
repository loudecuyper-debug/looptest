import Foundation

/// De coach: houdt bij hoe je lopen gaan en stuurt het plan bij.
///
/// Regels (goedgekeurd 15 okt 2026, eerst gesimuleerd in Python):
/// - Zones: 2 kwaliteitssessies op rij 3+ s/km sneller én RPE ≤ 7 → voorstel +0,5 niveau.
///   2 op rij 5+ s/km trager of vroeger gestopt → voorstel -0,5. Max 1 voorstel per 2 weken,
///   niet in de taperweek. Enkel het tempo beslist over de zones. Voorstel pas na "ja" toegepast.
/// - Tijdrit: niveau meteen op het resultaat.
/// - Rustige loop 10+ s/km sneller dan de zone → tip; 3 van de laatste 5 → waarschuwing (max om de 2 weken).
/// - RPE: week gemiddeld 1,5+ boven verwacht → volgende week groeit niet;
///   twee weken op rij → rustweek komt vroeger.
/// - Pijn → volgende loop rustig en korter; twee keer binnen 7 dagen → "Niet 100%" voorstellen.
/// - Gemist: rustig valt weg; kwaliteit en lange loop schuiven naar een vrije dag later die week
///   (niet naast een zware dag), anders weg. Lange loop weg → volgende week niet langer.
///   2+ sessies van een week gemist → die week telt niet mee voor de opbouw.
/// - "Niet 100%": de week telt niet mee, plus aanpassing per reden.
public struct Coach: Codable, Equatable, Sendable {
    public private(set) var input: PlanInput
    public private(set) var state: AdaptationState

    public init(input: PlanInput, state: AdaptationState = AdaptationState()) {
        self.input = input
        self.state = state
    }

    /// Het plan zoals het er nu uitziet, met alle aanpassingen.
    public func plan(calendar: Calendar = PlanCalendar.default) -> TrainingPlan? {
        PlanGenerator.generate(input, adaptation: state, calendar: calendar)
    }

    /// Verwachte RPE per type workout.
    public static func expectedRPE(_ type: WorkoutType) -> Double {
        switch type {
        case .recovery: return 3
        case .easy: return 3.5
        case .long: return 5
        case .progression: return 6
        case .tempo, .fartlek: return 7
        case .interval: return 8
        case .test: return 9
        }
    }

    // MARK: - Na een loop

    /// Registreer een loop (of een overgeslagen workout) en krijg terug wat de coach te zeggen heeft.
    public mutating func record(_ result: RunResult) -> [CoachEvent] {
        state.results.append(result)
        guard let plan = self.plan(), result.when.week < plan.weeks.count else { return [] }
        let w = result.when.week
        let week = plan.weeks[w]
        guard let workout = week.workout(on: result.when.day) else { return [] }   // vrije loop

        if result.status == .skipped {
            return handleSkip(workout, weekIndex: w, plan: plan)
        }

        var events: [CoachEvent] = []
        switch workout.type {
        case .easy, .recovery:
            events += checkEasy(result, week: week)
        case .tempo, .interval, .fartlek:
            events += checkQuality(result, workout: workout, week: week, weekIndex: w, weekCount: plan.weeks.count)
        case .test:
            events += checkTest(result, week: week)
        case .long, .progression:
            break
        }
        if result.pain {
            events += handlePain(at: result.when, plan: plan)
        }
        return events
    }

    /// Antwoord "ja" op een niveauvoorstel.
    public mutating func accept(_ suggestion: LevelSuggestion) {
        state.levelChanges.append(LevelChange(fromWeek: suggestion.fromWeek, vdot: suggestion.newVdot))
    }

    /// Op het einde van een week (of bij het openen van de app in een nieuwe week).
    public mutating func finishWeek(_ w: Int) -> [CoachEvent] {
        guard let plan = self.plan(), w < plan.weeks.count else { return [] }
        let week = plan.weeks[w]
        let done = state.results.filter { $0.when.week == w && $0.status != .skipped }
        let planned = week.workouts.filter { !$0.isExtra }
        let missed = planned.filter { p in !done.contains { $0.when.day == p.day } }.count

        var events: [CoachEvent] = []
        if missed >= 2 {
            state.update(week: w) { $0.freeze = true }
            events.append(.weekNotCounted(week: w, missed: missed))
        }

        let excess: [Double] = done.compactMap { r in
            guard let rpe = r.rpe, let p = week.workout(on: r.when.day) else { return nil }
            return Double(rpe) - Coach.expectedRPE(p.type)
        }
        let heavy = !excess.isEmpty && excess.reduce(0, +) / Double(excess.count) >= 1.5
        guard heavy else { return events }
        state.heavyWeeks.insert(w)

        let next = w + 1
        guard next < plan.weeks.count, plan.weeks[next].phase != .taper else { return events }
        if state.heavyWeeks.contains(w - 1) {
            state.update(week: next) { $0.recovery = true }
            let after = next + 1
            if after < plan.weeks.count, plan.weeks[after].isRecoveryWeek {
                state.update(week: after) { a in
                    a.recovery = false
                    a.freeze = true
                }
            }
            events.append(.recoveryEarlier(week: next))
        } else if !plan.weeks[next].isRecoveryWeek {
            state.update(week: next) { $0.freeze = true }
            events.append(.growthPaused(week: next))
        }
        return events
    }

    // MARK: - Extra loop

    public mutating func addExtraRun(_ when: PlanDay) {
        state.update(week: when.week) { a in
            if !a.extraDays.contains(when.day) { a.extraDays.append(when.day) }
        }
    }

    public mutating func removeExtraRun(_ when: PlanDay) {
        state.update(week: when.week) { $0.extraDays.removeAll { $0 == when.day } }
    }

    // MARK: - Niet 100%

    public mutating func notFeeling(_ reason: NotFeelingReason, at when: PlanDay) -> [CoachEvent] {
        guard let plan = self.plan(), when.week < plan.weeks.count else { return [] }
        let week = plan.weeks[when.week]
        state.update(week: when.week) { $0.freeze = true }
        var events: [CoachEvent] = [.notFeelingApplied(reason)]

        switch reason {
        case .sick:
            if !state.isSick { state.sickPeriods.append(SickPeriod(from: when, to: nil)) }

        case .pain:
            makeEasy(days: 3, from: when, plan: plan, shortened: true)

        case .noTime:
            for wo in week.workouts where wo.day >= when.day {
                switch wo.type {
                case .easy:
                    state.update(week: when.week) { $0.overrides[wo.day] = .skip }
                case .long, .progression:
                    let km = PlanGenerator.roundHalf(wo.estimatedDistance(zones: week.zones) / 1000 * 0.75)
                    state.update(week: when.week) { $0.overrides[wo.day] = .shorterLong(km: km) }
                default:
                    break
                }
            }

        case .tired:
            guard let today = week.workout(on: when.day) else { break }
            let km = PlanGenerator.typicalEasyKm(week.workouts)
            if today.type.isQuality, let to = Coach.freeSlot(for: when.day, in: week) {
                move(from: when.day, to: to, weekIndex: when.week)
                state.update(week: when.week) { $0.addedEasy[when.day] = km }
                events.append(.sessionMoved(title: today.title, to: to))
            } else {
                state.update(week: when.week) { $0.overrides[when.day] = .easy(km: min(km, today.plainKm ?? km)) }
            }
        }
        return events
    }

    /// Na "Ziek": je bent terug beter.
    public mutating func recovered(at when: PlanDay) -> [CoachEvent] {
        guard let i = state.sickPeriods.firstIndex(where: { $0.to == nil }) else { return [] }
        state.sickPeriods[i].to = when.adding(days: -1)
        if let plan = self.plan() {
            makeEasy(days: 3, from: when, plan: plan, shortened: false)
        }
        return [.backToPlan]
    }

    // MARK: - Intern

    private mutating func checkEasy(_ r: RunResult, week: PlanWeek) -> [CoachEvent] {
        guard let pace = r.averagePace else { return [] }
        let tooFast = pace < week.zones.easy.fast - 10
        state.easyTooFast.append(tooFast)
        state.easyTooFast = Array(state.easyTooFast.suffix(5))
        guard tooFast else { return [] }
        let count = state.easyTooFast.filter { $0 }.count
        let mayWarn = state.lastEasyWarningWeek.map { r.when.week - $0 >= 2 } ?? true
        if count >= 3 && mayWarn {
            state.lastEasyWarningWeek = r.when.week
            return [.easyTooFastWarning]
        }
        return [.easyTooFastTip]
    }

    private mutating func checkQuality(_ r: RunResult, workout: PlannedWorkout, week: PlanWeek,
                                       weekIndex w: Int, weekCount: Int) -> [CoachEvent] {
        guard week.phase != .taper else { return [] }
        let target = workout.mainTarget
        var signal = 0
        if r.status == .stoppedEarly {
            signal = -1
        } else if let pace = r.workPace {
            let deviation = pace - week.zones.pace(for: target)
            let rpe = Double(r.rpe ?? 7)
            if deviation <= -3 && rpe <= 7 {
                signal = 1
            } else if deviation >= 5 {
                signal = -1
            }
        }
        state.qualitySignals.append(signal)
        state.qualitySignals = Array(state.qualitySignals.suffix(2))

        let s = state.qualitySignals
        let mayChange = state.lastLevelChangeWeek.map { w - $0 >= 2 } ?? true
        guard s.count == 2, s[0] == s[1], s[0] != 0, mayChange, w + 1 < weekCount else { return [] }

        let newVdot = week.vdot + 0.5 * Double(s[0])
        let suggestion = LevelSuggestion(
            fromWeek: w + 1, oldVdot: week.vdot, newVdot: newVdot,
            exampleLabel: WorkoutText.targetLabel(target),
            oldPace: week.zones.pace(for: target),
            newPace: PaceZones(vdot: newVdot).pace(for: target))
        state.lastLevelChangeWeek = w
        state.qualitySignals = []
        return [.levelSuggestion(suggestion)]
    }

    private mutating func checkTest(_ r: RunResult, week: PlanWeek) -> [CoachEvent] {
        guard r.status == .done, let t = r.workDuration,
              let newVdot = Vdot.from(distance: input.goalDistance, time: t) else { return [] }
        state.levelChanges.append(LevelChange(fromWeek: r.when.week + 1, vdot: newVdot))
        state.lastLevelChangeWeek = r.when.week
        return [.testResult(oldVdot: week.vdot, newVdot: newVdot,
                            predicted10k: Vdot.predictedTime(distance: 10_000, vdot: newVdot))]
    }

    private mutating func handleSkip(_ workout: PlannedWorkout, weekIndex w: Int, plan: TrainingPlan) -> [CoachEvent] {
        let week = plan.weeks[w]
        switch workout.type {
        case .easy, .recovery, .test:
            return []
        case .long, .progression:
            if let to = Coach.freeSlot(for: workout.day, in: week) {
                move(from: workout.day, to: to, weekIndex: w)
                return [.sessionMoved(title: workout.title, to: to)]
            }
            if w + 1 < plan.weeks.count {
                state.update(week: w + 1) { $0.freezeLongRun = true }
                return [.longRunNotGrowing(week: w + 1)]
            }
            return []
        case .tempo, .interval, .fartlek:
            if let to = Coach.freeSlot(for: workout.day, in: week) {
                move(from: workout.day, to: to, weekIndex: w)
                return [.sessionMoved(title: workout.title, to: to)]
            }
            return [.sessionDropped(title: workout.title)]
        }
    }

    private mutating func handlePain(at when: PlanDay, plan: TrainingPlan) -> [CoachEvent] {
        let recent = state.painDays.contains { when.index - $0.index < 7 }
        state.painDays.append(when)
        if recent { return [.suggestNotFeeling] }

        // Volgende geplande loop rustig en korter.
        for wk in plan.weeks.dropFirst(when.week) {
            let w = wk.number - 1
            if let next = wk.workouts.first(where: { PlanDay(week: w, day: $0.day) > when }) {
                let km = Coach.shortEasyKm(wk)
                state.update(week: w) { $0.overrides[next.day] = .easy(km: min(km, next.plainKm ?? km)) }
                break
            }
        }
        return [.painNextRunEasy]
    }

    /// Workouts in de komende `days` dagen worden rustig.
    private mutating func makeEasy(days: Int, from start: PlanDay, plan: TrainingPlan, shortened: Bool) {
        for i in 0..<days {
            let d = start.adding(days: i)
            guard d.week < plan.weeks.count, let wo = plan.weeks[d.week].workout(on: d.day) else { continue }
            let wk = plan.weeks[d.week]
            let km = shortened ? Coach.shortEasyKm(wk) : PlanGenerator.typicalEasyKm(wk.workouts)
            state.update(week: d.week) { $0.overrides[d.day] = .easy(km: min(km, wo.plainKm ?? km)) }
        }
    }

    /// Verplaatst een workout. Houdt rekening met een eerdere verplaatsing van dezelfde workout.
    private mutating func move(from day: Weekday, to target: Weekday, weekIndex w: Int) {
        let original = state.adjustment(forWeek: w).moves.first { $0.value == day }?.key ?? day
        state.update(week: w) { $0.moves[original] = target }
    }

    /// Eerste vrije dag na `day` in deze week die niet naast een zware dag ligt.
    static func freeSlot(for day: Weekday, in week: PlanWeek) -> Weekday? {
        func isHard(_ d: Weekday) -> Bool {
            guard d != day, let w = week.workout(on: d) else { return false }
            return w.type.isQuality || w.type == .long || w.type == .progression
        }
        return Weekday.allCases.first { d in
            guard d > day, week.workout(on: d) == nil else { return false }
            let before = Weekday(rawValue: d.rawValue - 1).map(isHard) ?? false
            let after = Weekday(rawValue: d.rawValue + 1).map(isHard) ?? false
            return !before && !after
        }
    }

    /// Korte rustige loop: max 30 minuten, en niet langer dan een gewone rustige loop.
    static func shortEasyKm(_ week: PlanWeek) -> Double {
        let thirtyMinutes = PlanGenerator.roundHalf(1800 / week.zones.easy.target)
        return max(2, min(thirtyMinutes, PlanGenerator.typicalEasyKm(week.workouts)))
    }
}
