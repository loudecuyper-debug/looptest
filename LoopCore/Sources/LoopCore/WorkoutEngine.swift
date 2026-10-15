import Foundation

// De engine achter het lopen: houdt bij welk blok loopt, beslist welke cue wanneer klinkt,
// geeft tempofeedback, meet km-splits en bewaart per blok doel tegenover echt.
// Pure logica: de app geeft tijd, afstand en tempo door, de engine geeft cues en resultaten terug.
// Zo is alles te testen zonder GPS of stem.
//
// Afspraken (goedgekeurd 15 okt):
// - Begin van elk blok: wat en op welk tempo ("Interval 3 van 6: 1 minuut op 4 minuten 50.").
// - Aftellen: "Nog 100 meter." bij afstandsblokken vanaf 300 m, "Nog 10 seconden." bij tijdsblokken vanaf 30 s.
// - Tempo in snelle blokken: buiten de zone (2 s speling) gedurende 15 s → "Iets sneller" of "Iets rustiger",
//   niet in de eerste 20 s van een blok, hooguit om de 30 s.
// - Tempo in rustige blokken: enkel te snel (5 s voorbij de zone) gedurende 30 s, hooguit om de 2 minuten.
// - Halverwege een lang snel blok binnen de zone: één keer "Op tempo".
// - Elke volle kilometer: tijd van die kilometer.
// - Toon: zakelijk, feitelijk.

/// Welke cues de stem uitspreekt. Komt uit Instellingen.
public struct EngineSettings: Codable, Equatable, Sendable {
    /// Begin van elk blok.
    public var blockCues: Bool
    /// "Nog 100 meter", "Nog 10 seconden".
    public var countdown: Bool
    /// Te snel, te traag, op tempo.
    public var paceFeedback: Bool
    /// Tijd per kilometer.
    public var splits: Bool
    /// "Nog 3 te gaan" bij het herstel tussen intervallen.
    public var remaining: Bool

    public init(blockCues: Bool = true, countdown: Bool = true, paceFeedback: Bool = true,
                splits: Bool = true, remaining: Bool = false) {
        self.blockCues = blockCues
        self.countdown = countdown
        self.paceFeedback = paceFeedback
        self.splits = splits
        self.remaining = remaining
    }

    /// Alles uit behalve start en einde.
    public static let silent = EngineSettings(blockCues: false, countdown: false, paceFeedback: false,
                                              splits: false, remaining: false)
}

public enum CueKind: String, Codable, Sendable {
    case start, step, countdown, pace, onPace, split, finish
}

/// Eén zin voor de stem.
public struct Cue: Equatable, Sendable {
    public var kind: CueKind
    public var text: String

    public init(_ kind: CueKind, _ text: String) {
        self.kind = kind
        self.text = text
    }
}

/// Wat er bij een update gebeurde.
public struct EngineUpdate: Equatable, Sendable {
    public var cues: [Cue] = []
    public var finishedBlocks: [BlockResult] = []
    public var splits: [Split] = []
    public var finished = false

    public init() {}
}

/// Eén stap uit de workout, met herhalingen uitgeschreven en doeltempo berekend.
public struct EngineStep: Equatable, Sendable {
    public var step: WorkoutStep
    /// Herhaling binnen het blok (1-gebaseerd), nil als het blok niet herhaald wordt.
    public var rep: Int?
    public var reps: Int?
    /// Volgnummer van de snelle stap (1-gebaseerd), nil voor andere stappen.
    public var workNumber: Int?
    /// Aantal snelle stappen in de hele workout.
    public var workCount: Int
    /// Mikpunt in s/km.
    public var targetPace: Double
    /// Venster in s/km.
    public var range: PaceRange

    public var kind: StepKind { step.kind }

    /// Rustig of herstel: enkel waarschuwen als het te snel gaat.
    public var isEasy: Bool {
        if case .zone(let z) = step.target { return z == .easy || z == .recovery }
        return false
    }
}

/// Of je nu op tempo loopt, voor de kleur op het loopscherm.
public enum PaceStatus: Equatable, Sendable {
    case onPace, tooFast, tooSlow, unknown
}

/// Resterend deel van het huidige blok.
public enum StepRemaining: Equatable, Sendable {
    case time(TimeInterval)
    case distance(Double)
}

