import AppKit
import SwiftUI

struct ImageViewerPane: View {
    let state: ImageViewerTabState
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
            Image(systemName: "photo")
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

            IconButton(symbol: "arrow.clockwise", accessibilityLabel: "Reload Image") {
                Task { await state.reload() }
            }
            .help("Reload Image")

            IconButton(symbol: "minus.magnifyingglass", accessibilityLabel: "Zoom Out") {
                state.zoomOut()
            }
            .help("Zoom Out")
            .disabled(state.image == nil)

            IconButton(symbol: "plus.magnifyingglass", accessibilityLabel: "Zoom In") {
                state.zoomIn()
            }
            .help("Zoom In")
            .disabled(state.image == nil)

            IconButton(symbol: "1.magnifyingglass", accessibilityLabel: "Actual Size") {
                state.actualSize()
            }
            .help("Actual Size")
            .disabled(state.image == nil)

            IconButton(symbol: "arrow.up.left.and.arrow.down.right", accessibilityLabel: "Fit to Window") {
                state.fitToWindow()
            }
            .help("Fit to Window")
            .disabled(state.image == nil)
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
                if let image = state.image {
                    ZoomableImageView(image: image, command: state.zoomCommand)
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

private struct ZoomableImageView: NSViewRepresentable {
    let image: NSImage
    let command: ImageViewerZoomCommand?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context _: Context) -> ZoomableImageNSView {
        ZoomableImageNSView()
    }

    func updateNSView(_ nsView: ZoomableImageNSView, context: Context) {
        nsView.setImage(image)
        guard let command, context.coordinator.lastCommandID != command.id else { return }
        context.coordinator.lastCommandID = command.id
        nsView.apply(command.action)
    }

    final class Coordinator {
        var lastCommandID: UUID?
    }
}

private final class ZoomableImageNSView: NSView {
    private let scrollView = NSScrollView()
    private let canvas = PannableImageCanvas()
    private var imageID: ObjectIdentifier?
    private var fitMode = true
    private var applyingFit = false

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

    func setImage(_ image: NSImage) {
        let nextID = ObjectIdentifier(image)
        guard imageID != nextID else { return }
        imageID = nextID
        canvas.image = image
        fitMode = true
        updateDocumentSize()
        applyFit()
    }

    func apply(_ action: ImageViewerZoomCommand.Action) {
        switch action {
        case .fit:
            fitMode = true
            applyFit()
        case .actualSize:
            fitMode = false
            setMagnification(1)
        case .zoomIn:
            fitMode = false
            setMagnification(scrollView.magnification * 1.25)
        case .zoomOut:
            fitMode = false
            setMagnification(scrollView.magnification / 1.25)
        }
    }

    override func layout() {
        super.layout()
        updateDocumentSize()
        if fitMode {
            applyFit()
        }
    }

    private func setup() {
        wantsLayer = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.05
        scrollView.maxMagnification = 16
        scrollView.documentView = canvas
        canvas.scrollView = scrollView
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(liveMagnifyWillStart),
            name: NSScrollView.willStartLiveMagnifyNotification,
            object: scrollView
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(liveMagnifyDidEnd),
            name: NSScrollView.didEndLiveMagnifyNotification,
            object: scrollView
        )
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @objc
    private func liveMagnifyWillStart() {
        fitMode = false
    }

    @objc
    private func liveMagnifyDidEnd() {
        updateDocumentSize()
    }

    private func applyFit() {
        guard !applyingFit else { return }
        guard canvas.imageSize.width > 0, canvas.imageSize.height > 0 else { return }
        let available = scrollView.contentView.frame.size
        guard available.width > 0, available.height > 0 else { return }
        applyingFit = true
        let target = min(available.width / canvas.imageSize.width, available.height / canvas.imageSize.height)
        setMagnification(target)
        centerImage()
        applyingFit = false
    }

    private func setMagnification(_ value: CGFloat) {
        let clamped = min(scrollView.maxMagnification, max(scrollView.minMagnification, value))
        let center = visibleCenter()
        scrollView.setMagnification(clamped, centeredAt: center)
        updateDocumentSize()
    }

    private func visibleCenter() -> NSPoint {
        let bounds = scrollView.contentView.bounds
        return NSPoint(x: bounds.midX, y: bounds.midY)
    }

    private func updateDocumentSize() {
        guard canvas.imageSize.width > 0, canvas.imageSize.height > 0 else { return }
        let visible = scrollView.contentView.bounds.size
        canvas.frame = NSRect(
            x: 0,
            y: 0,
            width: max(canvas.imageSize.width, visible.width),
            height: max(canvas.imageSize.height, visible.height)
        )
        canvas.needsDisplay = true
    }

    private func centerImage() {
        let clipView = scrollView.contentView
        let visible = clipView.bounds.size
        let document = canvas.bounds.size
        let origin = NSPoint(
            x: max(0, (document.width - visible.width) / 2),
            y: max(0, (document.height - visible.height) / 2)
        )
        clipView.scroll(to: origin)
        scrollView.reflectScrolledClipView(clipView)
    }
}

private final class PannableImageCanvas: NSView {
    weak var scrollView: NSScrollView?
    var image: NSImage? {
        didSet {
            imageSize = image?.size ?? .zero
            needsDisplay = true
        }
    }

    private(set) var imageSize: NSSize = .zero
    private var dragStartWindowPoint: NSPoint?
    private var dragStartBoundsOrigin: NSPoint?
    private var pushedCursor = false

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let image else { return }
        image.draw(
            in: imageRect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        dragStartWindowPoint = event.locationInWindow
        dragStartBoundsOrigin = scrollView?.contentView.bounds.origin
        NSCursor.closedHand.push()
        pushedCursor = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let scrollView,
              let dragStartWindowPoint,
              let dragStartBoundsOrigin
        else { return }

        let current = event.locationInWindow
        let magnification = max(scrollView.magnification, 0.01)
        let target = NSPoint(
            x: dragStartBoundsOrigin.x + (dragStartWindowPoint.x - current.x) / magnification,
            y: dragStartBoundsOrigin.y + (current.y - dragStartWindowPoint.y) / magnification
        )
        let constrained = constrainedOrigin(target, in: scrollView.contentView)
        scrollView.contentView.scroll(to: constrained)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    override func mouseUp(with _: NSEvent) {
        dragStartWindowPoint = nil
        dragStartBoundsOrigin = nil
        if pushedCursor {
            NSCursor.pop()
            pushedCursor = false
        }
    }

    private var imageRect: NSRect {
        NSRect(
            x: max(0, (bounds.width - imageSize.width) / 2),
            y: max(0, (bounds.height - imageSize.height) / 2),
            width: imageSize.width,
            height: imageSize.height
        )
    }

    private func constrainedOrigin(_ origin: NSPoint, in clipView: NSClipView) -> NSPoint {
        NSPoint(
            x: min(max(0, origin.x), max(0, bounds.width - clipView.bounds.width)),
            y: min(max(0, origin.y), max(0, bounds.height - clipView.bounds.height))
        )
    }
}
