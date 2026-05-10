import Foundation
import SwiftUI

@MainActor
@Observable
final class AppState {
    struct SplitAreaRequest {
        let projectID: UUID
        let areaID: UUID
        let direction: SplitDirection
        let position: SplitPosition
    }

    enum Action {
        case selectProject(projectID: UUID, worktreeID: UUID, worktreePath: String, remoteHost: String?)
        case selectWorktree(projectID: UUID, worktreeID: UUID, worktreePath: String, remoteHost: String?)
        case removeProject(projectID: UUID)
        case removeWorktree(
            projectID: UUID,
            worktreeID: UUID,
            replacementWorktreeID: UUID?,
            replacementWorktreePath: String?,
            replacementRemoteHost: String?
        )
        case createTab(projectID: UUID, areaID: UUID?)
        case createVCSTab(projectID: UUID, areaID: UUID?)
        case createEditorTab(projectID: UUID, areaID: UUID?, filePath: String)
        case createExternalEditorTab(projectID: UUID, areaID: UUID?, filePath: String, command: String)
        case closeTab(projectID: UUID, areaID: UUID, tabID: UUID)
        case selectTab(projectID: UUID, areaID: UUID, tabID: UUID)
        case selectTabByIndex(projectID: UUID, areaID: UUID?, index: Int)
        case selectNextTab(projectID: UUID)
        case selectPreviousTab(projectID: UUID)
        case splitArea(SplitAreaRequest)
        case closeArea(projectID: UUID, areaID: UUID)
        case focusArea(projectID: UUID, areaID: UUID)
        case focusPaneLeft(projectID: UUID)
        case focusPaneRight(projectID: UUID)
        case focusPaneUp(projectID: UUID)
        case focusPaneDown(projectID: UUID)
        case moveTab(projectID: UUID, request: TabMoveRequest)
        case selectNextProject(projects: [Project], worktrees: [UUID: [Worktree]])
        case selectPreviousProject(projects: [Project], worktrees: [UUID: [Worktree]])
    }

    private let selectionStore: any ActiveProjectSelectionStoring
    private let terminalViews: any TerminalViewRemoving
    private let workspacePersistence: any WorkspacePersisting
    var onProjectsEmptied: (([UUID]) -> Void)?

    var activeProjectID: UUID?

    var activeWorktreeID: [UUID: UUID] = [:]

    struct PendingTabClose: Equatable {
        let projectID: UUID
        let areaID: UUID
        let tabID: UUID
    }

    var workspaceRoots: [WorktreeKey: SplitNode] = [:]
    var focusedAreaID: [WorktreeKey: UUID] = [:]
    var pendingUnsavedEditorTabClose: PendingTabClose?
    var pendingSaveErrorMessage: String?
    private var focusHistory: [WorktreeKey: [UUID]] = [:]

    init(
        selectionStore: any ActiveProjectSelectionStoring,
        terminalViews: any TerminalViewRemoving,
        workspacePersistence: any WorkspacePersisting
    ) {
        self.selectionStore = selectionStore
        self.terminalViews = terminalViews
        self.workspacePersistence = workspacePersistence
    }

    func restoreSelection(projects: [Project], worktrees: [UUID: [Worktree]]) {
        let restored = WorkspaceRestorer.restoreAll(
            from: workspacePersistence.loadWorkspaces(),
            projects: projects,
            worktrees: worktrees
        )
        for entry in restored {
            workspaceRoots[entry.key] = entry.root
            focusedAreaID[entry.key] = entry.focusedAreaID
        }

        let savedWorktreeIDs = selectionStore.loadActiveWorktreeIDs()
        for project in projects {
            let restoredKeysForProject = restored.map(\.key).filter { $0.projectID == project.id }
            guard !restoredKeysForProject.isEmpty else { continue }
            if let savedWorktreeID = savedWorktreeIDs[project.id],
               restoredKeysForProject.contains(where: { $0.worktreeID == savedWorktreeID })
            {
                activeWorktreeID[project.id] = savedWorktreeID
                continue
            }
            activeWorktreeID[project.id] = restoredKeysForProject[0].worktreeID
        }

        guard let id = selectionStore.loadActiveProjectID(),
              projects.contains(where: { $0.id == id }),
              activeWorktreeID[id] != nil
        else { return }
        activeProjectID = id
    }

    func saveWorkspaces() {
        let snapshots = WorkspaceRestorer.snapshotAll(
            workspaceRoots: workspaceRoots,
            focusedAreaID: focusedAreaID
        )
        workspacePersistence.saveWorkspaces(snapshots)
    }

