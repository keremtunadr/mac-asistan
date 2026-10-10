import AppKit
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
    /// Elle seçilen ya da otomatik modda ilk denenen sağlayıcı.
    @Published var provider: ProviderRef {
        didSet { defaults.set(provider.rawValue, forKey: "provider") }
    }
    /// Kullanıcının eklediği sağlayıcılar (DeepSeek, Mistral, Ollama …)
    @Published var customProviders: [CustomProvider] {
        didSet {
            if let data = try? JSONEncoder().encode(customProviders) { defaults.set(data, forKey: "customProviders") }
        }
    }
    /// Açıkken önce `provider` denenir; çalışmazsa anahtarı olan diğer sağlayıcılara geçilir.
    @Published var autoSelect: Bool {
        didSet { defaults.set(autoSelect, forKey: "autoSelect") }
    }
    /// Strahlentherapie-Fachmodus: yalnızca bilgi bankasındaki kaynaklardan cevap ver.
    @Published var evidenceMode: Bool {
        didSet { defaults.set(evidenceMode, forKey: "evidenceMode") }
    }
    @Published var responseSpeed: ResponseSpeed {
        didSet { defaults.set(responseSpeed.rawValue, forKey: "responseSpeed") }
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
    @Published var showInDock: Bool {
        didSet {
            defaults.set(showInDock, forKey: "showInDock")
            NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
        }
    }
    @Published var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
    }

    private init() {
        uiLanguage = AppLanguage(rawValue: defaults.string(forKey: "uiLanguage") ?? "") ?? .tr
        let savedCustom = defaults.data(forKey: "customProviders").flatMap { try? JSONDecoder().decode([CustomProvider].self, from: $0) } ?? []
        customProviders = savedCustom
        var savedProvider = ProviderRef(rawValue: defaults.string(forKey: "provider") ?? "") ?? .builtin(.anthropic)
        if case let .custom(id) = savedProvider, !savedCustom.contains(where: { $0.id == id }) { savedProvider = .builtin(.anthropic) }
        provider = savedProvider
        autoSelect = defaults.object(forKey: "autoSelect") as? Bool ?? true
        evidenceMode = defaults.bool(forKey: "evidenceMode")
        responseSpeed = ResponseSpeed(rawValue: defaults.string(forKey: "responseSpeed") ?? "") ?? .fast
        anthropicModel = defaults.string(forKey: "model.anthropic") ?? AIProviderKind.anthropic.defaultModel
        openAIModel = defaults.string(forKey: "model.openai") ?? AIProviderKind.openai.defaultModel
        geminiModel = defaults.string(forKey: "model.gemini") ?? AIProviderKind.gemini.defaultModel
        speechLanguage = SpeechLanguage(rawValue: defaults.string(forKey: "speechLanguage") ?? "") ?? .tr
        readAloud = defaults.object(forKey: "readAloud") as? Bool ?? true
        wakeWordEnabled = defaults.object(forKey: "wakeWordEnabled") as? Bool ?? false
        hotkeyEnabled = defaults.object(forKey: "hotkeyEnabled") as? Bool ?? true
        silenceSeconds = defaults.object(forKey: "silenceSeconds") as? Double ?? 1.5
        hasCompletedOnboarding = defaults.bool(forKey: "hasCompletedOnboarding")
        showInDock = defaults.object(forKey: "showInDock") as? Bool ?? true

        for kind in AIProviderKind.allCases where kind.retiredDefaults.contains(model(for: kind)) {
            setModel(kind.defaultModel, for: kind)
        }
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

    // MARK: Tüm sağlayıcılar (yerleşik + eklenen)

    var allProviders: [ProviderRef] {
        AIProviderKind.allCases.map { ProviderRef.builtin($0) } + customProviders.map(\.ref)
    }

    func custom(_ id: UUID) -> CustomProvider? { customProviders.first { $0.id == id } }

    func displayName(_ ref: ProviderRef) -> String {
        switch ref {
        case let .builtin(kind): return kind.displayName
        case let .custom(id): return custom(id)?.name ?? "?"
        }
    }

    func model(for ref: ProviderRef) -> String {
        switch ref {
        case let .builtin(kind): return model(for: kind)
        case let .custom(id): return custom(id)?.model ?? ""
        }
    }

    func setModel(_ model: String, for ref: ProviderRef) {
        switch ref {
        case let .builtin(kind): setModel(model, for: kind)
        case let .custom(id): updateCustom(id) { $0.model = model.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
    }

    func requiresKey(_ ref: ProviderRef) -> Bool {
        if case let .custom(id) = ref { return custom(id)?.requiresKey ?? true }
        return true
    }

    func suggestedModels(_ ref: ProviderRef) -> [String] {
        switch ref {
        case let .builtin(kind): return kind.suggestedModels
        case let .custom(id): return [custom(id)?.model].compactMap { $0 }.filter { !$0.isEmpty }
        }
    }

    func keyHelpURL(_ ref: ProviderRef) -> URL? {
        switch ref {
        case let .builtin(kind): return kind.keyHelpURL
        case let .custom(id): return custom(id)?.keyHelpURL.flatMap(URL.init(string:))
        }
    }

    func keyPrefix(_ ref: ProviderRef) -> String? {
        if case let .builtin(kind) = ref { return kind.keyPrefix }
        return nil
    }

    func client(for ref: ProviderRef) -> AIClient {
        switch ref {
        case let .builtin(kind):
            return kind.makeClient()
        case let .custom(id):
            let raw = (custom(id)?.baseURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmed = raw.hasSuffix("/") ? String(raw.dropLast()) : raw
            return OpenAIClient(base: URL(string: trimmed) ?? URL(string: "http://invalid")!, filterOpenAIModels: false)
        }
    }

    func updateCustom(_ id: UUID, _ change: (inout CustomProvider) -> Void) {
        guard let index = customProviders.firstIndex(where: { $0.id == id }) else { return }
        change(&customProviders[index])
    }

    @discardableResult
    func addCustom(from template: CustomProvider) -> CustomProvider {
        var provider = template
        provider.id = UUID()
        customProviders.append(provider)
        return provider
    }

    func removeCustom(_ id: UUID) {
        customProviders.removeAll { $0.id == id }
        if provider == .custom(id) { provider = .builtin(.anthropic) }
    }

    var currentModel: String { model(for: provider) }

    /// Sohbet/menü seçicileri için: "auto" veya sağlayıcı kodu.
    var providerSelection: String {
        get { autoSelect ? "auto" : provider.rawValue }
        set {
            if newValue == "auto" {
                autoSelect = true
            } else if let ref = ProviderRef(rawValue: newValue) {
                autoSelect = false
                provider = ref
            }
        }
    }
}
