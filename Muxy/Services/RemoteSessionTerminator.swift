import Foundation
import os

private let remoteSessionTerminatorLogger = Logger(subsystem: "app.muxy", category: "RemoteSessionTerminator")

enum RemoteSessionTerminator {
    static func kill(_ cleanup: RemoteSessionCleanup) {
        Task.detached {
            do {
                _ = try await GitProcessRunner.runRemoteShell(
                    sshDestination: cleanup.sshDestination,
                    command: "tmux kill-session -t \(ShellCommandEscaping.escape(cleanup.sessionName)) 2>/dev/null || true",
                    signpostName: "remote-tmux-kill"
                )
            } catch {
                remoteSessionTerminatorLogger.error(
                    "Failed to kill tmux session \(cleanup.sessionName) on \(cleanup.sshDestination): \(error.localizedDescription)"
                )
            }
        }
    }
}
