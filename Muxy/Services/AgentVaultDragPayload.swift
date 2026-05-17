import AppKit
import UniformTypeIdentifiers

enum AgentVaultDragPayload {
    static let typeIdentifier = "app.muxy.agent-vault-session"
    static let contentType = UTType(exportedAs: typeIdentifier)
    static let contentTypes: [UTType] = [contentType]
    static let pasteboardType = NSPasteboard.PasteboardType(typeIdentifier)
    static let dragMarkerPasteboardType = NSPasteboard.PasteboardType("\(typeIdentifier).active")
    static let routingPasteboardTypes = [
        pasteboardType,
        NSPasteboard.PasteboardType.string,
        NSPasteboard.PasteboardType(UTType.utf8PlainText.identifier),
        NSPasteboard.PasteboardType(UTType.plainText.identifier),
    ]

    private static let dragMarkerMaxAge: TimeInterval = 120

    private static var routingTypeIdentifiers: [String] {
        var seen = Set<String>()
        return [
            NSPasteboard.PasteboardType.string.rawValue,
            UTType.utf8PlainText.identifier,
            UTType.plainText.identifier,
        ].filter { seen.insert($0).inserted }
    }

    static func itemProvider(for session: AgentVaultSession) -> NSItemProvider {
        let provider = NSItemProvider()
        if let data = try? JSONEncoder().encode(session) {
            provider.registerDataRepresentation(forTypeIdentifier: typeIdentifier, visibility: .ownProcess) { completion in
                completion(data, nil)
                return nil
            }
            let routingData = Data(session.displayTitle.utf8)
            for typeIdentifier in routingTypeIdentifiers {
                provider.registerDataRepresentation(forTypeIdentifier: typeIdentifier, visibility: .ownProcess) { completion in
                    completion(routingData, nil)
                    return nil
                }
            }
            mirrorDrag(data: data, title: session.displayTitle)
        }
        provider.suggestedName = session.displayTitle
        return provider
    }

    static func pasteboardItem(for session: AgentVaultSession) -> NSPasteboardItem? {
        guard let data = try? JSONEncoder().encode(session) else { return nil }
        mirrorDrag(data: data, title: session.displayTitle)

        let item = NSPasteboardItem()
        item.setData(data, forType: pasteboardType)
        item.setString(session.displayTitle, forType: .string)
        item.setString(session.displayTitle, forType: NSPasteboard.PasteboardType(UTType.utf8PlainText.identifier))
        item.setString(session.displayTitle, forType: NSPasteboard.PasteboardType(UTType.plainText.identifier))
        item.setString("\(Date().timeIntervalSince1970)", forType: dragMarkerPasteboardType)
        return item
    }

    static func loadSession(
        from providers: [NSItemProvider],
        completion: @escaping @MainActor @Sendable (AgentVaultSession?) -> Void
    ) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(typeIdentifier) }) else {
            return false
        }

        provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
            let session = data.flatMap { try? JSONDecoder().decode(AgentVaultSession.self, from: $0) }
            Task { @MainActor in
                completion(session)
            }
        }
        return true
    }

    static func session(from pasteboard: NSPasteboard) -> AgentVaultSession? {
        if let session = session(fromData: pasteboard.data(forType: pasteboardType)) {
            return session
        }
        return session(fromData: NSPasteboard(name: .drag).data(forType: pasteboardType))
    }

    static func containsSession(in pasteboard: NSPasteboard) -> Bool {
        pasteboard.types?.contains(pasteboardType) == true
    }

    static func containsMirroredSessionDrag(
        in pasteboard: NSPasteboard = NSPasteboard(name: .drag),
        now: Date = Date()
    ) -> Bool {
        guard pasteboard.types?.contains(pasteboardType) == true,
              let rawTimestamp = pasteboard.string(forType: dragMarkerPasteboardType),
              let timestamp = Double(rawTimestamp)
        else { return false }
        return now.timeIntervalSince1970 - timestamp <= dragMarkerMaxAge
    }

    static func clearMirroredSessionDrag() {
        NSPasteboard(name: .drag).clearContents()
    }

    private static func session(fromData data: Data?) -> AgentVaultSession? {
        data.flatMap { try? JSONDecoder().decode(AgentVaultSession.self, from: $0) }
    }

    private static func mirrorDrag(data: Data, title: String) {
        let pasteboard = NSPasteboard(name: .drag)
        pasteboard.addTypes(routingPasteboardTypes + [dragMarkerPasteboardType], owner: nil)
        pasteboard.setData(data, forType: pasteboardType)
        pasteboard.setString(title, forType: .string)
        pasteboard.setString("\(Date().timeIntervalSince1970)", forType: dragMarkerPasteboardType)
    }
}
