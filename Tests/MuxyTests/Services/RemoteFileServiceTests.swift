import Testing

@testable import Muxy

@Suite("RemoteFileService")
struct RemoteFileServiceTests {
    @Test("fileSizeCommand quotes remote path")
    func fileSizeCommandQuotesRemotePath() {
        let command = RemoteFileService.fileSizeCommand(path: "/tmp/project/file name.swift")
        #expect(command == "wc -c < '/tmp/project/file name.swift'")
    }

    @Test("readCommand quotes single quotes in remote path")
    func readCommandQuotesSingleQuotes() {
        let command = RemoteFileService.readCommand(path: "/tmp/project/it's.md")
        #expect(command == "cat -- '/tmp/project/it'\\''s.md'")
    }

    @Test("writeCommand writes through same-directory temporary path")
    func writeCommandUsesTemporaryPath() {
        let command = RemoteFileService.writeCommand(path: "/tmp/project/file.swift", tempIdentifier: "abc123")
        #expect(command.contains("trap 'rm -f '\\''/tmp/project/.file.swift.muxy-abc123.tmp'\\''' EXIT"))
        #expect(command.contains("mode=$(stat -c %a '/tmp/project/file.swift'"))
        #expect(command.contains("cat > '/tmp/project/.file.swift.muxy-abc123.tmp'"))
        #expect(command.contains("chmod \"$mode\" '/tmp/project/.file.swift.muxy-abc123.tmp'"))
        #expect(command.contains("mv -f '/tmp/project/.file.swift.muxy-abc123.tmp' '/tmp/project/file.swift'"))
    }
}
