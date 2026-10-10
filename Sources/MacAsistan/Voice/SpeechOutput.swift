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

    // Akış (streaming) durumu: cevap geldikçe tamamlanan cümleler sıraya eklenir.
    private var streamActive = false
    private var streamText = ""
    private var consumed = 0
    private var streamLanguage: String?
    private var fallbackLanguage = "tr"
    private var pendingUtterances = 0

    /// Tek seferde bir metni okur.
    func speak(_ rawText: String, fallbackLanguage: String) {
        beginStream(fallbackLanguage: fallbackLanguage)
        finishStream(rawText)
    }

    /// Yeni bir cevabın okunmasına hazırlan (önceki okuma durur).
    func beginStream(fallbackLanguage: String) {
        stop()
        streamActive = true
        streamText = ""
        consumed = 0
        streamLanguage = nil
        self.fallbackLanguage = fallbackLanguage
        pendingUtterances = 0
    }

    /// Cevabın o ana kadarki hâli: biten cümleler hemen okunmaya başlar.
    func updateStream(_ text: String) {
        guard streamActive else { return }
        streamText = text
        flush(final: false)
    }

    /// Cevap tamamlandı: kalan kısmı da oku.
    func finishStream(_ text: String) {
        guard streamActive else { return }
        streamText = text
        flush(final: true)
        streamActive = false
        if pendingUtterances <= 0 { finished() }
    }

    func stop() {
        streamActive = false
        pendingUtterances = 0
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        finished()
    }

    private func finished() {
        guard isSpeaking else { return }
        isSpeaking = false
        onFinish?()
    }

    private func utteranceDone() {
        pendingUtterances = max(0, pendingUtterances - 1)
        if pendingUtterances == 0 && !streamActive { finished() }
    }

    private func flush(final: Bool) {
        let all = Array(streamText)
        guard consumed < all.count else { return }
        var rest = String(all[consumed...])

        // Kapanmamış bir kod bloğu varsa, bitene kadar onun öncesine kadar oku.
        if !final {
            let fences = rest.components(separatedBy: "```").count - 1
            if fences % 2 == 1, let open = rest.range(of: "```", options: .backwards) {
                rest = String(rest[..<open.lowerBound])
            }
        }

        var chunk: String
        if final {
            chunk = rest
        } else {
            // Son tamamlanan cümlenin sonuna kadar al.
            guard let regex = try? NSRegularExpression(pattern: "[.!?…:;](?=\\s)|\\n"),
                  let last = regex.matches(in: rest, range: NSRange(rest.startIndex..., in: rest)).last,
                  let range = Range(last.range, in: rest) else {
                if rest.count > 280, let space = rest.range(of: " ", options: .backwards) {
                    chunk = String(rest[..<space.upperBound])
                } else {
                    return
                }
                enqueue(chunk)
                return
            }
            chunk = String(rest[..<range.upperBound])
        }
        enqueue(chunk)
    }

    private func enqueue(_ chunk: String) {
        consumed += chunk.count
        let text = Self.cleanForSpeech(chunk)
        guard !text.isEmpty else { return }

        if streamLanguage == nil {
            let sample = Self.cleanForSpeech(streamText)
            streamLanguage = Self.detectLanguage(sample.count > text.count ? sample : text) ?? fallbackLanguage
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.voice(for: streamLanguage ?? fallbackLanguage)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        pendingUtterances += 1
        isSpeaking = true
        onStart?(text)
        synthesizer.speak(utterance)
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
        Task { @MainActor in self.utteranceDone() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.utteranceDone() }
    }
}
