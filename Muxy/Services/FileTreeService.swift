import Foundation

struct FileTreeEntry: Hashable {
    let name: String
    let absolutePath: String
    let relativePath: String
    let isDirectory: Bool
    let isIgnored: Bool
}

enum FileTreeService {
    static func loadChildren(
        of directoryAbsolutePath: String,
        repoRoot: String,
        remoteHost: String? = nil
    ) async -> [FileTreeEntry] {
        if let remoteHost {
            return await loadRemoteChildren(of: directoryAbsolutePath, repoRoot: repoRoot, remoteHost: remoteHost)
        }
        return await GitProcessRunner.offMain {
            loadChildrenSync(of: directoryAbsolutePath, repoRoot: repoRoot)
        }
    }

    private static func loadRemoteChildren(
        of directoryAbsolutePath: String,
        repoRoot: String,
        remoteHost: String
    ) async -> [FileTreeEntry] {
        do {
            let result = try await GitProcessRunner.runRemoteShell(
                sshDestination: remoteHost,
                command: remoteListCommand(directoryAbsolutePath: directoryAbsolutePath)
            )
            guard result.status == 0 else { return [] }
            let names = remoteCandidateNames(from: result.stdoutData)
            let ignored = await remoteIgnoredNames(
                directoryAbsolutePath: directoryAbsolutePath,
                repoRoot: repoRoot,
                remoteHost: remoteHost,
                candidates: names
            )
            return parseRemoteFindOutput(result.stdoutData, repoRoot: repoRoot, ignored: ignored)
        } catch {
            return []
        }
    }

