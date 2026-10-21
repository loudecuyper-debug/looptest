import Foundation

// Alles wat de coach onthoudt over hoe het plan bijgestuurd werd.
// De plangenerator past dit toe bij elke herberekening, zodat het plan altijd
// opnieuw opgebouwd kan worden uit de invoer + deze aanpassingen.

/// Absolute dag in het plan: week 0 maandag = 0, week 1 maandag = 7, ...
public struct PlanDay: Codable, Equatable, Comparable, Hashable, Sendable {
    public var week: Int
    public var day: Weekday

    public init(week: Int, day: Weekday) {
        self.week = week
        self.day = day
    }

    public init(index: Int) {
        week = index / 7
        day = Weekday(rawValue: index % 7) ?? .monday
    }

    public var index: Int { week * 7 + day.rawValue }

    public func adding(days: Int) -> PlanDay { PlanDay(index: index + days) }

    public static func < (a: PlanDay, b: PlanDay) -> Bool { a.index < b.index }
}

/// Wat er op één dag anders moet dan de generator zou plannen.
public enum DayOverride: Codable, Equatable, Sendable {
    /// Workout valt weg.
    case skip
    /// Workout wordt een rustige loop van zoveel km.
    case easy(km: Double)
    /// Lange loop wordt korter.
    case shorterLong(km: Double)
}

/// Aanpassingen voor één week.
public struct WeekAdjustment: Codable, Equatable, Sendable {
    /// Week telt niet mee voor de opbouw: volume, lange loop en sessies groeien niet.
    public var freeze = false
    /// Enkel de lange loop groeit niet.
    public var freezeLongRun = false
    /// Rustweek forceren (true) of schrappen (false). Nil = zoals gepland.
    public var recovery: Bool?
    /// Verplaatste workouts: van dag -> naar dag.
    public var moves: [Weekday: Weekday] = [:]
    public var overrides: [Weekday: DayOverride] = [:]
    /// Dagen met een extra rustige loop (bonus, telt niet mee).
    public var extraDays: [Weekday] = []
    /// Rustige loop toegevoegd door de coach (bv. vandaag rustig na "Moe"), in km.
    public var addedEasy: [Weekday: Double] = [:]

    public init() {}
}

/// Niveauwijziging vanaf een bepaalde week (na een voorstel of tijdrit).
public struct LevelChange: Codable, Equatable, Sendable {
    public var fromWeek: Int
    public var vdot: Double

    public init(fromWeek: Int, vdot: Double) {
        self.fromWeek = fromWeek
        self.vdot = vdot
    }
}

/// Periode waarin je ziek was. `to` is nil zolang je nog ziek bent.
public struct SickPeriod: Codable, Equatable, Sendable {
    public var from: PlanDay
    public var to: PlanDay?

    public func contains(_ d: PlanDay) -> Bool {
        d >= from && (to.map { d <= $0 } ?? true)
    }
}

public enum RunStatus: String, Codable, Sendable {
    case done, stoppedEarly, skipped
}

/// Wat de app na een loop weet.
public struct RunResult: Codable, Equatable, Sendable {
    public var when: PlanDay
    public var status: RunStatus
    /// RPE 1 tot 10.
    public var rpe: Int?
    public var pain: Bool
    /// Gemiddeld tempo van de hele loop (s/km).
    public var averagePace: Double?
    /// Gemiddeld tempo van de snelle blokken (s/km).
    public var workPace: Double?
    /// Tijd van het snelle deel (voor de tijdrit).
    public var workDuration: TimeInterval?

    public init(when: PlanDay, status: RunStatus = .done, rpe: Int? = nil, pain: Bool = false,
                averagePace: Double? = nil, workPace: Double? = nil, workDuration: TimeInterval? = nil) {
        self.when = when
        self.status = status
        self.rpe = rpe
        self.pain = pain
        self.averagePace = averagePace
        self.workPace = workPace
        self.workDuration = workDuration
    }
}

public enum NotFeelingReason: String, Codable, CaseIterable, Sendable {
    case sick, pain, noTime, tired

    public var name: String {
        switch self {
        case .sick: return "Ziek"
        case .pain: return "Pijn"
        case .noTime: return "Geen tijd"
        case .tired: return "Moe"
        }
    }
}

/// Voorstel om je niveau (en dus al je tempo's) aan te passen. Pas na "ja" toegepast.
public struct LevelSuggestion: Codable, Equatable, Sendable {
    public var fromWeek: Int
    public var oldVdot: Double
    public var newVdot: Double
    /// Zone of doel waarmee de vraag geïllustreerd wordt, met oud en nieuw tempo.
    public var exampleLabel: String
    public var oldPace: Double
    public var newPace: Double

    public var faster: Bool { newVdot > oldVdot }

