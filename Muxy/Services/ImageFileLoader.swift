import Foundation

struct LoadedImageFile {
    let data: Data
    let byteCount: Int
}

enum ImageFileLoaderError: LocalizedError {
    case missingFile
    case fileTooLarge(maxBytes: Int)
    case invalidImage
    case remoteReadFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingFile:
            "Image file could not be read."
        case let .fileTooLarge(maxBytes):
            "Image is larger than \(ByteCountFormatter.string(fromByteCount: Int64(maxBytes), countStyle: .file))."
        case .invalidImage:
            "Image format is not supported."
        case let .remoteReadFailed(message):
            message.isEmpty ? "Remote image file could not be read." : message
        }
    }
}

enum ImageFileLoader {
    static let maxImageBytes = 50 * 1024 * 1024

    static func loadData(filePath: String, remoteHost: String?) async throws -> LoadedImageFile {
        if let remoteHost {
            return try await loadRemoteData(filePath: filePath, remoteHost: remoteHost)
        }
        return try await GitProcessRunner.offMainThrowing {
            try loadLocalData(filePath: filePath)
        }
    }

    static func remoteReadCommand(filePath: String, maxBytes: Int = maxImageBytes) -> String {
        let escapedPath = ShellCommandEscaping.escape(filePath)
        return "bytes=$(wc -c < \(escapedPath) | tr -d '[:space:]') || exit 1; "
            + "[ \"${bytes:-0}\" -le \(maxBytes) ] || exit 2; "
            + "cat -- \(escapedPath)"
    }

    private static func loadLocalData(filePath: String) throws -> LoadedImageFile {
        let url = URL(fileURLWithPath: filePath)
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            throw ImageFileLoaderError.missingFile
        }
        guard size <= maxImageBytes else {
            throw ImageFileLoaderError.fileTooLarge(maxBytes: maxImageBytes)
        }
        let data = try Data(contentsOf: url)
        guard data.count <= maxImageBytes else {
            throw ImageFileLoaderError.fileTooLarge(maxBytes: maxImageBytes)
        }
        return LoadedImageFile(data: data, byteCount: data.count)
    }

    private static func loadRemoteData(filePath: String, remoteHost: String) async throws -> LoadedImageFile {
        let result = try await GitProcessRunner.runRemoteShell(
            sshDestination: remoteHost,
            command: remoteReadCommand(filePath: filePath),
            signpostName: "remote-image"
        )
        guard result.status == 0 else {
            if result.status == 2 {
                throw ImageFileLoaderError.fileTooLarge(maxBytes: maxImageBytes)
            }
            throw ImageFileLoaderError.remoteReadFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard !result.stdoutData.isEmpty else {
            throw ImageFileLoaderError.missingFile
        }
        guard result.stdoutData.count <= maxImageBytes else {
            throw ImageFileLoaderError.fileTooLarge(maxBytes: maxImageBytes)
        }
        return LoadedImageFile(data: result.stdoutData, byteCount: result.stdoutData.count)
    }
}
