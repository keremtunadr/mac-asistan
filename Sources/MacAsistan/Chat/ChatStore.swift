import Foundation

struct ChatMessage: Identifiable, Codable, Equatable {
    enum Role: String, Codable { case user, assistant }

    var id = UUID()
    var role: Role
    var text: String
    var date = Date()
    var viaVoice = false
    var isError = false
    var model: String?
}

struct Conversation: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var createdAt = Date()
    var updatedAt = Date()
    var messages: [ChatMessage] = []
}

/// Sohbet geçmişini yerel olarak saklar:
/// ~/Library/Application Support/MacAsistan/history.json
@MainActor
final class ChatStore: ObservableObject {
    @Published private(set) var conversations: [Conversation] = []
    @Published var selectedID: UUID?

    let folderURL: URL
    private let fileURL: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        folderURL = support.appendingPathComponent("MacAsistan", isDirectory: true)
        fileURL = folderURL.appendingPathComponent("history.json")
        load()
        selectedID = conversations.first?.id
    }

    var selected: Conversation? {
        guard let selectedID else { return nil }
        return conversations.first { $0.id == selectedID }
    }

    @discardableResult
    func newConversation() -> UUID {
        if let current = selected, current.messages.isEmpty { return current.id }
        let conversation = Conversation(title: L10n.t(.untitledChat))
        conversations.insert(conversation, at: 0)
        selectedID = conversation.id
        save()
        return conversation.id
    }

    /// Seçili sohbeti döndürür, yoksa yenisini oluşturur.
    func ensureSelected() -> UUID {
        if let selected { return selected.id }
        return newConversation()
    }

    func append(_ message: ChatMessage, to id: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[index].messages.append(message)
        conversations[index].updatedAt = Date()
        if message.role == .user, conversations[index].messages.filter({ $0.role == .user }).count == 1 {
            conversations[index].title = Self.makeTitle(from: message.text)
        }
        // En son kullanılan sohbet en üstte dursun.
        if index != 0 {
            let conversation = conversations.remove(at: index)
            conversations.insert(conversation, at: 0)
        }
        save()
    }

    /// Akış sırasında bir mesajın metnini günceller (diske her parçada yazmaz).
    func updateText(of messageID: UUID, in conversationID: UUID, to text: String, persist: Bool = false) {
        guard let c = conversations.firstIndex(where: { $0.id == conversationID }),
              let m = conversations[c].messages.firstIndex(where: { $0.id == messageID }) else { return }
        conversations[c].messages[m].text = text
        if persist {
            conversations[c].updatedAt = Date()
            save()
        }
    }

    func delete(_ id: UUID) {
        conversations.removeAll { $0.id == id }
        if selectedID == id { selectedID = conversations.first?.id }
        save()
    }

    func deleteAll() {
        conversations.removeAll()
        selectedID = nil
        save()
    }

    private static func makeTitle(from text: String) -> String {
        let singleLine = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        return singleLine.count > 48 ? String(singleLine.prefix(48)) + "…" : singleLine
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        conversations = (try? decoder.decode([Conversation].self, from: data)) ?? []
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted]
            try encoder.encode(conversations).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("MacAsistan: history could not be saved: \(error)")
        }
    }
}
