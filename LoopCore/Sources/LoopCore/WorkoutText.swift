import Foundation

/// Nederlandse omschrijvingen van workouts, voor schermen en de plan-preview.
public enum WorkoutText {

    /// Bv. "1,5 km rustig · 6× (1 min interval @ 4:50 + 1 min herstel) · 1 km rustig".
    public static func describe(_ workout: PlannedWorkout, zones: PaceZones) -> String {
        workout.blocks.map { (block: WorkoutBlock) -> String in
            let inner = block.steps.map { step($0, zones: zones) }.joined(separator: " + ")
            return block.repeats > 1 ? "\(block.repeats)× (\(inner))" : inner
        }
        .joined(separator: " · ")
    }

    public static func step(_ s: WorkoutStep, zones: PaceZones) -> String {
        let len: String
        switch s.length {
        case .distance(let m): len = TimeText.distance(m)
        case .time(let sec): len = duration(sec)
        }
        let label = targetLabel(s.target)
        switch s.target {
        case .zone(.easy), .zone(.recovery):
            return "\(len) \(label)"
        default:
            return "\(len) \(label) @ \(TimeText.clock(zones.pace(for: s.target)))"
        }
    }

    public static func targetLabel(_ t: StepTarget) -> String {
        switch t {
        case .zone(let z): return z.name.lowercased()
        case .racePace(let d): return "\(TimeText.distance(d).replacingOccurrences(of: " km", with: "k"))-tempo"
        }
    }

    /// 60 -> "1 min", 90 -> "1,5 min", 30 -> "30 s".
    public static func duration(_ seconds: Double) -> String {
        if seconds < 60 { return "\(Int(seconds.rounded())) s" }
        let minutes = seconds / 60
        if abs(minutes - minutes.rounded()) < 0.01 { return "\(Int(minutes.rounded())) min" }
        return String(format: "%.1f min", minutes).replacingOccurrences(of: ".", with: ",")
    }
}
