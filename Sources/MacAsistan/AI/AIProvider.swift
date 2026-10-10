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
        case .gemini: return "gemini-2.5-flash"
        }
    }

    /// Hazır öneriler. "Modelleri yükle" ile sağlayıcının güncel listesi de çekilebilir.
    var suggestedModels: [String] {
        switch self {
        case .anthropic: return ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5", "claude-fable-5-1"]
        case .openai: return ["gpt-5", "gpt-5-mini", "gpt-4.1", "gpt-4o"]
        case .gemini: return ["gemini-2.5-pro", "gemini-2.5-flash", "gemini-2.5-flash-lite"]
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
