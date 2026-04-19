import AppKit
import Foundation
import OSLog

private let logger = Logger(subsystem: "app.muxy", category: "ThemeService")

struct ThemePreview: Identifiable {
    let name: String
    let background: NSColor
    let foreground: NSColor
    let palette: [NSColor]
    var id: String { name }
}

@MainActor @Observable
final class ThemeService {
    static let shared = ThemeService()
    nonisolated static let defaultThemeName = "Muxy"
    nonisolated static let pinnedThemeNames: Set<String> = ["Muxy", "Muxy Light"]
    nonisolated private static let userThemesDirectory = NSHomeDirectory() + "/.config/ghostty/themes"

    @ObservationIgnored private let config: MuxyConfig
    @ObservationIgnored private let ghostty: GhosttyService
    @ObservationIgnored private var cachedColors: CachedThemeColors?

    private struct CachedThemeColors {
        let name: String
        let fg: UInt32
        let bg: UInt32
    }

    init(config: MuxyConfig = .shared, ghostty: GhosttyService = .shared) {
        self.config = config
        self.ghostty = ghostty
    }

    func loadThemes() async -> [ThemePreview] {
        await Task.detached { Self.discoverThemes() }.value
    }

    func currentThemeName() -> String? {
        config.configValue(for: "theme")?.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }

    func currentThemeColors() -> (fg: UInt32, bg: UInt32)? {
        guard let name = currentThemeName() else { return nil }
        if let cached = cachedColors, cached.name == name {
            return (fg: cached.fg, bg: cached.bg)
        }
        for dir in Self.themeDirectories() {
            let path = dir + "/" + name
            guard FileManager.default.fileExists(atPath: path),
                  let theme = Self.parseThemeFile(atPath: path, name: name)
            else { continue }
            let fg = Self.rgb(from: theme.foreground)
            let bg = Self.rgb(from: theme.background)
            cachedColors = CachedThemeColors(name: name, fg: fg, bg: bg)
            return (fg: fg, bg: bg)
        }
        return nil
    }

    nonisolated private static func rgb(from color: NSColor) -> UInt32 {
        let srgb = color.usingColorSpace(.sRGB) ?? color
        let r = UInt32((srgb.redComponent * 255).rounded()) & 0xFF
        let g = UInt32((srgb.greenComponent * 255).rounded()) & 0xFF
        let b = UInt32((srgb.blueComponent * 255).rounded()) & 0xFF
        return (r << 16) | (g << 8) | b
    }

    func applyDefaultThemeIfNeeded() {
        guard currentThemeName() == nil else { return }
        applyTheme(Self.defaultThemeName)
    }

    func applyTheme(_ name: String) {
        let sanitized = name.filter { $0 != "\"" && $0 != "\n" && $0 != "\r" }
        Self.installBundledThemesIfNeeded()
        config.updateConfigValue("theme", value: "\"\(sanitized)\"")
        cachedColors = nil
        ghostty.reloadConfig()
        NotificationCenter.default.post(name: .themeDidChange, object: nil)
    }

