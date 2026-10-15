import Foundation

/// Tijden en tempo's als tekst, voor schermen en de plan-preview.
public enum TimeText {
    /// 316 -> "5:16", 3725 -> "1:02:05".
    public static func clock(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded()))
        let h = s / 3600, m = (s % 3600) / 60, r = s % 60
        if h > 0 { return String(format: "%ld:%02ld:%02ld", h, m, r) }
        return String(format: "%ld:%02ld", m, r)
    }

    /// Tempo per km, bv. "5:16 /km".
    public static func pace(_ secPerKm: Double) -> String {
        clock(secPerKm) + " /km"
    }

    /// Tempovenster, bv. "6:19 - 6:57 /km".
    public static func range(_ r: PaceRange) -> String {
        "\(clock(r.fast)) - \(clock(r.slow)) /km"
    }

    /// Afstand in leesbare vorm: "400 m", "10 km", "21,1 km".
    public static func distance(_ meters: Double) -> String {
        if meters < 1000 { return "\(Int(meters.rounded())) m" }
        let km = meters / 1000
        if abs(km - km.rounded()) < 0.05 { return "\(Int(km.rounded())) km" }
        return String(format: "%.1f km", km).replacingOccurrences(of: ".", with: ",")
    }
}
