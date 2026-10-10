import Foundation

/// Google Gemini API (generativelanguage.googleapis.com)
struct GeminiClient: AIClient {
    private let base = URL(string: "https://generativelanguage.googleapis.com/v1beta")!

    private func headers(_ apiKey: String) -> [String: String] {
        ["x-goog-api-key": apiKey]
    }

    func complete(system: String, turns: [ChatTurn], model: String, apiKey: String) async throws -> String {
        let modelID = model.hasPrefix("models/") ? String(model.dropFirst("models/".count)) : model
        let contents: [[String: Any]] = turns.normalizedForAPI().map {
            ["role": $0.role == .user ? "user" : "model", "parts": [["text": $0.text]]]
        }
        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": system]]],
            "contents": contents,
        ]
        guard let url = URL(string: "\(base.absoluteString)/models/\(modelID):generateContent") else { throw AIError.invalidResponse }
        let json = try await HTTP.send("POST", url: url, headers: headers(apiKey), body: body)

        if let feedback = json["promptFeedback"] as? [String: Any], feedback["blockReason"] != nil {
            throw AIError.refusal
        }
        let candidates = json["candidates"] as? [[String: Any]] ?? []
        let parts = (candidates.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]] ?? []
        let text = parts
            .filter { ($0["thought"] as? Bool) != true }
            .compactMap { $0["text"] as? String }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            if (candidates.first?["finishReason"] as? String) == "SAFETY" { throw AIError.refusal }
            throw AIError.empty
        }
        return text
    }

    func listModels(apiKey: String) async throws -> [String] {
        var components = URLComponents(url: base.appendingPathComponent("models"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "pageSize", value: "200")]
        let json = try await HTTP.send("GET", url: components.url!, headers: headers(apiKey))
        let models = json["models"] as? [[String: Any]] ?? []
        return models
            .filter { ($0["supportedGenerationMethods"] as? [String] ?? []).contains("generateContent") }
            .compactMap { $0["name"] as? String }
            .map { $0.hasPrefix("models/") ? String($0.dropFirst("models/".count)) : $0 }
            .filter { $0.hasPrefix("gemini") }
            .sorted()
    }
}
