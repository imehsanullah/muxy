import Foundation
import Testing

@testable import Muxy

@Suite("RemoteProjectSessionCommand")
struct RemoteProjectSessionCommandTests {
    @Test("command uses SSH keepalives, retry loop, and tmux session")
    func commandUsesKeepalivesRetryLoopAndTmux() {
        let projectID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let worktreeID = UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!
        let sessionID = UUID(uuidString: "12345678-1234-5678-1234-567812345678")!
        let sessionName = RemoteProjectSessionCommand.sessionName(
            projectID: projectID,
            worktreeID: worktreeID,
            terminalSessionID: sessionID
        )

        let command = RemoteProjectSessionCommand.make(
            sshDestination: "dev@example.com",
            remotePath: "/srv/project",
            sessionName: sessionName,
            remoteCommand: "exec ${SHELL:-/bin/zsh} -l"
        )

        #expect(command.contains("ServerAliveInterval=15"))
        #expect(command.contains("ServerAliveCountMax=3"))
        #expect(command.contains("TCPKeepAlive=yes"))
        #expect(command.contains("while true; do"))
        #expect(command.contains("status=$?"))
        #expect(command.contains("tmux has-session"))
        #expect(command.contains("tmux new-session -d"))
        #expect(command.contains("tmux attach-session"))
        #expect(command.contains(sessionName))
    }

    @Test("command enables tmux mouse scrollback")
    func commandEnablesTmuxMouseScrollback() {
        let command = RemoteProjectSessionCommand.make(
            sshDestination: "dev@example.com",
            remotePath: "/srv/project",
            sessionName: "muxy-test",
            remoteCommand: "exec ${SHELL:-/bin/zsh} -l"
        )

        #expect(command.contains("tmux set-option -t '\\''muxy-test'\\'' mouse on"))
        #expect(command.contains("tmux set-option -t '\\''muxy-test'\\'' history-limit 1000000"))
    }

    @Test("command styles tmux status bar with default background and grey text")
    func commandStylesTmuxStatusBar() {
        let command = RemoteProjectSessionCommand.make(
            sshDestination: "dev@example.com",
            remotePath: "/srv/project",
            sessionName: "muxy-project-worktree-12345678-1234-5678-1234-567812345678",
            remoteCommand: "exec ${SHELL:-/bin/zsh} -l"
        )

        #expect(command.contains("status-style '\\''fg=colour238,bg=default'\\''"))
        #expect(command.contains("status-left '\\''muxy-5678 '\\''"))
        #expect(command.contains("window-status-style '\\''fg=colour238,bg=default'\\''"))
        #expect(command.contains("window-status-current-style '\\''fg=colour240,bg=default'\\''"))
    }

    @Test("command falls back to plain remote shell when tmux is missing")
    func commandFallsBackToPlainRemoteShellWithoutTmux() {
        let command = RemoteProjectSessionCommand.make(
            sshDestination: "dev@example.com",
            remotePath: "/srv/project",
            sessionName: "muxy-test",
            remoteCommand: "exec ${SHELL:-/bin/zsh} -l"
        )

        #expect(command.contains("if command -v tmux >/dev/null 2>&1; then tmux has-session"))
        #expect(command.contains("else cd -- '\\''/srv/project'\\'' && exec ${SHELL:-/bin/zsh} -l; fi"))
    }

    @Test("session name is stable and sanitized")
    func sessionNameIsStableAndSanitized() {
        let projectID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let worktreeID = UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!
        let sessionID = UUID(uuidString: "12345678-1234-5678-1234-567812345678")!

        let first = RemoteProjectSessionCommand.sessionName(
            projectID: projectID,
            worktreeID: worktreeID,
            terminalSessionID: sessionID
        )
        let second = RemoteProjectSessionCommand.sessionName(
            projectID: projectID,
            worktreeID: worktreeID,
            terminalSessionID: sessionID
        )

        #expect(first == second)
        #expect(first == "muxy-11111111-aaaaaaaa-12345678-1234-5678-1234-567812345678")
    }
}
