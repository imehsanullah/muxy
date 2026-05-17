import AppKit
import SwiftUI

struct AgentVaultSessionDragView: NSViewRepresentable {
    let session: AgentVaultSession
    let canResume: Bool
    let onDoubleClick: () -> Void

    func makeNSView(context _: Context) -> AgentVaultSessionDragNSView {
        let view = AgentVaultSessionDragNSView()
        view.session = session
        view.canResume = canResume
        view.onDoubleClick = onDoubleClick
        return view
    }

    func updateNSView(_ nsView: AgentVaultSessionDragNSView, context _: Context) {
        nsView.session = session
        nsView.canResume = canResume
        nsView.onDoubleClick = onDoubleClick
    }
}

final class AgentVaultSessionDragNSView: NSView, NSDraggingSource {
    var session: AgentVaultSession?
    var canResume = false
    var onDoubleClick: () -> Void = {}

    private var dragStartEvent: NSEvent?

    override var acceptsFirstResponder: Bool { false }

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point),
              let event = NSApp.currentEvent,
              event.type == .leftMouseDown || event.type == .leftMouseDragged
        else { return nil }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        guard event.clickCount < 2 else {
            if canResume {
                onDoubleClick()
            }
            return
        }
        dragStartEvent = event
    }

    override func mouseDragged(with event: NSEvent) {
        guard let session,
              dragStartEvent != nil,
              let item = AgentVaultDragPayload.pasteboardItem(for: session)
        else { return }
        dragStartEvent = nil

        let draggingItem = NSDraggingItem(pasteboardWriter: item)
        let image = dragImage(for: session)
        let origin = CGPoint(x: 0, y: (bounds.height - image.size.height) / 2)
        draggingItem.setDraggingFrame(CGRect(origin: origin, size: image.size), contents: image)
        let dragSession = beginDraggingSession(with: [draggingItem], event: event, source: self)
        dragSession.animatesToStartingPositionsOnCancelOrFail = false
    }

    override func mouseUp(with _: NSEvent) {
        dragStartEvent = nil
    }

    func draggingSession(
        _: NSDraggingSession,
        sourceOperationMaskFor _: NSDraggingContext
    ) -> NSDragOperation {
        .move
    }

    func draggingSession(_: NSDraggingSession, endedAt _: NSPoint, operation _: NSDragOperation) {
        AgentVaultDragPayload.clearMirroredSessionDrag()
        dragStartEvent = nil
    }

    private func dragImage(for session: AgentVaultSession) -> NSImage {
        let width = max(min(bounds.width, 280), 160)
        let height = max(min(bounds.height, 34), 26)
        let size = NSSize(width: width, height: height)
        let image = NSImage(size: size)
        image.lockFocus()

        let rect = NSRect(origin: .zero, size: size)
        NSColor.windowBackgroundColor.withAlphaComponent(0.94).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7).fill()
        NSColor.separatorColor.withAlphaComponent(0.45).setStroke()
        NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7).stroke()

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ]
        let textRect = rect.insetBy(dx: 10, dy: 6)
        session.displayTitle.draw(in: textRect, withAttributes: attributes)

        image.unlockFocus()
        return image
    }
}
