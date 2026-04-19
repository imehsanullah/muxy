import Foundation

@MainActor
@Observable
final class TerminalPaneState: Identifiable {
    let id = UUID()
    let projectPath: String
    let remoteHost: String?
    var title: String
    var currentWorkingDirectory: String?
    let startupCommand: String?
    let startupCommandInteractive: Bool
    let externalEditorFilePath: String?
    let searchState = TerminalSearchState()
    let branchObserver = PaneBranchObserver()
    @ObservationIgnored private var titleDebounceTask: Task<Void, Never>?

    init(
        projectPath: String,
        remoteHost: String? = nil,
        title: String = "Terminal",
        initialWorkingDirectory: String? = nil,
        startupCommand: String? = nil,
        startupCommandInteractive: Bool = false,
        externalEditorFilePath: String? = nil
    ) {
        self.projectPath = projectPath
        self.remoteHost = remoteHost
        self.title = title
        self.currentWorkingDirectory = initialWorkingDirectory
        self.startupCommand = startupCommand
        self.startupCommandInteractive = startupCommandInteractive
        self.externalEditorFilePath = externalEditorFilePath
        branchObserver.update(repoPath: initialWorkingDirectory ?? projectPath)
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

    func setWorkingDirectory(_ path: String) {
        currentWorkingDirectory = path
        branchObserver.update(repoPath: path)
    }
}
