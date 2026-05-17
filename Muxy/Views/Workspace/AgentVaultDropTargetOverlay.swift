import AppKit
import SwiftUI

struct AgentVaultDropTargetOverlay: NSViewRepresentable {
    let onHover: (DropZone?) -> Void
    let onDrop: (AgentVaultSession, DropZone) -> Bool

    func makeNSView(context _: Context) -> AgentVaultDropTargetNSView {
        let view = AgentVaultDropTargetNSView()
        view.onHover = onHover
        view.onDrop = onDrop
        return view
    }

    func updateNSView(_ nsView: AgentVaultDropTargetNSView, context _: Context) {
        nsView.onHover = onHover
        nsView.onDrop = onDrop
    }
}

final class AgentVaultDropTargetNSView: NSView {
    var onHover: (DropZone?) -> Void = { _ in }
    var onDrop: (AgentVaultSession, DropZone) -> Bool = { _, _ in false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes(AgentVaultDragPayload.routingPasteboardTypes)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        shouldCaptureHitTest() ? super.hitTest(point) : nil
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        updateDrag(sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        updateDrag(sender)
    }

    override func draggingExited(_: (any NSDraggingInfo)?) {
        onHover(nil)
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        hasSession(sender)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        defer {
            onHover(nil)
            AgentVaultDragPayload.clearMirroredSessionDrag()
        }
        guard hasSession(sender),
              let session = AgentVaultDragPayload.session(from: sender.draggingPasteboard)
        else { return false }
        return onDrop(session, dropZone(from: sender))
    }

    override func concludeDragOperation(_: (any NSDraggingInfo)?) {
        onHover(nil)
    }

    private func updateDrag(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard hasSession(sender) else {
            onHover(nil)
            return []
        }
        onHover(dropZone(from: sender))
        return .move
    }

    private func hasSession(_ sender: any NSDraggingInfo) -> Bool {
        AgentVaultDragPayload.containsSession(in: sender.draggingPasteboard) || hasMirroredSessionDrag()
    }

    private func shouldCaptureHitTest() -> Bool {
        guard hasMirroredSessionDrag() else { return false }
        guard let eventType = NSApp.currentEvent?.type else { return true }
        switch eventType {
        case .leftMouseUp,
             .rightMouseUp,
             .otherMouseUp,
             .mouseMoved,
             .cursorUpdate,
             .leftMouseDragged,
             .rightMouseDragged,
             .otherMouseDragged:
            return true
        default:
            return false
        }
    }

    private func hasMirroredSessionDrag() -> Bool {
        AgentVaultDragPayload.containsMirroredSessionDrag()
    }

    private func dropZone(from sender: any NSDraggingInfo) -> DropZone {
        let point = convert(sender.draggingLocation, from: nil)
        guard bounds.width > 0, bounds.height > 0 else { return .center }
        let relX = (point.x - bounds.minX) / bounds.width
        let relY = (point.y - bounds.minY) / bounds.height
        let edgeThreshold: CGFloat = 0.3

        if relX < edgeThreshold {
            return .left
        }
        if relX > 1 - edgeThreshold {
            return .right
        }
        if relY < edgeThreshold {
            return .bottom
        }
        if relY > 1 - edgeThreshold {
            return .top
        }
        return .center
    }
}
