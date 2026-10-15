import Foundation

/// "Extra loop deze week": een rustige bonusloop die niet meetelt voor de opbouw.
public enum ExtraRun {
    public static let minKm = 3.0
    public static let maxKm = 5.0
    /// Na zoveel weken op rij met een extra loop stelt de app voor om een vaste dag toe te voegen.
    public static let weeksBeforeSuggestion = 3

    /// Dagen waarop nog niets gepland staat.
    public static func freeDays(in week: PlanWeek) -> [Weekday] {
        Weekday.allCases.filter { week.workout(on: $0) == nil }
    }

    /// Lengte van de extra loop: zoals een gewone rustige loop van die week, tussen 3 en 5 km.
    public static func suggestedKm(in week: PlanWeek) -> Double {
        min(max(PlanGenerator.typicalEasyKm(week.workouts), minKm), maxKm)
    }

    /// Waarschuwing als de extra loop vlak voor een zware dag valt, anders nil.
    public static func warning(for day: Weekday, in week: PlanWeek) -> String? {
        guard day != .sunday, let next = Weekday(rawValue: day.rawValue + 1),
              let w = week.workout(on: next), w.type.isQuality || w.type == .long || w.type == .progression
        else { return nil }
        return "Morgen staat \(w.title.lowercased()) gepland. Een extra loop vandaag kan je benen zwaarder maken."
    }

    /// Voegt de extra loop toe. Geeft de week ongewijzigd terug als die dag al bezet is.
    public static func adding(to week: PlanWeek, on day: Weekday) -> PlanWeek {
        guard week.workout(on: day) == nil else { return week }
        var copy = week
        copy.workouts.append(SimpleRuns.easy(day: day, km: suggestedKm(in: week), isExtra: true))
        copy.workouts.sort { $0.day < $1.day }
        return copy
    }

    /// Haalt de extra loop weer weg.
    public static func removing(from week: PlanWeek, on day: Weekday) -> PlanWeek {
        var copy = week
        copy.workouts.removeAll { $0.day == day && $0.isExtra }
        return copy
    }

    /// True als de laatste `weeksBeforeSuggestion` weken elk een extra loop hadden.
    public static func shouldSuggestExtraDay(recentWeeks: [PlanWeek]) -> Bool {
        let last = recentWeeks.suffix(weeksBeforeSuggestion)
        return last.count == weeksBeforeSuggestion && last.allSatisfy { week in week.workouts.contains { workout in workout.isExtra } }
    }
}
