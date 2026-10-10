import Foundation

/// Kaynaklı cevaptaki doğrulanmış bir referans. Başlık, sayfa ve bağlantı her zaman
/// bilgi bankasından gelir; yapay zekâ yalnızca hangi pasajı kullandığını ve alıntıyı verir.
struct CitedSource: Codable, Equatable, Identifiable {
    var id = UUID()
    var number: Int
    var docID: UUID
    var citation: String
    var page: Int
    var section: String?
    var link: String?
    var isPDF: Bool
    var quote: String?
    var verified: Bool

    var locationText: String {
        var parts: [String] = []
        if page > 0 { parts.append("S. \(page)") }
        if let section, !section.isEmpty { parts.append(section) }
        return parts.joined(separator: " · ")
    }
}

/// Kaynak görüntüleyici penceresi için hedef.
struct SourceTarget: Codable, Hashable {
    var docID: UUID
    var page: Int
    var quote: String?
}

/// Strahlentherapie-Fachmodus: RETRIEVE → VERIFY → ANSWER → CITE
enum Evidence {
    static let marker = "BELEGE:"

    static func notFound(for language: String) -> String {
        switch language {
        case "tr": return "Bu konu hakkında yüklediğiniz kaynaklarda yeterli bilgi bulunamadı."
        case "en": return "Not enough information on this topic was found in your uploaded sources."
        default: return "Zu dieser Frage wurden in Ihren hochgeladenen Quellen keine ausreichenden Informationen gefunden."
        }
    }

    static func isNotFound(_ text: String) -> Bool {
        ["tr", "de", "en"].contains { text.contains(notFound(for: $0)) }
    }

    // MARK: - 1. Arama sorgusu

    static let queryPrompt = """
    You convert a radiation oncologist's question into keyword queries for a full-text (BM25) search over \
    radiation oncology literature written mostly in German and English (guidelines, trials, textbooks, protocols).
    Output ONLY a JSON object: {"queries": ["…", "…"]} with 4–8 short keyword queries.
    Include: German medical terms (also split compound words, e.g. "Hirnmetastasen" → "Hirnmetastasen Metastasen Gehirn"), \
    English terms, common abbreviations (SRS, FSRT, SBRT, IMRT, WBRT, EQD2, BED, PTV, CTV, GTV, OAR names), \
    tumour entity, treatment setting and dose units (Gy, Fraktionen) when relevant.
    If the question is a follow-up, resolve it using the conversation. Do not answer the question.
    """

