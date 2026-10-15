import Foundation

/// Een cue met het moment waarop hij klonk.
public struct TimedCue: Equatable, Sendable {
    public var time: TimeInterval
    public var cue: Cue

    public init(time: TimeInterval, cue: Cue) {
        self.time = time
        self.cue = cue
    }
}

/// Simuleert een loper die een workout loopt, voor de tests en de cue-preview.
/// Elke `tick` seconden komt er een meting met het tempo dat `pace` teruggeeft.
public enum EngineSimulator {
    public struct Result: Sendable {
        public var engine: WorkoutEngine
        public var cues: [TimedCue]
        public var elapsed: TimeInterval
        public var distance: Double

        public func texts(_ kind: CueKind? = nil) -> [String] {
            cues.filter { kind == nil || $0.cue.kind == kind }.map { $0.cue.text }
        }
    }

    /// - Parameters:
    ///   - pace: tempo (s/km) voor het huidige blok; nil bij vrij lopen.
    ///   - stopAtDistance: stopt (zoals de stopknop) zodra deze afstand bereikt is.
    ///   - stopAtTime: idem op tijd.
    public static func run(_ engine: WorkoutEngine, tick: TimeInterval = 1,
                           stopAtDistance: Double? = nil, stopAtTime: TimeInterval? = nil,
                           maxDuration: TimeInterval = 5 * 3600,
                           pace: (EngineStep?) -> Double) -> Result {
        var e = engine
        var cues = e.start().map { TimedCue(time: 0, cue: $0) }
        var t: TimeInterval = 0
        var d: Double = 0

        while !e.isFinished && t < maxDuration {
            let p = pace(e.currentStep)
            t += tick
            d += tick / p * 1000
            let u = e.update(elapsed: t, distance: d, pace: p)
            cues += u.cues.map { TimedCue(time: t, cue: $0) }
            if e.isFinished { break }
            let stopDistance = stopAtDistance.map { d >= $0 } ?? false
            let stopTime = stopAtTime.map { t >= $0 } ?? false
            if stopDistance || stopTime {
                let s = e.stop(elapsed: t, distance: d)
                cues += s.cues.map { TimedCue(time: t, cue: $0) }
            }
        }
        return Result(engine: e, cues: cues, elapsed: t, distance: d)
    }

    /// Tempo precies op het mikpunt van elk blok.
    public static func onTarget(_ step: EngineStep?) -> Double {
        step?.targetPace ?? 360
    }
}