public struct WorkoutEngine: Sendable {
    public let steps: [EngineStep]
    public let settings: EngineSettings
    /// Vrij lopen: geen blokken, enkel km-splits.
    public let isFreeRun: Bool
    public let workoutType: WorkoutType?
    public let workoutTitle: String

    public private(set) var currentIndex = 0
    public private(set) var isStarted = false
    public private(set) var isFinished = false
    public private(set) var stoppedEarly = false
    public private(set) var blocks: [BlockResult] = []
    public private(set) var splits: [Split] = []
    public private(set) var stepStartElapsed: TimeInterval = 0
    public private(set) var stepStartDistance: Double = 0

    // Laatste meting, om tussen twee metingen te interpoleren.
    private var prevElapsed: TimeInterval = 0
    private var prevDistance: Double = 0

    // Splits
    private var splitStartElapsed: TimeInterval = 0
    private var splitStartDistance: Double = 0

    // Per blok
    private var countdownDone = false
    private var onPaceDone = false

    // Tempofeedback
    private var offDirection = 0
    private var offSince: TimeInterval?
    private var lastPaceCue: TimeInterval?

    static let speling: Double = 2
    static let easyMargin: Double = 5

    // MARK: - Maken

    public init(workout: PlannedWorkout, zones: PaceZones, settings: EngineSettings = EngineSettings()) {
        steps = WorkoutEngine.makeSteps(workout, zones: zones)
        self.settings = settings
        isFreeRun = false
        workoutType = workout.type
        workoutTitle = workout.title
    }

    /// Vrij lopen zonder plan.
    public init(freeRunWith settings: EngineSettings = EngineSettings()) {
        steps = []
        self.settings = settings
        isFreeRun = true
        workoutType = nil
        workoutTitle = "Vrij lopen"
    }

    static func makeSteps(_ workout: PlannedWorkout, zones: PaceZones) -> [EngineStep] {
        let workCount = workout.flattenedSteps.filter { $0.kind == .work }.count
        var out: [EngineStep] = []
        var workNumber = 0
        for block in workout.blocks {
            for r in 0..<block.repeats {
                for s in block.steps {
                    if s.kind == .work { workNumber += 1 }
                    out.append(EngineStep(step: s,
                                          rep: block.repeats > 1 ? r + 1 : nil,
                                          reps: block.repeats > 1 ? block.repeats : nil,
                                          workNumber: s.kind == .work ? workNumber : nil,
                                          workCount: workCount,
                                          targetPace: zones.pace(for: s.target),
                                          range: range(for: s.target, zones: zones)))
                }
            }
        }
        return out
    }

    static func range(for target: StepTarget, zones: PaceZones) -> PaceRange {
        switch target {
        case .zone(let z):
            return zones.range(for: z)
        case .racePace(let d):
            let p = zones.racePace(distance: d)
            return PaceRange(fast: p - 5, slow: p + 5)
        }
    }

    // MARK: - Toestand voor het scherm

    public var currentStep: EngineStep? {
        currentIndex < steps.count ? steps[currentIndex] : nil
    }

    public var nextStep: EngineStep? {
        currentIndex + 1 < steps.count ? steps[currentIndex + 1] : nil
    }

    public func remaining(elapsed: TimeInterval, distance: Double) -> StepRemaining? {
        guard let s = currentStep else { return nil }
        switch s.step.length {
        case .time(let dur): return .time(max(0, dur - (elapsed - stepStartElapsed)))
        case .distance(let len): return .distance(max(0, len - (distance - stepStartDistance)))
        }
    }

    /// Hoe ver het huidige blok gevorderd is, 0 tot 1.
    public func progress(elapsed: TimeInterval, distance: Double) -> Double {
        guard let s = currentStep else { return isFinished ? 1 : 0 }
        switch s.step.length {
        case .time(let dur): return dur > 0 ? min(1, max(0, (elapsed - stepStartElapsed) / dur)) : 1
        case .distance(let len): return len > 0 ? min(1, max(0, (distance - stepStartDistance) / len)) : 1
        }
    }

