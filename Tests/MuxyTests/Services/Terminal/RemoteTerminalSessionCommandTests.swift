import Foundation
import Testing

@testable import Muxy

@Suite("Remote terminal persistence")
struct RemoteTerminalSessionCommandTests {
    private let key = WorktreeKey(
        projectID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
        worktreeID: UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!
    )
    private let sessionID = UUID(uuidString: "12345678-1234-5678-1234-567812345678")!

    @Test("Session names are stable and include project, worktree, and session identities")
    func stableSessionName() {
        let first = RemoteTerminalSessionName.make(worktreeKey: key, sessionID: sessionID)
        let second = RemoteTerminalSessionName.make(worktreeKey: key, sessionID: sessionID)

        #expect(first == "muxy-11111111-aaaaaaaa-12345678-1234-5678-1234-567812345678")
        #expect(second == first)
        #expect(first.count <= 80)
    }

    @Test("Session names sanitize shell and tmux metacharacters")
    func sanitizedSessionName() {
        let name = RemoteTerminalSessionName.sanitized(" --Prod; $(touch /tmp/pwn) 'name' ")

        #expect(name == "prod-touch-tmp-pwn-name")
        #expect(!name.contains(";"))
        #expect(!name.contains("$"))
        #expect(!name.contains("'"))
    }

    @Test("Reconnect policy has the required bounded increasing backoff")
    func reconnectBackoff() {
        #expect(RemoteTerminalReconnectPolicy.baseDelays == [5, 15, 30, 60, 120, 300])
        #expect(RemoteTerminalReconnectPolicy.baseDelay(forRetry: 0) == nil)
        #expect(RemoteTerminalReconnectPolicy.baseDelay(forRetry: 7) == nil)
        #expect(RemoteTerminalReconnectPolicy.jitteredDelay(forRetry: 1, entropy: 0) == 4)
        #expect(RemoteTerminalReconnectPolicy.jitteredDelay(forRetry: 1, entropy: 2) == 6)
        #expect(RemoteTerminalReconnectPolicy.jitteredDelay(forRetry: 6, entropy: 0) == 225)
        #expect(RemoteTerminalReconnectPolicy.jitteredDelay(forRetry: 6, entropy: 150) == 375)
    }

    @Test("Reconnect policy retries only transport failures within both limits")
    func retryFiltering() {
        #expect(RemoteTerminalReconnectPolicy.shouldRetry(exitStatus: 255, completedRetries: 0, immediateFailures: 0))
        #expect(!RemoteTerminalReconnectPolicy.shouldRetry(exitStatus: 1, completedRetries: 0, immediateFailures: 0))
        #expect(!RemoteTerminalReconnectPolicy.shouldRetry(exitStatus: 255, completedRetries: 6, immediateFailures: 0))
        #expect(!RemoteTerminalReconnectPolicy.shouldRetry(exitStatus: 255, completedRetries: 1, immediateFailures: 2))
    }

    @Test("Remote command creates once, configures tmux, attaches, and has a direct fallback")
    func tmuxCommand() {
        let command = RemoteTerminalSessionCommand.makeRemoteCommand(
            destination: SSHDestination(host: "prod", environment: ["LANG": "C.UTF-8"]),
            workingDirectory: "~/code/my project;still-safe",
            sessionName: "muxy-test",
            creationCommand: "/bin/sh -lc 'exec \"${SHELL:-/bin/sh}\" -l'",
            fallbackCommand: "exec \"${SHELL:-/bin/sh}\" -l"
        )

        #expect(command.contains("export LANG=C.UTF-8"))
        #expect(command.contains("export TERM=xterm-256color"))
        #expect(command.contains("if ! tmux has-session -t '=muxy-test'"))
        #expect(command.contains("tmux new-session -d -s muxy-test"))
        #expect(command.contains("/bin/sh -lc"))
        #expect(command.contains("history-limit 1000000"))
        #expect(command.contains("mouse on"))
        #expect(command.contains("status-style fg=colour238,bg=default,nobold,noitalics,nounderscore,noreverse"))
        #expect(command.contains("status-left-style fg=colour238,bg=default,nobold,noitalics,nounderscore,noreverse"))
        #expect(command.contains("status-right ''"))
        #expect(command.contains("status-right-style fg=colour238,bg=default,nobold,noitalics,nounderscore,noreverse"))
        #expect(command.contains("message-style fg=colour240,bg=default,nobold,noitalics,nounderscore,noreverse"))
        #expect(command.contains("allow-passthrough on"))
        #expect(command.contains("exec tmux attach-session -t '=muxy-test'"))
        #expect(command.contains("else export LANG=C.UTF-8; cd ~/"))
        #expect(command.contains("'code/my project;still-safe'"))
    }

