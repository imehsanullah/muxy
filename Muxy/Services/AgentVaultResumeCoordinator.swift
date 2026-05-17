import Foundation

@MainActor
enum AgentVaultResumeCoordinator {
    static func canResume(
        _ session: AgentVaultSession,
        appState: AppState,
        projectStore: ProjectStore,
        worktreeStore: WorktreeStore
    ) -> Bool {
        projectTarget(
            for: session,
            appState: appState,
            projectStore: projectStore,
            worktreeStore: worktreeStore
        ) != nil
    }

    static func resume(
        _ session: AgentVaultSession,
        preferredAreaID: UUID?,
        projectIDOverride: UUID? = nil,
        dropZone: DropZone? = nil,
        appState: AppState,
        projectStore: ProjectStore,
        worktreeStore: WorktreeStore,
        close: (() -> Void)? = nil
    ) {
        guard let target = projectTarget(
            for: session,
            projectIDOverride: projectIDOverride,
            appState: appState,
            projectStore: projectStore,
            worktreeStore: worktreeStore
        )
        else {
            ToastState.shared.show("Select or add a project before resuming an agent session.")
            return
        }

        worktreeStore.ensurePrimary(for: target.project)
        let worktree = target.worktree
            ?? worktreeStore.preferred(for: target.project.id, matching: appState.activeWorktreeID[target.project.id])
            ?? worktreeStore.primary(for: target.project.id)

        guard let worktree else {
            ToastState.shared.show("No worktree available for \(target.project.name).")
            return
        }

        appState.selectProject(target.project, worktree: worktree)
        if let preferredAreaID, let split = splitPlacement(for: dropZone) {
            appState.dispatch(.createCommandTabSplit(.init(
                projectID: target.project.id,
                areaID: preferredAreaID,
                name: session.tabTitle,
                command: session.resumeCommand,
                split: split
            )))
        } else {
            appState.dispatch(.createCommandTab(
                projectID: target.project.id,
                areaID: preferredAreaID,
                name: session.tabTitle,
                command: session.resumeCommand
            ))
        }
        close?()
    }

    private static func splitPlacement(for zone: DropZone?) -> SplitPlacement? {
        switch zone {
        case .left:
            SplitPlacement(direction: .horizontal, position: .first)
        case .right:
            SplitPlacement(direction: .horizontal, position: .second)
        case .top:
            SplitPlacement(direction: .vertical, position: .first)
        case .bottom:
            SplitPlacement(direction: .vertical, position: .second)
        case .center,
             nil:
            nil
        }
    }

    private static func projectTarget(
        for session: AgentVaultSession,
        projectIDOverride: UUID? = nil,
        appState: AppState,
        projectStore: ProjectStore,
        worktreeStore: WorktreeStore
    ) -> AgentVaultProjectTarget? {
        if let projectIDOverride,
           let project = projectStore.projects.first(where: { $0.id == projectIDOverride })
        {
            return AgentVaultProjectTarget(
                project: project,
                worktree: worktreeStore.preferred(for: project.id, matching: appState.activeWorktreeID[project.id])
            )
        }

        if let cwd = normalizedPath(session.cwd),
           let match = bestProjectMatch(for: cwd, projectStore: projectStore, worktreeStore: worktreeStore)
        {
            return match
        }

        guard let activeID = appState.activeProjectID,
              let project = projectStore.projects.first(where: { $0.id == activeID })
        else { return nil }

        return AgentVaultProjectTarget(
            project: project,
            worktree: worktreeStore.preferred(for: project.id, matching: appState.activeWorktreeID[project.id])
        )
    }

    private static func bestProjectMatch(
        for cwd: String,
        projectStore: ProjectStore,
        worktreeStore: WorktreeStore
    ) -> AgentVaultProjectTarget? {
        var best: (target: AgentVaultProjectTarget, length: Int)?

        for project in projectStore.projects where !project.isRemote {
            let candidates = worktreeStore.list(for: project.id).map { (path: $0.path, worktree: Optional($0)) }
                + [(path: project.path, worktree: nil)]

            for candidate in candidates {
                guard let path = normalizedPath(candidate.path),
                      cwd == path || cwd.hasPrefix(path + "/")
                else { continue }
                let length = path.count
                guard let currentBest = best else {
                    best = (AgentVaultProjectTarget(project: project, worktree: candidate.worktree), length)
                    continue
                }
                if length > currentBest.length {
                    best = (AgentVaultProjectTarget(project: project, worktree: candidate.worktree), length)
                }
            }
        }

        return best?.target
    }

    private static func normalizedPath(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else { return nil }
        return URL(fileURLWithPath: value).standardizedFileURL.resolvingSymlinksInPath().path
    }
}

private struct AgentVaultProjectTarget {
    let project: Project
    let worktree: Worktree?
}