    public func paceStatus(_ pace: Double?) -> PaceStatus {
        guard let pace, let s = currentStep else { return .unknown }
        if s.isEasy || s.kind == .warmup || s.kind == .cooldown || s.kind == .recovery {
            return pace < s.range.fast - WorkoutEngine.easyMargin ? .tooFast : .onPace
        }
        let dev = s.range.deviation(of: pace)
        if dev < -WorkoutEngine.speling { return .tooFast }
        if dev > WorkoutEngine.speling { return .tooSlow }
        return .onPace
    }

    /// Kort label voor het loopscherm, bv. "SNEL · 3 VAN 6".
    public func label(for s: EngineStep) -> String {
        switch s.kind {
        case .warmup: return "INLOPEN"
        case .cooldown: return "UITLOPEN"
        case .recovery: return "HERSTEL"
        case .steady: return s.isEasy ? "RUSTIG" : "TEMPO"
        case .work:
            if let n = s.workNumber, s.workCount > 1 { return "SNEL · \(n) VAN \(s.workCount)" }
            return workoutType == .test ? "TIJDRIT" : "SNEL"
        }
    }

    // MARK: - Lopen

    /// Start: geeft de eerste cue terug.
    public mutating func start() -> [Cue] {
        guard !isStarted else { return [] }
        isStarted = true
        if isFreeRun {
            return [Cue(.start, settings.splits ? "Vrij lopen gestart. Je hoort elke kilometer je tijd." : "Vrij lopen gestart.")]
        }
        guard !steps.isEmpty else { return [Cue(.start, "Workout gestart.")] }
        return [Cue(.start, "Workout gestart. " + intro(0))]
    }

    /// Nieuwe meting. `elapsed` is looptijd zonder pauzes, `distance` de totale afstand in meter,
    /// `pace` het actuele tempo (s/km) of nil als het nog niet bekend is.
    public mutating func update(elapsed e: TimeInterval, distance d: Double, pace: Double?) -> EngineUpdate {
        var out = EngineUpdate()
        guard isStarted, !isFinished else { return out }

        addSplits(elapsed: e, distance: d, into: &out)

        if !isFreeRun {
            while let s = currentStep, let end = endPoint(of: s, elapsed: e, distance: d) {
                close(at: end.time, distance: end.distance, into: &out)
                if currentStep == nil {
                    finish(elapsed: end.time, distance: end.distance, stopped: false, into: &out)
                    remember(elapsed: e, distance: d)
                    return out
                }
                if settings.blockCues { out.cues.append(Cue(.step, intro(currentIndex))) }
            }
            if let c = countdownCue(elapsed: e, distance: d) { out.cues.append(c) }
            if let c = paceCue(elapsed: e, distance: d, pace: pace) { out.cues.append(c) }
        }

        remember(elapsed: e, distance: d)
        return out
    }

    /// Huidig blok overslaan.
    public mutating func skipStep(elapsed e: TimeInterval, distance d: Double) -> EngineUpdate {
        var out = EngineUpdate()
        guard isStarted, !isFinished, !isFreeRun, currentStep != nil else { return out }
        addSplits(elapsed: e, distance: d, into: &out)
        close(at: e, distance: d, into: &out)
        if currentStep == nil {
            finish(elapsed: e, distance: d, stopped: false, into: &out)
        } else if settings.blockCues {
            out.cues.append(Cue(.step, intro(currentIndex)))
        }
        remember(elapsed: e, distance: d)
        return out
    }

    /// Vroeger stoppen (of vrij lopen afsluiten).
    public mutating func stop(elapsed e: TimeInterval, distance d: Double) -> EngineUpdate {
        var out = EngineUpdate()
        guard isStarted, !isFinished else { return out }
        addSplits(elapsed: e, distance: d, into: &out)
        // Vroeger gestopt als er nog meer dan het uitlopen restte.
        let early = !isFreeRun && steps[min(currentIndex, steps.count)...].contains { $0.kind != .cooldown }
        if !isFreeRun, currentStep != nil, e - stepStartElapsed >= 1 {
            close(at: e, distance: d, into: &out)
        }
        finish(elapsed: e, distance: d, stopped: early, into: &out)
        remember(elapsed: e, distance: d)
        return out
    }

    /// Het resultaat als bewaarbare loop.
    public func completedRun(date: Date, planDay: PlanDay?, workout: PlannedWorkout?, distance: Double,
                             duration: TimeInterval, route: RouteTrack = RouteTrack(),
                             cadence: Double? = nil, source: RunSource = .gps) -> CompletedRun {
        CompletedRun(date: date, source: source, planDay: planDay, workout: workout,
                     status: stoppedEarly ? .stoppedEarly : .done,
                     distance: distance, duration: duration, splits: splits, blocks: blocks,
                     route: route, cadence: cadence)
    }

