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

@MainActor
private struct WorkspaceMenu: View {
    @ObservedObject var viewModel: TrayMenuModel
    @Environment(\.openWindow) private var openWindow
    @AppStorage("spacePanelSortOrder") private var sortOrder: WorkspaceSortOrder = .name
    @State private var dropMessage: String?
    @GestureState private var drag: WorkspaceAppDrag?
    @State private var rowFrames: [String: CGRect] = [:]
    @State private var listSize: CGSize = .zero

    private let tileHeight: CGFloat = 78
    private let spacing: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Spaces").font(.title3.weight(.semibold))
                    Text("Drag an app icon to move its windows").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Picker("Sort spaces", selection: $sortOrder) {
                        Text("Space order").tag(WorkspaceSortOrder.name)
                        Text("Active spaces first").tag(WorkspaceSortOrder.active)
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Sort spaces")
                .accessibilityLabel("Sort spaces")
                Button { openWindow(id: settingsWindowId) } label: { Image(systemName: "gearshape") }
                    .help("Settings")
                    .accessibilityLabel("Settings")
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
                if let dropMessage {
                    Label(dropMessage, systemImage: "lock.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
                if viewModel.workspaces.isEmpty {
                    Text("No spaces yet. Open a window to create one.").foregroundStyle(.secondary)
                } else {
                    spaceList
                }
            }
        }
        .padding(14)
        .frame(width: 520)
    }

    private var spaceList: some View {
        ScrollViewReader { scroll in
            ScrollView(.vertical) {
                VStack(spacing: spacing) {
                    ForEach(sortedSpaces, id: \.name) { workspace in
                        WorkspaceTile(
                            workspace: workspace,
                            focus: { runAction { _ = Workspace.get(byName: workspace.name).focusWorkspace() } },
                            chooseLayout: { mode in runAction { mode.apply(to: Workspace.get(byName: workspace.name)) } },
                            toggleLock: { runAction { await WorkspaceLocks.shared.toggle(Workspace.get(byName: workspace.name)) } },
                            drag: _drag,
                            isDropTarget: drag.flatMap(dropTarget) == workspace.name,
                            finishDrag: finishDrag,
                        )
                        .frame(height: tileHeight)
                        .id(workspace.name)
                        .background {
                            GeometryReader { geometry in
                                Color.clear.preference(
                                    key: WorkspaceRowFrames.self,
                                    value: [workspace.name: geometry.frame(in: .named(WorkspaceDragArea.list))],
                                )
                            }
                        }
                    }
                }
            }
            .frame(height: listHeight)
            .coordinateSpace(name: WorkspaceDragArea.list)
            .onPreferenceChange(WorkspaceRowFrames.self) { rowFrames = $0 }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { listSize = $0 }
            .overlay(alignment: .topLeading) {
                if let drag {
                    WorkspaceAppIcon(app: drag.app)
                        .opacity(0.85)
                        .position(x: drag.location.x + 14, y: drag.location.y + 14)
                        .accessibilityHidden(true)
                        .allowsHitTesting(false)
                }
            }
            .clipped()
            .task(id: scrollDirection) {
                guard let direction = scrollDirection else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(260))
                    guard !Task.isCancelled, scrollDirection == direction else { return }
                    if let next = nextScrollSpace(direction) {
                        scroll.scrollTo(next, anchor: direction == .up ? .top : .bottom)
                    }
                }
            }
        }
    }

    private func dropTarget(_ drag: WorkspaceAppDrag) -> String? {
        workspaceDropTarget(source: drag.workspace, location: drag.location, listSize: listSize, rowFrames: rowFrames)
    }

    private func finishDrag(_ drag: WorkspaceAppDrag) {
        if let target = dropTarget(drag) { moveApp(drag, to: target) }
    }

    private var scrollDirection: WorkspaceScrollDirection? {
        guard let location = drag?.location, CGRect(origin: .zero, size: listSize).contains(location) else { return nil }
        if location.y < 24 { return .up }
        if location.y > listSize.height - 24 { return .down }
        return nil
    }

    private func nextScrollSpace(_ direction: WorkspaceScrollDirection) -> String? {
        let names = sortedSpaces.map(\.name)
        switch direction {
            case .up: return names.last { (rowFrames[$0]?.minY ?? 0) < -1 }
            case .down: return names.first { (rowFrames[$0]?.maxY ?? 0) > listSize.height + 1 }
        }
    }

    private var sortedSpaces: [WorkspaceViewModel] {
        guard sortOrder == .active else { return viewModel.workspaces }
        return viewModel.workspaces.enumerated().sorted {
            ($0.element.activityRank, $0.offset) < ($1.element.activityRank, $1.offset)
        }.map(\.element)
    }

    private var listHeight: CGFloat {
        let rows = CGFloat(viewModel.workspaces.count)
        return min(rows * tileHeight + max(0, rows - 1) * spacing, 476)
    }

    private func runAction(_ action: @escaping @MainActor () async -> Void) {
        guard let token: RunSessionGuard = .isServerEnabled else { return }
        dropMessage = nil
        Task.startUnstructured {
            try await runLightSession(.menuBarButton, token, body: action)
        }
    }

    private func moveApp(_ item: WorkspaceAppDrag, to targetName: String) {
        guard item.workspace != targetName else { return }
        let source = Workspace.get(byName: item.workspace)
        let target = Workspace.get(byName: targetName)
        if target.isLocked || source.isLocked {
            dropMessage = workspaceLockedMessage(target.isLocked ? target.name : source.name)
            return
        }
        runAction {
            let windows = item.app.windowIDs.compactMap { Window.get(byId: $0) }.filter { $0.membershipWorkspace == source }
            guard !windows.isEmpty else { return }
            if let locked = lockedWorkspaceForTransfer(windows[0], to: target) {
                dropMessage = workspaceLockedMessage(locked.name)
                return
            }
            resetClosedWindowsCache()
            let io = CmdIoImpl.emptyStdinIgnoringOut
            for window in windows {
                _ = moveWindowToWorkspace(window, target, io, focusFollowsWindow: false, failIfNoop: false)
            }
        }
    }
}

