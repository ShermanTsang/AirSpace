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
    @AppStorage("airspace.language") private var language = "system"
    @Environment(\.openWindow) private var openWindow
    @AppStorage("spacePanelSortOrder") private var sortOrder: WorkspaceSortOrder = .name
    @State private var actionMessage: String?
    @GestureState private var drag: WorkspaceAppDrag?
    @State private var dropFrames = WorkspaceDropFrames()
    @State private var listFrame: CGRect = .zero
    @State private var contentOffset: CGFloat = 0
    @State private var contentHeight: CGFloat?
    @State private var quickBarContentHeight: CGFloat?
    @State private var expandedIdleGroups: Set<WorkspaceDisplay.ID> = []
    @State private var isListHovered = false
    @State private var isQuickBarPinned = false

    private let columnCount = 2
    private let tileHeight: CGFloat = 78
    private let spacing: CGFloat = 8
    private let maxListHeight: CGFloat = 476

    private var hasMultipleSpaces: Bool { viewModel.workspaceGroups.sumOfInt { $0.workspaces.count } > 1 }
    private var showsQuickBar: Bool { hasMultipleSpaces && (isQuickBarPinned || drag != nil) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if showsQuickBar {
                    quickDropBar.frame(maxWidth: .infinity)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Spaces")).font(.title3.weight(.semibold))
                        Text(L("Drag an app icon to move its windows")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 4)
                if viewModel.axPermissionStatus == .granted, viewModel.isEnabled, hasMultipleSpaces {
                    Toggle(isOn: $isQuickBarPinned) {
                        Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                    }
                    .toggleStyle(.button)
                    .help(isQuickBarPinned ? L("Hide quick drop targets") : L("Show quick drop targets"))
                    .accessibilityLabel(isQuickBarPinned ? L("Hide quick drop targets") : L("Show quick drop targets"))
                }
                Menu {
                    Picker(L("Sort spaces"), selection: $sortOrder) {
                        Text(L("Space order")).tag(WorkspaceSortOrder.name)
                        Text(L("Active spaces first")).tag(WorkspaceSortOrder.active)
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .menuIndicator(.hidden)
                .fixedSize()
                .help(L("Sort spaces"))
                .accessibilityLabel(L("Sort spaces"))
                Button { openWindow(id: settingsWindowId) } label: { Image(systemName: "gearshape") }
                    .help(L("Settings"))
                    .accessibilityLabel(L("Settings"))
            }
            if viewModel.axPermissionStatus != .granted {
                Button(L("Grant accessibility permission")) { viewModel.axPermissionStatus = .waitingWithPrompt }
            } else if !viewModel.isEnabled {
                Text(L("AirSpace is paused. Enable it in Settings.")).foregroundStyle(.secondary)
            } else {
                if viewModel.lastReloadConfigContainedWarnings {
                    Button(L("Configuration contains warnings")) { openWindow(id: settingsWindowId) }
                        .foregroundStyle(.orange)
                }
                if let actionMessage {
                    Label(actionMessage, systemImage: "exclamationmark.circle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
                if viewModel.workspaceGroups.isEmpty {
                    Text(L("No spaces yet. Open a window to create one.")).foregroundStyle(.secondary)
                } else {
                    scrollableGrid
                }
            }
        }
        .overlay(alignment: .topLeading) {
            if let drag {
                WorkspaceAppIcon(app: drag.app)
                    .opacity(0.85)
                    .position(x: drag.location.x + 14, y: drag.location.y + 14)
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
            }
        }
        .coordinateSpace(name: WorkspaceDragArea.panel)
        .onPreferenceChange(WorkspaceDropFramePreference.self) { dropFrames = $0 }
        .onDisappear { isQuickBarPinned = false }
        .padding(14)
        .frame(width: 520)
    }

    private var scrollableGrid: some View {
        let targetName = drag.flatMap(dropTarget)
        return ScrollViewReader { scroll in
            ScrollView(.vertical, showsIndicators: false) {
                // Keep the source tile alive when a drag scrolls it out of view.
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(viewModel.workspaceGroups) { group in
                        displaySection(group, targetName: targetName)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.trailing, scrollRange > 0 ? 12 : 0)
                .id(WorkspaceDragArea.grid)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
                .onGeometryChange(for: CGFloat.self) { -$0.frame(in: .named(WorkspaceDragArea.list)).minY } action: { contentOffset = $0 }
            }
            .frame(height: listHeight)
            .coordinateSpace(name: WorkspaceDragArea.list)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(WorkspaceDragArea.panel)) } action: { listFrame = $0 }
            .overlay(alignment: .trailing) {
                if let contentHeight, scrollRange > 0 {
                    WorkspaceScrollbar(
                        viewportHeight: listHeight,
                        contentHeight: contentHeight,
                        progress: min(max(contentOffset / scrollRange, 0), 1),
                        isHovered: isListHovered,
                        scroll: { scroll.scrollTo(WorkspaceDragArea.grid, anchor: UnitPoint(x: 0, y: $0)) },
                    )
                }
            }
            .onHover { isListHovered = $0 }
            .task(id: scrollDirection) {
                guard let direction = scrollDirection, scrollRange > 0 else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(260))
                    guard !Task.isCancelled, scrollDirection == direction, scrollRange > 0 else { return }
                    let step = direction == .up ? -(tileHeight + spacing) : tileHeight + spacing
                    let progress = min(max((contentOffset + step) / scrollRange, 0), 1)
                    scroll.scrollTo(WorkspaceDragArea.grid, anchor: UnitPoint(x: 0, y: progress))
                }
            }
        }
    }

    private func displaySection(_ group: WorkspaceDisplayGroup, targetName: String?) -> some View {
        let spaces = sorted(group.workspaces)
        let idle = spaces.filter(\.isIdle)
        let expanded = expandedIdleGroups.contains(group.id)
        let otherDisplays = viewModel.workspaceGroups.filter { $0.id != group.id }.map(\.display)
        return VStack(alignment: .leading, spacing: spacing) {
            Label(group.display.title, systemImage: "display")
                .font(.subheadline.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            spaceRows(spaces.filter { !$0.isIdle }, targetName: targetName, otherDisplays: otherDisplays)
            if !idle.isEmpty {
                Button {
                    if expanded {
                        expandedIdleGroups.remove(group.id)
                    } else {
                        expandedIdleGroups.insert(group.id)
                    }
                } label: {
                    Label("Idle spaces (\(idle.count))", systemImage: expanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .accessibilityValue(expanded ? L("Expanded") : L("Collapsed"))
                if expanded { spaceRows(idle, targetName: targetName, otherDisplays: otherDisplays) }
            }
        }
    }

    @ViewBuilder private func spaceRows(_ spaces: [WorkspaceViewModel], targetName: String?, otherDisplays: [WorkspaceDisplay]) -> some View {
        ForEach(Array(stride(from: 0, to: spaces.count, by: columnCount)), id: \.self) { start in
            HStack(spacing: spacing) {
                ForEach(spaces[start..<min(start + columnCount, spaces.count)], id: \.name) { workspace in
                    tile(for: workspace, isDropTarget: targetName == workspace.name, otherDisplays: otherDisplays)
                }
                if start + 1 == spaces.count {
                    Color.clear.frame(minWidth: 0, maxWidth: .infinity).frame(height: tileHeight)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private func tile(for workspace: WorkspaceViewModel, isDropTarget: Bool, otherDisplays: [WorkspaceDisplay]) -> some View {
        WorkspaceTile(
            workspace: workspace,
            focus: { runAction { _ = Workspace.get(byName: workspace.name).focusWorkspace() } },
            chooseLayout: { mode in runAction { mode.apply(to: Workspace.get(byName: workspace.name)) } },
            restoreLayout: { runAction {
                let target = Workspace.get(byName: workspace.name)
                let monitor = target.workspaceMonitorInfo
                WorkspaceDisplayLayouts.shared.forget(workspace: target.name, display: monitor.displayKey)
                WorkspaceDisplayLayouts.shared.apply(to: target, on: monitor)
                resetClosedWindowsCache()
            } },
            toggleLock: { runAction { await WorkspaceLocks.shared.toggle(Workspace.get(byName: workspace.name)) } },
            otherDisplays: otherDisplays,
            moveToDisplay: { display in moveSpace(workspace.name, to: display) },
            drag: _drag,
            isDropTarget: isDropTarget,
            finishDrag: finishDrag,
        )
        .frame(height: tileHeight)
        .background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: WorkspaceDropFramePreference.self,
                    value: WorkspaceDropFrames(tiles: [workspace.name: geometry.frame(in: .named(WorkspaceDragArea.panel))]),
                )
            }
        }
    }

    private var quickDropBar: some View {
        let targetName = drag.flatMap(dropTarget)
        return ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(viewModel.workspaceGroups) { group in
                    Text(group.display.title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 30), spacing: 4)], spacing: 4) {
                        ForEach(sorted(group.workspaces), id: \.name) { workspace in
                            quickDropTarget(workspace, in: group.display, isTarget: targetName == workspace.name)
                        }
                    }
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { quickBarContentHeight = $0 }
        }
        .frame(height: min(quickBarContentHeight ?? 136, 136))
        .background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: WorkspaceDropFramePreference.self,
                    value: WorkspaceDropFrames(shortcutBar: geometry.frame(in: .named(WorkspaceDragArea.panel))),
                )
            }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.12)))
        .shadow(color: .black.opacity(0.16), radius: 5, y: 2)
    }

    private func quickDropTarget(_ workspace: WorkspaceViewModel, in display: WorkspaceDisplay, isTarget: Bool) -> some View {
        let tint = workspace.isLocked ? Color.orange : Color.accentColor
        return Text(workspace.name)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .frame(height: 24)
            .foregroundStyle(drag?.workspace == workspace.name ? .secondary : .primary)
            .background(isTarget ? tint.opacity(0.25) : Color.primary.opacity(0.075), in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(isTarget ? tint : .clear))
            .help("\(workspace.name) · \(display.title)")
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: WorkspaceDropFramePreference.self,
                        value: WorkspaceDropFrames(shortcuts: [workspace.name: geometry.frame(in: .named(WorkspaceDragArea.panel))]),
                    )
                }
            }
    }

    private func dropTarget(_ drag: WorkspaceAppDrag) -> String? {
        dropFrames.target(source: drag.workspace, location: drag.location, listFrame: listFrame)
    }

    private func finishDrag(_ drag: WorkspaceAppDrag) {
        if let target = dropTarget(drag) { moveApp(drag, to: target) }
    }

    private var scrollDirection: WorkspaceScrollDirection? {
        guard let location = drag?.location, listFrame.contains(location) else { return nil }
        // The floating bar covers the top edge. Scroll up just below it during a drag.
        let top = !isQuickBarPinned ? max(listFrame.minY, dropFrames.shortcutBar.maxY) : listFrame.minY
        if location.y < top { return nil }
        if location.y < top + 24 { return .up }
        if location.y > listFrame.maxY - 24 { return .down }
        return nil
    }

    private func sorted(_ spaces: [WorkspaceViewModel]) -> [WorkspaceViewModel] {
        guard sortOrder == .active else { return spaces }
        return spaces.enumerated().sorted {
            ($0.element.activityRank, $0.offset) < ($1.element.activityRank, $1.offset)
        }.map(\.element)
    }

    private var listHeight: CGFloat { min(contentHeight ?? maxListHeight, maxListHeight) }
    private var scrollRange: CGFloat { max(0, (contentHeight ?? 0) - listHeight) }

    private func moveSpace(_ name: String, to display: WorkspaceDisplay) {
        runAction {
            gcMonitors()
            guard let workspace = Workspace.all.first(where: { $0.name == name }) else {
                actionMessage = "Space \(name) is no longer available."
                return
            }
            guard !workspace.isLocked else {
                actionMessage = workspaceLockedMessage(name)
                return
            }
            guard let monitor = globalSortedMonitorInfos.first(where: { WorkspaceDisplay.ID($0) == display.id }) else {
                actionMessage = "\(display.title) is no longer connected."
                return
            }
            let focus = globalFocus.workspace
            let destinationIsFocused = focus.workspaceMonitorInfo.rect.topLeftCorner == monitor.rect.topLeftCorner
            // Do not displace the user's focused space when moving an unfocused one.
            let shouldShow = workspace == focus || (workspace.isVisible && !destinationIsFocused)
            // Match workspace garbage collection so a move cannot make the space disappear.
            if !shouldShow && workspace.isEffectivelyEmpty && !config.persistentWorkspaces.contains(name) {
                actionMessage = "Focus space \(name) before moving it. Empty automatic spaces cannot be moved in the background."
                return
            }
            guard moveWorkspace(workspace, to: monitor, showOnDestination: shouldShow) else {
                actionMessage = "Space \(name) is assigned to another display in the configuration."
                return
            }
            resetClosedWindowsCache()
        }
    }

    private func runAction(_ action: @escaping @MainActor () async -> Void) {
        guard let token: RunSessionGuard = .isServerEnabled else { return }
        actionMessage = nil
        Task.startUnstructured {
            try await runLightSession(.menuBarButton, token, body: action)
        }
    }

    private func moveApp(_ item: WorkspaceAppDrag, to targetName: String) {
        guard item.workspace != targetName else { return }
        let source = Workspace.get(byName: item.workspace)
        let target = Workspace.get(byName: targetName)
        if target.isLocked || source.isLocked {
            actionMessage = workspaceLockedMessage(target.isLocked ? target.name : source.name)
            return
        }
        runAction {
            let windows = item.app.windowIDs.compactMap { Window.get(byId: $0) }.filter { $0.membershipWorkspace == source }
            guard !windows.isEmpty else { return }
            if let locked = lockedWorkspaceForTransfer(windows[0], to: target) {
                actionMessage = workspaceLockedMessage(locked.name)
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

private enum WorkspaceDragArea { case panel, list, grid }
private enum WorkspaceScrollDirection { case up, down }

private struct WorkspaceAppDrag {
    let workspace: String
    let app: WorkspaceApp
    let location: CGPoint
}

struct WorkspaceDropFrames: Equatable {
    var tiles: [String: CGRect] = [:]
    var shortcuts: [String: CGRect] = [:]
    var shortcutBar: CGRect = .null

    func target(source: String, location: CGPoint, listFrame: CGRect) -> String? {
        if shortcutBar.contains(location) {
            return shortcuts.first { $0.key != source && $0.value.contains(location) }?.key
        }
        guard listFrame.contains(location) else { return nil }
        return tiles.first { $0.key != source && $0.value.contains(location) }?.key
    }
}

private struct WorkspaceDropFramePreference: PreferenceKey {
    static let defaultValue = WorkspaceDropFrames()

    static func reduce(value: inout WorkspaceDropFrames, nextValue: () -> WorkspaceDropFrames) {
        let next = nextValue()
        value.tiles.merge(next.tiles) { _, new in new }
        value.shortcuts.merge(next.shortcuts) { _, new in new }
        if !next.shortcutBar.isNull { value.shortcutBar = next.shortcutBar }
    }
}

private struct WorkspaceScrollbar: View {
    let viewportHeight: CGFloat
    let contentHeight: CGFloat
    let progress: CGFloat
    let isHovered: Bool
    let scroll: (CGFloat) -> Void

    @GestureState private var isDragging = false
    @State private var grabOffset: CGFloat?

    var body: some View {
        let thumbHeight = max(22, viewportHeight * viewportHeight / contentHeight)
        let travel = viewportHeight - thumbHeight
        let thumbTop = progress * travel
        Capsule()
            .fill(Color.primary.opacity(isDragging ? 0.28 : 0.17))
            .frame(width: 5, height: thumbHeight)
            .offset(y: thumbTop)
            .frame(width: 12, height: viewportHeight, alignment: .top)
            .contentShape(Rectangle())
            .opacity(isHovered || isDragging ? 1 : 0)
            .allowsHitTesting(isHovered || isDragging)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isDragging) { _, state, _ in state = true }
                    .onChanged { value in
                        if grabOffset == nil {
                            let start = value.startLocation.y - thumbTop
                            grabOffset = (0 ... thumbHeight).contains(start) ? start : thumbHeight / 2
                        }
                        let position = value.location.y - (grabOffset ?? 0)
                        scroll(min(max(position / travel, 0), 1))
                    },
            )
            .onChangeCompat(of: isDragging) { dragging in
                if !dragging { grabOffset = nil }
            }
            .accessibilityHidden(true)
    }
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
    @Environment(\.colorScheme) private var colorScheme

    let workspace: WorkspaceViewModel
    let focus: () -> Void
    let chooseLayout: (WorkspaceLayoutMode) -> Void
    let restoreLayout: () -> Void
    let toggleLock: () -> Void
    let otherDisplays: [WorkspaceDisplay]
    let moveToDisplay: (WorkspaceDisplay) -> Void
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
                .help(workspace.isFocused ? L("Focused space") : workspace.isVisible ? L("Visible on this display") : "Focus \(workspace.name)")
                .accessibilityValue(workspace.isFocused ? L("Focused") : workspace.isVisible ? L("Visible") : L("Hidden"))
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
                    Divider()
                    Text(workspace.isLocked ? L("Layout controlled by lock") : !workspace.canRememberDisplayLayout ? L("Display cannot be identified") : workspace.hasDisplayLayout ? L("Remembered for this display") : L("Using default layout"))
                    Button(L("Restore default layout"), action: restoreLayout)
                        .disabled(!workspace.hasDisplayLayout || workspace.isLocked)
                } label: {
                    Image(systemName: workspace.mode.icon)
                        .rotationEffect(.degrees(workspace.mode == .verticalAccordion ? 90 : 0))
                }
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Layout: \(workspace.mode.title)")
                .accessibilityLabel("Layout: \(workspace.mode.title)")
                Spacer()
                if !otherDisplays.isEmpty {
                    Menu {
                        ForEach(otherDisplays) { display in
                            Button(display.title) { moveToDisplay(display) }
                        }
                    } label: {
                        Image(systemName: "display.2")
                    }
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .disabled(workspace.isLocked)
                    .help(L("Move space to display"))
                    .accessibilityLabel("Move \(workspace.name) to display")
                }
                Button(action: toggleLock) {
                    Image(systemName: workspace.isLocked ? "lock.fill" : "lock.open")
                        .foregroundStyle(workspace.isLocked ? Color.orange : Color.secondary)
                }
                .help(workspace.isLocked ? "Unlock \(workspace.name)" : "Lock \(workspace.name)")
                .accessibilityLabel(workspace.isLocked ? "Unlock \(workspace.name)" : "Lock \(workspace.name)")
            }
            if workspace.apps.isEmpty {
                Text(L("No windows")).font(.caption).foregroundStyle(.secondary).frame(height: 24)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(workspace.apps) { app in
                            WorkspaceAppIcon(app: app)
                                .overlay(alignment: .bottomTrailing) {
                                    if app.windowIDs.count > 1 {
                                        Text("×\(app.windowIDs.count)")
                                            .font(.system(size: 9, weight: .bold).monospacedDigit())
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 3)
                                            .padding(.vertical, 1)
                                            .background(Color(white: 0.15), in: Capsule())
                                            .fixedSize()
                                            .allowsHitTesting(false)
                                            .accessibilityHidden(true)
                                    }
                                }
                                .contentShape(Rectangle())
                                .accessibilityAddTraits(.isButton)
                                .accessibilityLabel(Text(app.name))
                                .accessibilityValue(app.windowIDs.count == 1 ? L("1 window") : "\(app.windowIDs.count) windows")
                                .help("\(app.name) · \(app.windowIDs.count) window(s)")
                                // Keep the gesture local to the menu bar window, without starting a system drag session.
                                .highPriorityGesture(
                                    DragGesture(minimumDistance: 5, coordinateSpace: .named(WorkspaceDragArea.panel))
                                        .updating(drag) { value, state, _ in
                                            state = WorkspaceAppDrag(workspace: workspace.name, app: app, location: value.location)
                                        }
                                        .onEnded { value in
                                            finishDrag(WorkspaceAppDrag(workspace: workspace.name, app: app, location: value.location))
                                        },
                                )
                                .simultaneousGesture(TapGesture().onEnded { focus() })
                        }
                    }
                }
                .frame(height: 24)
            }
        }
        .padding(.horizontal, 12)
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(backgroundTint, in: RoundedRectangle(cornerRadius: 12))
        .background(Color.black.opacity(colorScheme == .dark ? 0.22 : 0.09), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(border, lineWidth: 1))
    }

    private var backgroundTint: Color {
        if isDropTarget { return (workspace.isLocked ? Color.orange : Color.accentColor).opacity(0.18) }
        return workspace.isFocused ? Color.accentColor.opacity(0.10) : .clear
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
        let button = Button(L("Reload config")) {
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
