import AppKit
import Foundation

struct ImageViewerZoomCommand: Equatable {
    enum Action: Equatable {
        case fit
        case actualSize
        case zoomIn
        case zoomOut
    }

    let id = UUID()
    let action: Action
}

@MainActor
@Observable
final class ImageViewerTabState {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    let projectPath: String
    let remoteHost: String?
    private(set) var filePath: String
    var image: NSImage?
    var byteCount: Int?
    var pixelSize: CGSize?
    var loadState: LoadState = .idle
    var zoomCommand: ImageViewerZoomCommand?

    init(projectPath: String, filePath: String, remoteHost: String? = nil) {
        self.projectPath = projectPath
        self.filePath = filePath
        self.remoteHost = remoteHost
    }

    var displayTitle: String {
        URL(fileURLWithPath: filePath).lastPathComponent
    }

    var metadata: String {
        let sizeText = pixelSize.map { "\(Int($0.width)) x \(Int($0.height))" }
        let byteText = byteCount.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }
        return [sizeText, byteText].compactMap(\.self).joined(separator: " · ")
    }

    func updateFilePath(_ newPath: String) {
        guard filePath != newPath else { return }
        filePath = newPath
        image = nil
        byteCount = nil
        pixelSize = nil
        loadState = .idle
    }

    func loadIfNeeded() async {
        guard image == nil, loadState != .loading else { return }
        await load()
    }

    func reload() async {
        image = nil
        byteCount = nil
        pixelSize = nil
        loadState = .idle
        await load()
    }

    func fitToWindow() {
        zoomCommand = ImageViewerZoomCommand(action: .fit)
    }

    func actualSize() {
        zoomCommand = ImageViewerZoomCommand(action: .actualSize)
    }

    func zoomIn() {
        zoomCommand = ImageViewerZoomCommand(action: .zoomIn)
    }

    func zoomOut() {
        zoomCommand = ImageViewerZoomCommand(action: .zoomOut)
    }

    private func load() async {
        let requestedPath = filePath
        loadState = .loading
        do {
            let loaded = try await ImageFileLoader.loadData(filePath: requestedPath, remoteHost: remoteHost)
            guard requestedPath == filePath else { return }
            guard let loadedImage = NSImage(data: loaded.data) else {
                throw ImageFileLoaderError.invalidImage
            }
            image = loadedImage
            byteCount = loaded.byteCount
            pixelSize = Self.pixelSize(for: loadedImage)
            loadState = .loaded
            fitToWindow()
        } catch {
            guard requestedPath == filePath else { return }
            image = nil
            byteCount = nil
            pixelSize = nil
            loadState = .failed(error.localizedDescription)
        }
    }

    private static func pixelSize(for image: NSImage) -> CGSize {
        let representation = image.representations.max { lhs, rhs in
            lhs.pixelsWide * lhs.pixelsHigh < rhs.pixelsWide * rhs.pixelsHigh
        }
        guard let representation, representation.pixelsWide > 0, representation.pixelsHigh > 0 else {
            return image.size
        }
        return CGSize(width: representation.pixelsWide, height: representation.pixelsHigh)
    }
}
