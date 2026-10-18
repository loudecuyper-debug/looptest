import Foundation

// Proof of concept (LoopTest): workout-opbouw, cue-timing en Nederlandse teksten
// voor de intervaltest onder Instellingen › Diagnose. De echte app gebruikt LoopCore.

enum SegmentKind {
    case fast, walk, free
}

struct Segment {
    let kind: SegmentKind
    let duration: TimeInterval?   // nil = open einde (vrij lopen)
}

struct WorkoutPlan {
    let name: String
    let segments: [Segment]

    var fastCount: Int { segments.filter { $0.kind == .fast }.count }

    static let intervalTest = WorkoutPlan(
        name: "Intervaltest",
        segments: (0..<3).flatMap { _ in
            [Segment(kind: .fast, duration: 60), Segment(kind: .walk, duration: 60)]
        }
    )

    static let freeRun = WorkoutPlan(
        name: "Vrij lopen",
        segments: [Segment(kind: .free, duration: nil)]
    )
}

struct SegmentResult: Identifiable {
    let id = UUID()
    let index: Int
    let kind: SegmentKind
    let title: String
    let duration: TimeInterval
    let distance: Double

    var pace: Double? { Format.pace(duration: duration, distance: distance) }
}

struct CueUpdate {
    var cues: [String] = []
    var finishedSegments: [SegmentResult] = []
    var workoutFinished = false
}

struct CueEngine {
    let plan: WorkoutPlan
    private(set) var index = 0
    private(set) var segStartElapsed: TimeInterval = 0
    private(set) var segStartDistance: Double = 0
    private(set) var finished = false
    private var warned10 = false
    private var paceCued = false
    private var lastKm = 0
    private var lastKmElapsed: TimeInterval = 0

    init(plan: WorkoutPlan) { self.plan = plan }

    var current: Segment? { index < plan.segments.count ? plan.segments[index] : nil }

    func remaining(elapsed: TimeInterval) -> TimeInterval? {
        guard let seg = current, let dur = seg.duration else { return nil }
        return max(0, dur - (elapsed - segStartElapsed))
    }

    func title(for i: Int) -> String {
        guard i < plan.segments.count else { return "Klaar" }
        switch plan.segments[i].kind {
        case .fast: return "Interval \(fastNumber(i)) van \(plan.fastCount): snel"
        case .walk: return "Wandelen"
        case .free: return "Vrij lopen"
        }
    }

    /// Kort label voor de Live Activity, bv. "SNEL · 2 VAN 3".
    func label(for i: Int) -> String {
        guard i < plan.segments.count else { return "KLAAR" }
        switch plan.segments[i].kind {
        case .fast: return "SNEL · \(fastNumber(i)) VAN \(plan.fastCount)"
        case .walk: return "WANDELEN"
        case .free: return "VRIJ LOPEN"
        }
    }

    /// Wat er na het huidige blok komt, bv. "Daarna: wandelen, 1:00". Nil bij het laatste blok.
    var nextText: String? {
        let i = index + 1
        guard i < plan.segments.count else { return nil }
        let seg = plan.segments[i]
        let dur = seg.duration.map { ", " + Format.clock($0) } ?? ""
        switch seg.kind {
        case .fast: return "Daarna: snel \(fastNumber(i)) van \(plan.fastCount)\(dur)"
        case .walk: return "Daarna: wandelen\(dur)"
        case .free: return "Daarna: vrij lopen"
        }
    }

    /// Of het huidige blok overgeslagen kan worden (enkel blokken met een vaste duur).
    var canSkip: Bool { !finished && current?.duration != nil }

    private func fastNumber(_ i: Int) -> Int {
        plan.segments[0...i].filter { $0.kind == .fast }.count
    }

    private func intro(_ i: Int) -> String {
        let seg = plan.segments[i]
        let dur = seg.duration.map { Format.spokenDuration($0) } ?? ""
        switch seg.kind {
        case .fast: return "Interval \(fastNumber(i)) van \(plan.fastCount). Snel lopen, \(dur)."
        case .walk: return "Wandelen, \(dur)."
        case .free: return "Vrij lopen. Ik meld je elke kilometer."
        }
    }

    mutating func start() -> String {
        "Test gestart. " + intro(0)
    }

