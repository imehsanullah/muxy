import Foundation

@MainActor
enum WorkspaceReducerShared {
    static func activeKey(projectID: UUID, state: WorkspaceState) -> WorktreeKey? {
        guard let worktreeID = state.activeWorktreeID[projectID] else { return nil }
        return WorktreeKey(projectID: projectID, worktreeID: worktreeID)
    }

    static func resolveArea(key: WorktreeKey, areaID: UUID?, state: WorkspaceState) -> TabArea? {
        guard let root = state.workspaceRoots[key] else { return nil }
        if let areaID {
            return root.findArea(id: areaID)
        }
        guard let focusedID = state.focusedAreaID[key] else { return nil }
        return root.findArea(id: focusedID)
    }

    static func ensureWorkspaceExists(
        _ selection: WorkspaceSelection,
        state: inout WorkspaceState,
        effects: inout WorkspaceSideEffects
    ) {
        let key = WorktreeKey(projectID: selection.projectID, worktreeID: selection.worktreeID)
        guard state.workspaceRoots[key] == nil else { return }
        let area = TabArea(projectPath: selection.worktreePath, remoteHost: selection.remoteHost)
        state.workspaceRoots[key] = .tabArea(area)
        state.focusedAreaID[key] = area.id
    }

    static func clearWorkspace(key: WorktreeKey, state: inout WorkspaceState) {
        state.workspaceRoots.removeValue(forKey: key)
        state.focusedAreaID.removeValue(forKey: key)
        state.focusHistory.removeValue(forKey: key)
    }

    static func handleProjectEmptiedIfNeeded(
        projectID: UUID,
        state: inout WorkspaceState,
        effects: inout WorkspaceSideEffects
    ) {
        let hasAnyWorkspace = state.workspaceRoots.keys.contains { $0.projectID == projectID }
        guard !hasAnyWorkspace else { return }
        guard !state.keepProjectOpenWhenEmpty else { return }
        state.activeWorktreeID.removeValue(forKey: projectID)
        if state.activeProjectID == projectID {
            state.activeProjectID = nil
        }
        effects.projectIDsToRemove.append(projectID)
    }

    static func appendRemoteSessionCleanups(
        from tabs: [TerminalTab],
        key: WorktreeKey,
        effects: inout WorkspaceSideEffects
    ) {
        for tab in tabs {
            appendRemoteSessionCleanup(from: tab, key: key, effects: &effects)
        }
    }

    static func appendRemoteSessionCleanup(
        from tab: TerminalTab,
        key: WorktreeKey,
        effects: inout WorkspaceSideEffects
    ) {
        guard let pane = tab.content.pane,
              let sshDestination = pane.remoteHost?.trimmingCharacters(in: .whitespacesAndNewlines),
              !sshDestination.isEmpty
        else { return }
        let cleanup = RemoteSessionCleanup(
            sshDestination: sshDestination,
            sessionName: RemoteProjectSessionCommand.sessionName(
                projectID: key.projectID,
                worktreeID: key.worktreeID,
                terminalSessionID: pane.sessionID
            )
        )
        guard !effects.remoteSessionsToKill.contains(cleanup) else { return }
        effects.remoteSessionsToKill.append(cleanup)
    }
}