private enum WorkspaceSortOrder: String {
    case name, active
}

private enum WorkspaceDragArea { case list }
private enum WorkspaceScrollDirection { case up, down }

private struct WorkspaceAppDrag {
    let workspace: String
    let app: WorkspaceApp
    let location: CGPoint
}

private struct WorkspaceRowFrames: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

func workspaceDropTarget(source: String, location: CGPoint, listSize: CGSize, rowFrames: [String: CGRect]) -> String? {
    guard CGRect(origin: .zero, size: listSize).contains(location) else { return nil }
    return rowFrames.first { $0.key != source && $0.value.contains(location) }?.key
}

private struct WorkspaceAppIcon: View {
    let app: WorkspaceApp

    var body: some View {
        Group {
            if let icon = app.icon {
                Image(nsImage: icon).resizable().scaledToFit()
            } else {
                Image(systemName: "app")
            }
        }
        .frame(width: 24, height: 24)
    }
}

@MainActor
private struct WorkspaceTile: View {
    let workspace: WorkspaceViewModel
    let focus: () -> Void
    let chooseLayout: (WorkspaceLayoutMode) -> Void
    let toggleLock: () -> Void
    let drag: GestureState<WorkspaceAppDrag?>
    let isDropTarget: Bool
    let finishDrag: (WorkspaceAppDrag) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button(action: focus) {
                    HStack(spacing: 6) {
                        Text(workspace.name).font(.headline).lineLimit(1)
                        if workspace.isFocused {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                        } else if workspace.isVisible {
                            Image(systemName: "display").foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .help("Focus \(workspace.name)")
                Menu {
                    ForEach(WorkspaceLayoutMode.allCases, id: \.self) { mode in
                        Button { chooseLayout(mode) } label: {
                            if mode == workspace.mode {
                                Label(mode.title, systemImage: "checkmark")
                            } else {
                                Label(mode.title, systemImage: mode.icon)
                            }
                        }
                    }
                } label: {
                    Image(systemName: workspace.mode.icon)
                        .rotationEffect(.degrees(workspace.mode == .verticalAccordion ? 90 : 0))
                }
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Layout: \(workspace.mode.title)")
                .accessibilityLabel("Layout: \(workspace.mode.title)")
                Spacer()
                Button(action: toggleLock) {
                    Image(systemName: workspace.isLocked ? "lock.fill" : "lock.open")
                        .foregroundStyle(workspace.isLocked ? Color.orange : Color.secondary)
                }
                .help(workspace.isLocked ? "Unlock \(workspace.name)" : "Lock \(workspace.name)")
                .accessibilityLabel(workspace.isLocked ? "Unlock \(workspace.name)" : "Lock \(workspace.name)")
            }
            if workspace.apps.isEmpty {
                Text("No windows").font(.caption).foregroundStyle(.secondary).frame(height: 24)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(workspace.apps) { app in
                            WorkspaceAppIcon(app: app)
                                .contentShape(Rectangle())
                                .accessibilityLabel(Text(app.name))
                                .help("\(app.name) · \(app.windowIDs.count) window(s)")
                                // Keep the gesture local to the menu bar window, without starting a system drag session.
                                .highPriorityGesture(
                                    DragGesture(minimumDistance: 5, coordinateSpace: .named(WorkspaceDragArea.list))
                                        .updating(drag) { value, state, _ in
                                            state = WorkspaceAppDrag(workspace: workspace.name, app: app, location: value.location)
                                        }
                                        .onEnded { value in
                                            finishDrag(WorkspaceAppDrag(workspace: workspace.name, app: app, location: value.location))
                                        },
                                )
                        }
                    }
                }
                .frame(height: 24)
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(border, lineWidth: 1))

    }

    private var background: Color {
        if isDropTarget { return (workspace.isLocked ? Color.orange : Color.accentColor).opacity(0.18) }
        return workspace.isFocused ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.035)
    }

    private var border: Color {
        if isDropTarget { return workspace.isLocked ? .orange : .accentColor }
        return workspace.isFocused ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.08)
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
