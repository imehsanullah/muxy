import Foundation

enum AgentVaultAgent: String, CaseIterable, Codable, Identifiable {
    case claude
    case codex

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude:
            "Claude Code"
        case .codex:
            "Codex"
        }
    }

    var iconName: String {
        switch self {
        case .claude:
            "claude"
        case .codex:
            "codex"
        }
    }
}

struct AgentVaultSession: Identifiable, Equatable, Codable {
    let id: String
    let agent: AgentVaultAgent
    let sessionID: String
    let title: String
    let cwd: String?
    let gitBranch: String?
    let model: String?
    let modified: Date
    let transcriptPath: String?
    let resumeCommand: String

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        return "Untitled session"
    }

    var folderName: String? {
        guard let cwd = cwd?.trimmingCharacters(in: .whitespacesAndNewlines),
              !cwd.isEmpty
        else { return nil }
        let url = URL(fileURLWithPath: cwd, isDirectory: true)
        let name = url.lastPathComponent
        return name.isEmpty ? url.path : name
    }

    var folderDisplayName: String {
        folderName ?? "Unknown"
    }

    var folderGroupingKey: String {
        guard let cwd = cwd?.trimmingCharacters(in: .whitespacesAndNewlines),
              !cwd.isEmpty
        else { return "unknown" }
        let expanded = NSString(string: cwd).expandingTildeInPath
        return URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL.path
    }

    var tabTitle: String {
        "\(agent.displayName) · \(displayTitle)"
    }
}
