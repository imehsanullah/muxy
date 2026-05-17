import AppKit
import SwiftUI

struct AgentVaultButton: View {
    let count: Int
    let onTap: () -> Void

    @State private var hovered = false

    private var foreground: Color {
        hovered ? MuxyTheme.fg : MuxyTheme.fgMuted
    }

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: count >= 1 ? "books.vertical.fill" : "books.vertical")
                    .font(.system(size: UIMetrics.fontEmphasis, weight: .semibold))
                    .foregroundStyle(foreground)
                    .frame(width: UIMetrics.controlMedium, height: UIMetrics.controlMedium)
                    .contentShape(Rectangle())
                if count >= 1 {
                    Circle()
                        .fill(MuxyTheme.accent)
                        .frame(width: UIMetrics.scaled(5), height: UIMetrics.scaled(5))
                        .offset(x: -UIMetrics.scaled(5), y: UIMetrics.scaled(5))
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityLabel("Agent Vault")
    }
}

struct AgentVaultToolbarItem: View {
    private let vault = AgentVaultStore.shared

    var body: some View {
        AgentVaultButton(
            count: vault.sessions.count,
            onTap: {
                NotificationCenter.default.post(name: .toggleAgentVault, object: nil)
            }
        )
        .help("Agent Vault (\(KeyBindingStore.shared.combo(for: .toggleAgentVault).displayString))")
    }
}

enum AgentVaultPanelPresentation {
    case popover
    case sidebar
}

struct AgentVaultSidePanel: View {
    let sessions: [AgentVaultSession]
    let isLoading: Bool
    let lastRefreshDate: Date?
    let onRefresh: () -> Void
    let onClose: () -> Void
    let onResume: (AgentVaultSession) -> Void
    let canResume: (AgentVaultSession) -> Bool
    let onDeleteSession: (AgentVaultSession) -> Void
    let onDeleteSessions: ([AgentVaultSession]) -> Void

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Rectangle().fill(MuxyTheme.border).frame(height: 1)
            AgentVaultPanel(
                sessions: sessions,
                isLoading: isLoading,
                lastRefreshDate: lastRefreshDate,
                onRefresh: onRefresh,
                onResume: onResume,
                canResume: canResume,
                onDeleteSession: onDeleteSession,
                onDeleteSessions: onDeleteSessions,
                presentation: .sidebar
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            AgentVaultCmuxSidebarBackground()
        }
        .accessibilityLabel("Agent Vault")
    }

    private var titleBar: some View {
        HStack(spacing: UIMetrics.spacing2) {
            Image(systemName: "books.vertical")
                .font(.system(size: UIMetrics.fontBody, weight: .semibold))
                .foregroundStyle(MuxyTheme.fgMuted)
                .frame(width: UIMetrics.iconMD, height: UIMetrics.iconMD)
            Text("Vault")
                .font(.system(size: UIMetrics.fontBody, weight: .semibold))
                .foregroundStyle(MuxyTheme.fg)
                .lineLimit(1)
            if !sessions.isEmpty {
                Text("\(sessions.count)")
                    .font(.system(size: UIMetrics.fontCaption, design: .monospaced))
                    .foregroundStyle(MuxyTheme.fgDim)
            }
            Spacer(minLength: 0)
            IconButton(symbol: "xmark", size: 11, accessibilityLabel: "Close Agent Vault", action: onClose)
                .help("Close Agent Vault")
        }
        .padding(.horizontal, UIMetrics.spacing4)
        .frame(height: UIMetrics.scaled(32))
    }
}

struct AgentVaultPanel: View {
    let sessions: [AgentVaultSession]
    let isLoading: Bool
    let lastRefreshDate: Date?
    let onRefresh: () -> Void
    let onResume: (AgentVaultSession) -> Void
    let canResume: (AgentVaultSession) -> Bool
    let onDeleteSession: (AgentVaultSession) -> Void
    let onDeleteSessions: ([AgentVaultSession]) -> Void
    var presentation: AgentVaultPanelPresentation = .popover

    @State private var query = ""
    @State private var grouping: AgentVaultGrouping = .folder
    @State private var collapsedSections: Set<String> = []
    @State private var pendingSessionDeletion: AgentVaultSession?
    @State private var pendingSectionDeletion: AgentVaultSessionSection?

