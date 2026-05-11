import AppKit
import Foundation
import os
import SwiftUI

private let logger = Logger(subsystem: "app.muxy", category: "AppBackgroundService")

enum AppBackgroundSourceMode: String, Codable, CaseIterable, Identifiable {
    case file
    case folder

    var id: String { rawValue }

    var title: String {
        switch self {
        case .file:
            "Single Image"
        case .folder:
            "Folder"
        }
    }
}

enum AppBackgroundFit: String, Codable, CaseIterable, Identifiable {
    case contain
    case cover
    case stretch
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .contain:
            "Contain"
        case .cover:
            "Cover"
        case .stretch:
            "Stretch"
        case .none:
            "Original"
        }
    }
}

enum AppBackgroundPosition: String, Codable, CaseIterable, Identifiable {
    case topLeft = "top-left"
    case topCenter = "top-center"
    case topRight = "top-right"
    case centerLeft = "center-left"
    case center
    case centerRight = "center-right"
    case bottomLeft = "bottom-left"
    case bottomCenter = "bottom-center"
    case bottomRight = "bottom-right"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .topLeft:
            "Top Left"
        case .topCenter:
            "Top"
        case .topRight:
            "Top Right"
        case .centerLeft:
            "Left"
        case .center:
            "Center"
        case .centerRight:
            "Right"
        case .bottomLeft:
            "Bottom Left"
        case .bottomCenter:
            "Bottom"
        case .bottomRight:
            "Bottom Right"
        }
    }

    var alignment: Alignment {
        switch self {
        case .topLeft:
            .topLeading
        case .topCenter:
            .top
        case .topRight:
            .topTrailing
        case .centerLeft:
            .leading
        case .center:
            .center
        case .centerRight:
            .trailing
        case .bottomLeft:
            .bottomLeading
        case .bottomCenter:
            .bottom
        case .bottomRight:
            .bottomTrailing
        }
    }
}

@MainActor
@Observable
final class AppBackgroundService {
    static let shared = AppBackgroundService()

    var isEnabled = false { didSet { settingsDidChange() } }
    var sourceMode: AppBackgroundSourceMode = .file { didSet { settingsDidChange() } }
    var sourcePath = "" { didSet { settingsDidChange() } }
    var imageOpacity = 0.32 { didSet { settingsDidChange() } }
    var chromeTintOpacity = 0.86 { didSet { settingsDidChange() } }
    var blurRadius = 0.0 { didSet { settingsDidChange() } }
    var position: AppBackgroundPosition = .center { didSet { settingsDidChange() } }
    var fit: AppBackgroundFit = .cover { didSet { settingsDidChange() } }
    var repeatImage = false { didSet { settingsDidChange() } }
    var floatMode = false { didSet { settingsDidChange() } }
    var slideshowEnabled = false { didSet { settingsDidChange() } }
    var slideshowInterval = 15.0 { didSet { settingsDidChange() } }

    private(set) var currentImagePath: String?
    private(set) var currentImage: NSImage?
    private(set) var availableImageCount = 0
    private(set) var version = 0

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private let config: MuxyConfig
    @ObservationIgnored private var isBatchLoading = false
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var slideshowImagePaths: [String] = []
    @ObservationIgnored private var slideshowIndex = 0

    private static let supportedExtensions = Set(["png", "jpg", "jpeg"])

    var hasVisibleBackground: Bool {
        isEnabled && currentImage != nil
    }

    var terminalBackgroundOpacity: Double {
        guard hasVisibleBackground else { return 1 }
        return max(0.18, min(0.5, chromeTintOpacity * 0.5))
    }

    var sourceDescription: String {
        guard !sourcePath.isEmpty else { return "None selected" }
        return sourcePath
    }

    private init(config: MuxyConfig = .shared) {
        self.config = config
        fileURL = MuxyFileStorage.fileURL(filename: "background-settings.json")
        load()
        settingsDidChange(reloadGhostty: false)
    }

    func setImagePath(_ path: String) {
        isBatchLoading = true
        sourceMode = .file
        sourcePath = path
        isEnabled = true
        isBatchLoading = false
        settingsDidChange()
    }

    func setFolderPath(_ path: String) {
        isBatchLoading = true
        sourceMode = .folder
        sourcePath = path
        slideshowEnabled = true
        isEnabled = true
        isBatchLoading = false
        settingsDidChange()
    }

    func clear() {
        isBatchLoading = true
        isEnabled = false
        sourcePath = ""
        sourceMode = .file
        slideshowEnabled = false
        isBatchLoading = false
        settingsDidChange()
    }

