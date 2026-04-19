import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AppearanceSettingsView: View {
    @State private var themeService = ThemeService.shared
    @Environment(AppBackgroundService.self) private var backgroundService
    @State private var showThemePicker = false
    @State private var currentTheme: String?
    @AppStorage("muxy.vcsDisplayMode") private var vcsDisplayMode = VCSDisplayMode.tab.rawValue

    var body: some View {
        @Bindable var backgroundService = backgroundService

        SettingsContainer {
            SettingsSection("Terminal") {
                SettingsRow("Theme") {
                    Button {
                        showThemePicker.toggle()
                    } label: {
                        HStack(spacing: 6) {
                            Text(currentTheme ?? "Default")
                                .font(.system(size: SettingsMetrics.labelFontSize))
                                .lineLimit(1)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 10))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showThemePicker) {
                        ThemePicker()
                            .environment(themeService)
                    }
                }
            }

            SettingsSection(
                "Background",
                footer: "Background images are rendered once behind the entire Muxy window. Terminal panes are made translucent so they reveal the shared app background instead of rendering their own copy."
            ) {
                SettingsToggleRow(label: "Enabled", isOn: $backgroundService.isEnabled)

                SettingsRow("Source Type") {
                    Picker("", selection: $backgroundService.sourceMode) {
                        ForEach(AppBackgroundSourceMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: SettingsMetrics.controlWidth)
                }

                SettingsRow("Source") {
                    VStack(alignment: .trailing, spacing: 6) {
                        HStack(spacing: 8) {
                            Button(backgroundService.sourceMode == .file ? "Choose Image" : "Choose Folder") {
                                if backgroundService.sourceMode == .file {
                                    chooseBackgroundImage()
                                } else {
                                    chooseBackgroundFolder()
                                }
                            }
                            .buttonStyle(.bordered)

                            Button("Clear") {
                                backgroundService.clear()
                            }
                            .buttonStyle(.bordered)
                            .disabled(backgroundService.sourcePath.isEmpty)
                        }

                        Text(backgroundService.sourceDescription)
                            .font(.system(size: SettingsMetrics.footnoteFontSize))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 260, alignment: .trailing)

                        if backgroundService.sourceMode == .folder, backgroundService.availableImageCount > 0 {
                            Text("\(backgroundService.availableImageCount) images found")
                                .font(.system(size: SettingsMetrics.footnoteFontSize))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if backgroundService.sourceMode == .folder {
                    SettingsToggleRow(label: "Slideshow", isOn: $backgroundService.slideshowEnabled)

                    SettingsRow("Interval") {
                        VStack(alignment: .trailing, spacing: 4) {
                            Slider(
                                value: $backgroundService.slideshowInterval,
                                in: 3 ... 120,
                                step: 1
                            )
                            .frame(width: SettingsMetrics.controlWidth)
                            Text("\(Int(backgroundService.slideshowInterval)) sec")
                                .font(.system(size: SettingsMetrics.footnoteFontSize))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                SettingsRow("Fit") {
                    Picker("", selection: $backgroundService.fit) {
                        ForEach(AppBackgroundFit.allCases) { fit in
                            Text(fit.title).tag(fit)
                        }
                    }
                    .labelsHidden()
                    .frame(width: SettingsMetrics.controlWidth, alignment: .trailing)
                }

                SettingsRow("Position") {
                    Picker("", selection: $backgroundService.position) {
                        ForEach(AppBackgroundPosition.allCases) { position in
                            Text(position.title).tag(position)
                        }
                    }
                    .labelsHidden()
                    .frame(width: SettingsMetrics.controlWidth, alignment: .trailing)
                }

                SettingsToggleRow(label: "Repeat Image", isOn: $backgroundService.repeatImage)
                SettingsToggleRow(label: "Float Mode", isOn: $backgroundService.floatMode)

                SettingsRow("Image Opacity") {
                    VStack(alignment: .trailing, spacing: 4) {
                        Slider(
                            value: $backgroundService.imageOpacity,
                            in: 0 ... 1,
                            step: 0.01
                        )
                        .frame(width: SettingsMetrics.controlWidth)
                        Text("\(Int(backgroundService.imageOpacity * 100))%")
                            .font(.system(size: SettingsMetrics.footnoteFontSize))
                            .foregroundStyle(.secondary)
                    }
                }

                SettingsRow("UI Tint") {
                    VStack(alignment: .trailing, spacing: 4) {
                        Slider(
                            value: $backgroundService.chromeTintOpacity,
                            in: 0.45 ... 1,
                            step: 0.01
                        )
                        .frame(width: SettingsMetrics.controlWidth)
                        Text("\(Int(backgroundService.chromeTintOpacity * 100))%")
                            .font(.system(size: SettingsMetrics.footnoteFontSize))
                            .foregroundStyle(.secondary)
                    }
                }

                SettingsRow("Blur") {
                    VStack(alignment: .trailing, spacing: 4) {
                        Slider(
                            value: $backgroundService.blurRadius,
                            in: 0 ... 30,
                            step: 1
                        )
                        .frame(width: SettingsMetrics.controlWidth)
                        Text(backgroundService.blurRadius == 0 ? "Off" : "\(Int(backgroundService.blurRadius)) px")
                            .font(.system(size: SettingsMetrics.footnoteFontSize))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            SettingsSection("Source Control", showsDivider: false) {
                SettingsRow("Display Mode") {
                    Picker("", selection: $vcsDisplayMode) {
                        ForEach(VCSDisplayMode.allCases) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: SettingsMetrics.controlWidth)
                }
            }
        }
        .task {
            currentTheme = themeService.currentThemeName()
        }
        .onReceive(NotificationCenter.default.publisher(for: .themeDidChange)) { _ in
            currentTheme = themeService.currentThemeName()
        }
    }

    private func chooseBackgroundImage() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType.png, UTType.jpeg]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        backgroundService.setImagePath(url.path)
    }

    private func chooseBackgroundFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        backgroundService.setFolderPath(url.path)
    }
}