    mutating func update(elapsed: TimeInterval, distance: Double, pace: Double?) -> CueUpdate {
        var out = CueUpdate()
        guard !finished else { return out }

        // Meerdere blokken kunnen tegelijk aflopen als een tick vertraagd binnenkomt.
        while let dur = current?.duration, elapsed - segStartElapsed >= dur {
            let endElapsed = segStartElapsed + dur
            out.finishedSegments.append(closeSegment(endElapsed: endElapsed, distance: distance))
            if current != nil {
                out.cues.append(intro(index))
            } else {
                finished = true
                out.workoutFinished = true
                return out
            }
        }

        guard let seg = current else { return out }
        let inSeg = elapsed - segStartElapsed

        if let dur = seg.duration {
            if dur >= 30, !warned10, dur - inSeg <= 10 {
                warned10 = true
                out.cues.append("Nog 10 seconden.")
            }
            if seg.kind == .fast, !paceCued, inSeg >= dur / 2 {
                paceCued = true
                if let p = pace { out.cues.append("Je tempo: \(Format.spokenPace(p)) per kilometer.") }
            }
        } else {
            let km = Int(distance / 1000)
            if km > lastKm {
                lastKm = km
                let split = elapsed - lastKmElapsed
                lastKmElapsed = elapsed
                out.cues.append("\(km) kilometer. Die kilometer liep je in \(Format.spokenDuration(split)).")
            }
        }
        return out
    }

    /// Huidig blok nu afsluiten en naar het volgende gaan.
    /// Geeft het afgesloten blok terug, de cue voor het nieuwe blok, en of de workout daarmee klaar is.
    mutating func skip(elapsed: TimeInterval, distance: Double) -> (result: SegmentResult?, cue: String?, finished: Bool) {
        guard canSkip else { return (nil, nil, false) }
        let result = closeSegment(endElapsed: max(elapsed, segStartElapsed), distance: distance)
        if current != nil {
            return (result, "Blok overgeslagen. " + intro(index), false)
        }
        finished = true
        return (result, nil, true)
    }

    /// Workout vroegtijdig stoppen: lopend blok afsluiten.
    mutating func stop(elapsed: TimeInterval, distance: Double) -> SegmentResult? {
        guard !finished else { return nil }
        finished = true
        guard current != nil, elapsed - segStartElapsed >= 1 else { return nil }
        return closeSegment(endElapsed: elapsed, distance: distance)
    }

    private mutating func closeSegment(endElapsed: TimeInterval, distance: Double) -> SegmentResult {
        let seg = plan.segments[index]
        let result = SegmentResult(
            index: index, kind: seg.kind, title: title(for: index),
            duration: endElapsed - segStartElapsed,
            distance: max(0, distance - segStartDistance)
        )
        index += 1
        segStartElapsed = endElapsed
        segStartDistance = distance
        warned10 = false
        paceCued = false
        return result
    }
}

enum Format {
    /// seconden per km, nil als het te traag is om zinvol te zijn (stilstaan, wandelen).
    static func pace(duration: TimeInterval, distance: Double) -> Double? {
        guard distance >= 20, duration > 0 else { return nil }
        let p = duration / distance * 1000
        return p <= 1200 ? p : nil
    }

    /// Tempo over de laatste `window` seconden op basis van (tijd, totale afstand)-metingen.
    static func rollingPace(samples: [(t: TimeInterval, d: Double)], now: TimeInterval, window: TimeInterval = 30) -> Double? {
        guard let last = samples.last, let first = samples.first(where: { $0.t >= now - window }) else { return nil }
        let dt = last.t - first.t
        guard dt >= 10 else { return nil }
        return pace(duration: dt, distance: last.d - first.d)
    }

    static func clock(_ t: TimeInterval) -> String {
        let s = max(0, Int(t.rounded()))
        return String(format: "%ld:%02ld", s / 60, s % 60)
    }

    static func paceShort(_ p: Double?) -> String {
        guard let p else { return "-:--" }
        return clock(p) + " /km"
    }

    static func km(_ d: Double) -> String {
        String(format: "%.2f km", d / 1000).replacingOccurrences(of: ".", with: ",")
    }

    static func spokenDuration(_ t: TimeInterval) -> String {
        let s = max(0, Int(t.rounded()))
        let m = s / 60, r = s % 60
        if m == 0 { return "\(r) seconden" }
        let min = m == 1 ? "1 minuut" : "\(m) minuten"
        return r == 0 ? min : "\(min) \(r)"
    }

    static func spokenPace(_ p: Double) -> String {
        let s = Int(p.rounded())
        let m = s / 60, r = s % 60
        return r == 0 ? "\(m) minuten" : "\(m) minuut \(r)"
    }

    static func spokenDistance(_ d: Double) -> String {
        if d < 1000 { return "\(Int(d)) meter" }
        return String(format: "%.2f", d / 1000).replacingOccurrences(of: ".", with: ",") + " kilometer"
    }
}
