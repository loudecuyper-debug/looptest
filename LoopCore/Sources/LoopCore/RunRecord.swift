import Foundation

// Een gelopen loop zoals de app hem bewaart. De geplande workout wordt mee bewaard
// zoals hij op dat moment gepland stond, zodat latere aanpassingen van de coach
// je geschiedenis niet veranderen.

public enum RunSource: String, Codable, Sendable {
    /// Gemeten met GPS.
    case gps
    /// Loopband of binnen: afstand via de bewegingssensor.
    case treadmill
    /// Achteraf manueel ingevuld.
    case manual
}

/// Eén kilometer (de laatste kan korter zijn).
public struct Split: Codable, Equatable, Sendable {
    public var distance: Double
    public var duration: TimeInterval

    public init(distance: Double, duration: TimeInterval) {
        self.distance = distance
        self.duration = duration
    }

    public var pace: Double? { distance > 0 ? duration / distance * 1000 : nil }
    public var isFullKm: Bool { distance >= 995 }
}

/// Resultaat van één blok uit de workout: wat gepland was en wat je liep.
public struct BlockResult: Codable, Equatable, Sendable {
    public var kind: StepKind
    public var target: StepTarget
    /// Doeltempo op het moment van lopen (s/km).
    public var targetPace: Double
    public var distance: Double
    public var duration: TimeInterval

    public init(kind: StepKind, target: StepTarget, targetPace: Double, distance: Double, duration: TimeInterval) {
        self.kind = kind
        self.target = target
        self.targetPace = targetPace
        self.distance = distance
        self.duration = duration
    }

    public var pace: Double? { distance >= 20 ? duration / distance * 1000 : nil }

    /// Negatief = sneller dan doel, positief = trager.
    public var deviation: Double? { pace.map { $0 - targetPace } }
}

/// Route als drie parallelle lijsten: compact in JSON en zonder CoreLocation.
public struct RouteTrack: Codable, Equatable, Sendable {
    public var latitudes: [Double] = []
    public var longitudes: [Double] = []
    /// Seconden sinds de start.
    public var times: [Double] = []

    public init() {}

    public var count: Int { latitudes.count }

    public mutating func append(latitude: Double, longitude: Double, time: Double) {
        latitudes.append(latitude)
        longitudes.append(longitude)
        times.append(time)
    }
}

public struct CompletedRun: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var date: Date
    public var source: RunSource
    /// Plek in het plan, nil voor een vrije loop.
    public var planDay: PlanDay?
    /// De workout zoals hij gepland stond, nil voor een vrije loop.
    public var workout: PlannedWorkout?
    public var status: RunStatus
    /// Afstand in meter.
    public var distance: Double
    /// Looptijd zonder pauzes, in seconden.
    public var duration: TimeInterval
    public var splits: [Split]
    public var blocks: [BlockResult]
    public var route: RouteTrack
    public var rpe: Int?
    public var pain: Bool
    /// Gemiddelde kadans in stappen per minuut.
    public var cadence: Double?
    public var note: String?

    public init(id: UUID = UUID(), date: Date, source: RunSource = .gps, planDay: PlanDay? = nil,
                workout: PlannedWorkout? = nil, status: RunStatus = .done,
                distance: Double, duration: TimeInterval,
                splits: [Split] = [], blocks: [BlockResult] = [], route: RouteTrack = RouteTrack(),
                rpe: Int? = nil, pain: Bool = false, cadence: Double? = nil, note: String? = nil) {
        self.id = id
        self.date = date
        self.source = source
        self.planDay = planDay
        self.workout = workout
        self.status = status
        self.distance = distance
        self.duration = duration
        self.splits = splits
        self.blocks = blocks
        self.route = route
        self.rpe = rpe
        self.pain = pain
        self.cadence = cadence
        self.note = note
    }

    /// Achteraf ingevulde loop (gsm vergeten, loopband zonder app).
    public static func manual(date: Date, planDay: PlanDay?, workout: PlannedWorkout?,
                              distance: Double, duration: TimeInterval,
                              rpe: Int? = nil, pain: Bool = false, note: String? = nil) -> CompletedRun {
        CompletedRun(date: date, source: .manual, planDay: planDay, workout: workout,
                     distance: distance, duration: duration, rpe: rpe, pain: pain, note: note)
    }

    public var averagePace: Double? {
        distance >= 100 && duration > 0 ? duration / distance * 1000 : nil
    }

    private var workBlocks: [BlockResult] { blocks.filter { $0.kind == .work } }

    /// Gemiddeld tempo van de snelle blokken.
    public var workPace: Double? {
        let d = workBlocks.reduce(0.0) { $0 + $1.distance }
        let t = workBlocks.reduce(0.0) { $0 + $1.duration }
        return d >= 100 ? t / d * 1000 : nil
    }

    /// Totale tijd van de snelle blokken (voor de tijdrit).
    public var workDuration: TimeInterval? {
        workBlocks.isEmpty ? nil : workBlocks.reduce(0.0) { $0 + $1.duration }
    }

    /// Wat de coach van deze loop moet weten. Nil voor een vrije loop.
    public var coachResult: RunResult? {
        guard let day = planDay else { return nil }
        return RunResult(when: day, status: status, rpe: rpe, pain: pain,
                         averagePace: averagePace, workPace: workPace, workDuration: workDuration)
    }

    /// Korte versie voor lijsten en grafieken.
    public var summary: RunSummary {
        RunSummary(id: id, date: date, source: source, planDay: planDay,
                   type: workout?.type, title: workout?.title ?? "Vrije loop",
                   distance: distance, duration: duration)
    }
}

/// Wat het overzichtsbestand per loop bijhoudt.
public struct RunSummary: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var date: Date
    public var source: RunSource
    public var planDay: PlanDay?
    public var type: WorkoutType?
    public var title: String
    public var distance: Double
    public var duration: TimeInterval

    public init(id: UUID, date: Date, source: RunSource, planDay: PlanDay?, type: WorkoutType?,
                title: String, distance: Double, duration: TimeInterval) {
        self.id = id
        self.date = date
        self.source = source
        self.planDay = planDay
        self.type = type
        self.title = title
        self.distance = distance
        self.duration = duration
    }
}
