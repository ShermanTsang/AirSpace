import Common
import Foundation
import SwiftUI

@MainActor
public func menuBar(viewModel: TrayMenuModel) -> some Scene { // todo should it be converted to "SwiftUI struct"?
    MenuBarExtra {
        WorkspaceMenu(viewModel: viewModel)
    } label: {
        switch (viewModel.axPermissionStatus, viewModel.isEnabled) {
            case (.granted, true):
                MenuBarLabel().environmentObject(viewModel)
            case (.granted, false):
                Image(systemName: "pause.circle.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            case (_, _):
                Image(systemName: "exclamationmark.triangle.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
        }
    }
    .menuBarExtraStyle(.window)
}

private struct WorkspaceMenu: View {
    @ObservedObject var viewModel: TrayMenuModel
    @Environment(\.openWindow) private var openWindow

    private let tileHeight: CGFloat = 92
    private let spacing: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Spaces").font(.headline)
                Spacer()
                Button { openWindow(id: settingsWindowId) } label: { Image(systemName: "gearshape") }
                    .help("Settings")
            }
            if viewModel.axPermissionStatus != .granted {
                Button("Grant accessibility permission") { viewModel.axPermissionStatus = .waitingWithPrompt }
            } else if !viewModel.isEnabled {
                Text("AirSpace is paused. Enable it in Settings.").foregroundStyle(.secondary)
            } else {
                if viewModel.lastReloadConfigContainedWarnings {
                    Button("Configuration contains warnings") { openWindow(id: settingsWindowId) }
                        .foregroundStyle(.orange)
                }
                if viewModel.workspaces.isEmpty {
                    Text("No spaces yet. Open a window to create one.").foregroundStyle(.secondary)
                } else {
                    ScrollView(.vertical) {
                        VStack(spacing: spacing) {
                            ForEach(workspaceRows) { row in
                                HStack(spacing: spacing) {
                                    ForEach(row.workspaces, id: \.name) { workspace in
                                        workspaceButton(workspace)
                                    }
                                    if row.workspaces.count == 1 {
                                        Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                                    }
                                }
                            }
                        }
                    }
                    .frame(height: gridHeight)
                }
            }
        }
        .padding(14)
        .frame(width: 380)
    }

    private func workspaceButton(_ workspace: WorkspaceViewModel) -> some View {
        Button {
            guard let token: RunSessionGuard = .isServerEnabled else { return }
            Task.startUnstructured {
                try await runLightSession(.menuBarButton, token) {
                    _ = Workspace.get(byName: workspace.name).focusWorkspace()
                }
            }
        } label: {
            WorkspaceTile(workspace: workspace)
                .frame(height: tileHeight)
        }
        .buttonStyle(.plain)
    }

    private var workspaceRows: [WorkspaceRow] {
        stride(from: 0, to: viewModel.workspaces.count, by: 2).map { start in
            let end = min(start + 2, viewModel.workspaces.count)
            return WorkspaceRow(workspaces: Array(viewModel.workspaces[start..<end]))
        }
    }

    private var gridHeight: CGFloat {
        let rows = CGFloat(workspaceRows.count)
        return min(rows * tileHeight + max(0, rows - 1) * spacing, 420)
    }
}

private struct WorkspaceRow: Identifiable {
    let workspaces: [WorkspaceViewModel]
    var id: String { workspaces.first?.name ?? "" }
}

private struct WorkspaceTile: View {
    let workspace: WorkspaceViewModel

    private static let maxVisibleApps = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(workspace.name).font(.headline).lineLimit(1)
                Spacer(minLength: 2)
                if workspace.isFocused {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                } else if workspace.isVisible {
                    Image(systemName: "display").foregroundStyle(.secondary)
                }
            }
            if workspace.apps.isEmpty {
                Text("Empty").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(Array(workspace.apps.prefix(Self.maxVisibleApps).enumerated()), id: \.offset) { _, app in
                    HStack(spacing: 5) {
                        if let icon = app.icon {
                            Image(nsImage: icon).resizable().interpolation(.high).frame(width: 16, height: 16)
                        } else {
                            Image(systemName: "app").frame(width: 16, height: 16)
                        }
                        Text(app.name).lineLimit(1)
                    }.font(.caption)
                }
                if workspace.apps.count > Self.maxVisibleApps {
                    Text("+\(workspace.apps.count - Self.maxVisibleApps) more app(s)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(10)
        .background(workspace.isFocused ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(workspace.isFocused ? Color.accentColor : Color.clear, lineWidth: 1))
        .contentShape(Rectangle())
    }
}

@MainActor @ViewBuilder
func openConfigButton(showShortcutGroup: Bool = false) -> some View {
    let editor = getTextEditorToOpenConfig()
    let button = Button("Open config in '\(editor.lastPathComponent)'") {
        openConfigInTextEditor()
    }.keyboardShortcut(",", modifiers: .command)
    switch showShortcutGroup {
        case true: shortcutGroup(label: Text("⌘ ,"), content: button)
        case false: button
    }
}

/// Opens the config file that the user actually edits in a text editor.
/// Copies the default config to `~/.aerospace.toml` when there is no custom config yet
@MainActor
func openConfigInTextEditor() {
    let editor = getTextEditorToOpenConfig()
    let fallbackConfig: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: configDotfileName)
    switch findCustomConfigUrl() {
        case .file(let url):
            url.open(with: editor)
        case .noCustomConfigExists:
            _ = try? FileManager.default.copyItem(atPath: defaultConfigUrl.path, toPath: fallbackConfig.path)
            fallbackConfig.open(with: editor)
        case .ambiguousConfigError:
            fallbackConfig.open(with: editor)
    }
}

@MainActor @ViewBuilder
func reloadConfigButton(showShortcutGroup: Bool = false, warningsAsErrors: Bool) -> some View {
    if let token: RunSessionGuard = .isServerEnabled {
        let button = Button("Reload config") {
            Task.startUnstructured {
                try await runLightSession(.menuBarButton, token) {
                    let args: ReloadConfigCmdArgs = ReloadConfigCmdArgs(rawArgs: []).with(\.warningsAsErrors, warningsAsErrors)
                    _ = await reloadConfig_nonCancellable(args: args)
                }
            }
        }.keyboardShortcut("R", modifiers: .command)
        switch showShortcutGroup {
            case true: shortcutGroup(label: Text("⌘ R"), content: button)
            case false: button
        }
    }
}

func shortcutGroup(label: some View, content: some View) -> some View {
    GroupBox {
        VStack(alignment: .trailing, spacing: 6) {
            label
                .foregroundStyle(Color.secondary)
            content
        }
    }
}

func getTextEditorToOpenConfig() -> URL {
    NSWorkspace.shared.urlForApplication(toOpen: findCustomConfigUrl().urlOrNil ?? defaultConfigUrl)?
        .takeIf { $0.lastPathComponent != "Xcode.app" } // Blacklist Xcode. It is too heavy to open plain text files
        ?? URL(filePath: "/System/Applications/TextEdit.app")
}