    private func saveSelection() {
        selectionStore.saveActiveProjectID(activeProjectID)
        selectionStore.saveActiveWorktreeIDs(activeWorktreeID)
    }

    func activeWorktreeKey(for projectID: UUID) -> WorktreeKey? {
        guard let worktreeID = activeWorktreeID[projectID] else { return nil }
        return WorktreeKey(projectID: projectID, worktreeID: worktreeID)
    }

    func workspaceRoot(for projectID: UUID) -> SplitNode? {
        guard let key = activeWorktreeKey(for: projectID) else { return nil }
        return workspaceRoots[key]
    }

    func focusedAreaID(for projectID: UUID) -> UUID? {
        guard let key = activeWorktreeKey(for: projectID) else { return nil }
        return focusedAreaID[key]
    }

    func selectProject(_ project: Project, worktree: Worktree) {
        dispatch(.selectProject(
            projectID: project.id,
            worktreeID: worktree.id,
            worktreePath: worktree.path,
            remoteHost: project.remoteHost
        ))
    }

    func selectWorktree(projectID: UUID, worktree: Worktree) {
        selectWorktree(projectID: projectID, remoteHost: nil, worktree: worktree)
    }

    func selectWorktree(projectID: UUID, remoteHost: String?, worktree: Worktree) {
        dispatch(.selectWorktree(
            projectID: projectID,
            worktreeID: worktree.id,
            worktreePath: worktree.path,
            remoteHost: remoteHost
        ))
    }

    func focusedArea(for projectID: UUID) -> TabArea? {
        guard let key = activeWorktreeKey(for: projectID),
              let root = workspaceRoots[key],
              let areaID = focusedAreaID[key]
        else { return nil }
        return root.findArea(id: areaID)
    }

    func allAreas(for projectID: UUID) -> [TabArea] {
        guard let key = activeWorktreeKey(for: projectID) else { return [] }
        return workspaceRoots[key]?.allAreas() ?? []
    }

    func splitFocusedArea(direction: SplitDirection, projectID: UUID) {
        guard let area = focusedArea(for: projectID) else { return }
        dispatch(.splitArea(.init(
            projectID: projectID,
            areaID: area.id,
            direction: direction,
            position: .second
        )))
    }

    func closeArea(_ areaID: UUID, projectID: UUID) {
        dispatch(.closeArea(projectID: projectID, areaID: areaID))
    }

    func createTab(projectID: UUID) {
        dispatch(.createTab(projectID: projectID, areaID: nil))
    }

    func createVCSTab(projectID: UUID) {
        dispatch(.createVCSTab(projectID: projectID, areaID: nil))
    }

    func openFile(_ filePath: String, projectID: UUID) {
        let settings = EditorSettings.shared
        if projectUsesRemoteSession(projectID: projectID) {
            let command = settings.externalEditorCommand.trimmingCharacters(in: .whitespacesAndNewlines)
            openFileInExternalEditor(
                filePath,
                projectID: projectID,
                command: command.isEmpty ? "vim" : command
            )
            return
        }
        if settings.defaultEditor == .terminalCommand {
            let command = settings.externalEditorCommand.trimmingCharacters(in: .whitespacesAndNewlines)
            if !command.isEmpty {
                openFileInExternalEditor(filePath, projectID: projectID, command: command)
                return
            }
        }
        for area in allAreas(for: projectID) {
            if let tab = area.tabs.first(where: { $0.content.editorState?.filePath == filePath }) {
                dispatch(.selectTab(projectID: projectID, areaID: area.id, tabID: tab.id))
                return
            }
        }
        dispatch(.createEditorTab(projectID: projectID, areaID: nil, filePath: filePath))
    }

    private func openFileInExternalEditor(_ filePath: String, projectID: UUID, command: String) {
        for area in allAreas(for: projectID) {
            if let tab = area.tabs.first(where: { $0.content.pane?.externalEditorFilePath == filePath }) {
                dispatch(.selectTab(projectID: projectID, areaID: area.id, tabID: tab.id))
                return
            }
        }
        dispatch(.createExternalEditorTab(projectID: projectID, areaID: nil, filePath: filePath, command: command))
    }

    private func projectUsesRemoteSession(projectID: UUID) -> Bool {
        allAreas(for: projectID).contains { $0.remoteHost != nil }
    }

    func closeTab(_ tabID: UUID, projectID: UUID) {
        guard let area = focusedArea(for: projectID) else { return }
        closeTab(tabID, areaID: area.id, projectID: projectID)
    }

