import Foundation

enum RemoteTerminalSessionName {
    static func make(worktreeKey: WorktreeKey, sessionID: UUID) -> String {
        sanitized([
            "muxy",
            shortID(worktreeKey.projectID),
            shortID(worktreeKey.worktreeID),
            sessionID.uuidString.lowercased(),
        ].joined(separator: "-"))
    }

    static func sanitized(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let mapped = raw.lowercased().unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let collapsed = String(mapped)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        let trimmed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        return String((trimmed.isEmpty ? "muxy" : trimmed).prefix(80))
    }

    private static func shortID(_ id: UUID) -> String {
        String(id.uuidString.lowercased().prefix(8))
    }
}

enum RemoteTerminalReconnectPolicy {
    static let baseDelays = [5, 15, 30, 60, 120, 300]
    static let immediateFailureLimit = 2
    static let immediateFailureDuration = 3

    static func baseDelay(forRetry retry: Int) -> Int? {
        guard retry > 0, retry <= baseDelays.count else { return nil }
        return baseDelays[retry - 1]
    }

    static func jitteredDelay(forRetry retry: Int, entropy: UInt64) -> Int? {
        guard let base = baseDelay(forRetry: retry) else { return nil }
        let spread = max(base / 4, 1)
        let range = UInt64(spread * 2 + 1)
        let offset = Int(entropy % range) - spread
        return max(base + offset, 1)
    }

    static func shouldRetry(exitStatus: Int32, completedRetries: Int, immediateFailures: Int) -> Bool {
        exitStatus == 255
            && completedRetries < baseDelays.count
            && immediateFailures < immediateFailureLimit
    }
}

enum RemoteTerminalSessionCommand {
    static func make(
        destination: SSHDestination,
        workingDirectory: String,
        sessionName: String,
        creationCommand: String,
        fallbackCommand: String
    ) -> String {
        let remoteCommand = makeRemoteCommand(
            destination: destination,
            workingDirectory: workingDirectory,
            sessionName: sessionName,
            creationCommand: creationCommand,
            fallbackCommand: fallbackCommand
        )
        let sshArguments = destination.connectionArguments
            + SSHDestination.persistentTerminalOptions
            + ["-tt", destination.target, "--", remoteCommand]
        let sshCommand = (["/usr/bin/ssh"] + sshArguments.map(ShellEscaper.escape))
            .joined(separator: " ")
        return "/bin/sh -c \(ShellEscaper.escape(reconnectScript(sshCommand: sshCommand, destination: destination)))"
    }

    static func makeRemoteCommand(
        destination: SSHDestination,
        workingDirectory: String,
        sessionName: String,
        creationCommand: String,
        fallbackCommand: String
    ) -> String {
        let name = RemoteTerminalSessionName.sanitized(sessionName)
        let session = ShellEscaper.escape(name)
        let target = ShellEscaper.escape("=\(name)")
        let path = RemoteCommandBuilder.quoteRemotePath(workingDirectory)
        let command = ShellEscaper.escape(creationCommand)
        let label = ShellEscaper.escape("muxy-\(name.suffix(4)) ")
        let dimStyle = "fg=colour238,bg=default"
        let activeStyle = "fg=colour240,bg=default"
        var tmuxEnvironment = destination.environment
        tmuxEnvironment.removeValue(forKey: "TERM")
        let persistentEnvironment = RemoteCommandBuilder.environmentPrefix(tmuxEnvironment)
        let fallbackEnvironment = RemoteCommandBuilder.environmentPrefix(destination.environment)
        let fallback = fallbackEnvironment
            + RemoteCommandBuilder.changeDirectoryPrefix(workingDirectory)
            + fallbackCommand
        let tmuxCommands = [
            "if ! tmux has-session -t \(target) 2>/dev/null; then tmux new-session -d -s \(session) -c \(path) \(command); fi",
            "tmux set-option -t \(target) mouse on",
            "tmux set-option -t \(target) history-limit 1000000",
            "tmux set-option -t \(target) status-style \(dimStyle)",
            "tmux set-option -t \(target) status-left \(label)",
            "tmux set-window-option -t \(target) allow-passthrough on 2>/dev/null || true",
            "tmux set-window-option -t \(target) window-status-style \(dimStyle)",
            "tmux set-window-option -t \(target) window-status-current-style \(activeStyle)",
            "exec tmux attach-session -t \(target)",
        ].joined(separator: "; ")
        return persistentEnvironment
            + "export TERM=xterm-256color; if command -v tmux >/dev/null 2>&1; then "
            + tmuxCommands
            + "; else \(fallback); fi"
    }

