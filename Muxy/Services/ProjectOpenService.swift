import AppKit

@MainActor
enum ProjectOpenService {
    static func addProject(
        appState: AppState,
        projectStore: ProjectStore,
        worktreeStore: WorktreeStore
    ) {
        let alert = NSAlert()
        alert.messageText = "Add Project"
        alert.informativeText = "Choose whether to add a local folder or an SSH-backed remote project."
        alert.addButton(withTitle: "Local")
        alert.addButton(withTitle: "Remote")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            openProject(appState: appState, projectStore: projectStore, worktreeStore: worktreeStore)
        case .alertSecondButtonReturn:
            openRemoteProject(appState: appState, projectStore: projectStore, worktreeStore: worktreeStore)
        default:
            return
        }
    }

    static func openProject(
        appState: AppState,
        projectStore: ProjectStore,
        worktreeStore: WorktreeStore
    ) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a project folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let project = Project(
            name: url.lastPathComponent,
            path: url.path(percentEncoded: false),
            sortOrder: projectStore.projects.count
        )
        projectStore.add(project)
        worktreeStore.ensurePrimary(for: project)
        guard let primary = worktreeStore.primary(for: project.id) else { return }
        appState.selectProject(project, worktree: primary)
    }

    static func openRemoteProject(
        appState: AppState,
        projectStore: ProjectStore,
        worktreeStore: WorktreeStore
    ) {
        guard let input = RemoteProjectPicker.present() else { return }
        let project = Project(
            name: input.name,
            path: input.remotePath,
            remoteHost: input.sshDestination,
            sortOrder: projectStore.projects.count
        )
        projectStore.add(project)
        worktreeStore.ensurePrimary(for: project)
        guard let primary = worktreeStore.primary(for: project.id) else { return }
        appState.selectProject(project, worktree: primary)
    }
}