    @Test("Startup command is confined to the create branch and safely escaped")
    func startupRunsOnlyOnCreate() {
        let payload = "printf 'created'; touch /tmp/pwn"
        let command = RemoteTerminalSessionCommand.makeRemoteCommand(
            destination: SSHDestination(host: "prod"),
            workingDirectory: "~",
            sessionName: "muxy-test",
            creationCommand: payload,
            fallbackCommand: "exec \"${SHELL:-/bin/sh}\" -l"
        )

        #expect(command.components(separatedBy: "touch /tmp/pwn").count == 2)
        #expect(command.contains("'\\''created'\\''"))
        #expect(!command.hasSuffix(payload))
    }

    @Test("Local retry wrapper contains exact SSH options, status filter, limits, and staggering")
    func retryWrapper() {
        let destination = SSHDestination(
            host: "prod",
            port: 2222,
            user: "deploy",
            identityFile: "/tmp/key with spaces"
        )
        let command = RemoteTerminalSessionCommand.make(
            destination: destination,
            workingDirectory: "~",
            sessionName: "muxy-test",
            creationCommand: "exec sh -l",
            fallbackCommand: "exec sh -l"
        )

        #expect(command.contains("ConnectTimeout=15"))
        #expect(command.contains("ConnectionAttempts=1"))
        #expect(command.contains("ServerAliveInterval=15"))
        #expect(command.contains("ServerAliveCountMax=3"))
        #expect(command.contains("TCPKeepAlive=yes"))
        #expect(command.contains("ControlMaster=no"))
        #expect(command.contains("if [ \"$status\" -ne 255 ]"))
        #expect(command.contains("if [ \"$attempt\" -gt 6 ]"))
        #expect(command.contains("if [ \"$immediate_failures\" -ge 2 ]"))
        #expect(command.contains("reserve_retry"))
        #expect(command.contains("mkdir \"$lock_dir\""))
        #expect(command.contains("Reconnecting in %s seconds"))
        #expect(!command.contains("Reconnecting in 3 seconds"))
    }

    @Test("Retry coordination key is stable per destination and distinct across destinations")
    func destinationCoordination() {
        let a1 = RemoteTerminalSessionCommand.reconnectScript(
            sshCommand: "ssh a",
            destination: SSHDestination(host: "prod", user: "deploy")
        )
        let a2 = RemoteTerminalSessionCommand.reconnectScript(
            sshCommand: "ssh a",
            destination: SSHDestination(host: "prod", user: "deploy")
        )
        let b = RemoteTerminalSessionCommand.reconnectScript(
            sshCommand: "ssh b",
            destination: SSHDestination(host: "prod", port: 2222, user: "deploy")
        )

        #expect(a1 == a2)
        #expect(a1 != b)
    }

    @Test("Termination command sanitizes its target and tolerates missing sessions")
    func terminationCommand() {
        let command = RemoteTerminalSessionTerminationCommand.make(
            sessionName: "muxy-safe; touch /tmp/pwn"
        )

        #expect(command == "tmux kill-session -t '=muxy-safe-touch-tmp-pwn' 2>/dev/null || true")
    }
}
