import Foundation

@MainActor
@Observable
final class VCSStateStore {
    static let shared = VCSStateStore()

    private(set) var states: [String: VCSTabState] = [:]

    private init() {}

    func state(for path: String, remoteHost: String? = nil) -> VCSTabState {
        let key = Self.key(path: path, remoteHost: remoteHost)
        if let existing = states[key] { return existing }
        let state = VCSTabState(projectPath: path, remoteHost: remoteHost)
        states[key] = state
        return state
    }

    func cachedState(for path: String, remoteHost: String? = nil) -> VCSTabState? {
        states[Self.key(path: path, remoteHost: remoteHost)]
    }

    func remove(path: String, remoteHost: String? = nil) {
        states.removeValue(forKey: Self.key(path: path, remoteHost: remoteHost))
    }

    private static func key(path: String, remoteHost: String?) -> String {
        let trimmedHost = remoteHost?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmedHost, !trimmedHost.isEmpty else { return "local:\(canonicalize(path))" }
        return "ssh:\(trimmedHost):\(path)"
    }

    private static func canonicalize(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }
}
