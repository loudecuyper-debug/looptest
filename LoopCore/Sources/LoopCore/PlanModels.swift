import Foundation

// Datamodel van een trainingsplan. Alles is Codable zodat de app het als JSON kan bewaren.

/// Dag van de week, maandag = 0.
public enum Weekday: Int, CaseIterable, Codable, Comparable, Sendable {
    case monday = 0, tuesday, wednesday, thursday, friday, saturday, sunday

    public var short: String {
        ["Ma", "Di", "Wo", "Do", "Vr", "Za", "Zo"][rawValue]
    }

    public var name: String {
        ["maandag", "dinsdag", "woensdag", "donderdag", "vrijdag", "zaterdag", "zondag"][rawValue]
    }

    /// Aantal dagen tussen twee weekdagen, rond de week heen (0 tot 3).
    public func gap(to other: Weekday) -> Int {
        let d = abs(rawValue - other.rawValue)
        return min(d, 7 - d)
    }

    public static func < (a: Weekday, b: Weekday) -> Bool { a.rawValue < b.rawValue }
}

public enum PlanGoal: String, Codable, Sendable {
    case further, faster, both
}

/// Alles wat de gebruiker invult bij het maken van een plan.
public struct PlanInput: Codable, Equatable, Sendable {
    public var goal: PlanGoal
    /// Doelafstand in meter (bv. 10 000).
    public var goalDistance: Double
    public var weeks: Int
    /// Startdatum. De generator schuift die op naar de eerstvolgende maandag.
    public var startDate: Date
    /// Recente prestatie waaruit het niveau berekend wordt.
    public var recentDistance: Double
    public var recentTime: TimeInterval
    public var weeklyVolumeKm: Double
    public var longestRunKm: Double
    public var runDays: [Weekday]
    public var longRunDay: Weekday

    public init(goal: PlanGoal, goalDistance: Double, weeks: Int, startDate: Date,
                recentDistance: Double, recentTime: TimeInterval,
                weeklyVolumeKm: Double, longestRunKm: Double,
                runDays: [Weekday], longRunDay: Weekday) {
        self.goal = goal
        self.goalDistance = goalDistance
        self.weeks = weeks
        self.startDate = startDate
        self.recentDistance = recentDistance
        self.recentTime = recentTime
        self.weeklyVolumeKm = weeklyVolumeKm
        self.longestRunKm = longestRunKm
        self.runDays = runDays
        self.longRunDay = longRunDay
    }
}

public enum Phase: String, Codable, CaseIterable, Sendable {
    case base, build, peak, taper

    public var name: String {
        switch self {
        case .base: return "Opbouw"
        case .build: return "Zwaarder"
        case .peak: return "Piek"
        case .taper: return "Taper"
        }
    }
}

public enum WorkoutType: String, Codable, CaseIterable, Sendable {
    case easy, long, tempo, interval, fartlek, progression, recovery, test

    /// Kwaliteitssessies: niet op opeenvolgende dagen plannen.
    public var isQuality: Bool {
        switch self {
        case .tempo, .interval, .fartlek, .test: return true
        default: return false
        }
    }
}

/// Lengte van een stap: een afstand in meter of een duur in seconden.
public enum StepLength: Codable, Equatable, Sendable {
    case distance(Double)
    case time(TimeInterval)
}

/// Waar het tempo van een stap op mikt.
public enum StepTarget: Codable, Equatable, Sendable {
    case zone(PaceZone)
    /// Wedstrijdtempo voor een afstand in meter (bv. 10 000 = 10k-tempo).
    case racePace(Double)
}

public enum StepKind: String, Codable, Sendable {
    case warmup, work, recovery, cooldown, steady
}

public struct WorkoutStep: Codable, Equatable, Sendable {
    public var kind: StepKind
    public var length: StepLength
    public var target: StepTarget

    public init(_ kind: StepKind, _ length: StepLength, _ target: StepTarget) {
        self.kind = kind
        self.length = length
        self.target = target
    }
}

/// Een of meer stappen die `repeats` keer herhaald worden.
public struct WorkoutBlock: Codable, Equatable, Sendable {
    public var repeats: Int
    public var steps: [WorkoutStep]

