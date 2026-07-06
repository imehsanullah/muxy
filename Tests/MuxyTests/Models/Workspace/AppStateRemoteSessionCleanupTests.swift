import Foundation
import Testing

@testable import Muxy

@Suite("AppState remote session cleanup")
@MainActor
struct AppStateRemoteSessionCleanupTests {
    @Test("Destructive effects resolve and terminate against the project's SSH destination")
    func remoteCleanupExecutes() {
        let terminator = RemoteSessionTerminatorStub()
        let appState = makeAppState(terminator: terminator)
        let (key, area, pane) = installWorkspace(in: appState)
        let destination = SSHDestination(host: "prod", port: 2222, user: "deploy")
        appState.workspaceContextProvider = { projectID in
            projectID == key.projectID ? .ssh(destination) : .local
        }

        appState.dispatch(.closeTab(
            projectID: key.projectID,
            areaID: area.id,
            tabID: area.tabs[0].id
        ))

        #expect(terminator.calls.count == 1)
        #expect(terminator.calls[0].reference == RemoteTerminalSessionReference(
            worktreeKey: key,
            sessionID: pane.remoteSessionID
        ))
        #expect(terminator.calls[0].destination == destination)
    }

    @Test("Local terminal destruction never invokes remote cleanup")
    func localCleanupIsIgnored() {
        let terminator = RemoteSessionTerminatorStub()
        let appState = makeAppState(terminator: terminator)
        let (key, area, _) = installWorkspace(in: appState)
        appState.workspaceContextProvider = { _ in .local }

        appState.dispatch(.closeTab(
            projectID: key.projectID,
            areaID: area.id,
            tabID: area.tabs[0].id
        ))

        #expect(terminator.calls.isEmpty)
    }

    @Test("Recovery restarts every disconnected remote pane and leaves healthy panes alone")
    func reconnectsDisconnectedRemotePanes() {
        let terminator = RemoteSessionTerminatorStub()
        let appState = makeAppState(terminator: terminator)
        let (key, area, disconnectedPane) = installWorkspace(in: appState)
        let healthyTabID = area.createTab()
        let healthyPane = area.tabs.first(where: { $0.id == healthyTabID })!.content.pane!
        disconnectedPane.markRemoteDisconnected()
        var restarted: [UUID] = []
        appState.workspaceContextProvider = { projectID in
            projectID == key.projectID ? .ssh(SSHDestination(host: "prod")) : .local
        }
        appState.remoteSessionRestarter = {
            restarted.append($0)
            return true
        }

        appState.reconnectDisconnectedRemoteSessions()

        #expect(restarted == [disconnectedPane.id])
        #expect(disconnectedPane.remoteConnectionState == .reconnecting)
        #expect(healthyPane.remoteConnectionState == TerminalPaneState.RemoteConnectionState.connected)
    }

    @Test("Recovery ignores disconnected panes in local projects")
    func reconnectIgnoresLocalPanes() {
        let terminator = RemoteSessionTerminatorStub()
        let appState = makeAppState(terminator: terminator)
        let (_, _, pane) = installWorkspace(in: appState)
        pane.markRemoteDisconnected()
        var restarted: [UUID] = []
        appState.workspaceContextProvider = { _ in .local }
        appState.remoteSessionRestarter = {
            restarted.append($0)
            return true
        }

        appState.reconnectDisconnectedRemoteSessions()

        #expect(restarted.isEmpty)
        #expect(pane.remoteConnectionState == .disconnected)
    }

    @Test("Restoring a remote workspace preserves identity without terminating its session")
    func restorationDoesNotCleanup() {
        let project = Project(name: "Remote", path: "/srv/repo")
        let worktree = Worktree(name: project.name, path: project.path, isPrimary: true)
        let key = WorktreeKey(projectID: project.id, worktreeID: worktree.id)
        let area = TabArea(projectPath: project.path)
        let sessionID = area.tabs[0].content.pane!.remoteSessionID
        let snapshots = WorkspaceRestorer.snapshotAll(
            workspaceRoots: [key: .tabArea(area)],
            focusedAreaID: [key: area.id]
        )
        let terminator = RemoteSessionTerminatorStub()
        let appState = AppState(
            selectionStore: RemoteCleanupSelectionStoreStub(),
            terminalViews: RemoteCleanupTerminalViewsStub(),
            workspacePersistence: RemoteCleanupWorkspacePersistenceStub(snapshots: snapshots),
            remoteSessionTerminator: terminator
        )
        appState.workspaceContextProvider = { _ in .ssh(SSHDestination(host: "prod")) }

        appState.restoreSelection(
            projects: [project],
            worktrees: [project.id: [worktree]]
        )

        let restoredPane = appState.workspaceRoots[key]?.allAreas().first?.tabs.first?.content.pane
        #expect(restoredPane?.remoteSessionID == sessionID)
        #expect(terminator.calls.isEmpty)
    }

    private func makeAppState(terminator: RemoteSessionTerminatorStub) -> AppState {
        AppState(
            selectionStore: RemoteCleanupSelectionStoreStub(),
            terminalViews: RemoteCleanupTerminalViewsStub(),
            workspacePersistence: RemoteCleanupWorkspacePersistenceStub(),
            remoteSessionTerminator: terminator
        )
    }

    private func installWorkspace(in appState: AppState) -> (WorktreeKey, TabArea, TerminalPaneState) {
        let key = WorktreeKey(projectID: UUID(), worktreeID: UUID())
        let area = TabArea(projectPath: "/repo")
        let pane = area.tabs[0].content.pane!
        appState.activeProjectID = key.projectID
        appState.activeWorktreeID[key.projectID] = key.worktreeID
        appState.workspaceRoots[key] = .tabArea(area)
        appState.focusedAreaID[key] = area.id
        return (key, area, pane)
    }
}

@MainActor
private final class RemoteSessionTerminatorStub: RemoteTerminalSessionTerminating {
    struct Call {
        let reference: RemoteTerminalSessionReference
        let destination: SSHDestination
    }

    private(set) var calls: [Call] = []

    func terminate(_ reference: RemoteTerminalSessionReference, destination: SSHDestination) {
        calls.append(Call(reference: reference, destination: destination))
    }
}

@MainActor
private final class RemoteCleanupSelectionStoreStub: ActiveProjectSelectionStoring {
    func loadActiveProjectID() -> UUID? { nil }
    func saveActiveProjectID(_: UUID?) {}
    func loadActiveWorktreeIDs() -> [UUID: UUID] { [:] }
    func saveActiveWorktreeIDs(_: [UUID: UUID]) {}
}

@MainActor
private final class RemoteCleanupTerminalViewsStub: TerminalViewRemoving {
    func removeView(for _: UUID) {}
    func needsConfirmQuit(for _: UUID) -> Bool { false }
}

private final class RemoteCleanupWorkspacePersistenceStub: WorkspacePersisting {
    private let snapshots: [WorkspaceSnapshot]

    init(snapshots: [WorkspaceSnapshot] = []) {
        self.snapshots = snapshots
    }

    func loadWorkspaces() throws -> [WorkspaceSnapshot] { snapshots }
    func saveWorkspaces(_: [WorkspaceSnapshot]) throws {}
}
