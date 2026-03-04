import AVFoundation

final class SpeechManager: NSObject, AVSpeechSynthesizerDelegate {

    private let speechSynthesizer = AVSpeechSynthesizer()
    private var lastSpokenByKey: [String: Date] = [:]
    private var lastAreaByKey: [String: Float] = [:]
    private var onFinishCurrentUtterance: (() -> Void)?

    private let perObjectCooldown: TimeInterval = 4.0
    private let areaIncreaseThreshold: Float = 1.25

    override init() {
        super.init()
        speechSynthesizer.delegate = self
    }

    func speakEvent(label: String, direction: String, distanceWord: String, area: Float) {
        let now = Date()
        let key = "\(label.lowercased())|\(direction)"

        let lastTime = lastSpokenByKey[key] ?? Date.distantPast
        let lastArea = lastAreaByKey[key] ?? 0
        let cooldownPassed = now.timeIntervalSince(lastTime) > perObjectCooldown
        let areaIncreased = area > lastArea * areaIncreaseThreshold

        guard cooldownPassed || areaIncreased else { return }

        lastSpokenByKey[key] = now
        lastAreaByKey[key] = area

        let phrase: String
        if distanceWord.isEmpty {
            phrase = "\(label) \(direction)."
        } else {
            phrase = "\(distanceWord) \(label) \(direction)."
        }
        speak(text: phrase)
    }

    func speak(text: String, onFinish: (() -> Void)? = nil) {
        if speechSynthesizer.isSpeaking { return }
        onFinishCurrentUtterance = onFinish
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.5
        utterance.prefersAssistiveTechnologySettings = true
        speechSynthesizer.speak(utterance)
    }

    func speakSummary(_ phrases: [String]) {
        guard !phrases.isEmpty else { return }
        speak(text: phrases.joined(separator: ". ") + ".")
    }

    func stopSpeaking() {
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        onFinishCurrentUtterance = nil
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let callback = onFinishCurrentUtterance
        onFinishCurrentUtterance = nil
        callback?()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        onFinishCurrentUtterance = nil
    }
}
