import PDFKit
import SwiftUI

struct PDFViewerPane: View {
    let state: PDFViewerTabState
    let focused: Bool
    let onFocus: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
        }
        .background(MuxyTheme.bg)
        .contentShape(Rectangle())
        .onTapGesture(perform: onFocus)
        .task(id: state.filePath) {
            await state.loadIfNeeded()
        }
    }

    private var toolbar: some View {
        HStack(spacing: UIMetrics.spacing3) {
            Image(systemName: "doc.richtext")
                .font(.system(size: UIMetrics.fontBody, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(state.displayTitle)
                .font(.system(size: UIMetrics.fontBody, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)

            if !state.metadata.isEmpty {
                Text(state.metadata)
                    .font(.system(size: UIMetrics.fontCaption))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: UIMetrics.spacing5)

            if !state.pageDisplayText.isEmpty {
                Text(state.pageDisplayText)
                    .font(.system(size: UIMetrics.fontCaption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: UIMetrics.scaled(52), alignment: .trailing)
            }

            IconButton(symbol: "arrow.clockwise", accessibilityLabel: "Reload PDF") {
                Task { await state.reload() }
            }
            .help("Reload PDF")

            IconButton(symbol: "chevron.up", accessibilityLabel: "Previous Page") {
                state.previousPage()
            }
            .help("Previous Page")
            .disabled(state.document == nil || !state.canGoToPreviousPage)

            IconButton(symbol: "chevron.down", accessibilityLabel: "Next Page") {
                state.nextPage()
            }
            .help("Next Page")
            .disabled(state.document == nil || !state.canGoToNextPage)

            IconButton(symbol: "minus.magnifyingglass", accessibilityLabel: "Zoom Out") {
                state.zoomOut()
            }
            .help("Zoom Out")
            .disabled(state.document == nil)

            IconButton(symbol: "plus.magnifyingglass", accessibilityLabel: "Zoom In") {
                state.zoomIn()
            }
            .help("Zoom In")
            .disabled(state.document == nil)

            IconButton(symbol: "1.magnifyingglass", accessibilityLabel: "Actual Size") {
                state.actualSize()
            }
            .help("Actual Size")
            .disabled(state.document == nil)

            IconButton(symbol: "arrow.left.and.right", accessibilityLabel: "Fit Width") {
                state.fitWidth()
            }
            .help("Fit Width")
            .disabled(state.document == nil)

            IconButton(symbol: "arrow.up.left.and.arrow.down.right", accessibilityLabel: "Fit Page") {
                state.fitPage()
            }
            .help("Fit Page")
            .disabled(state.document == nil)
        }
        .frame(height: UIMetrics.scaled(36))
        .padding(.horizontal, UIMetrics.spacing5)
    }

    private var content: some View {
        ZStack {
            switch state.loadState {
            case .idle,
                 .loading:
                ProgressView()
                    .controlSize(.small)
            case .loaded:
                if let document = state.document {
                    PDFKitViewerView(document: document, command: state.viewerCommand) { pageIndex in
                        Task { @MainActor in
                            state.updateCurrentPage(index: pageIndex)
                        }
                    }
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            case let .failed(message):
                VStack(spacing: UIMetrics.spacing4) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: UIMetrics.iconLG))
                        .foregroundStyle(.secondary)
                    Text(message)
                        .font(.system(size: UIMetrics.fontBody))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task { await state.reload() }
                    }
                    .buttonStyle(.bordered)
                }
                .padding(UIMetrics.spacing7)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PDFKitViewerView: NSViewRepresentable {
    let document: PDFDocument
    let command: PDFViewerCommand?
    let onPageChanged: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context _: Context) -> PDFKitViewerNSView {
        PDFKitViewerNSView()
    }

    func updateNSView(_ nsView: PDFKitViewerNSView, context: Context) {
        nsView.onPageChanged = onPageChanged
        nsView.setDocument(document)
        guard let command, context.coordinator.lastCommandID != command.id else { return }
        context.coordinator.lastCommandID = command.id
        nsView.apply(command.action)
    }

    final class Coordinator {
        var lastCommandID: UUID?
    }
}

private final class PDFKitViewerNSView: NSView {
    private enum FitMode {
        case none
        case page
        case width
    }

    private let pdfView = PDFView()
    private var documentID: ObjectIdentifier?
    private var fitMode: FitMode = .width
    var onPageChanged: ((Int) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func setDocument(_ document: PDFDocument) {
        let nextID = ObjectIdentifier(document)
        guard documentID != nextID else { return }
        documentID = nextID
        pdfView.document = document
        fitMode = .width
        applyFitWidth()
        notifyPageChanged()
    }

    func apply(_ action: PDFViewerCommand.Action) {
        switch action {
        case .fitPage:
            applyFitPage()
        case .fitWidth:
            applyFitWidth()
        case .actualSize:
            fitMode = .none
            pdfView.autoScales = false
            pdfView.displayMode = .singlePageContinuous
            setScale(1)
        case .zoomIn:
            fitMode = .none
            pdfView.autoScales = false
            setScale(pdfView.scaleFactor * 1.2)
        case .zoomOut:
            fitMode = .none
            pdfView.autoScales = false
            setScale(pdfView.scaleFactor / 1.2)
        case .previousPage:
            pdfView.goToPreviousPage(nil)
            notifyPageChanged()
        case .nextPage:
            pdfView.goToNextPage(nil)
            notifyPageChanged()
        }
    }

    override func layout() {
        super.layout()
        switch fitMode {
        case .page:
            pdfView.autoScales = true
        case .width:
            applyFitWidth()
        case .none:
            break
        }
    }

    private func setup() {
        wantsLayer = true
        pdfView.translatesAutoresizingMaskIntoConstraints = false
        pdfView.backgroundColor = .clear
        pdfView.displayDirection = .vertical
        pdfView.displayMode = .singlePageContinuous
        pdfView.displaysPageBreaks = true
        pdfView.minScaleFactor = 0.1
        pdfView.maxScaleFactor = 8
        addSubview(pdfView)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(pageChanged),
            name: .PDFViewPageChanged,
            object: pdfView
        )
        NSLayoutConstraint.activate([
            pdfView.leadingAnchor.constraint(equalTo: leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: trailingAnchor),
            pdfView.topAnchor.constraint(equalTo: topAnchor),
            pdfView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @objc
    private func pageChanged() {
        notifyPageChanged()
    }

    private func applyFitPage() {
        fitMode = .page
        pdfView.displayMode = .singlePage
        pdfView.autoScales = true
    }

    private func applyFitWidth() {
        fitMode = .width
        pdfView.displayMode = .singlePageContinuous
        pdfView.autoScales = false
        guard let page = pdfView.currentPage ?? pdfView.document?.page(at: 0) else { return }
        let pageBounds = page.bounds(for: pdfView.displayBox)
        let visibleWidth = pdfView.enclosingScrollView?.contentView.bounds.width ?? pdfView.bounds.width
        guard pageBounds.width > 0, visibleWidth > 0 else { return }
        setScale((visibleWidth - 28) / pageBounds.width)
    }

    private func setScale(_ scale: CGFloat) {
        pdfView.scaleFactor = min(pdfView.maxScaleFactor, max(pdfView.minScaleFactor, scale))
    }

    private func notifyPageChanged() {
        guard let document = pdfView.document, let currentPage = pdfView.currentPage else {
            onPageChanged?(0)
            return
        }
        let index = document.index(for: currentPage)
        guard index >= 0 else { return }
        onPageChanged?(index)
    }
}
