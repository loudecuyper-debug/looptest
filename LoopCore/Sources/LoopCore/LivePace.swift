import Foundation

/// Het tempo "nu" op het loopscherm (22 okt 2026).
///
/// Tot versie 0.7 was dit de afgelegde GPS-afstand over de laatste 30 s. Bij zwak signaal
/// (bomen, hoge gebouwen) verspringen GPS-posities en lopen ze soms achter om daarna in te
/// halen. Dat gaf schommelingen van 7:00 naar 4:55 bij een gelijk tempo.
///
/// Nu, in volgorde:
/// 1. **Doppler-snelheid van de GPS** (`CLLocation.speed`): gemeten uit de frequentieverschuiving
///    van het satellietsignaal, los van de positie. Verspringende posities hebben er geen invloed op.
///    Enkel gebruikt als de opgegeven nauwkeurigheid (`speedAccuracy`) 1,5 m/s of beter is.
/// 2. Valt die even weg: **de laatste waarde 10 s vasthouden**.
/// 3. Daarna: **tempo van de pasteller** (`CMPedometerData.currentPace`), uit passen en paslengte.
///    Iets minder nauwkeurig, maar los van GPS.
///
/// Elke nieuwe meting gaat door een mediaan van de laatste 5 (één uitschieter doet niets) en
/// daarna een tijdsgewogen glijdend gemiddelde (± 5 s bij goed signaal, 8 s anders). Een
/// tempowissel bij een interval staat zo na ongeveer 10 s op het scherm.
/// Getoetst met een simulatie in Python (ruis, zwak signaal met achterlopende posities, GPS-gat).
public struct LivePace: Equatable {
    public enum Source: String, Equatable {
        case gps, pedometer
    }

    /// Doppler-snelheid enkel bruikbaar met een nauwkeurigheid van 1,5 m/s of beter.
    public static let maxSpeedAccuracy = 1.5
    /// Zo lang blijft de laatste GPS-waarde staan als de Doppler-snelheid even wegvalt.
    public static let holdSeconds: TimeInterval = 10
    /// Zonder enige nieuwe meting toont het scherm daarna "-:--".
    public static let staleSeconds: TimeInterval = 15
    /// Trager dan 20:00 per km telt als stilstaan.
    public static let slowestSpeed = 1000.0 / 1200.0
    /// Aantal metingen voor de mediaan.
    public static let medianCount = 5

    public private(set) var source: Source?
    private var recent: [Double] = []
    private var speed: Double?
    private var lastUpdate: TimeInterval?
    private var lastGps: TimeInterval?

    public init() {}

    /// Na een pauze opnieuw beginnen.
    public mutating func reset() {
        self = LivePace()
    }

    /// Bruikbare Doppler-snelheid (m/s)? iOS geeft -1 als er geen is.
    public static func isUsable(speed: Double, speedAccuracy: Double) -> Bool {
        speed >= 0 && speedAccuracy >= 0 && speedAccuracy <= maxSpeedAccuracy
    }

    /// Een GPS-meting. `time` is de looptijd (zonder pauzes) op het moment van de meting.
    public mutating func addGPS(speed: Double, speedAccuracy: Double, at time: TimeInterval) {
        if LivePace.isUsable(speed: speed, speedAccuracy: speedAccuracy) {
            lastGps = time
            feed(.gps, speed: speed, at: time, tau: speedAccuracy <= 0.5 ? 5 : 8)
        } else if gpsFresh(at: time), self.speed != nil {
            lastUpdate = max(lastUpdate ?? time, time)   // even vasthouden
        }
        // Anders neemt de pasteller het over via addPedometer.
    }

    /// Tempo van de pasteller in seconden per km.
    public mutating func addPedometer(paceSecondsPerKm pace: Double, at time: TimeInterval) {
        guard pace > 0, pace.isFinite, !gpsFresh(at: time) else { return }
        feed(.pedometer, speed: 1000 / pace, at: time, tau: 8)
    }

    /// Tempo in seconden per km, nil bij stilstaan of zonder recente meting.
    public func pace(at now: TimeInterval) -> Double? {
        guard let speed, let last = lastUpdate, now - last <= LivePace.staleSeconds,
              speed >= LivePace.slowestSpeed else { return nil }
        return 1000 / speed
    }

    // MARK: - Intern

    private func gpsFresh(at time: TimeInterval) -> Bool {
        guard let lastGps else { return false }
        return time - lastGps <= LivePace.holdSeconds
    }

    private mutating func feed(_ src: Source, speed raw: Double, at time: TimeInterval, tau: TimeInterval) {
        if src != source {
            recent = []
            source = src
        }
        recent.append(raw)
        if recent.count > LivePace.medianCount { recent.removeFirst(recent.count - LivePace.medianCount) }
        let m = LivePace.median(recent)
        if let current = speed, let last = lastUpdate {
            let dt = max(time - last, 0.1)
            speed = current + (1 - exp(-dt / tau)) * (m - current)
        } else {
            speed = m
        }
        lastUpdate = max(lastUpdate ?? time, time)
    }

    static func median(_ values: [Double]) -> Double {
        let s = values.sorted()
        guard !s.isEmpty else { return 0 }
        let mid = s.count / 2
        return s.count % 2 == 1 ? s[mid] : (s[mid - 1] + s[mid]) / 2
    }
}
