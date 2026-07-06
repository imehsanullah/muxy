import Foundation
import Testing

@testable import Muxy

@Suite("Remote terminal connection state")
@MainActor
struct TerminalPaneRemoteConnectionTests {
    @Test("Reconnect transitions are deduplicated")
    func reconnectTransitions() {
        let pane = TerminalPaneState(projectPath: "/repo")
        pane.markRemoteDisconnected()

        #expect(pane.remoteConnectionState == .disconnected)
        let generation = pane.beginRemoteReconnect()
        #expect(generation != nil)
        #expect(pane.remoteConnectionState == .reconnecting)
        #expect(pane.beginRemoteReconnect() == nil)

        pane.finishRemoteReconnect(generation: generation!)
        #expect(pane.remoteConnectionState == .connected)
    }

    @Test("Stale reconnect completion cannot overwrite a newer disconnect")
    func staleReconnectCompletion() {
        let pane = TerminalPaneState(projectPath: "/repo")
        pane.markRemoteDisconnected()
        let staleGeneration = pane.beginRemoteReconnect()!

        pane.markRemoteDisconnected()
        pane.finishRemoteReconnect(generation: staleGeneration)

        #expect(pane.remoteConnectionState == .disconnected)
    }

    @Test("Remote session identity is immutable")
    func sessionIdentity() {
        let id = UUID()
        let pane = TerminalPaneState(remoteSessionID: id, projectPath: "/repo")

        pane.markRemoteDisconnected()
        _ = pane.beginRemoteReconnect()

        #expect(pane.remoteSessionID == id)
    }
}
