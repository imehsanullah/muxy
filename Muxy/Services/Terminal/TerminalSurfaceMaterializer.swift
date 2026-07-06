import Foundation

@MainActor
enum TerminalSurfaceMaterializer {
    static func materialize(paneID: UUID, appState: AppState) -> GhosttyTerminalNSView? {
        if let view = TerminalViewRegistry.shared.existingView(for: paneID) {
            return view.ensureLiveSurfaceForExternalIO() ? view : nil
        }
        guard let location = appState.locatePane(paneID: paneID) else { return nil }
        let pane = location.pane
        let workspaceContext = appState.workspaceContext(for: location.worktreeKey.projectID)
        let view = TerminalViewRegistry.shared.view(
            for: paneID,
            workingDirectory: pane.currentWorkingDirectory ?? pane.projectPath,
            command: pane.startupCommand,
            commandInteractive: pane.startupCommandInteractive,
            closesOnCommandExit: pane.closesOnStartupCommandExit,
            workspaceContext: workspaceContext,
            remoteSessionName: workspaceContext.isRemote
                ? RemoteTerminalSessionName.make(
                    worktreeKey: location.worktreeKey,
                    sessionID: pane.remoteSessionID
                )
                : nil
        )
        if view.envVars.isEmpty {
            view.envVars = TerminalEnvVarBuilder.build(paneID: paneID, worktreeKey: location.worktreeKey)
        }
        if workspaceContext.isRemote {
            view.onProcessExit = { [weak pane] in
                pane?.markRemoteDisconnected()
            }
        }
        view.materializeHeadless()
        return view.surface != nil ? view : nil
    }
}
