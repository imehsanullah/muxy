import AppKit
import Darwin
import Foundation

struct RemoteProjectInput {
    let name: String
    let sshDestination: String
    let remotePath: String
}

private struct RemoteDirectoryEntry {
    let name: String
    let path: String
    let isDirectory: Bool
}

private struct RemoteDirectoryListing {
    let resolvedPath: String
    let entries: [RemoteDirectoryEntry]
}

private enum RemoteDirectoryBrowserError: LocalizedError {
    case launchFailed(String)
    case commandFailed(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case let .launchFailed(message):
            return message
        case let .commandFailed(message):
            return message
        case .invalidResponse:
            return "The remote server returned an invalid directory listing."
        }
    }
}

private enum SSHConfigHostLoader {
    static func loadHosts() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let configURL = home.appendingPathComponent(".ssh/config")
        var visited: Set<String> = []
        let hosts = Set(loadHosts(from: configURL, visited: &visited))
        return hosts.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private static func loadHosts(from url: URL, visited: inout Set<String>) -> [String] {
        let standardized = url.standardizedFileURL.path
        guard visited.insert(standardized).inserted else { return [] }
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }

        var hosts: [String] = []
        let baseDirectory = url.deletingLastPathComponent()

        for rawLine in content.components(separatedBy: .newlines) {
            let line = sanitize(rawLine)
            guard !line.isEmpty else { continue }

            let parts = line.split(maxSplits: 1, whereSeparator: { $0.isWhitespace }).map(String.init)
            guard parts.count == 2 else { continue }

            let key = parts[0].lowercased()
            let value = parts[1]

            if key == "include" {
                for includeURL in expandIncludePatterns(value, relativeTo: baseDirectory) {
                    hosts.append(contentsOf: loadHosts(from: includeURL, visited: &visited))
                }
                continue
            }

            guard key == "host" else { continue }
            for token in value.split(whereSeparator: { $0.isWhitespace }).map(String.init) where isSelectableHost(token) {
                hosts.append(token)
            }
        }

