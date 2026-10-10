import Foundation

/// Konuşma tanıma dili.
enum SpeechLanguage: String, CaseIterable, Identifiable, Codable {
    case tr = "tr-TR"
    case de = "de-DE"
    case en = "en-US"

    var id: String { rawValue }
    var locale: Locale { Locale(identifier: rawValue) }

    var shortLabel: String {
        switch self {
        case .tr: return "TR"
        case .de: return "DE"
        case .en: return "EN"
        }
    }

    var displayName: String {
        switch self {
        case .tr: return "Türkçe (tr-TR)"
        case .de: return "Deutsch (de-DE)"
        case .en: return "English (en-US)"
        }
    }

    /// ISO 639-1 kodu (tr, de, en)
    var languageCode: String { String(rawValue.prefix(2)) }
}

/// Kalıcı kullanıcı ayarları (UserDefaults). API anahtarları burada DEĞİL, Keychain'de tutulur.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    @Published var uiLanguage: AppLanguage {
        didSet { defaults.set(uiLanguage.rawValue, forKey: "uiLanguage") }
    }
    @Published var provider: AIProviderKind {
        didSet { defaults.set(provider.rawValue, forKey: "provider") }
    }
    @Published var anthropicModel: String {
        didSet { defaults.set(anthropicModel, forKey: "model.anthropic") }
    }
    @Published var openAIModel: String {
        didSet { defaults.set(openAIModel, forKey: "model.openai") }
    }
    @Published var geminiModel: String {
        didSet { defaults.set(geminiModel, forKey: "model.gemini") }
    }
    @Published var speechLanguage: SpeechLanguage {
        didSet { defaults.set(speechLanguage.rawValue, forKey: "speechLanguage") }
    }
    @Published var readAloud: Bool {
        didSet { defaults.set(readAloud, forKey: "readAloud") }
    }
    @Published var wakeWordEnabled: Bool {
        didSet { defaults.set(wakeWordEnabled, forKey: "wakeWordEnabled") }
    }
    @Published var hotkeyEnabled: Bool {
        didSet { defaults.set(hotkeyEnabled, forKey: "hotkeyEnabled") }
    }
    @Published var silenceSeconds: Double {
        didSet { defaults.set(silenceSeconds, forKey: "silenceSeconds") }
    }
    @Published var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
    }

    private init() {
        uiLanguage = AppLanguage(rawValue: defaults.string(forKey: "uiLanguage") ?? "") ?? .tr
        provider = AIProviderKind(rawValue: defaults.string(forKey: "provider") ?? "") ?? .anthropic
        anthropicModel = defaults.string(forKey: "model.anthropic") ?? AIProviderKind.anthropic.defaultModel
        openAIModel = defaults.string(forKey: "model.openai") ?? AIProviderKind.openai.defaultModel
        geminiModel = defaults.string(forKey: "model.gemini") ?? AIProviderKind.gemini.defaultModel
        speechLanguage = SpeechLanguage(rawValue: defaults.string(forKey: "speechLanguage") ?? "") ?? .tr
        readAloud = defaults.object(forKey: "readAloud") as? Bool ?? true
        wakeWordEnabled = defaults.object(forKey: "wakeWordEnabled") as? Bool ?? false
        hotkeyEnabled = defaults.object(forKey: "hotkeyEnabled") as? Bool ?? true
        silenceSeconds = defaults.object(forKey: "silenceSeconds") as? Double ?? 1.5
        hasCompletedOnboarding = defaults.bool(forKey: "hasCompletedOnboarding")
    }

    func model(for kind: AIProviderKind) -> String {
        switch kind {
        case .anthropic: return anthropicModel
        case .openai: return openAIModel
        case .gemini: return geminiModel
        }
    }

    func setModel(_ model: String, for kind: AIProviderKind) {
        let value = model.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .anthropic: anthropicModel = value
        case .openai: openAIModel = value
        case .gemini: geminiModel = value
        }
    }

    var currentModel: String { model(for: provider) }
}
