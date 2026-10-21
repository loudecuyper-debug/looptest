import Foundation

/// Geluidssignalen tijdens het lopen (keuze van Louis, 20 okt: overal de warme marimba-klank).
/// De bestanden staan in `LoopApp/Sounds/signal-<naam>.m4a` en komen uit `Design/sounds/generate_sounds.py`.
/// Logica van de toonhoogte: stijgend = sneller of positief, dalend = rustiger, één toon = neutraal.
enum RunSignal: String, CaseIterable, Identifiable {
    case km, aftel, snel, herstel, sneller, rustiger, optempo, klaar, pauze, hervat

    var id: String { rawValue }

    var fileName: String { "signal-\(rawValue)" }

    /// Naam in Instellingen.
    var title: String {
        switch self {
        case .km: return "Kilometer gehaald"
        case .aftel: return "Aftellen naar een snel blok"
        case .snel: return "Start of snel blok begint"
        case .herstel: return "Herstel of rustig blok"
        case .sneller: return "Te traag: versnel"
        case .rustiger: return "Te snel: vertraag"
        case .optempo: return "Terug op tempo"
        case .klaar: return "Workout klaar"
        case .pauze: return "Pauze"
        case .hervat: return "Hervat"
        }
    }
}

/// Wat je hoort tijdens het lopen.
enum CueMode: Int, CaseIterable {
    case voice = 0, signals = 1, both = 2

    var usesVoice: Bool { self != .signals }
    var usesSignals: Bool { self != .voice }

    static var current: CueMode {
        CueMode(rawValue: UserDefaults.standard.object(forKey: CueSettings.mode) as? Int ?? CueMode.signals.rawValue) ?? .signals
    }
}
