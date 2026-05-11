import Foundation

struct LoadedPreviewFile {
    let data: Data
    let byteCount: Int
}

enum PreviewFileLoaderError: LocalizedError {
    case missingFile
    case fileTooLarge(maxBytes: Int)
    case invalidFormat(String)
    case remoteReadFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingFile:
            "File could not be read."
        case let .fileTooLarge(maxBytes):
            "File is larger than \(ByteCountFormatter.string(fromByteCount: Int64(maxBytes), countStyle: .file))."
        case let .invalidFormat(message):
            message
        case let .remoteReadFailed(message):
            message.isEmpty ? "Remote file could not be read." : message
        }
    }
}

enum PreviewFileLoader {
    static let maxImageBytes = 50 * 1024 * 1024
    static let maxPDFBytes = 100 * 1024 * 1024

    static func loadData(
        filePath: String,
        remoteHost: String?,
        maxBytes: Int,
        signpostName: StaticString
    ) async throws -> LoadedPreviewFile {
        if let remoteHost {
            return try await loadRemoteData(
                filePath: filePath,
                remoteHost: remoteHost,
                maxBytes: maxBytes,
                signpostName: signpostName
            )
        }
        return try await GitProcessRunner.offMainThrowing {
            try loadLocalData(filePath: filePath, maxBytes: maxBytes)
        }
    }

    static func remoteReadCommand(filePath: String, maxBytes: Int) -> String {
        let escapedPath = ShellCommandEscaping.escape(filePath)
        return "bytes=$(wc -c < \(escapedPath) | tr -d '[:space:]') || exit 1; "
            + "[ \"${bytes:-0}\" -le \(maxBytes) ] || exit 2; "
            + "cat -- \(escapedPath)"
    }

    private static func loadLocalData(filePath: String, maxBytes: Int) throws -> LoadedPreviewFile {
        let url = URL(fileURLWithPath: filePath)
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            throw PreviewFileLoaderError.missingFile
        }
        guard size <= maxBytes else {
            throw PreviewFileLoaderError.fileTooLarge(maxBytes: maxBytes)
        }
        let data = try Data(contentsOf: url)
        guard data.count <= maxBytes else {
            throw PreviewFileLoaderError.fileTooLarge(maxBytes: maxBytes)
        }
        return LoadedPreviewFile(data: data, byteCount: data.count)
    }

    private static func loadRemoteData(
        filePath: String,
        remoteHost: String,
        maxBytes: Int,
        signpostName: StaticString
    ) async throws -> LoadedPreviewFile {
        let result = try await GitProcessRunner.runRemoteShell(
            sshDestination: remoteHost,
            command: remoteReadCommand(filePath: filePath, maxBytes: maxBytes),
            signpostName: signpostName
        )
        guard result.status == 0 else {
            if result.status == 2 {
                throw PreviewFileLoaderError.fileTooLarge(maxBytes: maxBytes)
            }
            throw PreviewFileLoaderError.remoteReadFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard !result.stdoutData.isEmpty else {
            throw PreviewFileLoaderError.missingFile
        }
        guard result.stdoutData.count <= maxBytes else {
            throw PreviewFileLoaderError.fileTooLarge(maxBytes: maxBytes)
        }
        return LoadedPreviewFile(data: result.stdoutData, byteCount: result.stdoutData.count)
    }
}
