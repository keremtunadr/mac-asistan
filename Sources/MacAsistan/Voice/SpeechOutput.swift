import AVFoundation
import Foundation
import NaturalLanguage

/// Cevapları sesli okur. Dil NaturalLanguage ile otomatik algılanır,
/// uygun macOS sesi seçilir: Türkçe → Yelda, Almanca → Anna, İngilizce → Samantha
/// (yoksa o dilde yüklü en kaliteli ses).
@MainActor
final class SpeechOutput: NSObject, ObservableObject {
    @Published private(set) var isSpeaking = false

    var onStart: ((String) -> Void)?
    var onFinish: (() -> Void)?

    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ rawText: String, fallbackLanguage: String) {
        let text = Self.cleanForSpeech(rawText)
        guard !text.isEmpty else { return }
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }

        let language = Self.detectLanguage(text) ?? fallbackLanguage
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.voice(for: language)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        isSpeaking = true
        onStart?(text)
        synthesizer.speak(utterance)
    }

    func stop() {
        guard synthesizer.isSpeaking || isSpeaking else { return }
        synthesizer.stopSpeaking(at: .immediate)
        finished()
    }

    private func finished() {
        guard isSpeaking else { return }
        isSpeaking = false
        onFinish?()
    }

    // MARK: - Dil ve ses seçimi

    /// "tr", "de" veya "en" döndürür.
    static func detectLanguage(_ text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [.turkish, .german, .english]
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage else { return nil }
        switch language {
        case .turkish: return "tr"
        case .german: return "de"
        case .english: return "en"
        default: return nil
        }
    }

    static let preferredVoiceNames = ["tr": "Yelda", "de": "Anna", "en": "Samantha"]
    private static let preferredRegion = ["tr": "tr-TR", "de": "de-DE", "en": "en-US"]

    static func voice(for language: String) -> AVSpeechSynthesisVoice? {
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(language) }
        func rank(_ voice: AVSpeechSynthesisVoice) -> Int {
            switch voice.quality {
            case .premium: return 3
            case .enhanced: return 2
            default: return 1
            }
        }
        let regionCode = preferredRegion[language]
        func sorted(_ voices: [AVSpeechSynthesisVoice]) -> [AVSpeechSynthesisVoice] {
            voices.sorted { a, b in
                if rank(a) != rank(b) { return rank(a) > rank(b) }
                return (a.language == regionCode ? 1 : 0) > (b.language == regionCode ? 1 : 0)
            }
        }
        // Personal Voice / gürültü efektleri gibi alışılmadık sesleri ele.
        let normal = candidates.filter { !$0.voiceTraits.contains(.isNoveltyVoice) && !$0.voiceTraits.contains(.isPersonalVoice) }

        if let name = preferredVoiceNames[language] {
            let named = normal.filter { $0.name == name || $0.name.hasPrefix(name + " ") }
            if let best = sorted(named).first { return best }
        }
        if let best = sorted(normal).first { return best }
        return AVSpeechSynthesisVoice(language: regionCode ?? language)
    }

    /// Ayarlar ekranında göstermek için: dile göre seçilecek sesin adı.
    static func voiceDescription(for language: String) -> String? {
        guard let voice = voice(for: language) else { return nil }
        let quality: String
        switch voice.quality {
        case .premium: quality = "Premium"
        case .enhanced: quality = "Enhanced"
        default: quality = "Standard"
        }
        return "\(voice.name) (\(voice.language), \(quality))"
    }

    /// Markdown işaretlerini ve kod bloklarını sesli okumadan önce temizler.
    static func cleanForSpeech(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: "```[\\s\\S]*?```", with: " ", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^)]+\\)", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: "https?://\\S+", with: " ", options: .regularExpression)
        result = result.replacingOccurrences(of: "[*_#>`|~]", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "(?m)^\\s*[-•]\\s+", with: "", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension SpeechOutput: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finished() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finished() }
    }
}
