import Foundation

enum AgentVaultScanner {
    private struct FileCandidate {
        let url: URL
        let modified: Date
        let projectDirectoryName: String?
        let configRoot: String?
    }

    private struct ClaudeMetadata {
        var title = ""
        var cwd: String?
        var gitBranch: String?
        var model: String?
        var permissionMode: String?
    }

    private struct CodexMetadata {
        var sessionID = ""
        var title = ""
        var firstUserMessage = ""
        var cwd: String?
        var gitBranch: String?
        var model: String?
        var approvalPolicy: String?
        var sandboxMode: String?
        var effort: String?

        var displayTitle: String {
            title.isEmpty ? firstUserMessage : title
        }
    }

    private static let jsonLineByteLimit = 4 * 1024 * 1024

    static func scan(limitPerAgent: Int = 80) async -> [AgentVaultSession] {
        await Task.detached(priority: .utility) {
            let sessions = loadClaudeSessions(limit: limitPerAgent) + loadCodexSessions(limit: limitPerAgent)
            return sessions.sorted { $0.modified > $1.modified }
        }.value
    }

    static func loadClaudeSessions(
        configRoots: [String] = claudeConfigRoots(),
        limit: Int = 80
    ) -> [AgentVaultSession] {
        var candidates: [FileCandidate] = []
        for root in configRoots {
            let standardizedRoot = URL(fileURLWithPath: root).standardizedFileURL.path
            let projectsRoot = URL(fileURLWithPath: standardizedRoot, isDirectory: true)
                .appendingPathComponent("projects", isDirectory: true)
            guard let projectDirectories = try? FileManager.default.contentsOfDirectory(
                at: projectsRoot,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            else { continue }

            for directory in projectDirectories {
                guard directory.isDirectory else { continue }
                guard let files = try? FileManager.default.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                    options: [.skipsHiddenFiles]
                )
                else { continue }

                for file in files where file.pathExtension == "jsonl" {
                    guard file.isRegularFile,
                          let modified = file.contentModificationDate
                    else { continue }
                    candidates.append(FileCandidate(
                        url: file,
                        modified: modified,
                        projectDirectoryName: directory.lastPathComponent,
                        configRoot: standardizedRoot
                    ))
                }
            }
        }

        return candidates
            .sorted { $0.modified > $1.modified }
            .prefix(limit)
            .compactMap(parseClaudeSession)
    }

    static func loadCodexSessions(
        sessionsRoot: String = codexSessionsRoot(),
        limit: Int = 80
    ) -> [AgentVaultSession] {
        let rootURL = URL(fileURLWithPath: sessionsRoot, isDirectory: true).standardizedFileURL
        let codexHome = rootURL.deletingLastPathComponent().path
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        else { return [] }

        var candidates: [FileCandidate] = []
        for case let file as URL in enumerator where file.pathExtension == "jsonl" {
            guard file.isRegularFile,
                  let modified = file.contentModificationDate
            else { continue }
            candidates.append(FileCandidate(
                url: file,
                modified: modified,
                projectDirectoryName: nil,
                configRoot: codexHome
            ))
        }

        return candidates
            .sorted { $0.modified > $1.modified }
            .prefix(limit)
            .compactMap(parseCodexSession)
    }

    static func claudeConfigRoots(
        homeDirectory: String = NSHomeDirectory(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String] {
        var roots: [String] = []
        var seen = Set<String>()

        func append(_ path: String?) {
            guard let path else { return }
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let expanded = NSString(string: trimmed).expandingTildeInPath
            let standardized = URL(fileURLWithPath: expanded).standardizedFileURL.path
            let projectsPath = URL(fileURLWithPath: standardized, isDirectory: true)
                .appendingPathComponent("projects", isDirectory: true)
                .path
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: projectsPath, isDirectory: &isDirectory),
                  isDirectory.boolValue,
                  seen.insert(standardized).inserted
            else { return }
            roots.append(standardized)
        }

        append(environment["CLAUDE_CONFIG_DIR"])

        let accountsRoot = URL(fileURLWithPath: homeDirectory, isDirectory: true)
            .appendingPathComponent(".codex-accounts/claude", isDirectory: true)
        if let accountRoots = try? FileManager.default.contentsOfDirectory(
            at: accountsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for accountRoot in accountRoots.sorted(by: { $0.path < $1.path }) where accountRoot.isDirectory {
                append(accountRoot.path)
            }
        }

        append(URL(fileURLWithPath: homeDirectory, isDirectory: true)
            .appendingPathComponent(".claude", isDirectory: true)
            .path)

        return roots
    }

