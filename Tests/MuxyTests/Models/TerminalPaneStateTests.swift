import Foundation
import Testing

@testable import Muxy

@Suite("TerminalPaneState")
@MainActor
struct TerminalPaneStateTests {
    @Test("remote process exit preserves tab and marks disconnected")
    func remoteProcessExitPreservesTab() {
        let state = TerminalPaneState(projectPath: "/srv/project", remoteHost: "dev")

        let action = state.handleProcessExit()

        #expect(action == .preserveTab)
        #expect(state.remoteConnectionState == .disconnected)
    }

    @Test("local process exit closes tab")
    func localProcessExitClosesTab() {
        let state = TerminalPaneState(projectPath: "/tmp/project", startupCommand: "vim")

        let action = state.handleProcessExit()

        #expect(action == .closeTab)
        #expect(state.remoteConnectionState == .connected)
    }

    @Test("remote startup command uses worktree identity")
    func remoteStartupCommandUsesWorktreeIdentity() {
        let projectID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let worktreeID = UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!
        let sessionID = UUID(uuidString: "12345678-1234-5678-1234-567812345678")!
        let state = TerminalPaneState(
            sessionID: sessionID,
            projectPath: "/srv/project",
            remoteHost: "dev"
        )

        let command = state.resolvedStartupCommand(
            worktreeKey: WorktreeKey(projectID: projectID, worktreeID: worktreeID)
        )

        #expect(command?.contains("muxy-11111111-aaaaaaaa-12345678-1234-5678-1234-567812345678") == true)
        #expect(command?.contains("tmux new-session -A") == true)
    }
}
