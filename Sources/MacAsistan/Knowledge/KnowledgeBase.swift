import Foundation

/// Bilgi bankasındaki bir kaynak (PDF, URL, DOI).
struct KBDocument: Identifiable, Codable, Equatable {
    enum Kind: String, Codable { case pdf, web }
    enum Status: String, Codable { case processing, ready, failed }

    var id = UUID()
    var kind: Kind
    var title: String
    var authors = ""
    var year = ""
    var version = ""
    var url = ""
    var doi = ""
    /// Bilgi bankası klasöründeki PDF kopyasının adı
    var storedFileName: String?
    /// Kullanıcının yüklediği dosyanın orijinal adı
    var originalFileName: String?
    var addedAt = Date()
    var pageCount = 0
    var chunkCount = 0
    var ocrPages = 0
    var status: Status = .processing
    var statusMessage: String?

    var citationLine: String {
        var parts: [String] = [title]
        if !authors.isEmpty { parts.append(authors) }
        let yv = [year, version.isEmpty ? "" : "Version \(version)"].filter { !$0.isEmpty }.joined(separator: ", ")
        if !yv.isEmpty { parts.append(yv) }
        return parts.joined(separator: " – ")
    }

    var linkURL: URL? {
        if !doi.isEmpty { return URL(string: "https://doi.org/\(doi)") }
        if !url.isEmpty { return URL(string: url) }
        return nil
    }
}

/// Aranabilir metin parçası (sayfa ve bölüm bilgisiyle).
struct KBChunk: Codable, Identifiable, Sendable {
    var id = UUID()
    var docID: UUID
    /// 1'den başlayan sayfa numarası (web kaynaklarında 0)
    var page: Int
    var section: String?
    var text: String
}

/// Aramada bulunan parça.
struct KBHit {
    let chunk: KBChunk
    let document: KBDocument
    let score: Double
}

/// Kullanıcının kaynakları: ~/Library/Application Support/MacAsistan/Knowledge/
@MainActor
final class KnowledgeBase: ObservableObject {
    @Published private(set) var documents: [KBDocument] = []

    let folder: URL
    private var filesFolder: URL { folder.appendingPathComponent("files", isDirectory: true) }
    private var chunksFolder: URL { folder.appendingPathComponent("chunks", isDirectory: true) }
    private var indexURL: URL { folder.appendingPathComponent("documents.json") }