    static func codexSessionsRoot(homeDirectory: String = NSHomeDirectory()) -> String {
        URL(fileURLWithPath: homeDirectory, isDirectory: true)
            .appendingPathComponent(".codex/sessions", isDirectory: true)
            .path
    }

    private static func parseClaudeSession(_ candidate: FileCandidate) -> AgentVaultSession? {
        let sessionID = candidate.url.deletingPathExtension().lastPathComponent
        guard !sessionID.isEmpty else { return nil }
        let metadata = extractClaudeMetadata(from: candidate.url, projectDirectoryName: candidate.projectDirectoryName)
        let command = claudeResumeCommand(
            sessionID: sessionID,
            cwd: metadata.cwd,
            model: metadata.model,
            permissionMode: metadata.permissionMode,
            configRoot: candidate.configRoot
        )
        return AgentVaultSession(
            id: "claude:\(candidate.url.path)",
            agent: .claude,
            sessionID: sessionID,
            title: metadata.title,
            cwd: metadata.cwd,
            gitBranch: metadata.gitBranch,
            model: metadata.model,
            modified: candidate.modified,
            transcriptPath: candidate.url.path,
            resumeCommand: command
        )
    }

    private static func parseCodexSession(_ candidate: FileCandidate) -> AgentVaultSession? {
        let metadata = extractCodexMetadata(from: candidate.url)
        let sessionID = metadata.sessionID.isEmpty ? candidate.url.deletingPathExtension().lastPathComponent : metadata.sessionID
        guard !sessionID.isEmpty else { return nil }
        let command = codexResumeCommand(
            sessionID: sessionID,
            metadata: metadata,
            codexHome: candidate.configRoot
        )
        return AgentVaultSession(
            id: "codex:\(candidate.url.path)",
            agent: .codex,
            sessionID: sessionID,
            title: metadata.displayTitle,
            cwd: metadata.cwd,
            gitBranch: metadata.gitBranch,
            model: metadata.model,
            modified: candidate.modified,
            transcriptPath: candidate.url.path,
            resumeCommand: command
        )
    }

    private static func extractClaudeMetadata(from url: URL, projectDirectoryName: String?) -> ClaudeMetadata {
        var metadata = ClaudeMetadata()
        metadata.cwd = projectDirectoryName.flatMap(decodeClaudeProjectDirectory)

        forEachJSONLine(url: url, maxBytes: jsonLineByteLimit) { object in
            let type = object["type"] as? String
            let isMeta = object["isMeta"] as? Bool ?? false

            if let cwd = nonEmptyString(object["cwd"]) {
                metadata.cwd = cwd
            }
            if let branch = nonEmptyString(object["gitBranch"]) {
                metadata.gitBranch = branch
            }
            if let permissionMode = nonEmptyString(object["permissionMode"]) {
                metadata.permissionMode = permissionMode
            }
            if type == "assistant",
               let message = object["message"] as? [String: Any],
               let model = nonEmptyString(message["model"])
            {
                metadata.model = stripClaudeModelSuffix(model)
            }
            if metadata.title.isEmpty,
               type == "user",
               let message = object["message"] as? [String: Any],
               (message["role"] as? String) == "user",
               let title = claudeTitle(from: message["content"], isMeta: isMeta)
            {
                metadata.title = title
            }

            return !metadata.title.isEmpty
                && metadata.cwd != nil
                && metadata.gitBranch != nil
                && metadata.model != nil
        }

        return metadata
    }