        return hosts
    }

    private static func sanitize(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let hashIndex = trimmed.firstIndex(of: "#") else { return trimmed }
        return String(trimmed[..<hashIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isSelectableHost(_ host: String) -> Bool {
        !host.isEmpty
            && !host.hasPrefix("!")
            && !host.contains("*")
            && !host.contains("?")
    }

    private static func expandIncludePatterns(_ value: String, relativeTo directory: URL) -> [URL] {
        value
            .split(whereSeparator: \.isWhitespace)
            .flatMap { token in
                let rawPattern = String(token)
                let expandedPattern = expandTilde(rawPattern)
                let resolvedPattern: String
                if expandedPattern.hasPrefix("/") {
                    resolvedPattern = expandedPattern
                } else {
                    resolvedPattern = directory.appendingPathComponent(expandedPattern).path
                }
                return expandGlob(resolvedPattern).map { URL(fileURLWithPath: $0) }
            }
    }

    private static func expandTilde(_ path: String) -> String {
        if path == "~" {
            return NSHomeDirectory()
        }
        if path.hasPrefix("~/") {
            return (NSHomeDirectory() as NSString).appendingPathComponent(String(path.dropFirst(2)))
        }
        return path
    }

    private static func expandGlob(_ pattern: String) -> [String] {
        var result = glob_t()
        defer { globfree(&result) }

        let status = pattern.withCString { glob($0, GLOB_TILDE, nil, &result) }
        guard status == 0 else { return [] }

        return (0 ..< Int(result.gl_matchc)).compactMap { index in
            guard let path = result.gl_pathv[index] else { return nil }
            return String(cString: path)
        }
    }
}

private enum RemoteDirectoryBrowser {
    static func list(sshDestination: String, path: String?) throws -> RemoteDirectoryListing {
        let remoteCommand = makeRemoteCommand(path: path)
        let output = try runSSH(sshDestination: sshDestination, remoteCommand: remoteCommand)
        return try parse(output: output)
    }

    private static func makeRemoteCommand(path: String?) -> String {
        let trimmed = path?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let target = trimmed.isEmpty ? "~" : ShellCommandEscaping.escape(trimmed)
        return "cd -- \(target) 2>/dev/null && pwd && /bin/ls -1Ap"
    }

    private static func runSSH(sshDestination: String, remoteCommand: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "ssh",
            "-o",
            "BatchMode=yes",
            "-o",
            "ConnectTimeout=10",
            sshDestination,
            remoteCommand,
        ]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw RemoteDirectoryBrowserError.launchFailed(error.localizedDescription)
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw RemoteDirectoryBrowserError.commandFailed(
                stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                    : stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        return stdout
    }

    private static func parse(output: String) throws -> RemoteDirectoryListing {
        let lines = output.components(separatedBy: .newlines)
        guard let resolvedPath = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines),
              !resolvedPath.isEmpty
        else {
            throw RemoteDirectoryBrowserError.invalidResponse
        }

        let entries = lines
            .dropFirst()
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .compactMap { makeEntry(from: $0, in: resolvedPath) }
            .sorted {
                if $0.isDirectory != $1.isDirectory {
                    return $0.isDirectory && !$1.isDirectory
                }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }

        return RemoteDirectoryListing(resolvedPath: resolvedPath, entries: entries)
    }

    private static func makeEntry(from line: String, in directory: String) -> RemoteDirectoryEntry? {
        let isDirectory = line.hasSuffix("/")
        let strippedName = if isDirectory {
            String(line.dropLast())
        } else {
            line
        }
        let name = strippedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        let base = directory == "/" ? "" : directory
        let fullPath = "\(base)/\(name)"
        return RemoteDirectoryEntry(name: name, path: fullPath, isDirectory: isDirectory)
    }
}

@MainActor
enum RemoteProjectPicker {
    static func present() -> RemoteProjectInput? {
        RemoteProjectPickerController().runModal()
    }
}

@MainActor
private final class RemoteProjectPickerController: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSComboBoxDelegate {
    private let nameField = NSTextField(string: "")
    private let hostComboBox = NSComboBox()
    private let pathField = NSTextField(string: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let progressIndicator = NSProgressIndicator()
    private let tableView = NSTableView()
    private let addButton = NSButton(title: "Add", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private let reloadButton = NSButton(title: "Reload", target: nil, action: nil)
    private let openButton = NSButton(title: "Open", target: nil, action: nil)
    private let homeButton = NSButton(title: "Home", target: nil, action: nil)
    private let upButton = NSButton(title: "Up", target: nil, action: nil)
    private let window: NSPanel

    private var hosts: [String] = []
    private var entries: [RemoteDirectoryEntry] = []
    private var browseTask: Task<Void, Never>?
    private var result: RemoteProjectInput?
    private var isLoading = false

    override init() {
        window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        super.init()
        buildUI()
        loadHosts()
    }

    func runModal() -> RemoteProjectInput? {
        guard let contentView = window.contentView else { return nil }
        result = nil
        window.center()
        window.contentView = contentView
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        let response = NSApp.runModal(for: window)
        window.orderOut(nil)
        browseTask?.cancel()
        return response == .OK ? result : nil
    }

    func windowWillClose(_ notification: Notification) {
        if NSApp.modalWindow == window {
            NSApp.stopModal(withCode: .cancel)
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        entries.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0, row < entries.count else { return nil }
        let entry = entries[row]
        let identifier = tableColumn?.identifier ?? NSUserInterfaceItemIdentifier("Name")
        let textField = NSTextField(labelWithString: "")
        textField.lineBreakMode = .byTruncatingMiddle
        textField.font = .systemFont(ofSize: 12)

        if identifier.rawValue == "Kind" {
            textField.stringValue = entry.isDirectory ? "Folder" : "File"
            textField.textColor = .secondaryLabelColor
        } else {
            textField.stringValue = entry.name
            textField.textColor = .labelColor
        }

        let container = NSTableCellView()
        container.addSubview(textField)
        textField.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            textField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
            textField.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        return container
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard tableView.selectedRow >= 0, tableView.selectedRow < entries.count else {
            updateNameFieldForCurrentPath()
            updateButtons()
            return
        }
        let entry = entries[tableView.selectedRow]
        if entry.isDirectory {
            pathField.stringValue = entry.path
            nameField.stringValue = entry.name
            presentStatus("Selected \(entry.path). Click Add Project to add it, or Open to browse inside.", isError: false)
        }
        updateButtons()
    }

    @objc private func confirmSelection() {
        let sshDestination = hostComboBox.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let remotePath = pathField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !sshDestination.isEmpty else {
            presentStatus("Select or enter an SSH host.", isError: true)
            NSSound.beep()
            return
        }

        guard !remotePath.isEmpty else {
            presentStatus("Choose a remote folder before adding the project.", isError: true)
            NSSound.beep()
            return
        }

        let explicitName = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackName = URL(fileURLWithPath: remotePath).lastPathComponent
        let resolvedName = explicitName.isEmpty
            ? (fallbackName.isEmpty ? sshDestination : fallbackName)
            : explicitName

        result = RemoteProjectInput(
            name: resolvedName,
            sshDestination: sshDestination,
            remotePath: remotePath
        )
        NSApp.stopModal(withCode: .OK)
        window.orderOut(nil)
    }

    @objc private func cancelSelection() {
        NSApp.stopModal(withCode: .cancel)
        window.orderOut(nil)
    }

    @objc private func hostSelectionChanged() {
        browseHome()
    }

    @objc private func reloadCurrentPath() {
        browse(path: pathField.stringValue)
    }

    @objc private func browseHome() {
        browse(path: nil)
    }

    @objc private func browseParentDirectory() {
        let current = pathField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !current.isEmpty else {
            browse(path: nil)
            return
        }
        let parent = URL(fileURLWithPath: current).deletingLastPathComponent().path
        browse(path: parent.isEmpty ? "/" : parent)
    }

    @objc private func browseSelectedRow() {
        guard tableView.selectedRow >= 0, tableView.selectedRow < entries.count else { return }
        let entry = entries[tableView.selectedRow]
        guard entry.isDirectory else { return }
        browse(path: entry.path)
    }

    @objc private func chooseSelectedRow() {
        guard tableView.selectedRow >= 0, tableView.selectedRow < entries.count else { return }
        let entry = entries[tableView.selectedRow]
        guard entry.isDirectory else { return }
        pathField.stringValue = entry.path
        confirmSelection()
    }

    private func buildUI() {
        window.title = "Add Remote Project"
        window.delegate = self

        hostComboBox.isEditable = true
        hostComboBox.completes = true
        hostComboBox.usesDataSource = false
        hostComboBox.target = self
        hostComboBox.action = #selector(hostSelectionChanged)
        hostComboBox.delegate = self

        nameField.placeholderString = "Project name"
        pathField.placeholderString = "/absolute/remote/path"
        pathField.target = self
        pathField.action = #selector(reloadCurrentPath)

        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.isDisplayedWhenStopped = false

        let descriptionLabel = NSTextField(labelWithString: "Choose an SSH host from ~/.ssh/config or enter one manually, then browse to the remote project folder.")
        descriptionLabel.textColor = .secondaryLabelColor
        descriptionLabel.lineBreakMode = .byWordWrapping
        descriptionLabel.maximumNumberOfLines = 0

        let helperLabel = NSTextField(labelWithString: "Select a folder to stage it as the project. Use Browse Into to go deeper, or Add Project to add the selected folder.")
        helperLabel.textColor = .secondaryLabelColor
        helperLabel.font = .systemFont(ofSize: 11)

        let labels = ["Name", "SSH Host", "Remote Path"].map {
            let label = NSTextField(labelWithString: $0)
            label.alignment = .right
            label.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
            return label
        }

        reloadButton.target = self
        reloadButton.action = #selector(reloadCurrentPath)
        openButton.title = "Browse Into"
        openButton.target = self
        openButton.action = #selector(browseSelectedRow)
        homeButton.target = self
        homeButton.action = #selector(browseHome)
        upButton.target = self
        upButton.action = #selector(browseParentDirectory)

        let hostRow = NSStackView(views: [hostComboBox, reloadButton])
        hostRow.orientation = .horizontal
        hostRow.spacing = 8

        let pathRow = NSStackView(views: [pathField, openButton, homeButton, upButton])
        pathRow.orientation = .horizontal
        pathRow.spacing = 8

        let grid = NSGridView(views: [
            [labels[0], nameField],
            [labels[1], hostRow],
            [labels[2], pathRow],
        ])
        grid.rowSpacing = 10
        grid.columnSpacing = 12
        grid.xPlacement = .fill
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill

        let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Name"))
        nameColumn.title = "Name"
        nameColumn.width = 470
        let kindColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Kind"))
        kindColumn.title = "Type"
        kindColumn.width = 120

        tableView.addTableColumn(nameColumn)
        tableView.addTableColumn(kindColumn)
        tableView.headerView = nil
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.rowHeight = 24
        tableView.doubleAction = #selector(chooseSelectedRow)

        let scrollView = NSScrollView()
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.documentView = tableView
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingMiddle

        addButton.title = "Add Project"
        addButton.target = self
        addButton.action = #selector(confirmSelection)
        addButton.bezelStyle = .rounded
        addButton.keyEquivalent = "\r"

        cancelButton.target = self
        cancelButton.action = #selector(cancelSelection)
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"

        let statusRow = NSStackView(views: [progressIndicator, statusLabel])
        statusRow.orientation = .horizontal
        statusRow.spacing = 8
        statusRow.alignment = .centerY

        let footerSpacer = NSView()
        let footer = NSStackView(views: [footerSpacer, cancelButton, addButton])
        footer.orientation = .horizontal
        footer.spacing = 8
        footer.alignment = .centerY

        let rootStack = NSStackView(views: [descriptionLabel, grid, helperLabel, scrollView, statusRow, footer])
        rootStack.orientation = .vertical
        rootStack.spacing = 12
        rootStack.translatesAutoresizingMaskIntoConstraints = false

        let contentView = NSView()
        contentView.addSubview(rootStack)
        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            rootStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            rootStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            rootStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 300),
            nameField.widthAnchor.constraint(greaterThanOrEqualToConstant: 240),
            hostComboBox.widthAnchor.constraint(greaterThanOrEqualToConstant: 240),
            pathField.widthAnchor.constraint(greaterThanOrEqualToConstant: 240),
        ])

        window.contentView = contentView
        window.initialFirstResponder = hostComboBox
        updateButtons()
    }

    private func loadHosts() {
        hosts = SSHConfigHostLoader.loadHosts()
        hostComboBox.removeAllItems()
        hostComboBox.addItems(withObjectValues: hosts)

        if let first = hosts.first {
            hostComboBox.stringValue = first
            browseHome()
        } else {
            presentStatus("No SSH hosts were found in ~/.ssh/config. Enter a host or alias manually.", isError: false)
            updateButtons()
        }
    }

    private func browse(path: String?) {
        let sshDestination = hostComboBox.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sshDestination.isEmpty else {
            entries = []
            tableView.reloadData()
            presentStatus("Select or enter an SSH host to load remote folders.", isError: false)
            updateButtons()
            return
        }

        let requestedPath = path?.trimmingCharacters(in: .whitespacesAndNewlines)
        setLoading(true)
        presentStatus("Loading \(sshDestination)…", isError: false)
        browseTask?.cancel()
        browseTask = Task { [weak self] in
            guard let self else { return }
            do {
                let listing = try await GitProcessRunner.offMainThrowing {
                    try RemoteDirectoryBrowser.list(
                        sshDestination: sshDestination,
                        path: requestedPath
                    )
                }
                guard !Task.isCancelled else { return }
                entries = listing.entries
                tableView.reloadData()
                tableView.deselectAll(nil)
                pathField.stringValue = listing.resolvedPath
                updateNameFieldForCurrentPath()
                presentStatus("Loaded \(listing.entries.count) item\(listing.entries.count == 1 ? "" : "s") from \(sshDestination).", isError: false)
                setLoading(false)
            } catch {
                guard !Task.isCancelled else { return }
                entries = []
                tableView.reloadData()
                tableView.deselectAll(nil)
                presentStatus(error.localizedDescription, isError: true)
                setLoading(false)
            }
        }
    }

    private func setLoading(_ isLoading: Bool) {
        self.isLoading = isLoading
        if isLoading {
            progressIndicator.startAnimation(nil)
        } else {
            progressIndicator.stopAnimation(nil)
        }
        updateButtons()
    }

    private func presentStatus(_ message: String, isError: Bool) {
        statusLabel.stringValue = message
        statusLabel.textColor = isError ? .systemRed : .secondaryLabelColor
    }

    private func updateNameFieldForCurrentPath() {
        guard nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || tableView.selectedRow == -1
        else { return }
        let fallbackName = URL(fileURLWithPath: pathField.stringValue).lastPathComponent
        if !fallbackName.isEmpty {
            nameField.stringValue = fallbackName
        }
    }

    private func updateButtons() {
        let selectedDirectory = selectedDirectoryEntry != nil
        let hasPath = !pathField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        reloadButton.isEnabled = !isLoading
        openButton.isEnabled = !isLoading && selectedDirectory
        homeButton.isEnabled = !isLoading
        upButton.isEnabled = !isLoading && hasPath
        addButton.isEnabled = !isLoading && hasPath
        let projectName = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        addButton.title = projectName.isEmpty ? "Add Project" : "Add \(projectName)"
    }

    private var selectedDirectoryEntry: RemoteDirectoryEntry? {
        guard tableView.selectedRow >= 0, tableView.selectedRow < entries.count else { return nil }
        let entry = entries[tableView.selectedRow]
        return entry.isDirectory ? entry : nil
    }

    func comboBoxSelectionDidChange(_ notification: Notification) {
        browseHome()
    }
}