    private var visibleSessions: [AgentVaultSession] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return sessions }
        return sessions.filter { session in
            [
                session.agent.displayName,
                session.displayTitle,
                session.cwd ?? "",
                session.gitBranch ?? "",
                session.model ?? "",
                session.sessionID,
            ].contains {
                $0.range(of: trimmed, options: [.caseInsensitive, .literal]) != nil
            }
        }
    }

    private var sections: [AgentVaultSessionSection] {
        grouping.sections(for: visibleSessions)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            controlBar
            Rectangle().fill(MuxyTheme.border).frame(height: 1)
            searchField
            Rectangle().fill(MuxyTheme.border).frame(height: 1)
            content
        }
        .frame(width: presentation == .popover ? UIMetrics.scaled(370) : nil)
        .frame(height: presentation == .popover ? UIMetrics.scaled(540) : nil)
        .frame(maxWidth: presentation == .sidebar ? .infinity : nil)
        .frame(maxHeight: presentation == .sidebar ? .infinity : nil)
        .background(panelBackground)
        .confirmationDialog(
            "Delete Session?",
            isPresented: sessionDeletionConfirmation,
            titleVisibility: .visible,
            presenting: pendingSessionDeletion
        ) { session in
            Button("Delete Session", role: .destructive) {
                onDeleteSession(session)
                pendingSessionDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                pendingSessionDeletion = nil
            }
        } message: { session in
            Text("This deletes \(session.displayTitle) from the Vault by removing its transcript file.")
        }
        .confirmationDialog(
            "Delete Folder Sessions?",
            isPresented: sectionDeletionConfirmation,
            titleVisibility: .visible,
            presenting: pendingSectionDeletion
        ) { section in
            Button("Delete \(section.sessions.count) Sessions", role: .destructive) {
                onDeleteSessions(section.sessions)
                pendingSectionDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                pendingSectionDeletion = nil
            }
        } message: { section in
            Text("This deletes all Vault sessions in \(section.title) by removing their transcript files.")
        }
    }

    private var sessionDeletionConfirmation: Binding<Bool> {
        Binding(
            get: { pendingSessionDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    pendingSessionDeletion = nil
                }
            }
        )
    }

    private var sectionDeletionConfirmation: Binding<Bool> {
        Binding(
            get: { pendingSectionDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    pendingSectionDeletion = nil
                }
            }
        )
    }

    private var panelCornerRadius: CGFloat {
        presentation == .popover ? UIMetrics.radiusLG : 0
    }

    @ViewBuilder
    private var panelBackground: some View {
        if presentation == .popover {
            RoundedRectangle(cornerRadius: panelCornerRadius)
                .fill(MuxyTheme.surface)
        }
    }

    private var controlBar: some View {
        HStack(spacing: UIMetrics.spacing2) {
            ForEach(AgentVaultGrouping.allCases) { mode in
                AgentVaultGroupingButton(
                    grouping: mode,
                    isSelected: grouping == mode,
                    action: { grouping = mode }
                )
            }
            Spacer(minLength: UIMetrics.spacing2)
            if let lastRefreshDate {
                Text(Self.relativeFormatter.localizedString(for: lastRefreshDate, relativeTo: Date()))
                    .font(.system(size: UIMetrics.fontFootnote))
                    .foregroundStyle(MuxyTheme.fgDim)
                    .lineLimit(1)
            }
            Button(action: onRefresh) {
                Group {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: UIMetrics.fontFootnote, weight: .semibold))
                    }
                }
                .frame(width: UIMetrics.iconMD, height: UIMetrics.iconMD)
            }
            .buttonStyle(.plain)
            .foregroundStyle(MuxyTheme.fgMuted)
            .disabled(isLoading)
            .help("Refresh Vault")
        }
        .padding(.horizontal, UIMetrics.spacing4)
        .frame(height: UIMetrics.scaled(36))
    }

    private var searchField: some View {
        HStack(spacing: UIMetrics.spacing3) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: UIMetrics.fontFootnote, weight: .semibold))
                .foregroundStyle(MuxyTheme.fgDim)
            TextField("Search Vault", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: UIMetrics.fontBody))
                .foregroundStyle(MuxyTheme.fg)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: UIMetrics.fontFootnote, weight: .semibold))
                        .foregroundStyle(MuxyTheme.fgDim)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, UIMetrics.spacing4)
        .frame(height: UIMetrics.scaled(34))
    }

    @ViewBuilder
    private var content: some View {
        if isLoading, sessions.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if visibleSessions.isEmpty {
            Text(sessions.isEmpty ? "Vault is empty" : "No matching sessions")
                .font(.system(size: UIMetrics.fontBody))
                .foregroundStyle(MuxyTheme.fgDim)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(sections) { section in
                        sectionView(section)
                    }
                }
                .padding(.vertical, UIMetrics.spacing2)
            }
        }
    }

    private func sectionView(_ section: AgentVaultSessionSection) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                toggleSection(section.id)
            } label: {
                AgentVaultSectionHeader(
                    section: section,
                    isCollapsed: collapsedSections.contains(section.id)
                )
            }
            .buttonStyle(.plain)
            .contextMenu {
                if section.allowsBulkDelete {
                    Button("Delete All Sessions in Folder...", role: .destructive) {
                        requestSectionDeletion(section)
                    }
                }
            }

            if !collapsedSections.contains(section.id) {
                ForEach(section.sessions) { session in
                    AgentVaultSessionRow(
                        session: session,
                        canResume: canResume(session),
                        onResume: { onResume(session) },
                        onRequestDelete: { pendingSessionDeletion = session }
                    )
                }
            }
        }
    }

    private func requestSectionDeletion(_ section: AgentVaultSessionSection) {
        guard let folderGroupingKey = section.folderGroupingKey else { return }
        let targetSessions = sessions.filter { $0.folderGroupingKey == folderGroupingKey }
        guard !targetSessions.isEmpty else { return }
        pendingSectionDeletion = AgentVaultSessionSection(
            id: section.id,
            title: section.title,
            icon: section.icon,
            sessions: targetSessions,
            allowsBulkDelete: section.allowsBulkDelete,
            folderGroupingKey: folderGroupingKey
        )
    }

    private func toggleSection(_ id: String) {
        if collapsedSections.contains(id) {
            collapsedSections.remove(id)
        } else {
            collapsedSections.insert(id)
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}

private struct AgentVaultCmuxSidebarBackground: View {
    var body: some View {
        AgentVaultSidebarMaterialBackground()
            .overlay(Color.black.opacity(0.18))
    }
}

private struct AgentVaultSidebarMaterialBackground: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .withinWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context _: Context) {
        nsView.material = .sidebar
        nsView.blendingMode = .withinWindow
        nsView.state = .followsWindowActiveState
    }
}

