import Testing

@testable import Muxy

@Suite("ImageFileLoader")
struct ImageFileLoaderTests {
    @Test("remoteReadCommand quotes paths and checks size")
    func remoteReadCommandQuotesPathsAndChecksSize() {
        let command = ImageFileLoader.remoteReadCommand(filePath: "/srv/my repo/it's.png", maxBytes: 123)

        #expect(command.contains("wc -c < '/srv/my repo/it'\\''s.png'"))
        #expect(command.contains("[ \"${bytes:-0}\" -le 123 ] || exit 2"))
        #expect(command.contains("cat -- '/srv/my repo/it'\\''s.png'"))
    }
}
