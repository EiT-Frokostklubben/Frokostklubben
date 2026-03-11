import AVFoundation
import UIKit

@MainActor
final class AlertManager: NSObject, AVSpeechSynthesizerDelegate {

    private let speechSynthesizer = AVSpeechSynthesizer()
    private let notificationFeedback = UINotificationFeedbackGenerator()
    private let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)

    private var lastAlertKey = ""
    private var lastAlertDate = Date.distantPast

    private let repeatCooldown: TimeInterval = 2.0
    private let severeRepeatCooldown: TimeInterval = 1.0

    override init() {
        super.init()
        speechSynthesizer.delegate = self
        configureAudioSession()
    }

    func prepare() {
        notificationFeedback.prepare()
        impactFeedback.prepare()
    }

    func deliver(_ alert: ObstacleAlert) {
        let key = "\(alert.direction.rawValue)|\(alert.urgency.rawValue)|\(alert.message)"
        let now = Date()
        let cooldown = alert.urgency == .high ? severeRepeatCooldown : repeatCooldown

        guard key != lastAlertKey || now.timeIntervalSince(lastAlertDate) >= cooldown else { return }

        lastAlertKey = key
        lastAlertDate = now

        triggerHaptics(for: alert.urgency)
        speak(text: alert.message)
    }

    private func triggerHaptics(for urgency: ObstacleUrgency) {
        switch urgency {
        case .low:
            impactFeedback.impactOccurred(intensity: 0.5)
        case .medium:
            notificationFeedback.notificationOccurred(.warning)
        case .high:
            notificationFeedback.notificationOccurred(.error)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [impactFeedback] in
                impactFeedback.impactOccurred(intensity: 1.0)
            }
        }
    }

    private func speak(text: String) {
        guard !speechSynthesizer.isSpeaking else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.48
        utterance.prefersAssistiveTechnologySettings = true
        speechSynthesizer.speak(utterance)
    }

    private func configureAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try audioSession.setActive(true)
        } catch {
            print("AudioSession error:", error)
        }
    }
}