    private static func extractCodexMetadata(from url: URL) -> CodexMetadata {
        var metadata = CodexMetadata()

        forEachJSONLine(url: url, maxBytes: jsonLineByteLimit) { object in
            let type = object["type"] as? String
            let payload = object["payload"] as? [String: Any]

            if type == "session_meta", let payload {
                if let sessionID = nonEmptyString(payload["id"]) {
                    metadata.sessionID = sessionID
                }
                if let cwd = nonEmptyString(payload["cwd"]) {
                    metadata.cwd = cwd
                }
                if let git = payload["git"] as? [String: Any],
                   let branch = nonEmptyString(git["branch"])
                {
                    metadata.gitBranch = branch
                }
            }

            if type == "turn_context", let payload {
                if let model = nonEmptyString(payload["model"]) {
                    metadata.model = model
                }
                if let approvalPolicy = nonEmptyString(payload["approval_policy"]) {
                    metadata.approvalPolicy = approvalPolicy
                }
                if let effort = nonEmptyString(payload["effort"]) {
                    metadata.effort = effort
                }
                if let sandbox = payload["sandbox_policy"] as? [String: Any],
                   let sandboxMode = nonEmptyString(sandbox["type"])
                {
                    metadata.sandboxMode = sandboxMode
                }
            }

            if type == "event_msg",
               let payload,
               (payload["type"] as? String) == "thread_name_updated",
               let threadName = nonEmptyString(payload["thread_name"])
            {
                metadata.title = threadName
            }

            if metadata.firstUserMessage.isEmpty,
               type == "event_msg",
               let payload,
               (payload["type"] as? String) == "user_message",
               let message = nonEmptyString(payload["message"]),
               let title = realCodexUserMessage(message)
            {
                metadata.firstUserMessage = title
            }

            if metadata.firstUserMessage.isEmpty,
               type == "response_item",
               let payload,
               (payload["type"] as? String) == "message",
               (payload["role"] as? String) == "user",
               let content = payload["content"] as? [[String: Any]]
            {
                for part in content {
                    guard (part["type"] as? String) == "input_text",
                          let text = nonEmptyString(part["text"]),
                          let title = realCodexUserMessage(text)
                    else { continue }
                    metadata.firstUserMessage = title
                    break
                }
            }

            return !metadata.title.isEmpty
                && metadata.cwd != nil
                && !metadata.sessionID.isEmpty
                && metadata.model != nil
        }

        return metadata
    }