    func closeTab(_ tabID: UUID, areaID: UUID, projectID: UUID) {
        if needsUnsavedEditorConfirmation(tabID: tabID, areaID: areaID, projectID: projectID) {
            pendingUnsavedEditorTabClose = PendingTabClose(projectID: projectID, areaID: areaID, tabID: tabID)
            return
        }
        closeTabImmediately(tabID, areaID: areaID, projectID: projectID)
    }

    func forceCloseTab(_ tabID: UUID, areaID: UUID, projectID: UUID) {
        unpinTabIfNeeded(tabID, areaID: areaID, projectID: projectID)
        closeTabImmediately(tabID, areaID: areaID, projectID: projectID)
    }

    func confirmCloseUnsavedEditorTab() {
        guard let pending = pendingUnsavedEditorTabClose else { return }
        pendingUnsavedEditorTabClose = nil
        closeTabImmediately(pending.tabID, areaID: pending.areaID, projectID: pending.projectID)
    }

    func saveAndCloseUnsavedEditorTab() {
        guard let pending = pendingUnsavedEditorTabClose else { return }
        guard let key = activeWorktreeKey(for: pending.projectID),
              let root = workspaceRoots[key],
              let area = root.findArea(id: pending.areaID),
              let tab = area.tabs.first(where: { $0.id == pending.tabID }),
              let editorState = tab.content.editorState
        else {
            pendingUnsavedEditorTabClose = nil
            return
        }
        pendingUnsavedEditorTabClose = nil
        let fileName = editorState.fileName
        Task { [weak self] in
            do {
                try await editorState.saveFileAsync()
                self?.closeTabImmediately(pending.tabID, areaID: pending.areaID, projectID: pending.projectID)
            } catch {
                self?.pendingSaveErrorMessage = "Failed to save \(fileName): \(error.localizedDescription)"
            }
        }
    }

    func cancelCloseUnsavedEditorTab() {
        pendingUnsavedEditorTabClose = nil
    }

    private func closeTabImmediately(_ tabID: UUID, areaID: UUID, projectID: UUID) {
        dispatch(.closeTab(projectID: projectID, areaID: areaID, tabID: tabID))
    }

    private func unpinTabIfNeeded(_ tabID: UUID, areaID: UUID, projectID: UUID) {
        guard let key = activeWorktreeKey(for: projectID),
              let root = workspaceRoots[key],
              let area = root.findArea(id: areaID),
              let tab = area.tabs.first(where: { $0.id == tabID }),
              tab.isPinned
        else { return }
        area.togglePin(tabID)
    }

    func unsavedEditorTabs() -> [EditorTabState] {
        var result: [EditorTabState] = []
        for (_, root) in workspaceRoots {
            for area in root.allAreas() {
                for tab in area.tabs {
                    if let state = tab.content.editorState, state.isModified {
                        result.append(state)
                    }
                }
            }
        }
        return result
    }

    private func needsUnsavedEditorConfirmation(tabID: UUID, areaID: UUID, projectID: UUID) -> Bool {
        guard let key = activeWorktreeKey(for: projectID),
              let root = workspaceRoots[key],
              let area = root.findArea(id: areaID),
              let tab = area.tabs.first(where: { $0.id == tabID }),
              let editorState = tab.content.editorState
        else { return false }
        return editorState.isModified
    }

    func selectTabByIndex(_ index: Int, projectID: UUID) {
        dispatch(.selectTabByIndex(projectID: projectID, areaID: nil, index: index))
    }

    func selectNextTab(projectID: UUID) {
        dispatch(.selectNextTab(projectID: projectID))
    }

    func selectPreviousTab(projectID: UUID) {
        dispatch(.selectPreviousTab(projectID: projectID))
    }

    func activeTab(for projectID: UUID) -> TerminalTab? {
        focusedArea(for: projectID)?.activeTab
    }

    func togglePinActiveTab(projectID: UUID) {
        guard let area = focusedArea(for: projectID),
              let tabID = area.activeTabID
        else { return }
        area.togglePin(tabID)
        saveWorkspaces()
    }

