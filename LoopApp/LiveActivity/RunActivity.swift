import Foundation
import ActivityKit
import AppIntents

// Gedeeld tussen de app en de widget-extensie (RunnerWidgets):
// wat de Live Activity toont en de knoppen op het vergrendelscherm.

struct RunActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Kort label van het huidige blok, bv. "SNEL · 2 VAN 3".
        var blockTitle: String
        /// Wat erna komt, bv. "Daarna: wandelen, 1:00". Nil bij het laatste blok.
        var nextTitle: String?
        /// Einde van het blok als het op tijd loopt en niet gepauzeerd is: de klok telt dan zelf af.
        var blockEnd: Date?
        /// Vaste tekst voor de rest van het blok (bij pauze), bv. "0:42".
        var blockRemainingText: String?
        /// Start van de loop, verschoven met de pauzes: de totale tijd telt hiervan zelf op.
        var runStart: Date
        /// Vaste totale tijd (bij pauze of op het einde).
        var elapsedText: String
        var distanceText: String
        var paceText: String
        var paused: Bool
        var finished: Bool
        /// Of "Blok overslaan" kan (niet bij vrij lopen of in het laatste blok tijdens het aftellen).
        var canSkip: Bool

        // Ontwerp 20 okt (canvas "Runner loopscherm", rij Live Activity). Met standaardwaarden.

        /// Vrij lopen: tijd, afstand en tempo naast elkaar in plaats van een blok.
        var isFreeRun: Bool = false
        /// Aftellen voor de start.
        var isCountdown: Bool = false
        /// Kleur van het blok als hex (typekleur, groen voor rustig en herstel, oranje bij vrij lopen).
        var blockColor: UInt32 = 0xFF7A1A
        /// Begin van een tijdsblok, samen met `blockEnd` voor een balk die zelf vooruitgaat.
        var blockStart: Date? = nil
        /// Voortgang van een afstandsblok (0 tot 1), ververst om de paar seconden.
        var progress: Double? = nil
        /// Tempo zonder eenheid, bv. "4:39".
        var paceValue: String? = nil
        /// 0 onbekend, 1 op tempo, 2 te snel, 3 te traag: kleur van het tempo.
        var paceStatus: Int = 0
        /// Bv. "op tempo · doel 4:35 – 4:44".
        var targetText: String? = nil
        /// Korte regel rechtsboven: vrij lopen "km 4 · vorige 4:28", pauze "interval 3 van 5 · nog 420 m".
        var infoText: String? = nil
        /// Derde cijfer van de samenvatting op het einde, bv. ("GEM. TEMPO", "5:23").
        var summaryLabel: String = "GEM. TEMPO"
        var summaryValue: String? = nil
    }

    /// Naam van de workout, bv. "Intervaltest".
    var workoutName: String
}

/// Wat een knop op het vergrendelscherm vraagt.
enum RunControl: String {
    case pause, resume, skip, stop
}

/// De app registreert hier wat er moet gebeuren; in de extensie blijft dit leeg.
/// Live Activity-intents lopen altijd in het proces van de app zelf.
enum RunControlCenter {
    static var handler: ((RunControl) -> Void)?

    static func send(_ control: RunControl) async {
        await MainActor.run { handler?(control) }
    }
}

struct PauseRunIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Loop pauzeren"
    func perform() async throws -> some IntentResult {
        await RunControlCenter.send(.pause)
        return .result()
    }
}

struct ResumeRunIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Loop hervatten"
    func perform() async throws -> some IntentResult {
        await RunControlCenter.send(.resume)
        return .result()
    }
}

struct SkipBlockIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Blok overslaan"
    func perform() async throws -> some IntentResult {
        await RunControlCenter.send(.skip)
        return .result()
    }
}

struct StopRunIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Loop stoppen"
    func perform() async throws -> some IntentResult {
        await RunControlCenter.send(.stop)
        return .result()
    }
}
