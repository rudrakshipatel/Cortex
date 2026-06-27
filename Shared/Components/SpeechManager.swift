import SwiftUI
import AVFoundation

/// Reads case content aloud via the system text-to-speech engine.
final class SpeechManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = SpeechManager()

    private let synth = AVSpeechSynthesizer()
    @Published private(set) var speaking = false

    private override init() {
        super.init()
        synth.delegate = self
    }

    /// Toggles: speaks the text, or stops if already speaking.
    func toggle(_ text: String) {
        if synth.isSpeaking { stop() } else { speak(text) }
    }

    func speak(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        synth.stopSpeaking(at: .immediate)

        // Play even when the ringer is on silent.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.prefersAssistiveTechnologySettings = false
        speaking = true
        synth.speak(utterance)
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
        speaking = false
    }

    // MARK: AVSpeechSynthesizerDelegate
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        DispatchQueue.main.async { self.speaking = false }
    }
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) {
        DispatchQueue.main.async { self.speaking = false }
    }
}
