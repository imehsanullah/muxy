import Foundation
import Testing

@testable import Muxy

@Suite("AgentVaultModels")
struct AgentVaultModelsTests {
    @Test("folder grouping key preserves distinct same-named folders")
    func folderGroupingKeyPreservesDistinctSameNamedFolders() {
        let first = makeSession(id: "first", cwd: "/tmp/one/muxy")
        let second = makeSession(id: "second", cwd: "/tmp/two/muxy")

        #expect(first.folderName == "muxy")
        #expect(second.folderName == "muxy")
        #expect(first.folderGroupingKey != second.folderGroupingKey)
    }

    @Test("missing folder metadata uses unknown group")
    func missingFolderMetadataUsesUnknownGroup() {
        let session = makeSession(id: "unknown", cwd: " ")

        #expect(session.folderName == nil)
        #expect(session.folderDisplayName == "Unknown")
        #expect(session.folderGroupingKey == "unknown")
    }

    private func makeSession(id: String, cwd: String?) -> AgentVaultSession {
        AgentVaultSession(
            id: id,
            agent: .codex,
            sessionID: id,
            title: "Test session",
            cwd: cwd,
            gitBranch: "dev",
            model: "gpt",
            modified: Date(timeIntervalSince1970: 1_700_000_000),
            transcriptPath: "/tmp/\(id).jsonl",
            resumeCommand: "codex resume \(id)"
        )
    }
}
