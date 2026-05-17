import Foundation
import Testing

@testable import Muxy

@Suite("AgentVaultScanner")
struct AgentVaultScannerTests {
    @Test("loads Claude sessions and builds exact resume command")
    func loadsClaudeSessions() throws {
        let root = try temporaryDirectory()
        let configRoot = root.appendingPathComponent("claude", isDirectory: true)
        let projectRoot = configRoot
            .appendingPathComponent("projects", isDirectory: true)
            .appendingPathComponent("-tmp-muxy-project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        let file = projectRoot.appendingPathComponent("claude-session.jsonl")
        try """
        {"type":"user","cwd":"/tmp/muxy-project","gitBranch":"dev","message":{"role":"user","content":"Implement the vault"}}
        {"type":"assistant","message":{"model":"claude-sonnet-4-7"}}
        """.write(to: file, atomically: true, encoding: .utf8)

        let sessions = AgentVaultScanner.loadClaudeSessions(configRoots: [configRoot.path], limit: 10)

        #expect(sessions.count == 1)
        #expect(sessions[0].agent == .claude)
        #expect(sessions[0].sessionID == "claude-session")
        #expect(sessions[0].displayTitle == "Implement the vault")
        #expect(sessions[0].cwd == "/tmp/muxy-project")
        #expect(sessions[0].gitBranch == "dev")
        #expect(sessions[0].model == "claude-sonnet-4-7")
        #expect(sessions[0].resumeCommand.contains("CLAUDE_CONFIG_DIR="))
        #expect(sessions[0].resumeCommand.contains("claude --resume claude-session"))
    }

    @Test("loads Codex sessions and preserves launch flags")
    func loadsCodexSessions() throws {
        let root = try temporaryDirectory()
        let sessionsRoot = root.appendingPathComponent("codex/sessions/2026/05/16", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionsRoot, withIntermediateDirectories: true)
        let file = sessionsRoot.appendingPathComponent("rollout.jsonl")
        try """
        {"type":"session_meta","payload":{"id":"codex-session","cwd":"/tmp/muxy-project","git":{"branch":"dev"}}}
        {"type":"turn_context","payload":{"model":"gpt-5.3-codex","approval_policy":"never","sandbox_policy":{"type":"workspace-write"},"effort":"high"}}
        {"type":"event_msg","payload":{"type":"thread_name_updated","thread_name":"Build the vault"}}
        """.write(to: file, atomically: true, encoding: .utf8)

        let sessions = AgentVaultScanner.loadCodexSessions(sessionsRoot: root.appendingPathComponent("codex/sessions").path, limit: 10)

        #expect(sessions.count == 1)
        #expect(sessions[0].agent == .codex)
        #expect(sessions[0].sessionID == "codex-session")
        #expect(sessions[0].displayTitle == "Build the vault")
        #expect(sessions[0].cwd == "/tmp/muxy-project")
        #expect(sessions[0].gitBranch == "dev")
        #expect(sessions[0].model == "gpt-5.3-codex")
        #expect(sessions[0].resumeCommand.contains(
            "env CODEX_HOME=\(ShellEscaper.escape(root.appendingPathComponent("codex").path)) codex resume codex-session"
        ))
        #expect(sessions[0].resumeCommand.contains("-m gpt-5.3-codex"))
        #expect(sessions[0].resumeCommand.contains("-a never"))
        #expect(sessions[0].resumeCommand.contains("-s workspace-write"))
        #expect(sessions[0].resumeCommand.contains("model_reasoning_effort=high"))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentVaultScannerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
