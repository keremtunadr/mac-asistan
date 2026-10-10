import Foundation

enum AIProviderKind: String, CaseIterable, Identifiable, Codable {
    case anthropic, openai, gemini

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .anthropic: return "Anthropic Claude"
        case .openai: return "OpenAI"
        case .gemini: return "Google Gemini"
        }
    }

    var defaultModel: String {
        switch self {
        case .anthropic: return "claude-opus-5-5"
        case .openai: return "gpt-5"
        case .gemini: return "gemini-3.8-flash"
        }
    }

    /// Hazır öneriler. "Modelleri yükle" ile sağlayıcının güncel listesi de çekilebilir.
    var suggestedModels: [String] {
        switch self {
        case .anthropic: return ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5", "claude-fable-5-1"]
        case .openai: return ["gpt-5", "gpt-5-mini", "gpt-4.1", "gpt-4o"]
        case .gemini: return ["gemini-3.8-flash"]
        }
    }

    /// Gerçek anahtarların başladığı ön ek (yanlış metin yapıştırılmasını fark etmek için).
    var keyPrefix: String {
        switch self {
        case .anthropic: return "sk-ant-"
        case .openai: return "sk-"
        case .gemini: return "AIza"
        }
    }

    /// Artık kullanılamayan eski varsayılan modeller → yenisiyle değiştirilir.
    var retiredDefaults: Set<String> {
        switch self {
        case .gemini: return ["gemini-2.5-flash"]
        default: return []
        }
    }

    /// Keychain hesap adı
    var keychainAccount: String { rawValue }

    var keyHelpURL: URL {
        switch self {
        case .anthropic: return URL(string: "https://console.anthropic.com/settings/keys")!
        case .openai: return URL(string: "https://platform.openai.com/api-keys")!
        case .gemini: return URL(string: "https://aistudio.google.com/app/apikey")!
        }
    }

    func makeClient() -> AIClient {
        switch self {
        case .anthropic: return AnthropicClient()
        case .openai: return OpenAIClient()
        case .gemini: return GeminiClient()
        }
    }
}

struct ChatTurn {
    enum Role { case user, assistant }
    let role: Role
    let text: String
}

protocol AIClient {
    func complete(system: String, turns: [ChatTurn], model: String, apiKey: String) async throws -> String
    func listModels(apiKey: String) async throws -> [String]
}

enum AIError: LocalizedError {
    case http(Int, String)
    case invalidResponse
    case refusal
    case empty

    var errorDescription: String? {
        switch self {
        case let .http(code, message): return "HTTP \(code): \(message)"
        case .invalidResponse: return "Invalid response from server."
        case .refusal: return "refusal"
        case .empty: return "empty"
        }
    }
}

/// Basit JSON HTTP yardımcıları.
enum HTTP {
    static func send(_ method: String, url: URL, headers: [String: String], body: [String: Any]? = nil) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 300
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIError.invalidResponse }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard (200..<300).contains(http.statusCode) else {
            throw AIError.http(http.statusCode, errorMessage(json) ?? String(decoding: data.prefix(500), as: UTF8.self))
        }
        guard let json else { throw AIError.invalidResponse }
        return json
    }

    private static func errorMessage(_ json: [String: Any]?) -> String? {
        guard let json else { return nil }
        if let error = json["error"] as? [String: Any], let message = error["message"] as? String { return message }
        if let message = json["message"] as? String { return message }
        return nil
    }
}

extension Array where Element == ChatTurn {
    /// Sağlayıcıların çoğu kullanıcı/asistan sırasının dönüşümlü olmasını ve ilk mesajın kullanıcıdan gelmesini ister.
    /// Ardışık aynı roldeki mesajları birleştirir, baştaki asistan mesajlarını atar.
    func normalizedForAPI() -> [ChatTurn] {
        var result: [ChatTurn] = []
        for turn in self where !turn.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if result.isEmpty && turn.role == .assistant { continue }
            if let last = result.last, last.role == turn.role {
                result[result.count - 1] = ChatTurn(role: turn.role, text: last.text + "\n\n" + turn.text)
            } else {
                result.append(turn)
            }
        }
        return result
    }
}

// MARK: - Kullanıcının eklediği sağlayıcılar

/// Bir sağlayıcıya referans: yerleşik (Claude, OpenAI, Gemini) veya kullanıcının eklediği.
enum ProviderRef: Hashable {
    case builtin(AIProviderKind)
    case custom(UUID)

    init?(rawValue: String) {
        if let kind = AIProviderKind(rawValue: rawValue) {
            self = .builtin(kind)
        } else if rawValue.hasPrefix("custom:"), let id = UUID(uuidString: String(rawValue.dropFirst("custom:".count))) {
            self = .custom(id)
        } else {
            return nil
        }
    }

    var rawValue: String {
        switch self {
        case let .builtin(kind): return kind.rawValue
        case let .custom(id): return "custom:\(id.uuidString)"
        }
    }

    var keychainAccount: String {
        switch self {
        case let .builtin(kind): return kind.keychainAccount
        case let .custom(id): return "custom.\(id.uuidString)"
        }
    }
}

/// OpenAI uyumlu (Chat Completions) API sunan herhangi bir servis:
/// DeepSeek, Mistral, Groq, xAI, OpenRouter, Perplexity, Ollama, LM Studio …
struct CustomProvider: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var baseURL: String
    var model: String
    var requiresKey = true
    var keyHelpURL: String?

    var ref: ProviderRef { .custom(id) }

    /// Hazır şablonlar. Model adları değişebilir; "Modelleri yükle" ile güncel liste alınabilir.
    static let presets: [CustomProvider] = [
        CustomProvider(name: "DeepSeek", baseURL: "https://api.deepseek.com/v1", model: "deepseek-chat",
                       keyHelpURL: "https://platform.deepseek.com/api_keys"),
        CustomProvider(name: "Mistral", baseURL: "https://api.mistral.ai/v1", model: "mistral-large-latest",
                       keyHelpURL: "https://console.mistral.ai/api-keys"),
        CustomProvider(name: "Groq", baseURL: "https://api.groq.com/openai/v1", model: "llama-3.3-70b-versatile",
                       keyHelpURL: "https://console.groq.com/keys"),
        CustomProvider(name: "xAI Grok", baseURL: "https://api.x.ai/v1", model: "grok-4",
                       keyHelpURL: "https://console.x.ai"),
        CustomProvider(name: "OpenRouter", baseURL: "https://openrouter.ai/api/v1", model: "openrouter/auto",
                       keyHelpURL: "https://openrouter.ai/keys"),
        CustomProvider(name: "Perplexity", baseURL: "https://api.perplexity.ai", model: "sonar",
                       keyHelpURL: "https://www.perplexity.ai/settings/api"),
        CustomProvider(name: "Ollama (yerel)", baseURL: "http://localhost:11434/v1", model: "llama3.2",
                       requiresKey: false, keyHelpURL: "https://ollama.com/download"),
        CustomProvider(name: "LM Studio (yerel)", baseURL: "http://localhost:1234/v1", model: "local-model",
                       requiresKey: false, keyHelpURL: "https://lmstudio.ai"),
    ]
}
