import Foundation
import AVFoundation

/// Spreekt cues uit in het Nederlands en zet andere audio (Spotify) even stiller.
final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    private let synth = AVSpeechSynthesizer()
    private let session = AVAudioSession.sharedInstance()
    private var pending = 0
    let voice: AVSpeechSynthesisVoice?
    var onLog: ((String) -> Void)?

    override init() {
        // Beste Nederlandse stem kiezen: hoogste kwaliteit eerst, bij gelijke kwaliteit nl-BE.
        let dutch = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("nl") }
        let sorted = dutch.sorted { a, b in
            if a.quality.rawValue != b.quality.rawValue { return a.quality.rawValue > b.quality.rawValue }
            return a.language == "nl-BE" && b.language != "nl-BE"
        }
        voice = sorted.first ?? AVSpeechSynthesisVoice(language: "nl-BE") ?? AVSpeechSynthesisVoice(language: "nl-NL")
        super.init()
        synth.delegate = self
        do {
            try session.setCategory(.playback, mode: .voicePrompt,
                                    options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        } catch {
            log("Audio-categorie fout: \(error.localizedDescription)")
        }
    }

    var voiceDescription: String {
        guard let v = voice else { return "geen Nederlandse stem gevonden" }
        let q: String
        switch v.quality {
        case .premium: q = "premium"
        case .enhanced: q = "verbeterd"
        default: q = "standaard"
        }
        return "\(v.name) (\(v.language), \(q))"
    }

    func speak(_ text: String) {
        do {
            try session.setActive(true)
        } catch {
            log("Audio activeren mislukt: \(error.localizedDescription)")
        }
        let u = AVSpeechUtterance(string: text)
        u.voice = voice
        u.rate = AVSpeechUtteranceDefaultSpeechRate
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
