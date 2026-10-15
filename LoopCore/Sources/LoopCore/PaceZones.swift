import Foundation

/// De trainingszones die het plan gebruikt.
public enum PaceZone: String, CaseIterable, Codable, Sendable {
    case recovery, easy, marathon, threshold, interval, repetition

    /// Naam zoals de app hem toont en uitspreekt.
    public var name: String {
        switch self {
        case .recovery: return "Herstel"
        case .easy: return "Rustig"
        case .marathon: return "Duurtempo"
        case .threshold: return "Tempo"
        case .interval: return "Interval"
        case .repetition: return "Snelheid"
        }
    }

    /// Korte uitleg voor in de app.
    public var explanation: String {
        switch self {
        case .recovery: return "Heel rustig, na een zware dag."
        case .easy: return "Je kan makkelijk praten. Het grootste deel van je kilometers."
        case .marathon: return "Stevig maar lang vol te houden, voor progressielopen."
        case .threshold: return "Comfortabel zwaar, ongeveer een uur vol te houden."
        case .interval: return "Zwaar, blokken van 2 tot 5 minuten."
        case .repetition: return "Snel en ontspannen, korte stukken met volledig herstel."
        }
    }
}

/// Een tempovenster in seconden per km. `fast` is het kleinste getal.
public struct PaceRange: Codable, Equatable, Sendable {
    public var fast: Double
    public var slow: Double

    public init(fast: Double, slow: Double) {
        self.fast = min(fast, slow)
        self.slow = max(fast, slow)
    }

    /// Mikpunt: het midden van het venster.
    public var target: Double { (fast + slow) / 2 }

    /// Of een gelopen tempo binnen het venster valt, met optionele speling in seconden.
    public func contains(_ pace: Double, tolerance: Double = 0) -> Bool {
        pace >= fast - tolerance && pace <= slow + tolerance
    }

    /// Hoeveel seconden per km je buiten het venster zit.
    /// Negatief = te snel, positief = te traag, 0 = goed.
    public func deviation(of pace: Double) -> Double {
        if pace < fast { return pace - fast }
        if pace > slow { return pace - slow }
        return 0
    }
}

/// Alle tempozones voor één loopniveau, afgeleid uit VDOT.
///
/// Fracties van VDOT volgen de Daniels-methode:
/// rustig 62-70%, tempo 86-89%, interval 96-100%, snelheid 106-110%.
/// Duurtempo is het voorspelde marathontempo met 5 s speling.
public struct PaceZones: Codable, Equatable, Sendable {
    public let vdot: Double
    public let recovery: PaceRange
    public let easy: PaceRange
    public let marathon: PaceRange
    public let threshold: PaceRange
    public let interval: PaceRange
    public let repetition: PaceRange

    public init(vdot: Double) {
        let v = min(max(vdot, Vdot.validRange.lowerBound), Vdot.validRange.upperBound)
        func range(_ fastFraction: Double, _ slowFraction: Double) -> PaceRange {
            PaceRange(fast: Vdot.pace(fraction: fastFraction, vdot: v),
                      slow: Vdot.pace(fraction: slowFraction, vdot: v))
        }
        self.vdot = v
        recovery = range(0.62, 0.55)
        easy = range(0.70, 0.62)
        let mp = Vdot.predictedPace(distance: 42_195, vdot: v)
        marathon = PaceRange(fast: mp - 5, slow: mp + 5)
        threshold = range(0.89, 0.86)
        interval = range(1.00, 0.96)
        repetition = range(1.10, 1.06)
    }

    /// Zones uit een prestatie. Nil als de prestatie onzinnig is.
    public init?(distance: Double, time: TimeInterval) {
        guard let v = Vdot.from(distance: distance, time: time) else { return nil }
        self.init(vdot: v)
    }

    public func range(for zone: PaceZone) -> PaceRange {
        switch zone {
        case .recovery: return recovery
        case .easy: return easy
        case .marathon: return marathon
        case .threshold: return threshold
        case .interval: return interval
        case .repetition: return repetition
        }
    }

    /// Wedstrijdtempo (s/km) voor een afstand, bv. 10 km-tempo voor specifieke blokken.
    public func racePace(distance: Double) -> Double {
        Vdot.predictedPace(distance: distance, vdot: vdot)
    }

    /// Voorspelde eindtijd (s) voor een afstand.
    public func predictedTime(distance: Double) -> TimeInterval {
        Vdot.predictedTime(distance: distance, vdot: vdot)
    }

    /// Nieuwe zones na een aanpassing van het niveau (voor de adaptatieregels later).
    public func adjusted(byVdot delta: Double) -> PaceZones {
        PaceZones(vdot: vdot + delta)
    }
}
