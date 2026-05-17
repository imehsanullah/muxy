import Foundation

@MainActor
@Observable
final class AgentVaultStore {
    static let shared = AgentVaultStore()

    private(set) var sessions: [AgentVaultSession] = []
    private(set) var isLoading = false
    private(set) var lastRefreshDate: Date?

    @ObservationIgnored private var refreshTask: Task<[AgentVaultSession], Never>?

    private init() {}

    func refreshIfNeeded() async {
        guard let lastRefreshDate else {
            await refresh()
            return
        }
        guard Date().timeIntervalSince(lastRefreshDate) > 60 else { return }
        await refresh()
    }

    func refresh() async {
        if let refreshTask {
            sessions = await refreshTask.value
            return
        }

        isLoading = true
        let task = Task {
            await AgentVaultScanner.scan()
        }
        refreshTask = task
        let scanned = await task.value
        sessions = scanned
        lastRefreshDate = Date()
        isLoading = false
        refreshTask = nil
    }

    func deleteSession(_ session: AgentVaultSession) async -> AgentVaultDeletionResult {
        await deleteSessions([session])
    }

    func deleteSessions(_ targetSessions: [AgentVaultSession]) async -> AgentVaultDeletionResult {
        let result = await Task.detached(priority: .userInitiated) {
            AgentVaultDeletionService.deleteSessions(targetSessions)
        }.value

        if !result.deletedSessionIDs.isEmpty {
            sessions.removeAll { result.deletedSessionIDs.contains($0.id) }
            lastRefreshDate = Date()
        }

        return result
    }
}
