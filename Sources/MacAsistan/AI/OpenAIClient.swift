import Foundation

/// OpenAI Chat Completions API. Aynı API'yi sunan diğer servisler için de kullanılır (farklı `base` ile).
struct OpenAIClient: AIClient {
    var base = URL(string: "https://api.openai.com/v1")!
    /// Yalnızca OpenAI için: model listesinden ses/görsel vb. modelleri ele.
    var filterOpenAIModels = true

    private func headers(_ apiKey: String) -> [String: String] {
        apiKey.isEmpty ? [:] : ["Authorization": "Bearer \(apiKey)"]
    }

    func stream(system: String, turns: [ChatTurn], model: String, apiKey: String, speed: ResponseSpeed,
                onText: @escaping @Sendable (String) async -> Void) async throws -> String {
        var messages: [[String: Any]] = [["role": "system", "content": system]]
        messages += turns.normalizedForAPI().map {
            ["role": $0.role == .user ? "user" : "assistant", "content": $0.text]
        }
        var body: [String: Any] = ["model": model, "messages": messages, "stream": true]
        // Yalnızca OpenAI'ın akıl yürüten modellerinde (gpt-5, o-serisi) düşünme süresini ayarla.
        let isReasoningModel = model.hasPrefix("gpt-5") || model.hasPrefix("o1") || model.hasPrefix("o3") || model.hasPrefix("o4")
        if filterOpenAIModels && isReasoningModel {
            body["reasoning_effort"] = speed.effort
        }

        var text = ""
        var refusal = ""
        try await HTTP.streamEvents(url: base.appendingPathComponent("chat/completions"), headers: headers(apiKey), body: body) { event in
            guard let choices = event["choices"] as? [[String: Any]], let delta = choices.first?["delta"] as? [String: Any] else { return }
            if let piece = delta["content"] as? String, !piece.isEmpty {
                text += piece
                await onText(text)
            }
            if let piece = delta["refusal"] as? String { refusal += piece }
        }
        let final = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if final.isEmpty {
            if !refusal.isEmpty { return refusal }
            throw AIError.empty
        }
        return final
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
