import Foundation

@MainActor
@Observable
final class TerminalPaneState: Identifiable {
    enum RemoteConnectionState: String, Equatable {
        case connected
        case disconnected
        case reconnecting
    }

    enum ProcessExitAction: Equatable {
        case closeTab
        case preserveTab
    }

    let id = UUID()
    let sessionID: UUID
    let projectPath: String
    let remoteHost: String?
    var title: String
    let startupCommand: String?
    let externalEditorFilePath: String?
    var remoteConnectionState: RemoteConnectionState = .connected
    let searchState = TerminalSearchState()
    @ObservationIgnored private var titleDebounceTask: Task<Void, Never>?
    @ObservationIgnored private var reconnectGeneration = 0

    init(
        sessionID: UUID = UUID(),
        projectPath: String,
        remoteHost: String? = nil,
        title: String = "Terminal",
        startupCommand: String? = nil,
        externalEditorFilePath: String? = nil
    ) {
        self.sessionID = sessionID
        self.projectPath = projectPath
        self.remoteHost = remoteHost
        self.title = title
        self.startupCommand = startupCommand
        self.externalEditorFilePath = externalEditorFilePath
    }

    var workingDirectory: String {
        remoteHost == nil ? projectPath : NSHomeDirectory()
    }

    var resolvedStartupCommand: String? {
        resolvedStartupCommand(worktreeKey: nil)
    }

    var isRemoteSession: Bool {
        guard let remoteHost else { return false }
        return !remoteHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func resolvedStartupCommand(worktreeKey: WorktreeKey?) -> String? {
        guard let remoteHost else {
            return startupCommand
        }
        let sessionName = RemoteProjectSessionCommand.sessionName(
            projectID: worktreeKey?.projectID,
            worktreeID: worktreeKey?.worktreeID,
            terminalSessionID: sessionID
        )
        if let startupCommand {
            return RemoteProjectSessionCommand.make(
                sshDestination: remoteHost,
                remotePath: projectPath,
                sessionName: sessionName,
                remoteCommand: startupCommand
            )
        }
        return RemoteProjectSessionCommand.make(
            sshDestination: remoteHost,
            remotePath: projectPath,
            sessionName: sessionName,
            remoteCommand: "exec ${SHELL:-/bin/zsh} -l"
        )
    }

    func handleProcessExit() -> ProcessExitAction {
        guard isRemoteSession else { return .closeTab }
        remoteConnectionState = .disconnected
        return .preserveTab
    }

    func beginReconnect() -> Int? {
        guard isRemoteSession else { return nil }
        reconnectGeneration += 1
        remoteConnectionState = .reconnecting
        return reconnectGeneration
    }

    func finishReconnect(generation: Int) {
        guard reconnectGeneration == generation,
              remoteConnectionState == .reconnecting
        else { return }
        remoteConnectionState = .connected
    }

    func setTitle(_ newTitle: String) {
        titleDebounceTask?.cancel()
        titleDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self, self.title != newTitle else { return }
            self.title = newTitle
        }
    }
}
