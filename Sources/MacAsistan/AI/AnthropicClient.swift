import Foundation

/// Anthropic Messages API (https://api.anthropic.com/v1/messages)
struct AnthropicClient: AIClient {
    private let base = URL(string: "https://api.anthropic.com/v1")!

    /// Sunucu tarafı yedek model (refusal fallback) destekleyen modeller.
    private static let fallbackModels: Set<String> = ["claude-fable-5-1", "claude-opus-5-5", "claude-opus-5", "claude-sonnet-5-5"]

    private func headers(_ apiKey: String) -> [String: String] {
        ["x-api-key": apiKey, "anthropic-version": "2023-06-01"]
    }

    func complete(system: String, turns: [ChatTurn], model: String, apiKey: String) async throws -> String {
        let messages: [[String: Any]] = turns.normalizedForAPI().map {
            ["role": $0.role == .user ? "user" : "assistant", "content": $0.text]
        }
        var body: [String: Any] = [
            "model": model,
            "max_tokens": 16000,
            "system": system,
            "messages": messages,
        ]
        var hdrs = headers(apiKey)
        let useFallback = Self.fallbackModels.contains(model)
        if useFallback {
            body["fallbacks"] = "default"
            hdrs["anthropic-beta"] = "server-side-fallback-2026-07-01"
        }

        let json: [String: Any]
        do {
            json = try await HTTP.send("POST", url: base.appendingPathComponent("messages"), headers: hdrs, body: body)
        } catch AIError.http(400, let message) where useFallback && message.lowercased().contains("fallback") {
            // Yedek model özelliği bu hesapta kullanılamıyorsa onsuz tekrar dene.
            body.removeValue(forKey: "fallbacks")
            json = try await HTTP.send("POST", url: base.appendingPathComponent("messages"), headers: headers(apiKey), body: body)
        }

        let content = json["content"] as? [[String: Any]] ?? []
        let text = content
            .filter { ($0["type"] as? String) == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if text.isEmpty {
            if (json["stop_reason"] as? String) == "refusal" { throw AIError.refusal }
            throw AIError.empty
        }
        return text
    }

    func listModels(apiKey: String) async throws -> [String] {
        var components = URLComponents(url: base.appendingPathComponent("models"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "limit", value: "100")]
        let json = try await HTTP.send("GET", url: components.url!, headers: headers(apiKey))
        let data = json["data"] as? [[String: Any]] ?? []
        return data.compactMap { $0["id"] as? String }
    }
}
