import Foundation

/// Tijd, tempo en afstand als tekst op het loopscherm.
/// (Kwam uit de proof of concept in Diagnose, die op 20 okt verwijderd werd.)
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
