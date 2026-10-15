import Foundation

/// Kilometers van een week: gepland en al gelopen.
public struct WeekProgress: Equatable, Sendable {
    public var plannedKm: Double
    public var doneKm: Double

    /// Bv. "9,5 van 17,6 km".
    public var text: String {
        func f(_ km: Double) -> String { String(format: "%.1f", km).replacingOccurrences(of: ".", with: ",") }
        return "\(f(doneKm)) van \(f(plannedKm)) km"
    }

    public var fraction: Double { plannedKm > 0 ? min(doneKm / plannedKm, 1) : 0 }
}

public struct PersonalRecord: Equatable, Sendable {
    public var label: String
    /// Afstand in meter (voor de langste loop: de afstand zelf).
    public var distance: Double
    public var time: TimeInterval
    public var date: Date
    public var runID: UUID
}

public enum Stats {

    /// Alle loopjes (ook vrije en manuele) waarvan de datum in deze week valt.
    public static func progress(of week: PlanWeek, runs: [RunSummary],
                                calendar: Calendar = PlanCalendar.default) -> WeekProgress {
        let end = calendar.date(byAdding: .day, value: 7, to: week.startDate) ?? week.startDate
        let done = runs.filter { $0.date >= week.startDate && $0.date < end }
            .reduce(0.0) { $0 + $1.distance }
        return WeekProgress(plannedKm: week.estimatedDistance(zones: week.zones) / 1000, doneKm: done / 1000)
    }

    /// Gelopen km per week van het plan, voor de grafiek.
    public static func weeklyVolumes(plan: TrainingPlan, runs: [RunSummary],
                                     calendar: Calendar = PlanCalendar.default) -> [WeekProgress] {
        plan.weeks.map { progress(of: $0, runs: runs, calendar: calendar) }
    }

    /// Snelste 1 km, 5 km en 10 km (uit opeenvolgende volle km-splits) en de langste loop.
    /// Manuele loopjes tellen niet mee voor tijden, wel voor de langste loop.
    public static func personalRecords(_ runs: [CompletedRun]) -> [PersonalRecord] {
        var records: [PersonalRecord] = []
        for (km, label) in [(1, "1 km"), (5, "5 km"), (10, "10 km")] {
            var best: PersonalRecord?
            for run in runs where run.source != .manual {
                guard let t = bestTime(km: km, splits: run.splits) else { continue }
                if best == nil || t < best!.time {
                    best = PersonalRecord(label: label, distance: Double(km) * 1000, time: t,
                                          date: run.date, runID: run.id)
                }
            }
            if let best { records.append(best) }
        }
        if let longest = runs.max(by: { $0.distance < $1.distance }), longest.distance > 0 {
            records.append(PersonalRecord(label: "Langste loop", distance: longest.distance,
                                          time: longest.duration, date: longest.date, runID: longest.id))
        }
        return records
    }

    /// Snelste reeks van `km` opeenvolgende volle kilometers.
    static func bestTime(km: Int, splits: [Split]) -> TimeInterval? {
        let full = splits.prefix { $0.isFullKm }.map(\.duration)
        guard km > 0, full.count >= km else { return nil }
        var window = full.prefix(km).reduce(0, +)
        var best = window
        for i in km..<full.count {
            window += full[i] - full[i - km]
            best = min(best, window)
        }
        return best
    }
}