private enum AgentVaultGrouping: String, CaseIterable, Identifiable {
    case folder
    case agent

    var id: String { rawValue }

    var label: String {
        switch self {
        case .folder:
            "By folder"
        case .agent:
            "By agent"
        }
    }

    var iconName: String {
        switch self {
        case .folder:
            "folder"
        case .agent:
            "person.2"
        }
    }

    func sections(for sessions: [AgentVaultSession]) -> [AgentVaultSessionSection] {
        switch self {
        case .folder:
            groupedByFolder(sessions)
        case .agent:
            groupedByAgent(sessions)
        }
    }

    private func groupedByAgent(_ sessions: [AgentVaultSession]) -> [AgentVaultSessionSection] {
        AgentVaultAgent.allCases.compactMap { agent in
            let items = sessions
                .filter { $0.agent == agent }
                .sorted { $0.modified > $1.modified }
            guard !items.isEmpty else { return nil }
            return AgentVaultSessionSection(
                id: "agent:\(agent.rawValue)",
                title: agent.displayName,
                icon: .provider(agent.iconName),
                sessions: items,
                allowsBulkDelete: false,
                folderGroupingKey: nil
            )
        }
    }

    private func groupedByFolder(_ sessions: [AgentVaultSession]) -> [AgentVaultSessionSection] {
        let grouped = Dictionary(grouping: sessions) { session in
            session.folderGroupingKey
        }
        return grouped.keys.sorted { lhs, rhs in
            let leftDate = grouped[lhs]?.map(\.modified).max() ?? .distantPast
            let rightDate = grouped[rhs]?.map(\.modified).max() ?? .distantPast
            if leftDate != rightDate {
                return leftDate > rightDate
            }
            let leftTitle = grouped[lhs]?.first?.folderDisplayName ?? lhs
            let rightTitle = grouped[rhs]?.first?.folderDisplayName ?? rhs
            let titleOrder = leftTitle.localizedCaseInsensitiveCompare(rightTitle)
            if titleOrder != .orderedSame {
                return titleOrder == .orderedAscending
            }
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }.map { folderGroupingKey in
            let items = (grouped[folderGroupingKey] ?? []).sorted { $0.modified > $1.modified }
            return AgentVaultSessionSection(
                id: "folder:\(folderGroupingKey)",
                title: items.first?.folderDisplayName ?? "Unknown",
                icon: .system("folder"),
                sessions: items,
                allowsBulkDelete: true,
                folderGroupingKey: folderGroupingKey
            )
        }
    }
}

private struct AgentVaultGroupingButton: View {
    let grouping: AgentVaultGrouping
    let isSelected: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: UIMetrics.spacing1) {
                Image(systemName: grouping.iconName)
                    .font(.system(size: UIMetrics.fontCaption, weight: .semibold))
                Text(grouping.label)
                    .font(.system(size: UIMetrics.fontFootnote, weight: .medium))
            }
            .foregroundStyle(isSelected ? MuxyTheme.accent : MuxyTheme.fgMuted)
            .padding(.horizontal, UIMetrics.spacing3)
            .frame(height: UIMetrics.controlSmall)
            .background(
                isSelected || hovered ? MuxyTheme.hover : Color.clear,
                in: RoundedRectangle(cornerRadius: UIMetrics.radiusSM)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(grouping.label)
    }
}