    func resetToDefaults() {
        isBatchLoading = true
        isEnabled = false
        sourceMode = .file
        sourcePath = ""
        imageOpacity = 0.32
        chromeTintOpacity = 0.86
        blurRadius = 0
        position = .center
        fit = .cover
        repeatImage = false
        floatMode = false
        slideshowEnabled = false
        slideshowInterval = 15
        isBatchLoading = false
        settingsDidChange()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
            isBatchLoading = true
            isEnabled = snapshot.isEnabled ?? false
            sourceMode = snapshot.sourceMode ?? .file
            sourcePath = snapshot.sourcePath ?? ""
            imageOpacity = snapshot.imageOpacity ?? 0.32
            chromeTintOpacity = snapshot.chromeTintOpacity ?? 0.86
            blurRadius = snapshot.blurRadius ?? 0
            position = snapshot.position ?? .center
            fit = snapshot.fit ?? .cover
            repeatImage = snapshot.repeatImage ?? false
            floatMode = snapshot.floatMode ?? false
            slideshowEnabled = snapshot.slideshowEnabled ?? false
            slideshowInterval = snapshot.slideshowInterval ?? 15
            isBatchLoading = false
        } catch {
            logger.error("Failed to load background settings: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func save() {
        guard !isBatchLoading else { return }
        do {
            let snapshot = Snapshot(
                isEnabled: isEnabled,
                sourceMode: sourceMode,
                sourcePath: sourcePath,
                imageOpacity: imageOpacity,
                chromeTintOpacity: chromeTintOpacity,
                blurRadius: blurRadius,
                position: position,
                fit: fit,
                repeatImage: repeatImage,
                floatMode: floatMode,
                slideshowEnabled: slideshowEnabled,
                slideshowInterval: slideshowInterval
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            logger.error("Failed to save background settings: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func settingsDidChange(reloadGhostty: Bool = true) {
        guard !isBatchLoading else { return }
        resolveCurrentImage()
        restartTimerIfNeeded()
        save()
        syncGhosttyConfig(reloadGhostty: reloadGhostty)
        version += 1
    }

    private func resolveCurrentImage() {
        stopTimer()

        switch sourceMode {
        case .file:
            slideshowImagePaths = validatedImagePath(sourcePath).map { [$0] } ?? []
            slideshowIndex = 0
        case .folder:
            slideshowImagePaths = imagePaths(in: sourcePath)
            if slideshowImagePaths.isEmpty {
                slideshowIndex = 0
            } else if slideshowIndex >= slideshowImagePaths.count {
                slideshowIndex = 0
            }
        }

        availableImageCount = slideshowImagePaths.count
        let resolvedPath = slideshowImagePaths.isEmpty ? nil : slideshowImagePaths[slideshowIndex]
        currentImagePath = resolvedPath
        currentImage = resolvedPath.flatMap { NSImage(contentsOfFile: $0) }
    }

    private func restartTimerIfNeeded() {
        guard isEnabled,
              sourceMode == .folder,
              slideshowEnabled,
              slideshowImagePaths.count > 1
        else { return }

        let interval = max(3, slideshowInterval)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.advanceSlideshow()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func advanceSlideshow() {
        guard slideshowImagePaths.count > 1 else { return }
        slideshowIndex = (slideshowIndex + 1) % slideshowImagePaths.count
        currentImagePath = slideshowImagePaths[slideshowIndex]
        currentImage = currentImagePath.flatMap { NSImage(contentsOfFile: $0) }
        syncGhosttyConfig(reloadGhostty: true)
        version += 1
    }

    private func syncGhosttyConfig(reloadGhostty: Bool) {
        let updates: [String: String?] = if isEnabled, currentImagePath != nil {
            [
                "background-image": nil,
                "background-image-opacity": nil,
                "background-image-position": nil,
                "background-image-fit": nil,
                "background-image-repeat": nil,
                "background-opacity": formatted(terminalBackgroundOpacity),
                "background-opacity-cells": "true",
            ]
        } else {
            [
                "background-image": nil,
                "background-image-opacity": nil,
                "background-image-position": nil,
                "background-image-fit": nil,
                "background-image-repeat": nil,
                "background-opacity": nil,
                "background-opacity-cells": nil,
            ]
        }

        config.updateConfigValues(updates)
        guard reloadGhostty else { return }
        GhosttyService.shared.reloadConfig(recreateSurfaces: true)
    }

    private func validatedImagePath(_ path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: trimmed, isDirectory: &isDirectory),
              !isDirectory.boolValue
        else { return nil }
        let ext = URL(fileURLWithPath: trimmed).pathExtension.lowercased()
        guard Self.supportedExtensions.contains(ext) else { return nil }
        return trimmed
    }

    private func imagePaths(in folderPath: String) -> [String] {
        let trimmed = folderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: trimmed, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { return [] }
        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: URL(fileURLWithPath: trimmed),
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            return files
                .filter { Self.supportedExtensions.contains($0.pathExtension.lowercased()) }
                .map(\.path)
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        } catch {
            logger
                .error(
                    "Failed to enumerate background folder \(trimmed, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            return []
        }
    }

    private func formatted(_ value: Double) -> String {
        let clamped = max(0, min(1, value))
        return String(format: "%.2f", clamped)
    }
}

private struct Snapshot: Codable {
    let isEnabled: Bool?
    let sourceMode: AppBackgroundSourceMode?
    let sourcePath: String?
    let imageOpacity: Double?
    let chromeTintOpacity: Double?
    let blurRadius: Double?
    let position: AppBackgroundPosition?
    let fit: AppBackgroundFit?
    let repeatImage: Bool?
    let floatMode: Bool?
    let slideshowEnabled: Bool?
    let slideshowInterval: Double?
}