    public var question: String {
        "Je loopt \(faster ? "sneller" : "trager") dan gepland. Tempo's aanpassen? "
            + "(\(exampleLabel) \(TimeText.clock(oldPace)) → \(TimeText.clock(newPace)))"
    }
}

/// Wat de coach je laat weten. Toon: zakelijk en feitelijk, zonder verkleinwoorden.
public enum CoachEvent: Equatable, Sendable {
    case levelSuggestion(LevelSuggestion)
    case testResult(oldVdot: Double, newVdot: Double, predicted10k: TimeInterval)
    case easyTooFastTip
    case easyTooFastWarning
    case painNextRunEasy
    case suggestNotFeeling
    case sessionMoved(title: String, to: Weekday)
    case sessionDropped(title: String)
    case longRunNotGrowing(week: Int)
    case weekNotCounted(week: Int, missed: Int)
    case growthPaused(week: Int)
    case recoveryEarlier(week: Int)
    case notFeelingApplied(NotFeelingReason)
    case backToPlan

    /// Nederlandse tekst. Weeknummers zijn hier 1-gebaseerd.
    public var message: String {
        switch self {
        case .levelSuggestion(let s):
            return s.question
        case .testResult(let old, let new, let t):
            let lvl = { (v: Double) in String(format: "%.1f", v).replacingOccurrences(of: ".", with: ",") }
            return "Tijdrit verwerkt: niveau van \(lvl(old)) naar \(lvl(new)). Voorspelde 10 km: \(TimeText.clock(t))."
        case .easyTooFastTip:
            return "Deze rustige loop was sneller dan je rustige zone."
        case .easyTooFastWarning:
            return "3 van je laatste 5 rustige loopjes waren sneller dan je rustige zone. Rustige kilometers bouwen je basis op, hou het tempo lager."
        case .painNextRunEasy:
            return "Pijn gemeld: je volgende loop wordt een korte rustige loop van maximaal 30 minuten."
        case .suggestNotFeeling:
            return "Twee keer pijn gemeld binnen 7 dagen. Zet \"Niet 100%\" aan voor enkele lichtere dagen."
        case .sessionMoved(let title, let to):
            return "\(title) verplaatst naar \(to.name)."
        case .sessionDropped(let title):
            return "\(title) vervalt deze week: er is geen geschikte dag meer vrij."
        case .longRunNotGrowing(let w):
            return "Lange loop gemist: in week \(w + 1) wordt hij niet langer."
        case .weekNotCounted(let w, let missed):
            return "\(missed) sessies gemist: week \(w + 1) telt niet mee voor de opbouw."
        case .growthPaused(let w):
            return "De week was zwaarder dan verwacht: week \(w + 1) bouwt niet verder op."
        case .recoveryEarlier(let w):
            return "Twee weken op rij zwaarder dan verwacht: de rustweek komt vroeger, in week \(w + 1)."
        case .notFeelingApplied(let r):
            switch r {
            case .sick: return "Je trainingen staan op pauze tot je aangeeft dat je hersteld bent."
            case .pain: return "De komende 3 dagen enkel korte rustige loopjes."
            case .noTime: return "Deze week enkel je kwaliteitssessie en een kortere lange loop."
            case .tired: return "Vandaag wordt een rustige loop."
            }
        case .backToPlan:
            return "Hersteld genoteerd. Eerst 3 rustige dagen, daarna volg je het plan opnieuw."
        }
    }
}

/// De volledige toestand van de coach. Codable, de app bewaart dit als JSON.
public struct AdaptationState: Codable, Equatable, Sendable {
    public var adjustments: [Int: WeekAdjustment] = [:]
    public var levelChanges: [LevelChange] = []
    public var sickPeriods: [SickPeriod] = []
    public var results: [RunResult] = []
    /// Laatste plandag (index) die `Coach.catchUp` verwerkte: gemist genoteerd en, op zondag, de week afgesloten.
    /// Optioneel, zodat oudere bewaarde gegevens zonder dit veld gewoon inladen.
    public var processedThrough: Int?

    // Geheugen voor de regels
    var qualitySignals: [Int] = []
    var lastLevelChangeWeek: Int?
    var heavyWeeks: Set<Int> = []
    var easyTooFast: [Bool] = []
    var lastEasyWarningWeek: Int?
    var painDays: [PlanDay] = []

    public init() {}

    /// Niveau dat in een bepaalde week geldt.
    public func vdot(forWeek week: Int, initial: Double) -> Double {
        levelChanges.filter { $0.fromWeek <= week }.last?.vdot ?? initial
    }

    public func adjustment(forWeek week: Int) -> WeekAdjustment {
        adjustments[week] ?? WeekAdjustment()
    }

    mutating func update(week: Int, _ change: (inout WeekAdjustment) -> Void) {
        var a = adjustments[week] ?? WeekAdjustment()
        change(&a)
        adjustments[week] = a
    }

    public var isSick: Bool { sickPeriods.contains { $0.to == nil } }
}
