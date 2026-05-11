import Foundation

enum ExternalEditorCommand {
    private static let imageFileExtensions: Set<String> = [
        "avif",
        "bmp",
        "gif",
        "heic",
        "heif",
        "jpeg",
        "jpg",
        "png",
        "tif",
        "tiff",
        "webp",
    ]

    static func remoteCommand(preferredCommand: String) -> String {
        let command = preferredCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return vimMouseCommand(executable: "vim", arguments: "") }
        return commandWithMouseSupportIfNeeded(command)
    }

    static func isImageFile(_ filePath: String) -> Bool {
        let pathExtension = (filePath as NSString).pathExtension.lowercased()
        return imageFileExtensions.contains(pathExtension)
    }

    private static func commandWithMouseSupportIfNeeded(_ command: String) -> String {
        let parts = command.split(maxSplits: 1, whereSeparator: \.isWhitespace)
        guard let executable = parts.first.map(String.init) else { return command }
        guard ["vim", "nvim"].contains(executable) else { return command }
        guard !command.contains("mouse=") else { return command }
        let arguments = parts.count > 1 ? String(parts[1]) : ""
        return vimMouseCommand(executable: executable, arguments: arguments)
    }

    private static func vimMouseCommand(executable: String, arguments: String) -> String {
        let mouseCommand = "\(executable) -c 'set mouse=a'"
        guard !arguments.isEmpty else { return mouseCommand }
        return "\(mouseCommand) \(arguments)"
    }
}
