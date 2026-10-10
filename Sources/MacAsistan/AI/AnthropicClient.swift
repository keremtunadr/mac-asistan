import Foundation

/// Anthropic Messages API (https://api.anthropic.com/v1/messages), akış (streaming) ile.
struct AnthropicClient: AIClient {
    private let base = URL(string: "https://api.anthropic.com/v1")!

    /// Sunucu tarafı yedek model (refusal fallback) destekleyen modeller.
    private static let fallbackModels: Set<String> = ["claude-fable-5-1", "claude-opus-5-5", "claude-opus-5", "claude-sonnet-5-5"]

    private func headers(_ apiKey: String) -> [String: String] {
        ["x-api-key": apiKey, "anthropic-version": "2023-06-01"]
    }

    /// `output_config.effort` destekleyen modeller (Claude 4.6 ve sonrası; Haiku 4.5 hariç).
    private static func supportsEffort(_ model: String) -> Bool {
        let families = ["claude-opus-5", "claude-sonnet-5", "claude-haiku-5", "claude-fable-5", "claude-mythos-5",
                        "claude-opus-4-6", "claude-opus-4-7", "claude-opus-4-8", "claude-sonnet-4-6"]
        return families.contains { model.hasPrefix($0) }
    }

    func stream(system: String, turns: [ChatTurn], model: String, apiKey: String, speed: ResponseSpeed,
                onText: @escaping @Sendable (String) async -> Void) async throws -> String {
        let messages: [[String: Any]] = turns.normalizedForAPI().map {
            ["role": $0.role == .user ? "user" : "assistant", "content": $0.text]
        }
        var body: [String: Any] = [
            "model": model,
            "max_tokens": 16000,
            "system": system,
            "messages": messages,
            "stream": true,
        ]
        var hdrs = headers(apiKey)
        if Self.fallbackModels.contains(model) {
            body["fallbacks"] = "default"
            hdrs["anthropic-beta"] = "server-side-fallback-2026-07-01"
        }
        if Self.supportsEffort(model) {
            body["output_config"] = ["effort": speed.effort]
        }

        do {
            return try await run(body: body, headers: hdrs, onText: onText)
        } catch AIError.http(400, let message) {
            // Bu hesapta/modelde desteklenmeyen isteğe bağlı alanları çıkarıp bir kez daha dene.
            let lower = message.lowercased()
            var retried = false
            if lower.contains("fallback") || lower.contains("beta") {
                body.removeValue(forKey: "fallbacks")
                hdrs.removeValue(forKey: "anthropic-beta")
                retried = true
            }
            if lower.contains("effort") || lower.contains("output_config") {
                body.removeValue(forKey: "output_config")
                retried = true
            }
            guard retried else { throw AIError.http(400, message) }
            return try await run(body: body, headers: hdrs, onText: onText)
        }
    }

    private func run(body: [String: Any], headers: [String: String],
                     onText: @escaping @Sendable (String) async -> Void) async throws -> String {
        var text = ""
        var stopReason: String?
        try await HTTP.streamEvents(url: base.appendingPathComponent("messages"), headers: headers, body: body) { event in
            switch event["type"] as? String {
            case "content_block_delta":
                if let delta = event["delta"] as? [String: Any],
                   (delta["type"] as? String) == "text_delta",
                   let piece = delta["text"] as? String {
                    text += piece
                    await onText(text)
                }
            case "message_delta":
                if let reason = (event["delta"] as? [String: Any])?["stop_reason"] as? String { stopReason = reason }
            default:
                break
            }
        }
        let final = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if final.isEmpty {
            if stopReason == "refusal" { throw AIError.refusal }
            throw AIError.empty
        }
        return final
    }

    func listModels(apiKey: String) async throws -> [String] {
        var components = URLComponents(url: base.appendingPathComponent("models"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "limit", value: "100")]
        let json = try await HTTP.send("GET", url: components.url!, headers: headers(apiKey))
        let data = json["data"] as? [[String: Any]] ?? []
        return data.compactMap { $0["id"] as? String }
    }
}
