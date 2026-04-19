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
            remoteCommand: "exec ${SHELL:-/bin/zsh} -l"
        )
    }

    static func make(sshDestination: String, remotePath: String, remoteCommand: String) -> String {
        let command = "cd -- \(ShellCommandEscaping.escape(remotePath)) && \(remoteCommand)"
        return "exec ssh -t \(ShellCommandEscaping.escape(sshDestination)) \(ShellCommandEscaping.escape(command))"
    }
}
