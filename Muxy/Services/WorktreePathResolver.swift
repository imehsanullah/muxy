import Foundation

enum WorktreePathResolver {
    static func path(for project: Project, name: String) -> String {
        let slug = slug(from: name)
        if project.isRemote {
            let projectURL = URL(fileURLWithPath: project.path)
            let parentURL = projectURL.deletingLastPathComponent()
            let baseName = projectURL.lastPathComponent
            return parentURL
                .appendingPathComponent("\(baseName)-\(slug)", isDirectory: true)
                .path(percentEncoded: false)
        }

        return MuxyFileStorage
            .worktreeDirectory(forProjectID: project.id, name: slug)
            .path(percentEncoded: false)
    }

    static func slug(from name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let scalars = name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let collapsed = String(scalars)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return collapsed.isEmpty ? UUID().uuidString : collapsed
    }
}