    /// Bellekteki arama dizini (ilk aramada yüklenir)
    private var chunkCache: [UUID: [KBChunk]] = [:]
    private var index: BM25Index?

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        folder = support.appendingPathComponent("MacAsistan/Knowledge", isDirectory: true)
        try? FileManager.default.createDirectory(at: filesFolder, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: chunksFolder, withIntermediateDirectories: true)
        load()
        // Uygulama işlem sırasında kapandıysa yarım kalan kayıtları işaretle.
        for i in documents.indices where documents[i].status == .processing {
            documents[i].status = .failed
            documents[i].statusMessage = "Interrupted – please add again."
        }
    }

    var readyDocuments: [KBDocument] { documents.filter { $0.status == .ready } }

    func document(_ id: UUID) -> KBDocument? { documents.first { $0.id == id } }

    func fileURL(for doc: KBDocument) -> URL? {
        doc.storedFileName.map { filesFolder.appendingPathComponent($0) }
    }

    // MARK: - Ekleme

    func addPDFs(_ urls: [URL]) {
        for url in urls { addPDF(url) }
    }

    func addPDF(_ source: URL) {
        var doc = KBDocument(kind: .pdf, title: source.deletingPathExtension().lastPathComponent)
        doc.originalFileName = source.lastPathComponent
        let stored = "\(doc.id.uuidString).pdf"
        doc.storedFileName = stored
        let destination = filesFolder.appendingPathComponent(stored)
        do {
            let scoped = source.startAccessingSecurityScopedResource()
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }
            try FileManager.default.copyItem(at: source, to: destination)
        } catch {
            doc.status = .failed
            doc.statusMessage = error.localizedDescription
            documents.append(doc)
            save()
            return
        }
        documents.append(doc)
        save()
        let id = doc.id
        process(id) { try await Ingest.pdf(at: destination, docID: id) }
    }

    /// URL veya DOI ekler (ör. "https://…", "10.1016/…", "https://doi.org/10…").
    func addLink(_ raw: String) {
        let input = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        var doc = KBDocument(kind: .web, title: input)
        if let doi = Ingest.extractDOI(input) {
            doc.doi = doi
        } else {
            doc.url = input.hasPrefix("http") ? input : "https://\(input)"
        }
        documents.append(doc)
        save()
        let id = doc.id, url = doc.url, doi = doc.doi
        let filesFolder = self.filesFolder
        process(id) { try await Ingest.link(url: url, doi: doi, docID: id, filesFolder: filesFolder) }
    }

    private func process(_ id: UUID, work: @escaping @Sendable () async throws -> Ingest.Result) {
        Task {
            do {
                let result = try await work()
                update(id) { doc in
                    // Başlığı yalnızca kullanıcı henüz değiştirmediyse belgedeki bilgiyle doldur.
                    let fileStem = ((doc.originalFileName ?? "") as NSString).deletingPathExtension
                    let untouched = doc.kind == .web || doc.title == fileStem
                    if let title = result.title, !title.isEmpty, untouched { doc.title = title }
                    if doc.authors.isEmpty, let authors = result.authors { doc.authors = authors }
                    if doc.year.isEmpty, let year = result.year { doc.year = year }
                    if doc.url.isEmpty, let url = result.finalURL { doc.url = url }
                    if let stored = result.storedFileName { doc.storedFileName = stored }
                    doc.pageCount = result.pageCount
                    doc.chunkCount = result.chunks.count
                    doc.ocrPages = result.ocrPages
                    if result.chunks.isEmpty {
                        doc.status = .failed
                        doc.statusMessage = "No readable text found."
                    } else {
                        doc.status = .ready
                        doc.statusMessage = nil
                    }
                }
                if !result.chunks.isEmpty { saveChunks(result.chunks, for: id) }
            } catch {
                update(id) { doc in
                    doc.status = .failed
                    doc.statusMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Düzenleme / silme

    func update(_ id: UUID, _ change: (inout KBDocument) -> Void) {
        guard let i = documents.firstIndex(where: { $0.id == id }) else { return }
        change(&documents[i])
        save()
    }

    func remove(_ id: UUID) {
        guard let doc = document(id) else { return }
        if let file = fileURL(for: doc) { try? FileManager.default.removeItem(at: file) }
        try? FileManager.default.removeItem(at: chunksFolder.appendingPathComponent("\(id.uuidString).json"))
        documents.removeAll { $0.id == id }
        chunkCache[id] = nil
        index = nil
        save()
    }

    // MARK: - Arama

    /// En ilgili parçaları döndürür (yalnızca hazır belgelerde).
    func search(_ queries: [String], limit: Int = 10) -> [KBHit] {
        let ready = readyDocuments
        guard !ready.isEmpty else { return [] }
        let idx = buildIndexIfNeeded(for: ready)
        let docsByID = Dictionary(uniqueKeysWithValues: ready.map { ($0.id, $0) })
        return idx.search(queries, limit: limit).compactMap { result in
            guard let doc = docsByID[result.chunk.docID] else { return nil }
            return KBHit(chunk: result.chunk, document: doc, score: result.score)
        }
    }

    private func buildIndexIfNeeded(for ready: [KBDocument]) -> BM25Index {
        let ids = Set(ready.map(\.id))
        if let index, index.documentIDs == ids { return index }
        var all: [KBChunk] = []
        for doc in ready {
            if chunkCache[doc.id] == nil { chunkCache[doc.id] = loadChunks(for: doc.id) }
            all += chunkCache[doc.id] ?? []
        }
        let built = BM25Index(chunks: all, documentIDs: ids)
        index = built
        return built
    }

    // MARK: - Kalıcılık

    private func load() {
        guard let data = try? Data(contentsOf: indexURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        documents = (try? decoder.decode([KBDocument].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        try? encoder.encode(documents).write(to: indexURL, options: .atomic)
    }

    private func saveChunks(_ chunks: [KBChunk], for id: UUID) {
        try? JSONEncoder().encode(chunks).write(to: chunksFolder.appendingPathComponent("\(id.uuidString).json"), options: .atomic)
        chunkCache[id] = chunks
        index = nil
    }

    private func loadChunks(for id: UUID) -> [KBChunk] {
        guard let data = try? Data(contentsOf: chunksFolder.appendingPathComponent("\(id.uuidString).json")) else { return [] }
        return (try? JSONDecoder().decode([KBChunk].self, from: data)) ?? []
    }
}
