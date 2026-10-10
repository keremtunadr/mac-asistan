import Foundation

/// Basit BM25 tam metin araması (yerel, internetsiz).
struct BM25Index {
    struct Result {
        let chunk: KBChunk
        let score: Double
    }

    let documentIDs: Set<UUID>
    private let chunks: [KBChunk]
    private let termFrequencies: [[String: Int]]
    private let lengths: [Int]
    private let documentFrequency: [String: Int]
    private let averageLength: Double

    init(chunks: [KBChunk], documentIDs: Set<UUID>) {
        self.chunks = chunks
        self.documentIDs = documentIDs
        var tfs: [[String: Int]] = []
        var lengths: [Int] = []
        var df: [String: Int] = [:]
        tfs.reserveCapacity(chunks.count)
        for chunk in chunks {
            let tokens = Self.tokenize(chunk.text + " " + (chunk.section ?? ""))
            var tf: [String: Int] = [:]
            for token in tokens { tf[token, default: 0] += 1 }
            for token in tf.keys { df[token, default: 0] += 1 }
            tfs.append(tf)
            lengths.append(tokens.count)
        }
        termFrequencies = tfs
        self.lengths = lengths
        documentFrequency = df
        averageLength = lengths.isEmpty ? 1 : Double(lengths.reduce(0, +)) / Double(lengths.count)
    }

    func search(_ queries: [String], limit: Int) -> [Result] {
        let terms = Set(queries.flatMap(Self.tokenize))
        guard !terms.isEmpty, !chunks.isEmpty else { return [] }
        let n = Double(chunks.count)
        let k1 = 1.4, b = 0.75
        var scores: [(Int, Double, Int)] = []
        for (i, tf) in termFrequencies.enumerated() {
            var score = 0.0
            var matched = 0
            for term in terms {
                guard let f = tf[term] else { continue }
                matched += 1
                let df = Double(documentFrequency[term] ?? 0)
                let idf = log(1 + (n - df + 0.5) / (df + 0.5))
                let freq = Double(f)
                score += idf * freq * (k1 + 1) / (freq + k1 * (1 - b + b * Double(lengths[i]) / averageLength))
            }
            if matched > 0 { scores.append((i, score, matched)) }
        }
        // Çok terim eşleşen parçaları öne al.
        scores.sort { ($0.1 * (1 + 0.15 * Double($0.2))) > ($1.1 * (1 + 0.15 * Double($1.2))) }
        return scores.prefix(limit).map { Result(chunk: chunks[$0.0], score: $0.1) }
    }

    private static let stopwords: Set<String> = [
        // de
        "der", "die", "das", "und", "oder", "mit", "bei", "fur", "von", "den", "dem", "des", "ein", "eine", "einer", "ist", "sind",
        "wird", "werden", "im", "in", "zu", "zur", "zum", "auf", "als", "nach", "wie", "was", "welche", "nicht", "auch", "an", "es",
        // en
        "the", "and", "or", "of", "for", "with", "in", "on", "to", "is", "are", "be", "by", "at", "as", "an", "what", "which", "how",
        // tr
        "ve", "veya", "ile", "bir", "bu", "su", "icin", "mi", "mu", "ne", "nedir", "nasil", "hangi", "olan", "da", "de", "ki",
    ]

    static func tokenize(_ text: String) -> [String] {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return folded
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { token in
                guard !token.isEmpty else { return false }
                if token.allSatisfy(\.isNumber) { return true }
                return token.count >= 2 && !stopwords.contains(token)
            }
    }
}
