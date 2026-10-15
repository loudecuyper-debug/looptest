import Foundation

/// Tijden, tempo's en afstanden zoals de stem ze uitspreekt.
/// Geschreven voor een Nederlandse stem: "4 minuten 50", "anderhalve kilometer".
public enum CueText {

    /// 45 -> "45 seconden", 60 -> "1 minuut", 90 -> "1 minuut 30", 1764 -> "29 minuten 24",
    /// 3900 -> "1 uur 5 minuten".
    public static func duration(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded()))
        let h = s / 3600, m = (s % 3600) / 60, r = s % 60
        if h > 0 {
            if m == 0 { return "\(h) uur" }
            return "\(h) uur \(minutes(m))"
        }
        if m == 0 { return r == 1 ? "1 seconde" : "\(r) seconden" }
        return r == 0 ? minutes(m) : "\(minutes(m)) \(r)"
    }

    /// Tempo in seconden per km: 290 -> "4 minuten 50", 300 -> "5 minuten", 245 -> "4 minuten 5".
    public static func pace(_ secPerKm: Double) -> String {
        let s = max(0, Int(secPerKm.rounded()))
        let m = s / 60, r = s % 60
        return r == 0 ? minutes(m) : "\(minutes(m)) \(r)"
    }

    /// 400 -> "400 meter", 1000 -> "1 kilometer", 1500 -> "anderhalve kilometer",
    /// 2500 -> "2 en een halve kilometer", 4620 -> "4,6 kilometer".
    public static func distance(_ meters: Double) -> String {
        if meters < 1000 {
            let rounded = Int((meters / 10).rounded()) * 10
            return "\(rounded) meter"
        }
        let km = meters / 1000
        if abs(km - km.rounded()) < 0.05 {
            return "\(Int(km.rounded())) kilometer"
        }
        let halves = km * 2
        if abs(halves - halves.rounded()) < 0.05, Int(halves.rounded()) % 2 == 1 {
            let whole = Int(halves.rounded()) / 2
            return whole == 1 ? "anderhalve kilometer" : "\(whole) en een halve kilometer"
        }
        return String(format: "%.1f", km).replacingOccurrences(of: ".", with: ",") + " kilometer"
    }

    private static func minutes(_ m: Int) -> String {
        m == 1 ? "1 minuut" : "\(m) minuten"
    }
}