private struct AgentVaultSessionSection: Identifiable {
    let id: String
    let title: String
    let icon: AgentVaultSectionIcon
    let sessions: [AgentVaultSession]
    let allowsBulkDelete: Bool
    let folderGroupingKey: String?
}

private enum AgentVaultSectionIcon {
    case provider(String)
    case system(String)
}

private struct AgentVaultSectionHeader: View {
    let section: AgentVaultSessionSection
    let isCollapsed: Bool

    var body: some View {
        HStack(spacing: UIMetrics.spacing2) {
            sectionIcon
            Text(section.title)
                .font(.system(size: UIMetrics.fontEmphasis, weight: .semibold))
                .foregroundStyle(MuxyTheme.fg)
                .lineLimit(1)
                .truncationMode(.middle)
            Image(systemName: "chevron.down")
                .font(.system(size: UIMetrics.fontCaption, weight: .semibold))
                .foregroundStyle(MuxyTheme.fgMuted)
                .rotationEffect(.degrees(isCollapsed ? -90 : 0))
            Spacer(minLength: 0)
            Text("\(section.sessions.count)")
                .font(.system(size: UIMetrics.fontBody, design: .monospaced))
                .foregroundStyle(MuxyTheme.fgMuted)
                .padding(.horizontal, UIMetrics.spacing2)
                .frame(height: UIMetrics.scaled(18))
                .background(MuxyTheme.fgMuted.opacity(0.12), in: Capsule())
        }
        .padding(.horizontal, UIMetrics.spacing4)
        .padding(.vertical, UIMetrics.spacing2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(
            MuxyTheme.surface,
            in: RoundedRectangle(cornerRadius: UIMetrics.radiusSM)
        )
        .padding(.horizontal, UIMetrics.spacing2)
        .padding(.top, UIMetrics.spacing2)
    }

    @ViewBuilder
    private var sectionIcon: some View {
        switch section.icon {
        case let .provider(iconName):
            ProviderIconView(iconName: iconName, size: UIMetrics.iconMD, style: .monochrome(MuxyTheme.fg))
        case let .system(iconName):
            Image(systemName: iconName)
                .font(.system(size: UIMetrics.fontBody, weight: .semibold))
                .foregroundStyle(MuxyTheme.fg)
                .frame(width: UIMetrics.iconMD, height: UIMetrics.iconMD)
        }
    }
}

private struct AgentVaultSessionRow: View {
    let session: AgentVaultSession
    let canResume: Bool
    let onResume: () -> Void
    let onRequestDelete: () -> Void

    @State private var hovered = false

    var body: some View {
        HStack(spacing: UIMetrics.spacing3) {
            ProviderIconView(iconName: session.agent.iconName, size: UIMetrics.iconLG, style: .monochrome(sessionForeground))

            Text(session.displayTitle)
                .font(.system(size: UIMetrics.fontEmphasis))
                .foregroundStyle(sessionForeground)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: UIMetrics.spacing2)

            Text(Self.relativeFormatter.localizedString(for: session.modified, relativeTo: Date()))
                .font(.system(size: UIMetrics.fontBody, design: .monospaced))
                .foregroundStyle(MuxyTheme.fgDim)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.leading, UIMetrics.spacing10)
        .padding(.trailing, UIMetrics.spacing6)
        .padding(.vertical, UIMetrics.spacing2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(rowBackground)
        .overlay {
            AgentVaultSessionDragView(
                session: session,
                canResume: canResume,
                onDoubleClick: onResume
            )
        }
        .onHover { hovered = $0 }
        .contextMenu {
            Button("Resume in New Tab", action: onResume)
                .disabled(!canResume)
            Button("Copy Resume Command") {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(session.resumeCommand, forType: .string)
            }
            if let transcriptPath = session.transcriptPath {
                Button("Reveal Transcript") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: transcriptPath)])
                }
            }
            if let cwd = session.cwd {
                Button("Open Working Directory") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: cwd))
                }
            }
            Divider()
            Button("Delete Session...", role: .destructive, action: onRequestDelete)
                .disabled(session.transcriptPath == nil)
        }
        .help(helpText)
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: UIMetrics.radiusSM)
            .fill(hovered ? MuxyTheme.hover : Color.clear)
            .padding(.horizontal, UIMetrics.spacing2)
    }

    private var sessionForeground: Color {
        guard canResume else { return MuxyTheme.fgDim }
        return hovered ? MuxyTheme.fg : MuxyTheme.fgMuted
    }

    private var helpText: String {
        [
            session.displayTitle,
            session.cwd,
            session.model,
            session.gitBranch,
        ].compactMap(\.self).joined(separator: "\n")
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}
