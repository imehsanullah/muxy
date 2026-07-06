import Foundation
import Testing

@testable import Muxy

@Suite("Remote terminal session lifecycle")
@MainActor
struct RemoteTerminalSessionLifecycleTests {
    private func makeState() -> (WorkspaceState, WorktreeKey, TabArea) {
        let key = WorktreeKey(projectID: UUID(), worktreeID: UUID())
        let area = TabArea(projectPath: "/repo")
        let state = WorkspaceState(
            activeProjectID: key.projectID,
            activeWorktreeID: [key.projectID: key.worktreeID],
            workspaceRoots: [key: .tabArea(area)],
            focusedAreaID: [key: area.id],
            focusHistory: [:]
        )
        return (state, key, area)
    }

    @Test("Closing a tab queues its stable session identity")
    func closeTabQueuesCleanup() {
        var (state, key, area) = makeState()
        area.createTab()
        let tab = area.tabs[0]
        let sessionID = tab.content.pane!.remoteSessionID

        let effects = WorkspaceReducer.reduce(
            action: .closeTab(projectID: key.projectID, areaID: area.id, tabID: tab.id),
            state: &state
        )

        #expect(effects.remoteSessionsToKill == [
            RemoteTerminalSessionReference(worktreeKey: key, sessionID: sessionID),
        ])
    }

    @Test("Closing an area queues every terminal session once")
    func closeAreaQueuesCleanup() {
        var (state, key, area) = makeState()
        area.createTab()
        let expected = Set(area.tabs.compactMap { tab in
            tab.content.pane.map {
                RemoteTerminalSessionReference(worktreeKey: key, sessionID: $0.remoteSessionID)
            }
        })

        let effects = WorkspaceReducer.reduce(
            action: .closeArea(projectID: key.projectID, areaID: area.id),
            state: &state
        )

        #expect(Set(effects.remoteSessionsToKill) == expected)
        #expect(effects.remoteSessionsToKill.count == expected.count)
    }

    @Test("Removing a project queues sessions across all worktrees")
    func removeProjectQueuesAllCleanup() {
        var (state, key, area) = makeState()
        let secondKey = WorktreeKey(projectID: key.projectID, worktreeID: UUID())
        let secondArea = TabArea(projectPath: "/repo-2")
        state.workspaceRoots[secondKey] = .tabArea(secondArea)
        state.focusedAreaID[secondKey] = secondArea.id
        let expected = Set([
            RemoteTerminalSessionReference(
                worktreeKey: key,
                sessionID: area.tabs[0].content.pane!.remoteSessionID
            ),
            RemoteTerminalSessionReference(
                worktreeKey: secondKey,
                sessionID: secondArea.tabs[0].content.pane!.remoteSessionID
            ),
        ])

        let effects = WorkspaceReducer.reduce(
            action: .removeProject(projectID: key.projectID),
            state: &state
        )

        #expect(Set(effects.remoteSessionsToKill) == expected)
    }

    @Test("Removing a worktree queues only that worktree's sessions")
    func removeWorktreeQueuesCleanup() {
        var (state, key, area) = makeState()
        let sessionID = area.tabs[0].content.pane!.remoteSessionID

        let effects = WorkspaceReducer.reduce(
            action: .removeWorktree(
                projectID: key.projectID,
                worktreeID: key.worktreeID,
                replacementWorktreeID: nil,
                replacementWorktreePath: nil
            ),
            state: &state
        )

        #expect(effects.remoteSessionsToKill == [
            RemoteTerminalSessionReference(worktreeKey: key, sessionID: sessionID),
        ])
    }

    @Test("Replacing a layout queues sessions from the replaced layout")
    func layoutReplacementQueuesCleanup() {
        var (state, key, area) = makeState()
        let sessionID = area.tabs[0].content.pane!.remoteSessionID
        let layout = LayoutConfig(root: .leaf(tabs: [.init(name: "New", command: nil)]))

        let effects = WorkspaceReducer.reduce(
            action: .applyLayout(projectID: key.projectID, worktreePath: "/repo", config: layout),
            state: &state
        )

        #expect(effects.remoteSessionsToKill == [
            RemoteTerminalSessionReference(worktreeKey: key, sessionID: sessionID),
        ])
    }

    @Test("Moving a tab never queues cleanup")
    func movingTabDoesNotQueueCleanup() {
        var (state, key, sourceArea) = makeState()
        _ = WorkspaceReducer.reduce(
            action: .splitArea(.init(
                projectID: key.projectID,
                areaID: sourceArea.id,
                direction: .horizontal,
                position: .second
            )),
            state: &state
        )
        let destinationArea = state.workspaceRoots[key]!.allAreas().first { $0.id != sourceArea.id }!
        let tabID = sourceArea.tabs[0].id

        let effects = WorkspaceReducer.reduce(
            action: .moveTab(
                projectID: key.projectID,
                request: .toArea(
                    tabID: tabID,
                    sourceAreaID: sourceArea.id,
                    destinationAreaID: destinationArea.id
                )
            ),
            state: &state
        )

        #expect(effects.remoteSessionsToKill.isEmpty)
    }

    @Test("Project and worktree selection never queue cleanup")
    func selectionDoesNotQueueCleanup() {
        var (state, key, _) = makeState()

        let projectEffects = WorkspaceReducer.reduce(
            action: .selectProject(
                projectID: key.projectID,
                worktreeID: key.worktreeID,
                worktreePath: "/repo"
            ),
            state: &state
        )
        let worktreeEffects = WorkspaceReducer.reduce(
            action: .selectWorktree(
                projectID: key.projectID,
                worktreeID: key.worktreeID,
                worktreePath: "/repo"
            ),
            state: &state
        )

        #expect(projectEffects.remoteSessionsToKill.isEmpty)
        #expect(worktreeEffects.remoteSessionsToKill.isEmpty)
    }
}
