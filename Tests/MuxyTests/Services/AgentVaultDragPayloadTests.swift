import AppKit
import Testing

@testable import Muxy

@Suite("AgentVaultDragPayload")
struct AgentVaultDragPayloadTests {
    @Test("pasteboard item carries session payload and mirror marker")
    func pasteboardItemCarriesSessionPayload() {
        let session = AgentVaultSession(
            id: "claude:test",
            agent: .claude,
            sessionID: "test",
            title: "Test session",
            cwd: "/tmp/project",
            gitBranch: "dev",
            model: "sonnet",
            modified: Date(timeIntervalSince1970: 1_700_000_000),
            transcriptPath: "/tmp/project/session.jsonl",
            resumeCommand: "claude --resume test"
        )

        guard let item = AgentVaultDragPayload.pasteboardItem(for: session) else {
            Issue.record("Expected pasteboard item")
            return
        }

        guard let data = item.data(forType: AgentVaultDragPayload.pasteboardType) else {
            Issue.record("Expected encoded session data")
            return
        }

        let decodedSession = try? JSONDecoder().decode(AgentVaultSession.self, from: data)
        #expect(decodedSession == session)
        #expect(item.string(forType: .string) == session.displayTitle)
        #expect(item.string(forType: AgentVaultDragPayload.dragMarkerPasteboardType) != nil)

        AgentVaultDragPayload.clearMirroredSessionDrag()
    }

    @Test("fresh mirror marker is recognized")
    func freshMirrorMarkerIsRecognized() {
        let pasteboard = NSPasteboard(name: .init("muxy-agent-vault-test-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setData(Data(), forType: AgentVaultDragPayload.pasteboardType)
        pasteboard.setString("\(Date().timeIntervalSince1970)", forType: AgentVaultDragPayload.dragMarkerPasteboardType)

        #expect(AgentVaultDragPayload.containsMirroredSessionDrag(in: pasteboard))

        pasteboard.clearContents()
    }
}
