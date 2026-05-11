import Foundation
import PDFKit

struct PDFViewerCommand: Equatable {
    enum Action: Equatable {
        case fitPage
        case fitWidth
        case actualSize
        case zoomIn
        case zoomOut
        case previousPage
        case nextPage
    }

    let id = UUID()
    let action: Action
}

@MainActor
@Observable
final class PDFViewerTabState {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    let projectPath: String
    let remoteHost: String?
    private(set) var filePath: String
    var document: PDFDocument?
    var byteCount: Int?
    var pageCount: Int?
    var currentPageIndex = 0
    var loadState: LoadState = .idle
    var viewerCommand: PDFViewerCommand?

    init(projectPath: String, filePath: String, remoteHost: String? = nil) {
        self.projectPath = projectPath
        self.filePath = filePath
        self.remoteHost = remoteHost
    }

    var displayTitle: String {
        URL(fileURLWithPath: filePath).lastPathComponent
    }

    var metadata: String {
        let pageText = pageCount.map { $0 == 1 ? "1 page" : "\($0) pages" }
        let byteText = byteCount.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }
        return [pageText, byteText].compactMap(\.self).joined(separator: " · ")
    }

    var pageDisplayText: String {
        guard let pageCount, pageCount > 0 else { return "" }
        return "\(currentPageIndex + 1) / \(pageCount)"
    }

    var canGoToPreviousPage: Bool {
        currentPageIndex > 0
    }

    var canGoToNextPage: Bool {
        guard let pageCount else { return false }
        return currentPageIndex < pageCount - 1
    }

    func updateFilePath(_ newPath: String) {
        guard filePath != newPath else { return }
        filePath = newPath
        document = nil
        byteCount = nil
        pageCount = nil
        currentPageIndex = 0
        loadState = .idle
    }

    func loadIfNeeded() async {
        guard document == nil, loadState != .loading else { return }
        await load()
    }

    func reload() async {
        document = nil
        byteCount = nil
        pageCount = nil
        currentPageIndex = 0
        loadState = .idle
        await load()
    }

    func fitPage() {
        viewerCommand = PDFViewerCommand(action: .fitPage)
    }

    func fitWidth() {
        viewerCommand = PDFViewerCommand(action: .fitWidth)
    }

    func actualSize() {
        viewerCommand = PDFViewerCommand(action: .actualSize)
    }

    func zoomIn() {
        viewerCommand = PDFViewerCommand(action: .zoomIn)
    }

    func zoomOut() {
        viewerCommand = PDFViewerCommand(action: .zoomOut)
    }

    func previousPage() {
        viewerCommand = PDFViewerCommand(action: .previousPage)
    }

    func nextPage() {
        viewerCommand = PDFViewerCommand(action: .nextPage)
    }

    func updateCurrentPage(index: Int) {
        currentPageIndex = max(0, min(index, (pageCount ?? 1) - 1))
    }

    private func load() async {
        let requestedPath = filePath
        loadState = .loading
        do {
            let loaded = try await PreviewFileLoader.loadData(
                filePath: requestedPath,
                remoteHost: remoteHost,
                maxBytes: PreviewFileLoader.maxPDFBytes,
                signpostName: "remote-pdf"
            )
            guard requestedPath == filePath else { return }
            guard let loadedDocument = PDFDocument(data: loaded.data), loadedDocument.pageCount > 0 else {
                throw PreviewFileLoaderError.invalidFormat("PDF format is not supported.")
            }
            document = loadedDocument
            byteCount = loaded.byteCount
            pageCount = loadedDocument.pageCount
            currentPageIndex = 0
            loadState = .loaded
            fitWidth()
        } catch {
            guard requestedPath == filePath else { return }
            document = nil
            byteCount = nil
            pageCount = nil
            currentPageIndex = 0
            loadState = .failed(error.localizedDescription)
        }
    }
}