    // MARK: - Intern: blokken

    private func endPoint(of s: EngineStep, elapsed e: TimeInterval, distance d: Double)
        -> (time: TimeInterval, distance: Double)? {
        switch s.step.length {
        case .time(let dur):
            let endT = stepStartElapsed + dur
            guard e >= endT else { return nil }
            return (endT, distanceAt(endT, elapsed: e, distance: d))
        case .distance(let len):
            let endD = stepStartDistance + len
            guard d >= endD else { return nil }
            return (timeAt(endD, elapsed: e, distance: d), endD)
        }
    }

    private mutating func close(at t: TimeInterval, distance x: Double, into out: inout EngineUpdate) {
        guard let s = currentStep else { return }
        let result = BlockResult(kind: s.kind, target: s.step.target, targetPace: s.targetPace,
                                 distance: max(0, x - stepStartDistance),
                                 duration: max(0, t - stepStartElapsed))
        blocks.append(result)
        out.finishedBlocks.append(result)
        currentIndex += 1
        stepStartElapsed = t
        stepStartDistance = x
        countdownDone = false
        onPaceDone = false
        offDirection = 0
        offSince = nil
    }

    private mutating func finish(elapsed e: TimeInterval, distance d: Double, stopped: Bool,
                                 into out: inout EngineUpdate) {
        // Laatste, onvolledige kilometer.
        let rest = d - splitStartDistance
        if rest >= 5 {
            let split = Split(distance: rest, duration: max(0, e - splitStartElapsed))
            splits.append(split)
            out.splits.append(split)
            splitStartDistance = d
            splitStartElapsed = e
        }
        isFinished = true
        stoppedEarly = stopped
        out.finished = true

        var text = "\(CueText.distance(d)) in \(CueText.duration(e))."
        if d >= 100, e > 0 {
            text += " Gemiddeld \(CueText.pace(e / d * 1000)) per kilometer."
        }
        let opening: String
        if isFreeRun {
            opening = "Vrij lopen gestopt."
        } else {
            opening = stopped ? "Workout gestopt." : "Workout klaar."
        }
        out.cues.append(Cue(.finish, "\(opening) \(text)"))
    }

    private mutating func remember(elapsed e: TimeInterval, distance d: Double) {
        prevElapsed = e
        prevDistance = d
    }

    private func distanceAt(_ t: TimeInterval, elapsed e: TimeInterval, distance d: Double) -> Double {
        guard e > prevElapsed else { return d }
        let f = min(max((t - prevElapsed) / (e - prevElapsed), 0), 1)
        return prevDistance + f * (d - prevDistance)
    }

    private func timeAt(_ x: Double, elapsed e: TimeInterval, distance d: Double) -> TimeInterval {
        guard d > prevDistance else { return e }
        let f = min(max((x - prevDistance) / (d - prevDistance), 0), 1)
        return prevElapsed + f * (e - prevElapsed)
    }

    // MARK: - Intern: splits

    private mutating func addSplits(elapsed e: TimeInterval, distance d: Double, into out: inout EngineUpdate) {
        while d - splitStartDistance >= 1000 {
            let mark = splitStartDistance + 1000
            let t = timeAt(mark, elapsed: e, distance: d)
            let split = Split(distance: 1000, duration: max(0, t - splitStartElapsed))
            splits.append(split)
            out.splits.append(split)
            splitStartDistance = mark
            splitStartElapsed = t
            if settings.splits {
                let km = Int((mark / 1000).rounded())
                out.cues.append(Cue(.split, "\(km) kilometer. \(CueText.pace(split.duration)) per kilometer."))
            }
        }
    }

    // MARK: - Intern: aftellen en tempo

    private mutating func countdownCue(elapsed e: TimeInterval, distance d: Double) -> Cue? {
        guard settings.countdown, !countdownDone, let s = currentStep else { return nil }
        switch s.step.length {
        case .time(let dur):
            guard dur >= 30, dur - (e - stepStartElapsed) <= 10 else { return nil }
            countdownDone = true
            return Cue(.countdown, "Nog 10 seconden.")
        case .distance(let len):
            guard len >= 300, len - (d - stepStartDistance) <= 100 else { return nil }
            countdownDone = true
            return Cue(.countdown, "Nog 100 meter.")
        }
    }