    private static func loadChildrenSync(of directoryAbsolutePath: String, repoRoot: String) -> [FileTreeEntry] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: directoryAbsolutePath) else {
            return []
        }

        let classification = classifyNames(in: directoryAbsolutePath, repoRoot: repoRoot, candidates: contents)
        let normalizedRoot = repoRoot.hasSuffix("/") ? String(repoRoot.dropLast()) : repoRoot

        var entries: [FileTreeEntry] = []
        entries.reserveCapacity(classification.visible.count)

        for name in classification.visible {
            if name == "." || name == ".." { continue }
            let absolute = directoryAbsolutePath.hasSuffix("/")
                ? directoryAbsolutePath + name
                : directoryAbsolutePath + "/" + name

            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: absolute, isDirectory: &isDir) else { continue }

            let relative: String = if absolute.hasPrefix(normalizedRoot + "/") {
                String(absolute.dropFirst(normalizedRoot.count + 1))
            } else {
                name
            }

            entries.append(FileTreeEntry(
                name: name,
                absolutePath: absolute,
                relativePath: relative,
                isDirectory: isDir.boolValue,
                isIgnored: classification.ignored.contains(name)
            ))
        }

        return sort(entries)
    }

    private struct NameClassification {
        let visible: [String]
        let ignored: Set<String>
    }

    private static func classifyNames(
        in directoryAbsolutePath: String,
        repoRoot: String,
        candidates: [String]
    ) -> NameClassification {
        let isRepoChild = isInsideRepo(path: directoryAbsolutePath, repoRoot: repoRoot)
        guard isRepoChild else {
            return NameClassification(visible: candidates, ignored: [])
        }

        let ignored = ignoredNames(directoryAbsolutePath: directoryAbsolutePath, candidates: candidates)
        let visible = candidates.filter { $0 != ".git" }
        return NameClassification(visible: visible, ignored: ignored)
    }

    private static func isInsideRepo(path: String, repoRoot: String) -> Bool {
        let normalizedRoot = repoRoot.hasSuffix("/") ? String(repoRoot.dropLast()) : repoRoot
        return path == normalizedRoot || path.hasPrefix(normalizedRoot + "/")
    }

    private static func ignoredNames(
        directoryAbsolutePath: String,
        candidates: [String]
    ) -> Set<String> {
        guard !candidates.isEmpty else { return [] }
        guard let gitPath = GitProcessRunner.resolveExecutable("git") else { return [] }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: gitPath)
        process.arguments = ["check-ignore", "-z", "--stdin"]
        process.currentDirectoryURL = URL(fileURLWithPath: directoryAbsolutePath)

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return []
        }

        var payload = Data()
        for name in candidates {
            if let data = name.data(using: .utf8) {
                payload.append(data)
                payload.append(0)
            }
        }
        try? stdinPipe.fileHandleForWriting.write(contentsOf: payload)
        try? stdinPipe.fileHandleForWriting.close()

        let outData = (try? stdoutPipe.fileHandleForReading.readToEnd()) ?? Data()
        _ = try? stderrPipe.fileHandleForReading.readToEnd()
        process.waitUntilExit()

        return parseNullSeparatedNames(outData)
    }

    static func remoteListCommand(directoryAbsolutePath: String) -> String {
        "find \(ShellCommandEscaping.escape(directoryAbsolutePath)) -mindepth 1 -maxdepth 1 -printf '%y%p\\0' 2>/dev/null"
    }

    static func remoteIgnoredNamesCommand(directoryAbsolutePath: String) -> String {
        let findCommand = "find . -mindepth 1 -maxdepth 1 -printf '%f\\0'"
        return "cd -- \(ShellCommandEscaping.escape(directoryAbsolutePath)) && \(findCommand) | git check-ignore -z --stdin"
    }

    static func parseRemoteFindOutput(_ data: Data, repoRoot: String, ignored: Set<String>) -> [FileTreeEntry] {
        guard let output = String(data: data, encoding: .utf8) else { return [] }
        let normalizedRoot = repoRoot.hasSuffix("/") ? String(repoRoot.dropLast()) : repoRoot
        var entries: [FileTreeEntry] = []

        for record in output.split(separator: "\0", omittingEmptySubsequences: true) {
            guard let kind = record.first else { continue }
            let absolute = String(record.dropFirst())
            let name = (absolute as NSString).lastPathComponent
            guard !absolute.isEmpty, name != ".git" else { continue }
            let relative: String = if absolute.hasPrefix(normalizedRoot + "/") {
                String(absolute.dropFirst(normalizedRoot.count + 1))
            } else {
                name
            }

            entries.append(FileTreeEntry(
                name: name,
                absolutePath: absolute,
                relativePath: relative,
                isDirectory: kind == "d",
                isIgnored: ignored.contains(name)
            ))
        }

        return sort(entries)
    }

    private static func remoteCandidateNames(from data: Data) -> [String] {
        guard let output = String(data: data, encoding: .utf8) else { return [] }
        return output.split(separator: "\0", omittingEmptySubsequences: true).compactMap { record in
            guard record.count > 1 else { return nil }
            return (String(record.dropFirst()) as NSString).lastPathComponent
        }
    }

    private static func remoteIgnoredNames(
        directoryAbsolutePath: String,
        repoRoot: String,
        remoteHost: String,
        candidates: [String]
    ) async -> Set<String> {
        guard !candidates.isEmpty, isInsideRepo(path: directoryAbsolutePath, repoRoot: repoRoot) else { return [] }
        do {
            let result = try await GitProcessRunner.runRemoteShell(
                sshDestination: remoteHost,
                command: remoteIgnoredNamesCommand(directoryAbsolutePath: directoryAbsolutePath)
            )
            return parseNullSeparatedNames(result.stdoutData)
        } catch {
            return []
        }
    }

    private static func parseNullSeparatedNames(_ data: Data) -> Set<String> {
        var result: Set<String> = []
        var current = Data()
        for byte in data {
            if byte == 0 {
                if let name = String(data: current, encoding: .utf8), !name.isEmpty {
                    result.insert(name)
                }
                current.removeAll(keepingCapacity: true)
            } else {
                current.append(byte)
            }
        }
        return result
    }

    private static func sort(_ entries: [FileTreeEntry]) -> [FileTreeEntry] {
        entries.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory && !rhs.isDirectory }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}
