import Foundation

enum ShellCommandEscaping {
    static func escape(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

enum RemoteProjectSessionCommand {
    static func make(sshDestination: String, remotePath: String) -> String {
        make(
            sshDestination: sshDestination,
            remotePath: remotePath,
            sessionName: fallbackSessionName(remotePath: remotePath),
            remoteCommand: "exec ${SHELL:-/bin/zsh} -l"
        )
    }

    static func make(
        sshDestination: String,
        remotePath: String,
        sessionName: String,
        remoteCommand: String
    ) -> String {
        let command = remoteSessionCommand(
            remotePath: remotePath,
            sessionName: sessionName,
            remoteCommand: remoteCommand
        )
        let sshCommand = [
            "ssh",
            "-t",
            "-o ServerAliveInterval=15",
            "-o ServerAliveCountMax=3",
            "-o TCPKeepAlive=yes",
            ShellCommandEscaping.escape(sshDestination),
            ShellCommandEscaping.escape(command),
        ].joined(separator: " ")
        let retryScript = """
        while true; do
        \(sshCommand)
        status=$?
        if [ "$status" -ne 255 ]; then exit "$status"; fi
        printf '\\nMuxy remote connection lost. Reconnecting in 3 seconds...\\n' >&2
        sleep 3
        done
        """
        return "exec /bin/sh -c \(ShellCommandEscaping.escape(retryScript))"
    }

    static func sessionName(projectID: UUID? = nil, worktreeID: UUID? = nil, terminalSessionID: UUID) -> String {
        let parts = [
            "muxy",
            projectID.map { shortID($0) },
            worktreeID.map { shortID($0) },
            terminalSessionID.uuidString.lowercased(),
        ].compactMap(\.self)
        return sanitizedSessionName(parts.joined(separator: "-"))
    }

    private static func remoteSessionCommand(remotePath: String, sessionName: String, remoteCommand: String) -> String {
        let escapedSession = ShellCommandEscaping.escape(sessionName)
        let displayName = ShellCommandEscaping.escape(displayName(sessionName: sessionName))
        let tmuxCommand = [
            "tmux has-session -t \(escapedSession) 2>/dev/null || tmux new-session -d -s \(escapedSession) -c \(ShellCommandEscaping.escape(remotePath)) \(ShellCommandEscaping.escape(remoteCommand))",
            "tmux set-option -t \(escapedSession) mouse on",
            "tmux set-option -t \(escapedSession) history-limit 1000000",
            "tmux set-option -t \(escapedSession) status-style \(ShellCommandEscaping.escape("fg=colour238,bg=default"))",
            "tmux set-option -t \(escapedSession) status-left \(displayName)",
            "tmux set-window-option -t \(escapedSession) window-status-style \(ShellCommandEscaping.escape("fg=colour238,bg=default"))",
            "tmux set-window-option -t \(escapedSession) window-status-current-style \(ShellCommandEscaping.escape("fg=colour240,bg=default"))",
            "exec tmux attach-session -t \(escapedSession)",
        ].joined(separator: "; ")
        let fallbackCommand = "cd -- \(ShellCommandEscaping.escape(remotePath)) && \(remoteCommand)"
        return "if command -v tmux >/dev/null 2>&1; then \(tmuxCommand); else \(fallbackCommand); fi"
    }

    private static func displayName(sessionName: String) -> String {
        let suffix = sessionName.split(separator: "-").last.map(String.init) ?? sessionName
        return "muxy-\(suffix.suffix(4)) "
    }

    private static func fallbackSessionName(remotePath: String) -> String {
        sanitizedSessionName("muxy-\(remotePath)")
    }

    private static func shortID(_ id: UUID) -> String {
        String(id.uuidString.lowercased().prefix(8))
    }

    private static func sanitizedSessionName(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let mapped = raw.lowercased().unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let collapsed = String(mapped)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        let trimmed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        let name = trimmed.isEmpty ? "muxy" : trimmed
        return String(name.prefix(80))
    }
}
