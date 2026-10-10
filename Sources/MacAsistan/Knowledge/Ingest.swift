import AppKit
import Foundation
import PDFKit
import Vision

/// Belgeleri okuyup aranabilir parçalara böler: PDF (gerekirse OCR), web sayfası, DOI.
enum Ingest {
    struct Result: Sendable {
        var title: String?
        var authors: String?
        var year: String?
        var finalURL: String?
        var storedFileName: String?
        var pageCount = 0
        var ocrPages = 0
        var chunks: [KBChunk] = []
    }

    enum IngestError: LocalizedError {
        case cannotOpenPDF, download(String)
        var errorDescription: String? {
            switch self {
            case .cannotOpenPDF: return "PDF could not be opened."
            case let .download(message): return message
            }
        }
    }

    // MARK: - PDF

    static func pdf(at url: URL, docID: UUID) async throws -> Result {
        try await Task.detached(priority: .utility) {
            guard let pdf = PDFDocument(url: url) else { throw IngestError.cannotOpenPDF }
            var result = Result()
            let attributes = pdf.documentAttributes ?? [:]
            result.title = (attributes[PDFDocumentAttribute.titleAttribute] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            result.authors = (attributes[PDFDocumentAttribute.authorAttribute] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let date = attributes[PDFDocumentAttribute.creationDateAttribute] as? Date {
                result.year = String(Calendar(identifier: .gregorian).component(.year, from: date))
            }
            result.pageCount = pdf.pageCount
            let sections = outlineSections(pdf)

            for index in 0..<pdf.pageCount {
                guard let page = pdf.page(at: index) else { continue }
                var text = page.string ?? ""
                if text.trimmingCharacters(in: .whitespacesAndNewlines).count < 30, result.ocrPages < 600 {
                    // Taranmış sayfa: Vision ile metin tanıma (cihaz üzerinde).
                    let recognized = ocr(page)
                    if !recognized.isEmpty {
                        text = recognized
                        result.ocrPages += 1
                    }
                }
                let section = sections.last { $0.page <= index }?.title
                for piece in chunk(text) {
                    result.chunks.append(KBChunk(docID: docID, page: index + 1, section: section, text: piece))
                }
            }
            return result
        }.value
    }

    /// PDF içindekiler tablosundan (sayfa, başlık) listesi.
    private static func outlineSections(_ pdf: PDFDocument) -> [(page: Int, title: String)] {
        var items: [(page: Int, title: String)] = []
        func walk(_ node: PDFOutline, depth: Int) {
            for i in 0..<node.numberOfChildren {
                guard let child = node.child(at: i) else { continue }
                if let page = child.destination?.page, let label = child.label, !label.isEmpty {
                    items.append((pdf.index(for: page), label))
                }
                if depth < 3 { walk(child, depth: depth + 1) }
            }
        }
        if let root = pdf.outlineRoot { walk(root, depth: 0) }
        return items.sorted { $0.page < $1.page }
    }

    private static func ocr(_ page: PDFPage) -> String {
        let bounds = page.bounds(for: .mediaBox)
        let image = page.thumbnail(of: NSSize(width: bounds.width * 2, height: bounds.height * 2), for: .mediaBox)
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return "" }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["de-DE", "en-US"]
        do {
            try VNImageRequestHandler(cgImage: cgImage).perform([request])
        } catch {
            return ""
        }
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    // MARK: - URL / DOI

    static func extractDOI(_ input: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "10\\.\\d{4,9}/[^\\s\"<>]+", options: [.caseInsensitive]),
              let match = regex.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)),
              let range = Range(match.range, in: input) else { return nil }
        return String(input[range]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;)"))
    }

    static func link(url: String, doi: String, docID: UUID, filesFolder: URL) async throws -> Result {
        var metadata = Result()
        var target = url
        if !doi.isEmpty {
            metadata = await doiMetadata(doi)
            target = "https://doi.org/\(doi)"
        }
        guard let requestURL = URL(string: target) else { throw IngestError.download("Invalid URL") }

        var request = URLRequest(url: requestURL)
        request.timeoutInterval = 60
        request.setValue("text/html,application/xhtml+xml,application/pdf;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 (Macintosh) MacAsistan", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw IngestError.download("No response") }
        guard (200..<300).contains(http.statusCode) else {
            throw IngestError.download("HTTP \(http.statusCode) – the page may require a login. Download the PDF and add it as a file.")
        }
        let finalURL = http.url?.absoluteString ?? target
        let isPDF = (http.mimeType ?? "").contains("pdf") || data.starts(with: Array("%PDF".utf8))

        var result: Result
        if isPDF {
            let stored = "\(docID.uuidString).pdf"
            let destination = filesFolder.appendingPathComponent(stored)
            try data.write(to: destination, options: .atomic)
            result = try await pdf(at: destination, docID: docID)
            result.storedFileName = stored
        } else {
            let html = String(decoding: data, as: UTF8.self)
            let text = await MainActor.run { htmlToText(data) }
            result = Result()
            result.title = htmlTitle(html)
            result.chunks = chunk(text).map { KBChunk(docID: docID, page: 0, section: nil, text: $0) }
        }
        result.finalURL = finalURL
        // DOI kayıt bilgileri sayfadakinden daha güvenilir.
        if let title = metadata.title { result.title = title }
        if let authors = metadata.authors { result.authors = authors }
        if let year = metadata.year { result.year = year }
        return result
    }

    /// doi.org'dan başlık, yazar ve yıl (CSL JSON).
    private static func doiMetadata(_ doi: String) async -> Result {
        var result = Result()
        guard let url = URL(string: "https://doi.org/\(doi)") else { return result }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("application/vnd.citationstyles.csl+json", forHTTPHeaderField: "Accept")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return result }
        result.title = (json["title"] as? String) ?? (json["title"] as? [String])?.first
        if let authors = json["author"] as? [[String: Any]] {
            let names = authors.prefix(6).compactMap { author -> String? in
                if let family = author["family"] as? String {
                    let given = (author["given"] as? String).map { " \($0.prefix(1))." } ?? ""
                    return family + given
                }
                return author["name"] as? String
            }
            result.authors = names.joined(separator: ", ") + (authors.count > 6 ? " et al." : "")
        }
        if let issued = json["issued"] as? [String: Any], let parts = issued["date-parts"] as? [[Any]],
           let year = parts.first?.first {
            result.year = "\(year)"
        }
        return result
    }

    @MainActor
    private static func htmlToText(_ data: Data) -> String {
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue,
        ]
        if let attributed = try? NSAttributedString(data: data, options: options, documentAttributes: nil) {
            return attributed.string
        }
        return String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
    }

    private static func htmlTitle(_ html: String) -> String? {
        guard let range = html.range(of: "<title[^>]*>([\\s\\S]*?)</title>", options: [.regularExpression, .caseInsensitive]) else { return nil }
        return String(html[range])
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Parçalama

    /// Metni ~1200 karakterlik, biraz örtüşen parçalara böler.
    static func chunk(_ text: String, size: Int = 1200, overlap: Int = 200) -> [String] {
        // Satır sonu tirelemesini birleştir ("Bestrah-\nlung" → "Bestrahlung").
        let cleaned = text
            .replacingOccurrences(of: "-\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
        let paragraphs = cleaned.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var chunks: [String] = []
        var current = ""
        for paragraph in paragraphs {
            if current.count + paragraph.count + 1 > size, !current.isEmpty {
                chunks.append(current)
                current = String(current.suffix(overlap))
            }
            current += (current.isEmpty ? "" : "\n") + paragraph
            while current.count > size * 2 {
                let head = String(current.prefix(size))
                chunks.append(head)
                current = String(current.dropFirst(size - overlap))
            }
        }
        if current.trimmingCharacters(in: .whitespacesAndNewlines).count > 20 { chunks.append(current) }
        return chunks
    }
}
