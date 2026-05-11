import Foundation
import Testing

@testable import Muxy

@Suite("FileTreeService")
struct FileTreeServiceTests {
    @Test("remote list command quotes the directory path")
    func remoteListCommandQuotesDirectoryPath() {
        let command = FileTreeService.remoteListCommand(directoryAbsolutePath: "/srv/my repo")

        #expect(command == "find '/srv/my repo' -mindepth 1 -maxdepth 1 -printf '%y%p\\0' 2>/dev/null")
    }

    @Test("remote ignored names command streams directory children")
    func remoteIgnoredNamesCommandStreamsDirectoryChildren() {
        let command = FileTreeService.remoteIgnoredNamesCommand(directoryAbsolutePath: "/srv/my repo")
        let findCommand = "find . -mindepth 1 -maxdepth 1 -printf '%f\\0'"
        let expected = "cd -- \(ShellCommandEscaping.escape("/srv/my repo")) && \(findCommand) | git check-ignore -z --stdin"

        #expect(command == expected)
    }

    @Test("remote find output parses entries sorted with directories first")
    func remoteFindOutputParsesEntries() {
        let payload = "f/srv/repo/z.txt\0d/srv/repo/src\0d/srv/repo/.git\0f/srv/repo/a.txt\0f/srv/repo/build.log\0"
        let entries = FileTreeService.parseRemoteFindOutput(
            Data(payload.utf8),
            repoRoot: "/srv/repo",
            ignored: ["build.log"]
        )

        #expect(entries.map(\.name) == ["src", "a.txt", "build.log", "z.txt"])
        #expect(entries.map(\.relativePath) == ["src", "a.txt", "build.log", "z.txt"])
        #expect(entries.map(\.isDirectory) == [true, false, false, false])
        #expect(entries.first { $0.name == "build.log" }?.isIgnored == true)
        #expect(entries.contains { $0.name == ".git" } == false)
    }
}
