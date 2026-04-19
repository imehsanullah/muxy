import Foundation

@MainActor
@Observable
final class TerminalPaneState: Identifiable {
    let id = UUID()
    let projectPath: String
    let remoteHost: String?
    var title: String
    let startupCommand: String?
    let externalEditorFilePath: String?
    let searchState = TerminalSearchState()
    @ObservationIgnored private var titleDebounceTask: Task<Void, Never>?

    init(
        projectPath: String,
        remoteHost: String? = nil,
        title: String = "Terminal",
        startupCommand: String? = nil,
        externalEditorFilePath: String? = nil
    ) {
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
        guard let remoteHost else {
            return startupCommand
        }
        if let startupCommand {
            return RemoteProjectSessionCommand.make(
                sshDestination: remoteHost,
                remotePath: projectPath,
                remoteCommand: startupCommand
            )
        }
        return RemoteProjectSessionCommand.make(
            sshDestination: remoteHost,
            remotePath: projectPath
        )
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
