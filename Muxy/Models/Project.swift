import Foundation

struct Project: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var path: String
    var remoteHost: String?
    var sortOrder: Int
    var createdAt: Date
    var icon: String?
    var logo: String?
    var iconColor: String?

    init(name: String, path: String, remoteHost: String? = nil, sortOrder: Int = 0) {
        self.id = UUID()
        self.name = name
        self.path = path
        self.remoteHost = remoteHost?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.sortOrder = sortOrder
        self.createdAt = Date()
        self.icon = nil
        self.logo = nil
        self.iconColor = nil
    }

    var isRemote: Bool {
        guard let remoteHost else { return false }
        return !remoteHost.isEmpty
    }

    var sshDestination: String? {
        guard let remoteHost = remoteHost?.trimmingCharacters(in: .whitespacesAndNewlines),
              !remoteHost.isEmpty
        else { return nil }
        return remoteHost
    }

    var locationLabel: String {
        guard let sshDestination else { return path }
        return "\(sshDestination):\(path)"
    }

    var terminalWorkingDirectory: String {
        isRemote ? NSHomeDirectory() : path
    }

    var terminalStartupCommand: String? {
        guard let sshDestination else { return nil }
        return RemoteProjectSessionCommand.make(
            sshDestination: sshDestination,
            remotePath: path
        )
    }

    var pathExists: Bool {
        if isRemote {
            return true
        }
        return FileManager.default.fileExists(atPath: path)
    }
}