    static func reconnectScript(sshCommand: String, destination: SSHDestination) -> String {
        let coordinationKey = stableHash(destination.connectionCoordinationIdentity)
        return """
        state_dir="${TMPDIR:-/tmp}/muxy-remote-reconnect"
        lock_dir="$state_dir/\(coordinationKey).lock"
        next_file="$state_dir/\(coordinationKey).next"
        attempt=0
        immediate_failures=0
        mkdir -p "$state_dir" 2>/dev/null || true

        acquire_lock() {
        while ! mkdir "$lock_dir" 2>/dev/null; do
        lock_pid=$(cat "$lock_dir/pid" 2>/dev/null || true)
        if [ -n "$lock_pid" ] && ! kill -0 "$lock_pid" 2>/dev/null; then
        rm -rf "$lock_dir" 2>/dev/null || true
        continue
        fi
        sleep 1
        done
        printf '%s\\n' "$$" > "$lock_dir/pid" 2>/dev/null || true
        }

        release_lock() {
        rm -f "$lock_dir/pid" 2>/dev/null || true
        rmdir "$lock_dir" 2>/dev/null || true
        }

        delay_for_attempt() {
        case "$1" in
        1) base=5 ;;
        2) base=15 ;;
        3) base=30 ;;
        4) base=60 ;;
        5) base=120 ;;
        *) base=300 ;;
        esac
        spread=$((base / 4)); if [ "$spread" -lt 1 ]; then spread=1; fi
        range=$((spread * 2 + 1))
        offset=$((($(date +%s) + $$ + $1 * 17) % range - spread))
        delay=$((base + offset)); if [ "$delay" -lt 1 ]; then delay=1; fi
        printf '%s\\n' "$delay"
        }

        reserve_retry() {
        acquire_lock
        now=$(date +%s)
        next=$(cat "$next_file" 2>/dev/null || printf '0')
        case "$next" in ''|*[!0-9]*) next=0 ;; esac
        if [ "$next" -lt "$now" ]; then next=$now; fi
        scheduled=$((next + $1))
        printf '%s\\n' "$scheduled" > "$next_file" 2>/dev/null || true
        release_lock
        wait_seconds=$((scheduled - now)); if [ "$wait_seconds" -lt 1 ]; then wait_seconds=1; fi
        printf '%s\\n' "$wait_seconds"
        }

        while true; do
        started_at=$(date +%s)
        \(sshCommand)
        status=$?
        finished_at=$(date +%s)
        if [ "$status" -ne 255 ]; then exit "$status"; fi
        attempt=$((attempt + 1))
        duration=$((finished_at - started_at))
        if [ "$duration" -le 3 ]; then immediate_failures=$((immediate_failures + 1)); else immediate_failures=0; fi
        if [ "$immediate_failures" -ge 2 ]; then
        printf '\\nMuxy stopped automatic reconnect after repeated immediate SSH failures.\\n' >&2
        printf 'Check authentication, host key, rate limits, or server access, then use Reconnect.\\n' >&2
        exit "$status"
        fi
        if [ "$attempt" -gt 6 ]; then
        printf '\\nMuxy stopped automatic reconnect after repeated SSH failures. Use Reconnect when the server is ready.\\n' >&2
        exit "$status"
        fi
        delay=$(delay_for_attempt "$attempt")
        wait_seconds=$(reserve_retry "$delay")
        printf '\\nMuxy remote connection lost. Reconnecting in %s seconds...\\n' "$wait_seconds" >&2
        sleep "$wait_seconds"
        done
        """
    }

    private static func stableHash(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}

private extension SSHDestination {
    var connectionCoordinationIdentity: String {
        [target, port.map(String.init) ?? "22", identityFile ?? ""].joined(separator: "\u{1F}")
    }
}