    private mutating func paceCue(elapsed e: TimeInterval, distance d: Double, pace: Double?) -> Cue? {
        guard settings.paceFeedback, let pace, let s = currentStep,
              s.kind == .work || s.kind == .steady else {
            offDirection = 0
            offSince = nil
            return nil
        }
        let inStep = e - stepStartElapsed
        let direction: Int
        if s.isEasy {
            direction = pace < s.range.fast - WorkoutEngine.easyMargin ? -1 : 0
        } else {
            let dev = s.range.deviation(of: pace)
            direction = dev < -WorkoutEngine.speling ? -1 : (dev > WorkoutEngine.speling ? 1 : 0)
        }

        if direction == 0 {
            offDirection = 0
            offSince = nil
            return onPaceCue(s, elapsed: e, distance: d, pace: pace)
        }
        if direction != offDirection {
            offDirection = direction
            offSince = e
        }
        let sustained = e - (offSince ?? e)
        let need: TimeInterval = s.isEasy ? 30 : 15
        let gap: TimeInterval = s.isEasy ? 120 : 30
        let spaced = lastPaceCue.map { e - $0 >= gap } ?? true
        guard inStep >= 20, sustained >= need, spaced else { return nil }
        lastPaceCue = e
        offSince = e

        if s.isEasy {
            return Cue(.pace, "Rustiger. Je loopt \(CueText.pace(pace)), rustig is rond \(CueText.pace(s.targetPace)).")
        }
        return Cue(.pace, direction < 0
                   ? "Iets rustiger. Je loopt \(CueText.pace(pace))."
                   : "Iets sneller. Je loopt \(CueText.pace(pace)).")
    }

    /// Eén keer halverwege een lang snel blok, als je binnen de zone loopt.
    private mutating func onPaceCue(_ s: EngineStep, elapsed e: TimeInterval, distance d: Double, pace: Double) -> Cue? {
        guard s.kind == .work, !s.isEasy, !onPaceDone else { return nil }
        let halfway: Bool
        switch s.step.length {
        case .time(let dur): halfway = dur >= 90 && e - stepStartElapsed >= dur / 2
        case .distance(let len): halfway = len >= 600 && d - stepStartDistance >= len / 2
        }
        guard halfway else { return nil }
        onPaceDone = true
        lastPaceCue = e
        return Cue(.onPace, "Op tempo, \(CueText.pace(pace)).")
    }

    // MARK: - Intern: teksten

    private func lengthText(_ length: StepLength) -> String {
        switch length {
        case .distance(let m): return CueText.distance(m)
        case .time(let s): return CueText.duration(s)
        }
    }

    private var workLabel: String {
        switch workoutType {
        case .interval?, .fartlek?: return "Interval"
        case .tempo?: return "Tempoblok"
        case .progression?: return "Versnelling"
        case .test?: return "Tijdrit"
        default: return "Blok"
        }
    }

    /// Aantal snelle stappen na stap `i`.
    private func workLeft(after i: Int) -> Int {
        steps[(i + 1)...].filter { $0.kind == .work }.count
    }

    func intro(_ i: Int) -> String {
        let s = steps[i]
        let len = lengthText(s.step.length)
        let pace = CueText.pace(s.targetPace)
        switch s.kind {
        case .warmup:
            return "Inlopen: \(len) rustig."
        case .cooldown:
            return "Uitlopen: \(len) rustig."
        case .recovery:
            var text = "Herstel: \(len) rustig."
            if settings.remaining {
                let left = workLeft(after: i)
                if left > 0 { text += left == 1 ? " Nog 1 te gaan." : " Nog \(left) te gaan." }
            }
            return text
        case .work:
            if let n = s.workNumber, s.workCount > 1 {
                return "\(workLabel) \(n) van \(s.workCount): \(len) op \(pace)."
            }
            return "\(workLabel): \(len) op \(pace)."
        case .steady:
            if s.isEasy {
                return "\(workoutTitle): \(len) rustig, rond \(pace) per kilometer."
            }
            return "\(len) op \(pace)."
        }
    }
}
