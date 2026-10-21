import Foundation

/// Een gelopen loop gebruiken als niveautest (bv. een vrije loop waarin je alles gaf).
///
/// Regels (20 okt 2026):
/// - Het gemeten niveau komt uit de VDOT-formule (minstens 1500 m).
/// - Vanaf 5 km telt het gemeten niveau volledig.
/// - Korter dan 5 km telt de helft van het verschil met je huidige niveau: een korte all-out loop
///   test vooral snelheid, niet uithouding, en overschat je dus op langere afstanden.
/// - Het voorstel wordt naar beneden afgerond op 0,5 (voorzichtig).
public enum LevelTest {

    /// Afstand vanaf waar een test volledig meetelt.
    public static let fullDistance: Double = 5_000

    /// Niveau volgens de formule, nil als de loop te kort of onrealistisch is.
    public static func measured(distance: Double, time: TimeInterval) -> Double? {
        Vdot.from(distance: distance, time: time)
    }

    /// Voorgesteld nieuw niveau, rekening houdend met de lengte van de test.
    public static func suggested(distance: Double, time: TimeInterval, current: Double) -> Double? {
        guard let m = measured(distance: distance, time: time) else { return nil }
        let value = distance >= fullDistance ? m : current + (m - current) / 2
        return roundDownHalf(value)
    }

    /// Telt de test maar voor de helft mee?
    public static func countsHalf(distance: Double) -> Bool { distance < fullDistance }

    /// Afronden naar beneden op 0,5.
    public static func roundDownHalf(_ x: Double) -> Double {
        (x * 2 + 1e-9).rounded(.down) / 2
    }

    /// Toegelaten bereik bij een manuele aanpassing.
    public static let allowedRange: ClosedRange<Double> = 25...85
}
