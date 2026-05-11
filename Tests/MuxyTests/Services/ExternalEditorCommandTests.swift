import Testing

@testable import Muxy

@Suite("ExternalEditorCommand")
struct ExternalEditorCommandTests {
    @Test("remoteCommand defaults to vim with mouse support")
    func remoteCommandDefaultsToVimWithMouseSupport() {
        let command = ExternalEditorCommand.remoteCommand(preferredCommand: " ")
        #expect(command == "vim -c 'set mouse=a'")
    }

    @Test("remoteCommand adds mouse support to vim")
    func remoteCommandAddsMouseSupportToVim() {
        let command = ExternalEditorCommand.remoteCommand(preferredCommand: "vim")
        #expect(command == "vim -c 'set mouse=a'")
    }

    @Test("remoteCommand preserves vim arguments")
    func remoteCommandPreservesVimArguments() {
        let command = ExternalEditorCommand.remoteCommand(preferredCommand: "vim -n +20")
        #expect(command == "vim -c 'set mouse=a' -n +20")
    }

    @Test("remoteCommand adds mouse support to nvim")
    func remoteCommandAddsMouseSupportToNvim() {
        let command = ExternalEditorCommand.remoteCommand(preferredCommand: "nvim --clean")
        #expect(command == "nvim -c 'set mouse=a' --clean")
    }

    @Test("remoteCommand preserves non-vim commands")
    func remoteCommandPreservesNonVimCommands() {
        let command = ExternalEditorCommand.remoteCommand(preferredCommand: "nano")
        #expect(command == "nano")
    }

    @Test("remoteCommand does not duplicate explicit mouse configuration")
    func remoteCommandDoesNotDuplicateExplicitMouseConfiguration() {
        let command = ExternalEditorCommand.remoteCommand(preferredCommand: "vim -c 'set mouse=n'")
        #expect(command == "vim -c 'set mouse=n'")
    }

    @Test("imageViewerCommand defaults to chafa kitty")
    func imageViewerCommandDefaultsToChafaKitty() {
        let command = ExternalEditorCommand.imageViewerCommand(preferredCommand: " ")
        #expect(command == ExternalEditorCommand.defaultImageViewerCommand)
    }

    @Test("imageViewerCommand preserves custom command")
    func imageViewerCommandPreservesCustomCommand() {
        let command = ExternalEditorCommand.imageViewerCommand(preferredCommand: "kitten icat")
        #expect(command == "kitten icat")
    }

    @Test("isImageFile recognizes common image extensions")
    func isImageFileRecognizesCommonImageExtensions() {
        #expect(ExternalEditorCommand.isImageFile("/tmp/picture.PNG"))
        #expect(ExternalEditorCommand.isImageFile("/tmp/photo.jpeg"))
        #expect(ExternalEditorCommand.isImageFile("/tmp/clip.webp"))
        #expect(!ExternalEditorCommand.isImageFile("/tmp/readme.md"))
    }
}