    static func parseQueries(_ text: String) -> [String] {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end,
              let data = String(text[start...end]).data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let queries = json["queries"] as? [String] else { return [] }
        return queries.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    // MARK: - 2. Cevap talimatı

    static func systemPrompt(hits: [KBHit], uiLanguage: AppLanguage) -> String {
        var passages = ""
        var budget = 18_000
        for (i, hit) in hits.enumerated() {
            let doc = hit.document
            var header = "[S\(i + 1)] Document: \(doc.citationLine)"
            if hit.chunk.page > 0 { header += " | Page \(hit.chunk.page)" }
            if let section = hit.chunk.section { header += " | Section: \(section)" }
            let text = String(hit.chunk.text.prefix(budget))
            budget -= text.count
            passages += "\(header)\n\(text)\n---\n"
            if budget <= 0 { break }
        }

        return """
        You are a specialised clinical knowledge assistant for a board-certified radiation oncologist (Facharzt für Strahlentherapie). \
        This is professional clinical decision support; you do not prescribe or authorise treatment.

        STRICT SOURCE RULE (highest priority):
        - Use ONLY information explicitly contained in the SOURCE PASSAGES below. They were retrieved from the user's own approved literature database.
        - Do NOT use general medical knowledge, memory, internet knowledge or assumptions, even if you are confident.
        - Never invent references, guideline recommendations, trial results, radiation doses, fractionations or dose constraints.
        - If the passages do not directly support an answer, reply with exactly this sentence and nothing else: \
        "\(notFound(for: "de"))" (Turkish question: "\(notFound(for: "tr"))"; English question: "\(notFound(for: "en"))").

        DOSE AND FRACTIONATION SAFETY:
        - Copy numbers and units exactly. Verify the fractionation schedule (dose per fraction × number of fractions).
        - Distinguish physical dose, BED and EQD2 and give the alpha/beta ratio when the source does.
        - Never substitute one dose-volume parameter for another (Dmax, D0.03cc, D0.1cc, D1cc, D2cc, Dmean, V20Gy …).
        - Distinguish conventional from stereotactic treatment; label re-irradiation recommendations explicitly.
        - Do not extrapolate constraints across fractionation schedules.

        CONFLICTS AND PRIORITY:
        - If passages disagree, state the discrepancy, name the sources and the relevant differences (population, technique, date). Do not invent a consensus.
        - Prefer the most directly applicable source, then current guidelines, consensus statements, randomised trials, other studies, textbooks/institutional protocols. \
        A newer publication does not automatically override an institutional protocol.

        PATIENT-SPECIFIC QUESTIONS: if critical information is missing to interpret the evidence, ask only for that information. Never invent patient characteristics.

        LANGUAGE: answer in German by default. If the user's latest question is in Turkish, answer in Turkish; if it is in English, answer in English. \
        (Interface language: \(uiLanguage.englishName).) Be concise and clinical, no introductions.

        OUTPUT FORMAT (follow exactly):
        Klinische Antwort   (Turkish: "Klinik Yanıt", English: "Clinical answer")
        2–5 sentences answering only what was asked. Put source markers like [S2] or [S1][S3] after every factual statement.

        \(marker)
        [S2] "verbatim quote copied character-for-character from passage S2 that supports the statement"
        [S3] "…"

        Rules for the \(marker) section: one line per passage you used; the quote must be an exact, contiguous copy from that passage \
        in its original language (no translation, no paraphrase, no omissions, max. 40 words); only use markers of the passages below. \
        Do NOT write a reference list, titles, page numbers, URLs or DOIs yourself — the app adds verified references automatically.
        If you answer with the "not found" sentence, omit the \(marker) section.

        SOURCE PASSAGES:
        \(passages)
        """
    }

    // MARK: - 3. Doğrulama

    /// Akış sırasında ekranda gösterilecek kısım (BELEGE bölümü gizlenir).
    static func visibleText(_ raw: String) -> String {
        guard let range = raw.range(of: marker) else {
            // Belirteç henüz yarım gelmiş olabilir ("BELE…").
            if let partial = raw.range(of: "\nBELE", options: .backwards), raw.distance(from: partial.lowerBound, to: raw.endIndex) < 9 {
                return String(raw[..<partial.lowerBound])
            }
            return raw
        }
        return String(raw[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Cevabı ve doğrulanmış kaynak listesini çıkarır.
    static func finalize(raw: String, hits: [KBHit]) -> (answer: String, sources: [CitedSource]) {
        var answer = visibleText(raw)
        if isNotFound(answer) { return (answer, []) }

        // Alıntılar
        var quotes: [Int: String] = [:]
        if let range = raw.range(of: marker) {
            let section = raw[range.upperBound...]
            let regex = try? NSRegularExpression(pattern: "\\[S(\\d+)\\]\\s*[–:-]?\\s*[\"„“”«'](.+)[\"“”»']\\s*$", options: [.anchorsMatchLines])
            let text = String(section)
            for match in regex?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? [] {
                guard let n = Range(match.range(at: 1), in: text).flatMap({ Int(text[$0]) }),
                      let q = Range(match.range(at: 2), in: text) else { continue }
                if quotes[n] == nil { quotes[n] = String(text[q]) }
            }
        }

        // Cevaptaki işaretler, ilk geçiş sırasına göre 1, 2, 3 … olarak numaralanır.
        let markerRegex = try! NSRegularExpression(pattern: "\\[S(\\d+)\\]")
        var order: [Int] = []
        for match in markerRegex.matches(in: answer, range: NSRange(answer.startIndex..., in: answer)) {
            if let r = Range(match.range(at: 1), in: answer), let n = Int(answer[r]), !order.contains(n) { order.append(n) }
        }
        for n in quotes.keys.sorted() where !order.contains(n) { order.append(n) }
        let valid = order.filter { $0 >= 1 && $0 <= hits.count }
        var numbering: [Int: Int] = [:]
        for (i, n) in valid.enumerated() { numbering[n] = i + 1 }

        // [S3] → [1]; var olmayan pasaj işaretleri → [?]
        let ns = answer as NSString
        var result = ""
        var last = 0
        for match in markerRegex.matches(in: answer, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            let n = Int(ns.substring(with: match.range(at: 1))) ?? 0
            result += numbering[n].map { "[\($0)]" } ?? "[?]"
            last = match.range.location + match.range.length
        }
        result += ns.substring(from: last)
        answer = result

        let sources: [CitedSource] = valid.map { n in
            let hit = hits[n - 1]
            let quote = quotes[n]
            let doc = hit.document
            return CitedSource(
                number: numbering[n] ?? 0,
                docID: doc.id,
                citation: doc.citationLine,
                page: hit.chunk.page,
                section: hit.chunk.section,
                link: doc.linkURL?.absoluteString,
                isPDF: doc.storedFileName != nil,
                quote: quote,
                verified: quote.map { verify($0, in: hit.chunk.text) } ?? false
            )
        }
        return (answer, sources)
    }

    /// Alıntı, pasaj metninde gerçekten geçiyor mu?
    static func verify(_ quote: String, in passage: String) -> Bool {
        let haystack = normalize(passage)
        let parts = quote.components(separatedBy: CharacterSet(charactersIn: "…")).flatMap { $0.components(separatedBy: "...") }
            .map(normalize)
            .filter { $0.split(separator: " ").count >= 3 }
        guard !parts.isEmpty else { return false }
        return parts.allSatisfy { haystack.contains($0) }
    }

    static func normalize(_ text: String) -> String {
        var t = text.lowercased()
            .replacingOccurrences(of: "-\n", with: "")
            .replacingOccurrences(of: "\u{00AD}", with: "")
        for (a, b) in [("„", "\""), ("“", "\""), ("”", "\""), ("‘", "'"), ("’", "'"), ("–", "-"), ("—", "-"), ("\u{00A0}", " ")] {
            t = t.replacingOccurrences(of: a, with: b)
        }
        t = t.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return t.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ".,;:\"'")))
    }
}
