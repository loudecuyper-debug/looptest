import Foundation

/// Rekenkern op basis van de formules van Daniels en Gilbert (VDOT).
/// Eén getal dat je loopniveau samenvat: hoger = sneller.
/// Een 5 km in 25:00 geeft ongeveer VDOT 38,3.
public enum Vdot {
    /// Redelijke grenzen: daarbuiten is de input bijna zeker fout.
    public static let validRange: ClosedRange<Double> = 20...85

    /// Zuurstofkost (ml/kg/min) van lopen aan snelheid v (meter per minuut).
    public static func oxygenCost(metersPerMinute v: Double) -> Double {
        -4.60 + 0.182258 * v + 0.000104 * v * v
    }

    /// Fractie van je VO2max die je kan volhouden gedurende t minuten.
    public static func sustainableFraction(minutes t: Double) -> Double {
        0.8 + 0.1894393 * exp(-0.012778 * t) + 0.2989558 * exp(-0.1932605 * t)
    }

    /// Snelheid (m/min) waarbij de zuurstofkost gelijk is aan `vo2`. Inverse van `oxygenCost`.
    public static func velocity(forOxygenCost vo2: Double) -> Double {
        let a = 0.000104, b = 0.182258, c = -4.60 - vo2
        return (-b + (b * b - 4 * a * c).squareRoot()) / (2 * a)
    }

    /// VDOT uit een prestatie (wedstrijd, testloop of tijdrit).
    /// Geeft nil bij onzinnige input: te korte afstand of een onrealistisch tempo.
    public static func from(distance: Double, time: TimeInterval) -> Double? {
        guard distance >= 1500, time > 0 else { return nil }
        let secPerKm = time / distance * 1000
        guard (150...900).contains(secPerKm) else { return nil }   // 2:30 tot 15:00 per km
        let value = raw(distance: distance, minutes: time / 60)
        guard value.isFinite, validRange.contains(value) else { return nil }
        return value
    }

    /// VDOT uit de Cooper-test: zo ver mogelijk lopen in 12 minuten.
    public static func fromCooperTest(distance: Double) -> Double? {
        from(distance: distance, time: 12 * 60)
    }

    /// Voorspelde eindtijd (seconden) over `distance` meter bij een gegeven VDOT.
    public static func predictedTime(distance: Double, vdot: Double) -> TimeInterval {
        // De VDOT van een prestatie daalt naarmate de tijd stijgt, dus bisectie werkt.
        // Zoekbereik: 2:00 tot 20:00 per km.
        var lo = distance / 1000 * 2
        var hi = distance / 1000 * 20
        for _ in 0..<100 {
            let mid = (lo + hi) / 2
            if raw(distance: distance, minutes: mid) > vdot {
                lo = mid
            } else {
                hi = mid
            }
        }
        return (lo + hi) / 2 * 60
    }

    /// Voorspeld wedstrijdtempo (seconden per km) over `distance` meter.
    public static func predictedPace(distance: Double, vdot: Double) -> Double {
        predictedTime(distance: distance, vdot: vdot) / distance * 1000
    }

    /// Tempo (seconden per km) dat overeenkomt met `fraction` van je VDOT.
    public static func pace(fraction: Double, vdot: Double) -> Double {
        60_000 / velocity(forOxygenCost: fraction * vdot)
    }

    private static func raw(distance: Double, minutes: Double) -> Double {
        oxygenCost(metersPerMinute: distance / minutes) / sustainableFraction(minutes: minutes)
    }
}
