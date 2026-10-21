import Foundation
import AVFoundation

/// Spreekt cues uit in het Nederlands, speelt geluidssignalen af (`RunSignal`)
/// en zet andere audio (Spotify) even stiller.
final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    private let synth = AVSpeechSynthesizer()
    private let session = AVAudioSession.sharedInstance()
    private var pending = 0
    private var players: [String: AVAudioPlayer] = [:]
    /// Tot wanneer er nog een signaal speelt (de audiosessie blijft dan actief).
    private var signalUntil = Date.distantPast
    let voice: AVSpeechSynthesisVoice?
    /// 1 = normaal spreektempo, 0,9 = trager, 1,1 = sneller.
    var rateFactor: Float = 1
    var onLog: ((String) -> Void)?

    /// Beste Nederlandse stem: hoogste kwaliteit eerst, bij gelijke kwaliteit nl-BE.
    static func bestVoice() -> AVSpeechSynthesisVoice? {
        let dutch = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("nl") }
        let sorted = dutch.sorted { a, b in
            if a.quality.rawValue != b.quality.rawValue { return a.quality.rawValue > b.quality.rawValue }
            return a.language == "nl-BE" && b.language != "nl-BE"
        }
        return sorted.first ?? AVSpeechSynthesisVoice(language: "nl-BE") ?? AVSpeechSynthesisVoice(language: "nl-NL")
    }

    /// Bv. "Ellen · België · verbeterd".
    static func describe(_ v: AVSpeechSynthesisVoice?) -> String {
        guard let v else { return "Geen Nederlandse stem gevonden" }
        let q: String
        switch v.quality {
        case .premium: q = "premium"
        case .enhanced: q = "verbeterd"
        default: q = "standaard"
        }
        let region = v.language == "nl-BE" ? "België" : "Nederland"
        // iOS zet de kwaliteit soms al in de naam, bv. "Xander (verbeterd)".
        let name = v.name.replacingOccurrences(of: #"\s*\(.*\)"#, with: "", options: .regularExpression)
        return "\(name) · \(region) · \(q)"
    }

    /// `duck`: muziek even stiller zetten tijdens een cue (anders speelt ze op hetzelfde volume verder).
    init(duck: Bool = true) {
        voice = Speaker.bestVoice()
        super.init()
        synth.delegate = self
        do {
            let options: AVAudioSession.CategoryOptions = duck
                ? [.duckOthers, .interruptSpokenAudioAndMixWithOthers]
                : [.mixWithOthers, .interruptSpokenAudioAndMixWithOthers]
            try session.setCategory(.playback, mode: .voicePrompt, options: options)
        } catch {
            log("Audio-categorie fout: \(error.localizedDescription)")
        }
    }

    var voiceDescription: String { Speaker.describe(voice) }

    /// `delay`: extra wachttijd voor de zin, bv. om eerst een signaal te laten klinken.
    func speak(_ text: String, delay: TimeInterval = 0) {
        activate()
        let u = AVSpeechUtterance(string: text)
        u.voice = voice
        u.rate = AVSpeechUtteranceDefaultSpeechRate * rateFactor
        u.preUtteranceDelay = 0.15 + delay
        pending += 1
        synth.speak(u)
        log("🔊 \(text)")
    }

    /// Speelt een geluidssignaal. Geeft de duur terug (0 als het bestand ontbreekt).
    @discardableResult
    func play(_ signal: RunSignal) -> TimeInterval {
        guard let player = player(for: signal) else {
            log("Signaal ontbreekt: \(signal.fileName)")
            return 0
        }
        activate()
        player.currentTime = 0
        player.play()
        let duration = player.duration
        signalUntil = max(signalUntil, Date().addingTimeInterval(duration))
        log("🔔 \(signal.rawValue)")
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.4) { [weak self] in
            self?.deactivateIfIdle()
        }
        return duration
    }

    func stopAll() {
        synth.stopSpeaking(at: .immediate)
        players.values.forEach { $0.stop() }
        signalUntil = .distantPast
    }

    private func player(for signal: RunSignal) -> AVAudioPlayer? {
        if let p = players[signal.rawValue] { return p }
        guard let url = Bundle.main.url(forResource: signal.fileName, withExtension: "m4a"),
              let p = try? AVAudioPlayer(contentsOf: url) else { return nil }
        p.prepareToPlay()
        players[signal.rawValue] = p
        return p
    }

    private func activate() {
        do {
            try session.setActive(true)
        } catch {
            log("Audio activeren mislukt: \(error.localizedDescription)")
        }
    }

    /// Muziek terug luider zodra er geen zin en geen signaal meer klinkt.
    private func deactivateIfIdle() {
        guard pending == 0, !synth.isSpeaking, Date() >= signalUntil else { return }
        do {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            log("Audio deactiveren mislukt: \(error.localizedDescription)")
        }
    }

    private func utteranceDone() {
        DispatchQueue.main.async {
            self.pending = max(0, self.pending - 1)
            guard self.pending == 0 else { return }
            // Kort wachten zodat de muziek niet tussen twee zinnen opveert.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                self.deactivateIfIdle()
            }
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        utteranceDone()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        utteranceDone()
    }

    private func log(_ s: String) {
        DispatchQueue.main.async { self.onLog?(s) }
    }
}