    nonisolated static func installBundledThemesIfNeeded() {
        let sources = bundledThemeSources()
        guard !sources.isEmpty else { return }

        do {
            try FileManager.default.createDirectory(
                atPath: userThemesDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            logger.error("Failed to create Ghostty theme directory at \(userThemesDirectory, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return
        }

        for source in sources {
            let destination = userThemesDirectory + "/" + source.lastPathComponent
            do {
                if FileManager.default.fileExists(atPath: destination) {
                    let sourceData = try Data(contentsOf: source)
                    let destinationData = try Data(contentsOf: URL(fileURLWithPath: destination))
                    if sourceData == destinationData {
                        continue
                    }
                }

                if FileManager.default.fileExists(atPath: destination) {
                    try FileManager.default.removeItem(atPath: destination)
                }
                try FileManager.default.copyItem(at: source, to: URL(fileURLWithPath: destination))
            } catch {
                logger.error("Failed to install bundled theme \(source.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    nonisolated private static func discoverThemes() -> [ThemePreview] {
        var themesByName: [String: ThemePreview] = [:]
        let directories = themeDirectories()

        for dir in directories {
            guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
            for file in files {
                guard let theme = parseThemeFile(atPath: dir + "/" + file, name: file) else { continue }
                themesByName[theme.name] = theme
            }
        }

        if themesByName.isEmpty {
            logger.error("No themes discovered in directories: \(directories.joined(separator: ", "), privacy: .public)")
        }

        return themesByName.values.sorted {
            let pinned0 = pinnedThemeNames.contains($0.name)
            let pinned1 = pinnedThemeNames.contains($1.name)
            if pinned0 != pinned1 { return pinned0 }
            if pinned0, pinned1 { return $0.name < $1.name }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    nonisolated private static func themeDirectories() -> [String] {
        var dirs: [String] = []
        if let resourcesDir = getenv("GHOSTTY_RESOURCES_DIR").map({ String(cString: $0) }) {
            appendDirectory(resourcesDir + "/themes", into: &dirs)
        }

        let appBundlePaths = [
            "/Applications/Ghostty.app/Contents/Resources/ghostty/themes",
            NSHomeDirectory() + "/Applications/Ghostty.app/Contents/Resources/ghostty/themes",
        ]
        for path in appBundlePaths {
            appendDirectory(path, into: &dirs)
        }

        appendDirectory(NSHomeDirectory() + "/.config/ghostty/themes", into: &dirs)

        if let bundleResources = Bundle.appResources.resourceURL?.path {
            appendDirectory(bundleResources + "/themes", into: &dirs)
            appendDirectory(bundleResources, into: &dirs)
        }

        return dirs
    }

    nonisolated private static func bundledThemeSources() -> [URL] {
        guard let bundleResources = Bundle.appResources.resourceURL else { return [] }
        let candidates = [
            bundleResources.appendingPathComponent("themes", isDirectory: true),
            bundleResources,
        ]

        var seenPaths = Set<String>()
        var sources: [URL] = []
        for directory in candidates {
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for file in files {
                guard seenPaths.insert(file.path).inserted else { continue }
                guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey]),
                      values.isRegularFile == true
                else { continue }
                guard parseThemeFile(atPath: file.path, name: file.lastPathComponent) != nil else { continue }
                sources.append(file)
            }
        }
        return sources.sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    }

    nonisolated private static func appendDirectory(_ path: String, into directories: inout [String]) {
        guard !directories.contains(path) else { return }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else { return }
        directories.append(path)
    }

    nonisolated private static func parseThemeFile(atPath path: String, name: String) -> ThemePreview? {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        var bg: NSColor?
        var fg: NSColor?
        var palette: [Int: NSColor] = [:]
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("background"), !trimmed.hasPrefix("background-") {
                bg = extractColor(from: trimmed)
            } else if trimmed.hasPrefix("foreground"), !trimmed.hasPrefix("foreground-") {
                fg = extractColor(from: trimmed)
            } else if trimmed.hasPrefix("palette") {
                parsePaletteEntry(trimmed, into: &palette)
            }
        }
        guard let bg, let fg else { return nil }
        let sortedPalette = (0 ..< 16).compactMap { palette[$0] }
        return ThemePreview(name: name, background: bg, foreground: fg, palette: sortedPalette)
    }

    nonisolated private static func parsePaletteEntry(_ line: String, into palette: inout [Int: NSColor]) {
        guard let eqIndex = line.firstIndex(of: "=") else { return }
        let value = line[line.index(after: eqIndex)...].trimmingCharacters(in: .whitespaces)
        guard let eqIndex2 = value.firstIndex(of: "=") else { return }
        guard let index = Int(value[..<eqIndex2]) else { return }
        guard index >= 0, index < 16 else { return }
        guard let color = parseHex(String(value[value.index(after: eqIndex2)...])) else { return }
        palette[index] = color
    }

    nonisolated private static func extractColor(from line: String) -> NSColor? {
        guard let eqIndex = line.firstIndex(of: "=") else { return nil }
        let value = line[line.index(after: eqIndex)...].trimmingCharacters(in: .whitespaces)
        return parseHex(value)
    }

    nonisolated private static func parseHex(_ hex: String) -> NSColor? {
        var h = hex
        if h.hasPrefix("#") { h = String(h.dropFirst()) }
        guard h.count == 6, let val = UInt32(h, radix: 16) else { return nil }
        return NSColor(
            srgbRed: CGFloat((val >> 16) & 0xFF) / 255,
            green: CGFloat((val >> 8) & 0xFF) / 255,
            blue: CGFloat(val & 0xFF) / 255,
            alpha: 1
        )
    }
}
