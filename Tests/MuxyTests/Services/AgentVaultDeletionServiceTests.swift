import Foundation
import Testing

@testable import Muxy

@Suite("AgentVaultDeletionService")
struct AgentVaultDeletionServiceTests {
    @Test("deletes transcript file and reports session")
    func deletesTranscriptFileAndReportsSession() throws {
        let root = try temporaryDirectory()
        let file = root.appendingPathComponent("session.jsonl")
        try "{}\n".write(to: file, atomically: true, encoding: .utf8)
        let session = makeSession(id: "codex:file", path: file.path)

        let result = AgentVaultDeletionService.deleteSessions([session])

        #expect(result.deletedSessionIDs == Set([session.id]))
        #expect(result.deletedFileCount == 1)
        #expect(result.failures.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test("missing transcript file removes stale session")
    func missingTranscriptFileRemovesStaleSession() throws {
        let root = try temporaryDirectory()
        let file = root.appendingPathComponent("missing.jsonl")
        let session = makeSession(id: "codex:missing", path: file.path)

        let result = AgentVaultDeletionService.deleteSessions([session])

        #expect(result.deletedSessionIDs == Set([session.id]))
        #expect(result.deletedFileCount == 0)
        #expect(result.failures.isEmpty)
    }

    @Test("session without transcript path reports failure")
    func sessionWithoutTranscriptPathReportsFailure() {
        let session = makeSession(id: "codex:no-path", path: nil)

        let result = AgentVaultDeletionService.deleteSessions([session])

        #expect(result.deletedSessionIDs.isEmpty)
        #expect(result.deletedFileCount == 0)
        #expect(result.failures.count == 1)
        #expect(result.failures[0].sessionID == session.id)
    }

    private func makeSession(id: String, path: String?) -> AgentVaultSession {
        AgentVaultSession(
            id: id,
            agent: .codex,
            sessionID: id,
            title: "Test session",
            cwd: "/tmp/muxy-project",
            gitBranch: "dev",
            model: "gpt",
            modified: Date(timeIntervalSince1970: 1_700_000_000),
            transcriptPath: path,
            resumeCommand: "codex resume \(id)"
        )
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentVaultDeletionServiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
