import Foundation
import os

struct RemoteTerminalSessionReference: Hashable {
    let worktreeKey: WorktreeKey
    let sessionID: UUID

    var sessionName: String {
        RemoteTerminalSessionName.make(worktreeKey: worktreeKey, sessionID: sessionID)
    }
}

enum RemoteTerminalSessionTerminationCommand {
    static func make(sessionName: String) -> String {
        let name = RemoteTerminalSessionName.sanitized(sessionName)
        return "tmux kill-session -t \(ShellEscaper.escape("=\(name)")) 2>/dev/null || true"
    }
}

@MainActor
protocol RemoteTerminalSessionTerminating: AnyObject {
    func terminate(_ reference: RemoteTerminalSessionReference, destination: SSHDestination)
}

private let remoteSessionLogger = Logger(subsystem: "app.muxy", category: "RemoteTerminalSessionTerminator")

@MainActor
final class RemoteTerminalSessionTerminator: RemoteTerminalSessionTerminating {
    static let shared = RemoteTerminalSessionTerminator()

    func terminate(_ reference: RemoteTerminalSessionReference, destination: SSHDestination) {
        let sessionName = reference.sessionName
        Task {
            do {
                _ = try await SSHCommandRunner.run(
                    destination: destination,
                    remoteCommand: RemoteTerminalSessionTerminationCommand.make(sessionName: sessionName)
                )
            } catch {
                remoteSessionLogger.error(
                    "Failed to kill tmux session \(sessionName) on \(destination.target): \(error.localizedDescription)"
                )
            }
        }
    }
}
