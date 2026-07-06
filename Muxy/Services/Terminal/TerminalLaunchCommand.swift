import Darwin
import Foundation

struct RemoteTerminalLaunchConfiguration {
    let startupCommand: String?
    let fallbackStartupCommand: String?
    let interactive: Bool
    let keepsShellOpen: Bool
}

enum TerminalLaunchCommand {
    static let environmentKey = "MUXY_STARTUP_COMMAND"

    static func shellCommand(
        interactive: Bool,
        keepsShellOpen: Bool = false,
        shell: String = userShell()
    ) -> String {
        let flags = interactive ? "-l -i" : "-l"
        let escapedShell = ShellEscaper.escape(shell)
        return "\(escapedShell) \(flags) -c '\(script(keepsShellOpen: keepsShellOpen))' \(escapedShell)"
    }

    static func remoteShellCommand(
        destination: SSHDestination,
        workingDirectory: String,
        sessionName: String,
        configuration: RemoteTerminalLaunchConfiguration
    ) -> String {
        let creationCommand = remoteLoginShell(
            startupCommand: configuration.startupCommand,
            interactive: configuration.interactive,
            keepsShellOpen: configuration.keepsShellOpen,
            wrapsInExecutableShell: true
        )
        let fallbackCommand = remoteLoginShell(
            startupCommand: configuration.fallbackStartupCommand,
            interactive: configuration.interactive,
            keepsShellOpen: configuration.keepsShellOpen
        )
        return RemoteTerminalSessionCommand.make(
            destination: destination,
            workingDirectory: workingDirectory,
            sessionName: sessionName,
            creationCommand: creationCommand,
            fallbackCommand: fallbackCommand
        )
    }

    private static func remoteLoginShell(
        startupCommand: String?,
        interactive: Bool,
        keepsShellOpen: Bool,
        wrapsInExecutableShell: Bool = false
    ) -> String {
        let flags = interactive ? "-l -i" : "-l"
        let command: String
        if let startupCommand, !startupCommand.isEmpty {
            let scriptText = ShellEscaper.escape(script(keepsShellOpen: keepsShellOpen))
            let assignment = "\(environmentKey)=\(ShellEscaper.escape(startupCommand))"
            command = "export \(assignment); exec \"${SHELL:-/bin/sh}\" \(flags) -c \(scriptText) \"${SHELL:-/bin/sh}\""
        } else {
            command = "exec \"${SHELL:-/bin/sh}\" \(flags)"
        }
        guard wrapsInExecutableShell else { return command }
        return "/bin/sh -lc \(ShellEscaper.escape(command))"
    }

    private static func script(keepsShellOpen: Bool) -> String {
        var segments = [
            "eval \"$\(environmentKey)\"",
            "muxy_status=$?",
            "if [ $muxy_status -ne 0 ]",
            "then exec \"$0\" -l",
        ]
        segments.append(keepsShellOpen ? "else exec \"$0\" -l" : "else exit $muxy_status")
        segments.append("fi")
        return segments.joined(separator: "; ")
    }

    private static func userShell() -> String {
        if let shell = ProcessInfo.processInfo.environment["SHELL"], !shell.isEmpty {
            return shell
        }
        guard let pw = getpwuid(getuid()), let shellPtr = pw.pointee.pw_shell else {
            return "/bin/zsh"
        }
        return String(cString: shellPtr)
    }
}