    static func forEachJSONLine(
        url: URL,
        maxBytes: Int,
        body: ([String: Any]) -> Bool
    ) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }

        var buffered = Data()
        var totalRead = 0
        let chunkSize = 64 * 1024

        while totalRead < maxBytes {
            let chunk = (try? handle.read(upToCount: chunkSize)) ?? Data()
            if chunk.isEmpty { break }
            totalRead += chunk.count
            buffered.append(chunk)

            while let newlineIndex = buffered.firstIndex(of: 0x0A) {
                let lineData = buffered.subdata(in: 0 ..< newlineIndex)
                buffered.removeSubrange(0 ..< (newlineIndex + 1))
                if parseJSONLine(lineData, body: body) {
                    return
                }
            }
        }

        if !buffered.isEmpty {
            _ = parseJSONLine(buffered, body: body)
        }
    }

    private static func parseJSONLine(_ data: Data, body: ([String: Any]) -> Bool) -> Bool {
        guard !data.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        return body(object)
    }

    private static func claudeResumeCommand(
        sessionID: String,
        cwd: String?,
        model: String?,
        permissionMode: String?,
        configRoot: String?
    ) -> String {
        var parts = ["claude --resume \(ShellEscaper.escape(sessionID))"]
        if let model, !model.isEmpty {
            parts.append("--model \(ShellEscaper.escape(model))")
        }
        if let permissionMode, !permissionMode.isEmpty {
            parts.append("--permission-mode \(ShellEscaper.escape(permissionMode))")
        }
        var command = parts.joined(separator: " ")
        if let configRoot, shouldSetClaudeConfigDirectory(configRoot) {
            command = "env CLAUDE_CONFIG_DIR=\(ShellEscaper.escape(configRoot)) \(command)"
        }
        return commandWithWorkingDirectory(cwd, command: command)
    }

    private static func codexResumeCommand(
        sessionID: String,
        metadata: CodexMetadata,
        codexHome: String?
    ) -> String {
        var parts = ["codex resume \(ShellEscaper.escape(sessionID))"]
        if let model = metadata.model, !model.isEmpty {
            parts.append("-m \(ShellEscaper.escape(model))")
        }
        if let approvalPolicy = metadata.approvalPolicy, !approvalPolicy.isEmpty {
            parts.append("-a \(ShellEscaper.escape(approvalPolicy))")
        }
        if let sandboxMode = metadata.sandboxMode, !sandboxMode.isEmpty {
            parts.append("-s \(ShellEscaper.escape(sandboxMode))")
        }
        if let effort = metadata.effort, !effort.isEmpty {
            parts.append("-c model_reasoning_effort=\(ShellEscaper.escape(effort))")
        }
        var command = parts.joined(separator: " ")
        if let codexHome, !codexHome.isEmpty {
            command = "env CODEX_HOME=\(ShellEscaper.escape(codexHome)) \(command)"
        }
        return commandWithWorkingDirectory(metadata.cwd, command: command)
    }

    private static func commandWithWorkingDirectory(_ cwd: String?, command: String) -> String {
        guard let cwd = cwd?.trimmingCharacters(in: .whitespacesAndNewlines),
              !cwd.isEmpty
        else { return command }
        return "cd -- \(ShellEscaper.escape(cwd)) && \(command)"
    }

    private static func shouldSetClaudeConfigDirectory(_ configRoot: String) -> Bool {
        let defaultRoot = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent(".claude", isDirectory: true)
            .standardizedFileURL
            .path
        return URL(fileURLWithPath: configRoot).standardizedFileURL.path != defaultRoot
    }

    private static func decodeClaudeProjectDirectory(_ raw: String) -> String? {
        guard !raw.isEmpty else { return nil }
        let stripped = raw.hasPrefix("-") ? String(raw.dropFirst()) : raw
        let candidate = "/" + stripped.replacingOccurrences(of: "-", with: "/")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: candidate, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { return nil }
        return candidate
    }

    private static func claudeTitle(from value: Any?, isMeta: Bool) -> String? {
        if isMeta {
            return nil
        }
        if let string = value as? String {
            return normalizedTitle(string)
        }
        if let parts = value as? [[String: Any]] {
            for part in parts {
                guard (part["type"] as? String) == "text",
                      let text = nonEmptyString(part["text"]),
                      let title = normalizedTitle(text)
                else { continue }
                return title
            }
        }
        return nil
    }

    private static func normalizedTitle(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("<command-") || trimmed.hasPrefix("<local-command") {
            return nil
        }
        if trimmed.hasPrefix("<system-reminder>") {
            return nil
        }
        return String(trimmed.prefix(180))
    }

    private static func realCodexUserMessage(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let ignoredPrefixes = [
            "<environment_context",
            "<user_instructions",
            "<permissions",
            "<system",
            "# AGENTS.md",
        ]
        guard !ignoredPrefixes.contains(where: { trimmed.hasPrefix($0) }) else {
            return nil
        }
        return String(trimmed.prefix(180))
    }

    private static func stripClaudeModelSuffix(_ model: String) -> String {
        guard let bracket = model.firstIndex(of: "[") else { return model }
        return String(model[..<bracket])
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension URL {
    var isDirectory: Bool {
        (try? resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    var isRegularFile: Bool {
        (try? resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }

    var contentModificationDate: Date? {
        try? resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}
