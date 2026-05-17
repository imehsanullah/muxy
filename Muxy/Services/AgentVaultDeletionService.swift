import Foundation

struct AgentVaultDeletionResult: Equatable {
    let deletedSessionIDs: Set<String>
    let deletedFileCount: Int
    let failures: [AgentVaultDeletionFailure]

    var deletedSessionCount: Int {
        deletedSessionIDs.count
    }
}

struct AgentVaultDeletionFailure: Equatable {
    let sessionID: String
    let displayTitle: String
    let path: String?
    let message: String
}

enum AgentVaultDeletionService {
    static func deleteSessions(
        _ sessions: [AgentVaultSession],
        fileManager: FileManager = .default
    ) -> AgentVaultDeletionResult {
        var deletedSessionIDs = Set<String>()
        var deletedFileCount = 0
        var failures: [AgentVaultDeletionFailure] = []
        var deletedPaths = Set<String>()

        for session in sessions {
            guard let path = session.transcriptPath?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !path.isEmpty
            else {
                failures.append(failure(for: session, message: "Session has no transcript path."))
                continue
            }

            let url = URL(fileURLWithPath: path).standardizedFileURL
            if deletedPaths.contains(url.path) {
                deletedSessionIDs.insert(session.id)
                continue
            }

            guard fileManager.fileExists(atPath: url.path) else {
                deletedSessionIDs.insert(session.id)
                deletedPaths.insert(url.path)
                continue
            }

            do {
                try fileManager.removeItem(at: url)
                deletedSessionIDs.insert(session.id)
                deletedPaths.insert(url.path)
                deletedFileCount += 1
            } catch {
                failures.append(failure(for: session, path: url.path, message: error.localizedDescription))
            }
        }

        return AgentVaultDeletionResult(
            deletedSessionIDs: deletedSessionIDs,
            deletedFileCount: deletedFileCount,
            failures: failures
        )
    }

    private static func failure(
        for session: AgentVaultSession,
        path: String? = nil,
        message: String
    ) -> AgentVaultDeletionFailure {
        AgentVaultDeletionFailure(
            sessionID: session.id,
            displayTitle: session.displayTitle,
            path: path ?? session.transcriptPath,
            message: message
        )
    }
}
