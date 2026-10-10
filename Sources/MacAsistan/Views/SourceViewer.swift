import AppKit
import PDFKit
import SwiftUI

/// Kaynak PDF'i ilgili sayfada açar ve alıntıyı vurgular.
struct SourceViewer: View {
    @EnvironmentObject var app: AppState
    let target: SourceTarget?

    var body: some View {
        if let target, let doc = app.knowledge.document(target.docID), let file = app.knowledge.fileURL(for: doc) {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(doc.citationLine).font(.headline).lineLimit(2)
                        if target.page > 0 { Text("S. \(target.page)").font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    Button(L10n.t(.openInPreview)) { NSWorkspace.shared.open(file) }
                }
                .padding(10)
                Divider()
                PDFKitView(url: file, page: target.page, quote: target.quote)
            }
            .navigationTitle(doc.title)
            .frame(minWidth: 600, minHeight: 700)
        } else {
            Text("—").frame(width: 300, height: 200)
        }
    }
}

private struct PDFKitView: NSViewRepresentable {
    let url: URL
    let page: Int
    let quote: String?

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
        }
        guard let document = view.document, page >= 1, let pdfPage = document.page(at: page - 1) else { return }
        view.go(to: pdfPage)

        // Alıntının ilk kelimelerini sayfada bul ve vurgula.
        guard let quote, !quote.isEmpty else { return }
        let words = quote.split(separator: " ").prefix(6).joined(separator: " ")
        let matches = document.findString(words, withOptions: [.caseInsensitive])
            .filter { $0.pages.contains(pdfPage) }
        if let selection = matches.first {
            selection.color = NSColor.systemYellow.withAlphaComponent(0.5)
            view.highlightedSelections = [selection]
            view.go(to: selection)
        }
    }
}