    func dispatch(_ action: Action) {
        if case let .focusArea(projectID, areaID) = action,
           let key = activeWorktreeKey(for: projectID),
           focusedAreaID[key] == areaID
        {
            return
        }

        if case let .selectTab(projectID, areaID, tabID) = action,
           let key = activeWorktreeKey(for: projectID),
           let root = workspaceRoots[key],
           let area = root.findArea(id: areaID),
           area.activeTabID == tabID,
           focusedAreaID[key] == areaID
        {
            return
        }

        let currentWorkspaceRootSignature = workspaceRootSignature(workspaceRoots)
        var workspace = WorkspaceState(
            activeProjectID: activeProjectID,
            activeWorktreeID: activeWorktreeID,
            workspaceRoots: workspaceRoots,
            focusedAreaID: focusedAreaID,
            focusHistory: focusHistory
        )
        let effects = WorkspaceReducer.reduce(action: action, state: &workspace)
        if activeProjectID != workspace.activeProjectID {
            activeProjectID = workspace.activeProjectID
        }
        if activeWorktreeID != workspace.activeWorktreeID {
            activeWorktreeID = workspace.activeWorktreeID
        }
        if currentWorkspaceRootSignature != workspaceRootSignature(workspace.workspaceRoots) {
            workspaceRoots = workspace.workspaceRoots
        }
        if focusedAreaID != workspace.focusedAreaID {
            focusedAreaID = workspace.focusedAreaID
        }
        if focusHistory != workspace.focusHistory {
            focusHistory = workspace.focusHistory
        }
        reconcilePendingClosures()

        for cleanup in effects.remoteSessionsToKill {
            RemoteSessionTerminator.kill(cleanup)
        }

        for paneID in effects.paneIDsToRemove {
            terminalViews.removeView(for: paneID)
        }

        if !effects.projectIDsToRemove.isEmpty {
            onProjectsEmptied?(effects.projectIDsToRemove)
        }

        if let activeTabID = NotificationNavigator.activeTabID(appState: self) {
            NotificationStore.shared.markAsRead(tabID: activeTabID)
        }

        saveWorkspaces()
        saveSelection()
    }

    private func workspaceRootSignature(_ roots: [WorktreeKey: SplitNode]) -> [WorktreeKey: UUID] {
        roots.mapValues(\.id)
    }

    private func reconcilePendingClosures() {
        if let pending = pendingUnsavedEditorTabClose,
           !tabExists(tabID: pending.tabID, areaID: pending.areaID, projectID: pending.projectID)
        {
            pendingUnsavedEditorTabClose = nil
        }
    }

    private func tabExists(tabID: UUID, areaID: UUID, projectID: UUID) -> Bool {
        guard let key = activeWorktreeKey(for: projectID),
              let root = workspaceRoots[key],
              let area = root.findArea(id: areaID)
        else { return false }
        return area.tabs.contains(where: { $0.id == tabID })
    }

    func focusArea(_ areaID: UUID, projectID: UUID) {
        dispatch(.focusArea(projectID: projectID, areaID: areaID))
    }

    func focusPaneLeft(projectID: UUID) {
        dispatch(.focusPaneLeft(projectID: projectID))
    }

    func focusPaneRight(projectID: UUID) {
        dispatch(.focusPaneRight(projectID: projectID))
    }

    func focusPaneUp(projectID: UUID) {
        dispatch(.focusPaneUp(projectID: projectID))
    }

    func focusPaneDown(projectID: UUID) {
        dispatch(.focusPaneDown(projectID: projectID))
    }

    func selectProjectByIndex(_ index: Int, projects: [Project], worktrees: [UUID: [Worktree]]) {
        guard index >= 0, index < projects.count else { return }
        let project = projects[index]
        let list = worktrees[project.id] ?? []
        guard let target = list.first(where: { $0.isPrimary }) ?? list.first else { return }
        selectProject(project, worktree: target)
    }

    func selectNextProject(projects: [Project], worktrees: [UUID: [Worktree]]) {
        dispatch(.selectNextProject(projects: projects, worktrees: worktrees))
    }

    func selectPreviousProject(projects: [Project], worktrees: [UUID: [Worktree]]) {
        dispatch(.selectPreviousProject(projects: projects, worktrees: worktrees))
    }

    func removeProject(_ projectID: UUID) {
        dispatch(.removeProject(projectID: projectID))
    }

    func removeWorktree(projectID: UUID, worktree: Worktree, replacement: Worktree?) {
        guard !worktree.isPrimary else { return }
        dispatch(.removeWorktree(
            projectID: projectID,
            worktreeID: worktree.id,
            replacementWorktreeID: replacement?.id,
            replacementWorktreePath: replacement?.path,
            replacementRemoteHost: nil
        ))
    }

    func removeWorktree(projectID: UUID, remoteHost: String?, worktree: Worktree, replacement: Worktree?) {
        guard !worktree.isPrimary else { return }
        dispatch(.removeWorktree(
            projectID: projectID,
            worktreeID: worktree.id,
            replacementWorktreeID: replacement?.id,
            replacementWorktreePath: replacement?.path,
            replacementRemoteHost: remoteHost
        ))
    }
}
