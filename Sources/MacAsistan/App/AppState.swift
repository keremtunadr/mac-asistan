import AppKit
import Combine
import Foundation
import SwiftUI

/// Uygulamanın merkezi: ayarlar, sohbet geçmişi, ses girişi/çıkışı ve yapay zekâ isteklerini birbirine bağlar.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    let settings = AppSettings.shared
    let store = ChatStore()
    let speechIn = SpeechInput()
    let speechOut = SpeechOutput()

    /// Keychain'den okunan anahtarlar (tekrar tekrar Keychain'e sormamak için bellekte tutulur).
    @Published private(set) var apiKeys: [AIProviderKind: String] = [:]
    @Published private(set) var isSending = false

    /// SwiftUI pencerelerini kod içinden açabilmek için (menü çubuğu görünümü tarafından atanır).
    var openWindowAction: OpenWindowAction? {
        didSet {
            if let id = pendingWindow, openWindowAction != nil {
                pendingWindow = nil
                openWindow(id)
            }
        }
    }
    private var pendingWindow: String?

    private var cancellables: Set<AnyCancellable> = []
    private var didStart = false

    private init() {
        reloadKeys()
        wire()
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in AppState.shared.reloadKeys() }
        }
    }

    /// Anahtarları Keychain'den yeniden okur (başka bir pencerede/oturumda kaydedilmiş olabilir).
    func reloadKeys() {
        var keys: [AIProviderKind: String] = [:]
        for kind in AIProviderKind.allCases {
            if let key = Keychain.get(account: kind.keychainAccount) { keys[kind] = key }
        }
        if keys != apiKeys { apiKeys = keys }
    }

    /// Bellekte yoksa Keychain'e bir kez daha bakar.
    private func key(for kind: AIProviderKind) -> String? {
        if let key = apiKeys[kind] { return key }
        reloadKeys()
        return apiKeys[kind]
    }

    var hasKeyForCurrentProvider: Bool {
        settings.autoSelect ? !apiKeys.isEmpty : apiKeys[settings.provider] != nil
    }

    /// Yakın zamanda başarısız olan sağlayıcılar bu zamana kadar atlanır (otomatik modda).
    private var cooldownUntil: [AIProviderKind: Date] = [:]
    private static let cooldown: TimeInterval = 10 * 60

    /// Bu hata başka bir sağlayıcıyı denemeye değer mi? (anahtar, kredi, model, sunucu, ağ)
    private static func shouldTryNext(after error: Error) -> Bool {
        switch error {
        case let AIError.http(code, _): return [401, 402, 403, 404, 408, 429].contains(code) || code >= 500
        case AIError.invalidResponse, AIError.empty: return true
        case is URLError: return true
        default: return false
        }
    }

    /// Denenecek sağlayıcılar, sırasıyla.
    private func providerCandidates() -> [AIProviderKind] {
        let preferred = settings.provider
        guard settings.autoSelect else { return [preferred] }
        let ordered = [preferred] + AIProviderKind.allCases.filter { $0 != preferred }
        let withKeys = ordered.filter { key(for: $0) != nil }
        let now = Date()
        let ready = withKeys.filter { (cooldownUntil[$0] ?? .distantPast) <= now }
        // Hepsi beklemedeyse yine de hepsini dene.
        return ready.isEmpty ? withKeys : ready
    }

    // MARK: - Başlangıç

    /// Uygulama açılırken bir kez çağrılır.
    func start() {
        guard !didStart else { return }
        didStart = true

        speechIn.language = settings.speechLanguage
        speechIn.silenceSeconds = settings.silenceSeconds
        if settings.hotkeyEnabled { registerHotKey() }
        if settings.wakeWordEnabled { speechIn.setWakeEnabled(true) }

        if !settings.hasCompletedOnboarding || apiKeys.isEmpty {
            openWindow("settings")
        } else {
            openWindow("chat")
        }
    }

    private func wire() {
        speechIn.onCommand = { [weak self] text in
            guard let self else { return }
            Task { await self.send(text, viaVoice: true) }
        }
        speechIn.onBargeIn = { [weak self] in
            self?.speechOut.stop()
        }
        speechOut.onStart = { [weak self] text in
            self?.speechIn.speakingStarted(text: text)
        }
        speechOut.onFinish = { [weak self] in
            self?.speechIn.speakingFinished()
        }

        // Ayar değişikliklerini ses motoruna aktar (receive(on:) → değer atandıktan sonra çalışır).
        settings.$speechLanguage.dropFirst().receive(on: DispatchQueue.main)
            .sink { [weak self] value in self?.speechIn.setLanguage(value) }
            .store(in: &cancellables)
        settings.$wakeWordEnabled.dropFirst().receive(on: DispatchQueue.main)
            .sink { [weak self] value in self?.speechIn.setWakeEnabled(value) }
            .store(in: &cancellables)
        settings.$silenceSeconds.receive(on: DispatchQueue.main)
            .sink { [weak self] value in self?.speechIn.silenceSeconds = value }
            .store(in: &cancellables)
        settings.$hotkeyEnabled.dropFirst().receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                if value { self?.registerHotKey() } else { HotKey.shared.unregister() }
            }
            .store(in: &cancellables)
        settings.$readAloud.dropFirst().receive(on: DispatchQueue.main)
            .sink { [weak self] value in if !value { self?.speechOut.stop() } }
            .store(in: &cancellables)

        // İç nesnelerdeki değişiklikleri görünümlere ilet.
        for publisher in [speechIn.objectWillChange.eraseToAnyPublisher(),
                          speechOut.objectWillChange.eraseToAnyPublisher(),
                          store.objectWillChange.eraseToAnyPublisher(),
                          settings.objectWillChange.eraseToAnyPublisher()] {
            publisher.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        }
    }

    private func registerHotKey() {
        HotKey.shared.handler = { [weak self] in
            Task { @MainActor in self?.toggleListening() }
        }
        HotKey.shared.register()
    }

    // MARK: - Pencereler

    func openWindow(_ id: String) {
        NSApp.activate(ignoringOtherApps: true)
        if let action = openWindowAction {
            action(id: id)
        } else {
            pendingWindow = id
        }
    }

    // MARK: - Ses

    func toggleListening() {
        if speechIn.mode == .command {
            speechIn.finishCommand()
        } else {
            speechOut.stop()
            NSSound(named: "Tink")?.play()
            speechIn.startCommand()
        }
    }

    func stopSpeaking() {
        speechOut.stop()
    }

    func speak(_ text: String) {
        speechOut.speak(text, fallbackLanguage: settings.speechLanguage.languageCode)
    }

    // MARK: - API anahtarları

    func saveKey(_ key: String, for kind: AIProviderKind) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try Keychain.set(trimmed, account: kind.keychainAccount)
        apiKeys[kind] = trimmed
        settings.hasCompletedOnboarding = true
    }

    /// Ayarlarda göstermek için: "sk-ant-…KrJM"
    func maskedKey(for kind: AIProviderKind) -> String? {
        guard let key = apiKeys[kind] else { return nil }
        guard key.count > 12 else { return String(repeating: "•", count: key.count) }
        return "\(key.prefix(7))…\(key.suffix(4))"
    }

    /// Anahtarı sağlayıcıya küçük bir istekle dener (model listesini çeker).
    func testKey(for kind: AIProviderKind) async -> Result<Int, Error> {
        do {
            return .success(try await listModels(for: kind).count)
        } catch {
            return .failure(error)
        }
    }

    func deleteKey(for kind: AIProviderKind) {
        Keychain.delete(account: kind.keychainAccount)
        apiKeys[kind] = nil
    }

    func listModels(for kind: AIProviderKind) async throws -> [String] {
        guard let key = key(for: kind) else { throw AIError.http(401, L10n.t(.keyNotSet)) }
        return try await kind.makeClient().listModels(apiKey: key)
    }

    // MARK: - Sohbet

    func send(_ rawText: String, viaVoice: Bool = false) async {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let conversationID = store.ensureSelected()
        store.append(ChatMessage(role: .user, text: text, viaVoice: viaVoice), to: conversationID)

        let candidates = providerCandidates()
        guard !candidates.isEmpty, key(for: candidates[0]) != nil else {
            let provider = settings.provider
            store.append(ChatMessage(role: .assistant, text: "\(L10n.t(.noApiKey)): \(provider.displayName). \(L10n.t(.noApiKeyHint))", isError: true), to: conversationID)
            openWindow("settings")
            return
        }

        let turns: [ChatTurn] = (store.conversations.first { $0.id == conversationID }?.messages ?? [])
            .filter { !$0.isError }
            .map { ChatTurn(role: $0.role == .user ? .user : .assistant, text: $0.text) }

        isSending = true
        defer { isSending = false }

        let system = systemPrompt(viaVoice: viaVoice)
        var failures: [(AIProviderKind, String, Error)] = []

        for (index, provider) in candidates.enumerated() {
            guard let key = key(for: provider) else { continue }
            let model = settings.model(for: provider)
            do {
                let answer = try await provider.makeClient().complete(system: system, turns: turns, model: model, apiKey: key)
                cooldownUntil[provider] = nil
                store.append(ChatMessage(role: .assistant, text: answer, model: model), to: conversationID)
                if settings.readAloud { speak(answer) }
                return
            } catch {
                failures.append((provider, model, error))
                let isLast = index == candidates.count - 1
                if settings.autoSelect && Self.shouldTryNext(after: error) && !isLast {
                    cooldownUntil[provider] = Date().addingTimeInterval(Self.cooldown)
                    continue
                }
                break
            }
        }

        if failures.count == 1, let failure = failures.first {
            store.append(ChatMessage(role: .assistant, text: describe(failure.2), isError: true, model: failure.1), to: conversationID)
        } else {
            let lines = failures.map { "• \($0.0.displayName) (\($0.1)): \(describe($0.2))" }
            let text = L10n.t(.allProvidersFailed) + "\n\n" + lines.joined(separator: "\n\n")
            store.append(ChatMessage(role: .assistant, text: text, isError: true), to: conversationID)
        }
    }

    private func describe(_ error: Error) -> String {
        switch error {
        case AIError.refusal: return L10n.t(.refusal)
        case AIError.empty: return L10n.t(.emptyAnswer)
        case AIError.http(401, _), AIError.http(403, _):
            return "\(L10n.t(.errorPrefix)): \(error.localizedDescription)\n\n\(L10n.t(.hintInvalidKey))"
        case AIError.http(404, _):
            return "\(L10n.t(.errorPrefix)): \(error.localizedDescription)\n\n\(L10n.t(.hintModelNotFound))"
        case AIError.http(402, _), AIError.http(429, _):
            return "\(L10n.t(.errorPrefix)): \(error.localizedDescription)\n\n\(L10n.t(.hintBilling))"
        default: return "\(L10n.t(.errorPrefix)): \(error.localizedDescription)"
        }
    }

    private func systemPrompt(viaVoice: Bool) -> String {
        var prompt = """
        You are "Mac Asistan", a friendly and helpful personal assistant running on the user's Mac.

        Language rule (most important): always reply in the same language the user used in their most recent message. \
        The user mostly writes or speaks Turkish, German or English and may switch between them at any time; \
        switch with them. Never answer in a different language than the user's latest message unless they explicitly ask you to. \
        If the language of the latest message is unclear (e.g. only a name or a number), use \(settings.uiLanguage.englishName).

        Be clear and concise. Today's date is \(Self.dateFormatter.string(from: Date())).
        """
        if viaVoice || settings.readAloud {
            prompt += """


            Your answer may be read aloud by a text-to-speech voice, so prefer short, natural spoken sentences. \
            Avoid tables, long lists and code blocks unless the user explicitly asks for them.
            """
        }
        if viaVoice {
            prompt += """

            The user's latest message was dictated by voice; speech recognition may contain small errors, so interpret it sensibly.
            """
        }
        return prompt
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd (EEEE)"
        return formatter
    }()
}
