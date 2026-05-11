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
        let safeSessionName = sanitizedSessionName(sessionName)
        let escapedPath = ShellCommandEscaping.escape(remotePath)
        let escapedCommand = ShellCommandEscaping.escape(remoteCommand)
        let displayName = ShellCommandEscaping.escape(displayName(sessionName: safeSessionName))
        let dimStyle = "fg=colour238,bg=default"
        let currentStyle = "fg=colour240,bg=default"
        let windowOption = "tmux set-window-option -t \(safeSessionName)"
        let createSessionCommand = [
            "tmux has-session -t \(safeSessionName) 2>/dev/null",
            "tmux new-session -d -s \(safeSessionName) -c \(escapedPath) \(escapedCommand)",
        ].joined(separator: " || ")
        let tmuxCommand = [
            createSessionCommand,
            "tmux set-option -t \(safeSessionName) mouse on",
            "tmux set-option -t \(safeSessionName) history-limit 1000000",
            "tmux set-option -t \(safeSessionName) status-style \(dimStyle)",
            "tmux set-option -t \(safeSessionName) status-left \(displayName)",
            "\(windowOption) window-status-style \(dimStyle)",
            "\(windowOption) window-status-current-style \(currentStyle)",
            "exec tmux attach-session -t \(safeSessionName)",
        ].joined(separator: "; ")
        let fallbackCommand = ["cd -- \(escapedPath)", remoteCommand].joined(separator: " && ")
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
