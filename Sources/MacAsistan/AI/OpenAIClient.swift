import Foundation

/// OpenAI Chat Completions API. Aynı API'yi sunan diğer servisler için de kullanılır (farklı `base` ile).
struct OpenAIClient: AIClient {
    var base = URL(string: "https://api.openai.com/v1")!
    /// Yalnızca OpenAI için: model listesinden ses/görsel vb. modelleri ele.
    var filterOpenAIModels = true

    private func headers(_ apiKey: String) -> [String: String] {
        apiKey.isEmpty ? [:] : ["Authorization": "Bearer \(apiKey)"]
    }

    func complete(system: String, turns: [ChatTurn], model: String, apiKey: String) async throws -> String {
        var messages: [[String: Any]] = [["role": "system", "content": system]]
        messages += turns.normalizedForAPI().map {
            ["role": $0.role == .user ? "user" : "assistant", "content": $0.text]
        }
        let body: [String: Any] = ["model": model, "messages": messages]
        let json = try await HTTP.send("POST", url: base.appendingPathComponent("chat/completions"), headers: headers(apiKey), body: body)

        guard let choices = json["choices"] as? [[String: Any]], let first = choices.first,
              let message = first["message"] as? [String: Any] else { throw AIError.invalidResponse }
        if let refusal = message["refusal"] as? String, !refusal.isEmpty { return refusal }
        let text = (message["content"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { throw AIError.empty }
        return text
    }

    func listModels(apiKey: String) async throws -> [String] {
        let json = try await HTTP.send("GET", url: base.appendingPathComponent("models"), headers: headers(apiKey))
        let data = json["data"] as? [[String: Any]] ?? []
        guard filterOpenAIModels else { return data.compactMap { $0["id"] as? String }.sorted() }
        let excluded = ["audio", "realtime", "tts", "transcribe", "image", "embedding", "moderation", "search", "whisper", "dall-e"]
        return data.compactMap { $0["id"] as? String }
            .filter { id in
                (id.hasPrefix("gpt") || id.hasPrefix("o1") || id.hasPrefix("o3") || id.hasPrefix("o4") || id.hasPrefix("chatgpt"))
                    && !excluded.contains(where: { id.contains($0) })
            }
            .sorted()
    }
}
