import Foundation

/// "Hey AI" uyandırma ifadesini Türkçe, Almanca ve İngilizce transkriptlerde bulur.
/// Konuşma tanıma "AI"yı dile göre farklı yazabilir: "AI", "A.I.", "ay", "ei", "eyay", "KI" (Almanca) …
enum WakeWord {
    private static let regex: NSRegularExpression = {
        let sep = "[\\s\\p{P}]*"
        let variants = [
            "a\(sep)i", "ay", "ai", "e\(sep)i", "eye", "ey\(sep)ay", "ey\(sep)ai", "k\(sep)i", "aj", "ej",
        ]
        let pattern = "\\b(?:(?:hey|hei|hay|hej|heyy)\(sep)(?:\(variants.joined(separator: "|")))|heyai|heyay|heyei|heyeyay)\\b"
        return try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }()

    /// Uyandırma ifadesi bulunursa, ifadeden SONRA gelen metni döndürür (boş olabilir).
    /// Bulunamazsa nil döner.
    static func match(in text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        guard let found = regex.firstMatch(in: text, range: range),
              let swiftRange = Range(found.range, in: text) else { return nil }
        let remainder = text[swiftRange.upperBound...]
        return remainder.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
    }
}
