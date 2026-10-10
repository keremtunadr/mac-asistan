import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Bilgi bankası: onaylı kaynakları ekle, düzenle, kaldır.
struct LibraryView: View {
    @EnvironmentObject var app: AppState
    @State private var link = ""
    @State private var selection: UUID?
    @State private var dropTargeted = false

    private var kb: KnowledgeBase { app.knowledge }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    choosePDFs()
                } label: {
                    Label(L10n.t(.addPDF), systemImage: "doc.badge.plus")
                }
                Divider().frame(height: 18)
                TextField(L10n.t(.linkPlaceholder), text: $link)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addLink)
                Button(L10n.t(.add), action: addLink)
                    .disabled(link.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(12)

            Divider()

            if kb.documents.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "books.vertical").font(.system(size: 40)).foregroundStyle(.secondary)
                    Text(L10n.t(.libraryEmpty)).multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 420)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    List(selection: $selection) {
                        ForEach(kb.documents) { doc in
                            DocumentRow(doc: doc).tag(doc.id)
                        }
                    }
                    .frame(minWidth: 260)

                    Group {
                        if let id = selection, kb.document(id) != nil {
                            DocumentDetail(id: id)
                        } else {
                            Text(L10n.t(.libraryTitle)).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(minWidth: 360)
                }
            }

            Divider()
            Label(L10n.t(.libraryPrivacy), systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 12).stroke(Color.accentColor, lineWidth: 3).padding(4)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, url.pathExtension.lowercased() == "pdf" else { return }
                    Task { @MainActor in app.knowledge.addPDF(url) }
                }
            }
            return true
        }
        .navigationTitle(L10n.t(.libraryTitle))
        .frame(minWidth: 720, minHeight: 460)
    }

    private func choosePDFs() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK { kb.addPDFs(panel.urls) }
    }

    private func addLink() {
        kb.addLink(link)
        link = ""
    }
}

private struct DocumentRow: View {
    let doc: KBDocument

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Group {
                switch doc.status {
                case .processing: ProgressView().controlSize(.small)
                case .ready: Image(systemName: doc.kind == .pdf ? "doc.richtext" : "globe").foregroundStyle(.tint)
                case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
            }
            .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(doc.title).lineLimit(2)
                Text([doc.authors, doc.year, doc.version].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct DocumentDetail: View {
    @EnvironmentObject var app: AppState
    @Environment(\.openWindow) private var openWindow
    let id: UUID
    @State private var confirmRemove = false

    private var kb: KnowledgeBase { app.knowledge }
    private var doc: KBDocument? { kb.document(id) }

    private func field(_ keyPath: WritableKeyPath<KBDocument, String>) -> Binding<String> {
        Binding(get: { kb.document(id)?[keyPath: keyPath] ?? "" },
                set: { value in kb.update(id) { $0[keyPath: keyPath] = value } })
    }

    var body: some View {
        if let doc {
            Form {
                Section {
                    TextField(L10n.t(.docTitle), text: field(\.title))
                    TextField(L10n.t(.docAuthors), text: field(\.authors))
                    TextField(L10n.t(.docYear), text: field(\.year))
                    TextField(L10n.t(.docVersion), text: field(\.version))
                    TextField(L10n.t(.docURL), text: field(\.url))
                    TextField(L10n.t(.docDOI), text: field(\.doi))
                }
                Section {
                    LabeledContent("Status") {
                        switch doc.status {
                        case .processing: Text(L10n.t(.docProcessing))
                        case .ready: Text(L10n.t(.docReady)).foregroundStyle(.green)
                        case .failed: Text("\(L10n.t(.docFailed)): \(doc.statusMessage ?? "")").foregroundStyle(.red)
                        }
                    }
                    if doc.pageCount > 0 { LabeledContent(L10n.t(.docPages), value: "\(doc.pageCount)") }
                    LabeledContent(L10n.t(.docChunks), value: "\(doc.chunkCount)")
                    if doc.ocrPages > 0 { LabeledContent(L10n.t(.docOCR), value: "\(doc.ocrPages)") }
                    if let file = doc.originalFileName { LabeledContent("PDF", value: file) }
                    LabeledContent(L10n.t(.docAdded), value: doc.addedAt.formatted(date: .abbreviated, time: .shortened))
                }
                Section {
                    HStack {
                        if doc.storedFileName != nil {
                            Button(L10n.t(.openSource)) {
                                NSApp.activate(ignoringOtherApps: true)
                                openWindow(id: "source", value: SourceTarget(docID: doc.id, page: 1, quote: nil))
                            }
                        }
                        if let url = doc.linkURL {
                            Button(url.host ?? "Link") { NSWorkspace.shared.open(url) }
                        }
                        Spacer()
                        Button(L10n.t(.delete), role: .destructive) { confirmRemove = true }
                    }
                }
            }
            .formStyle(.grouped)
            .confirmationDialog(L10n.t(.removeAIConfirm), isPresented: $confirmRemove) {
                Button(L10n.t(.delete), role: .destructive) { kb.remove(id) }
                Button(L10n.t(.cancel), role: .cancel) {}
            }
        }
    }
}
