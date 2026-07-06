import Foundation

struct TerminalPaneLaunch: Equatable {
    let command: String?
    let interactive: Bool
    let closesOnCommandExit: Bool
}

@MainActor
@Observable
final class TerminalPaneState: Identifiable {
    enum RemoteConnectionState: String, Equatable {
        case connected
        case disconnected
        case reconnecting
    }

    let id: UUID
    let remoteSessionID: UUID
    let projectPath: String
    var title: String
    var currentWorkingDirectory: String?
    let startupCommand: String?
    let startupCommandInteractive: Bool
    let closesOnStartupCommandExit: Bool
    let externalEditorFilePath: String?
    var isOffline = false
    var remoteConnectionState: RemoteConnectionState = .connected
    let searchState = TerminalSearchState()
    @ObservationIgnored private var titleDebounceTask: Task<Void, Never>?
    @ObservationIgnored private var reconnectGeneration = 0

    init(
        id: UUID = UUID(),
        remoteSessionID: UUID = UUID(),
        projectPath: String,
        title: String = "Terminal",
        initialWorkingDirectory: String? = nil,
        startupCommand: String? = nil,
        startupCommandInteractive: Bool = false,
        closesOnStartupCommandExit: Bool = true,
        externalEditorFilePath: String? = nil
    ) {
        self.id = id
        self.remoteSessionID = remoteSessionID
        self.projectPath = projectPath
        self.title = title
        self.currentWorkingDirectory = initialWorkingDirectory
        self.startupCommand = startupCommand
        self.startupCommandInteractive = startupCommandInteractive
        self.closesOnStartupCommandExit = closesOnStartupCommandExit
        self.externalEditorFilePath = externalEditorFilePath
    }

    func consumeRestoredLaunch() -> TerminalPaneLaunch {
        TerminalPaneLaunch(
            command: startupCommand,
            interactive: startupCommandInteractive,
            closesOnCommandExit: closesOnStartupCommandExit
        )
    }

    func markRemoteDisconnected() {
        reconnectGeneration += 1
        remoteConnectionState = .disconnected
    }

    func beginRemoteReconnect() -> Int? {
        guard remoteConnectionState != .reconnecting else { return nil }
        reconnectGeneration += 1
        remoteConnectionState = .reconnecting
        return reconnectGeneration
    }

    func finishRemoteReconnect(generation: Int) {
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
            self.notifyTabUpdated()
        }
    }

    func setWorkingDirectory(_ path: String) {
        guard currentWorkingDirectory != path else { return }
        currentWorkingDirectory = path
        notifyTabUpdated()
    }

    private func notifyTabUpdated() {
        guard let appState = NotificationStore.shared.appState else { return }
        ExtensionEventEmitter.emitTabUpdated(forPane: id, appState: appState)
    }
}
