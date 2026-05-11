import Foundation

enum RemoteFileServiceError: LocalizedError {
    case commandFailed(String)
    case invalidTextEncoding

    var errorDescription: String? {
        switch self {
        case let .commandFailed(message):
            message
        case .invalidTextEncoding:
            "Remote file content is not valid UTF-8."
        }
    }
}

enum RemoteFileService {
    static func fileSize(path: String, sshDestination: String) async throws -> Int64? {
        let result = try await GitProcessRunner.runRemoteShell(
            sshDestination: sshDestination,
            command: fileSizeCommand(path: path),
            signpostName: "remote-file-size"
        )
        guard result.status == 0 else {
            throw RemoteFileServiceError.commandFailed(remoteErrorMessage(
                stderr: result.stderr,
                fallback: "Failed to inspect remote file."
            ))
        }
        return Int64(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func readFile(path: String, sshDestination: String) async throws -> Data {
        let result = try await GitProcessRunner.runRemoteShell(
            sshDestination: sshDestination,
            command: readCommand(path: path),
            signpostName: "remote-file-read"
        )
        guard result.status == 0 else {
            throw RemoteFileServiceError.commandFailed(remoteErrorMessage(
                stderr: result.stderr,
                fallback: "Failed to read remote file."
            ))
        }
        return result.stdoutData
    }

    static func writeFile(text: String, path: String, sshDestination: String) async throws {
        guard let data = text.data(using: .utf8) else {
            throw RemoteFileServiceError.invalidTextEncoding
        }
        try await GitProcessRunner.offMainThrowing {
            try writeFileSync(data: data, path: path, sshDestination: sshDestination)
        }
    }

    static func fileSizeCommand(path: String) -> String {
        "wc -c < \(ShellCommandEscaping.escape(path))"
    }

    static func readCommand(path: String) -> String {
        "cat -- \(ShellCommandEscaping.escape(path))"
    }

    static func writeCommand(path: String, tempIdentifier: String) -> String {
        let tempPath = temporaryPath(for: path, identifier: tempIdentifier)
        let escapedPath = ShellCommandEscaping.escape(path)
        let escapedTempPath = ShellCommandEscaping.escape(tempPath)
        let cleanup = "rm -f \(ShellCommandEscaping.escape(tempPath))"
        let mode = "mode=$(stat -c %a \(escapedPath) 2>/dev/null || stat -f %Lp \(escapedPath) 2>/dev/null || true)"
        let write = "cat > \(escapedTempPath)"
        let applyMode = "[ -z \"$mode\" ] || chmod \"$mode\" \(escapedTempPath)"
        let move = "mv -f \(escapedTempPath) \(escapedPath)"
        return [
            "trap \(ShellCommandEscaping.escape(cleanup)) EXIT",
            mode,
            "\(write) && \(applyMode) && \(move)",
        ].joined(separator: "; ")
    }

    private static func writeFileSync(data: Data, path: String, sshDestination: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "ssh",
            "-o",
            "BatchMode=yes",
            "-o",
            "ConnectTimeout=10",
            sshDestination,
            writeCommand(path: path, tempIdentifier: UUID().uuidString.lowercased()),
        ]

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw RemoteFileServiceError.commandFailed(error.localizedDescription)
        }

        stdinPipe.fileHandleForWriting.write(data)
        try? stdinPipe.fileHandleForWriting.close()

        _ = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""
            throw RemoteFileServiceError.commandFailed(remoteErrorMessage(
                stderr: stderr,
                fallback: "Failed to write remote file."
            ))
        }
    }

    private static func temporaryPath(for path: String, identifier: String) -> String {
        let nsPath = path as NSString
        let directory = nsPath.deletingLastPathComponent
        let filename = nsPath.lastPathComponent
        let tempName = ".\(filename).muxy-\(identifier).tmp"
        guard directory != "/" else { return "/\(tempName)" }
        return "\(directory)/\(tempName)"
    }

    private static func remoteErrorMessage(stderr: String, fallback: String) -> String {
        let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