    public init(repeats: Int = 1, _ steps: [WorkoutStep]) {
        self.repeats = max(1, repeats)
        self.steps = steps
    }
}

public struct PlannedWorkout: Codable, Equatable, Sendable {
    public var day: Weekday
    public var type: WorkoutType
    public var title: String
    public var blocks: [WorkoutBlock]
    /// Extra loop die de gebruiker zelf toevoegde. Telt niet mee voor de opbouw.
    public var isExtra: Bool

    public init(day: Weekday, type: WorkoutType, title: String, blocks: [WorkoutBlock], isExtra: Bool = false) {
        self.day = day
        self.type = type
        self.title = title
        self.blocks = blocks
        self.isExtra = isExtra
    }

    /// Alle stappen achter elkaar, herhalingen uitgeschreven (voor de cue-engine).
    public var flattenedSteps: [WorkoutStep] {
        blocks.flatMap { block in (0..<block.repeats).flatMap { _ in block.steps } }
    }

    /// Geschatte afstand in meter, tijdstappen omgerekend met het mikpunt-tempo.
    public func estimatedDistance(zones: PaceZones) -> Double {
        flattenedSteps.reduce(0.0) { (sum: Double, step: WorkoutStep) -> Double in
            switch step.length {
            case .distance(let m): return sum + m
            case .time(let s): return sum + s / zones.pace(for: step.target) * 1000
            }
        }
    }

    /// Geschatte duur in seconden.
    public func estimatedDuration(zones: PaceZones) -> TimeInterval {
        flattenedSteps.reduce(0.0) { (sum: Double, step: WorkoutStep) -> Double in
            switch step.length {
            case .distance(let m): return sum + m / 1000 * zones.pace(for: step.target)
            case .time(let s): return sum + s
            }
        }
    }
}

public struct PlanWeek: Codable, Equatable, Sendable {
    public var number: Int
    public var phase: Phase
    public var isRecoveryWeek: Bool
    /// Maandag van deze week.
    public var startDate: Date
    public var workouts: [PlannedWorkout]

    public init(number: Int, phase: Phase, isRecoveryWeek: Bool, startDate: Date, workouts: [PlannedWorkout]) {
        self.number = number
        self.phase = phase
        self.isRecoveryWeek = isRecoveryWeek
        self.startDate = startDate
        self.workouts = workouts
    }

    public func workout(on day: Weekday) -> PlannedWorkout? {
        workouts.first { $0.day == day }
    }

    public func estimatedDistance(zones: PaceZones, includeExtra: Bool = true) -> Double {
        workouts.filter { includeExtra || !$0.isExtra }
            .reduce(0.0) { $0 + $1.estimatedDistance(zones: zones) }
    }

    /// Datum van een dag in deze week.
    public func date(for day: Weekday, calendar: Calendar = PlanCalendar.default) -> Date {
        calendar.date(byAdding: .day, value: day.rawValue, to: startDate) ?? startDate
    }
}

public struct TrainingPlan: Codable, Equatable, Sendable {
    public var input: PlanInput
    public var zones: PaceZones
    public var weeks: [PlanWeek]

    public init(input: PlanInput, zones: PaceZones, weeks: [PlanWeek]) {
        self.input = input
        self.zones = zones
        self.weeks = weeks
    }
}

public enum PlanCalendar {
    /// ISO-kalender (week begint op maandag) in de tijdzone van het toestel.
    public static var `default`: Calendar {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = .current
        return c
    }

    /// De datum zelf als het maandag is, anders de eerstvolgende maandag (begin van de dag).
    public static func nextMonday(onOrAfter date: Date, calendar: Calendar = PlanCalendar.default) -> Date {
        let start = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: start)   // zondag = 1, maandag = 2
        let offset = (9 - weekday) % 7
        return calendar.date(byAdding: .day, value: offset, to: start) ?? start
    }
}

extension PaceZones {
    /// Mikpunt-tempo (s/km) voor een stapdoel.
    public func pace(for target: StepTarget) -> Double {
        switch target {
        case .zone(let z): return range(for: z).target
        case .racePace(let d): return racePace(distance: d)
        }
    }
}
