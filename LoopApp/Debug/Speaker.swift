import Foundation
import AVFoundation

/// Spreekt cues uit in het Nederlands en zet andere audio (Spotify) even stiller.
final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    private let synth = AVSpeechSynthesizer()
    private let session = AVAudioSession.sharedInstance()
    private var pending = 0
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

    override init() {
        voice = Speaker.bestVoice()
        super.init()
        synth.delegate = self
        do {
            try session.setCategory(.playback, mode: .voicePrompt,
                                    options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        } catch {
            log("Audio-categorie fout: \(error.localizedDescription)")
        }
    }

    var voiceDescription: String { Speaker.describe(voice) }

    func speak(_ text: String) {
        do {
            try session.setActive(true)
        } catch {
            log("Audio activeren mislukt: \(error.localizedDescription)")
        }
        let u = AVSpeechUtterance(string: text)
        u.voice = voice
        u.rate = AVSpeechUtteranceDefaultSpeechRate * rateFactor
        u.preUtteranceDelay = 0.15
        pending += 1
        synth.speak(u)
        log("🔊 \(text)")
    }

    func stopAll() {
        synth.stopSpeaking(at: .immediate)
    }

    private func utteranceDone() {
        DispatchQueue.main.async {
            self.pending = max(0, self.pending - 1)
            guard self.pending == 0 else { return }
            // Kort wachten zodat de muziek niet tussen twee zinnen opveert.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                guard self.pending == 0, !self.synth.isSpeaking else { return }
                do {
                    try self.session.setActive(false, options: .notifyOthersOnDeactivation)
                } catch {
                    self.log("Audio deactiveren mislukt: \(error.localizedDescription)")
                }
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
