import AppKit
import Combine
import Common
import QuartzCore
import SwiftUI

private enum NavigatorControl: Hashable {
    case layoutMode(WorkspaceLayoutMode)
    case workspace(String)
    case overflowSpaces
}

/// Keeps a compact navigator capsule visible outside the menu bar.
///
/// The capsule always floats. Clicking it expands an inline panel with layout-style and
/// space-switching controls; dragging moves it. Hovering does not expand it. The panel never
/// participates in tiling: AirSpace ignores windows of its own process (see
/// `MacApp.getOrRegister`), and the panel deliberately has no `Window` counterpart.
@MainActor
final class WindowNavigatorPanelController {
    static let shared = WindowNavigatorPanelController()

    /// Top-right corner of the panel in screen coordinates
    private static let anchorDefaultsKey = "airspace.windowNavigator.anchor"
    private static let screenMargin: CGFloat = 12
    private static let animationDuration: TimeInterval = 0.26

    private let navigator = WindowNavigatorModel()
    private var contentSize = CGSize(width: 120, height: 44)
    private var collapsedContentSize = CGSize(width: 120, height: 44)
    private var expansionGeneration = 0
    private var isCollapsing = false

    private var statusPanel: WindowNavigatorStatusPanel?
    private var container: WindowNavigatorStatusContentView?
    private var configReloadSubscription: AnyCancellable?
    private var observers: [NSObjectProtocol] = []
    private var eventMonitors: [Any] = []

    private init() {}

    func start() {
        guard configReloadSubscription == nil else { return }
        applyConfig()
        configReloadSubscription = TrayMenuModel.shared.$configReloadEpoch
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.applyConfig()
                }
            }

        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main,
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.layoutPanel()
            }
        })
        installEventMonitors()
    }

    private func applyConfig() {
        let navigatorConfig = config.windowNavigator
        guard navigatorConfig.enabled else {
            expansionGeneration += 1
            isCollapsing = false
            navigator.isExpanded = false
            container?.controlFrames = [:]
            statusPanel?.orderOut(nil)
            return
        }
        navigator.size = navigatorConfig.size
        let panel = statusPanel ?? makeStatusPanel()
        statusPanel = panel
        layoutPanel()
        panel.orderFrontRegardless()
    }

    private func makeStatusPanel() -> WindowNavigatorStatusPanel {
        let panel = WindowNavigatorStatusPanel()
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false

        let content = WindowNavigatorStatusView(
            navigator: navigator,
            onContentSizeChange: { [weak self] size in
                self?.contentSizeChanged(size)
            },
            onControlFramesChange: { [weak self] frames in
                self?.container?.controlFrames = frames
            },
        )
        .environmentObject(TrayMenuModel.shared)
        let hostingView = StatusHostingView(rootView: AnyView(content))
        hostingView.autoresizingMask = [.width, .height]

        let container = WindowNavigatorStatusContentView(frame: NSRect(origin: .zero, size: contentSize))
        hostingView.frame = container.bounds
        container.addSubview(hostingView)
        container.toolTip = L("Click to open the navigator. Drag to move.")
        container.onToggleExpansion = { [weak self] in
            self?.toggleExpansion()
        }
        container.onActivateControl = { [weak self] control in
            self?.activate(control)
        }
        container.onDragEnd = { [weak self] in
            self?.statusPanelDidMove()
        }
        container.onOpenSettings = {
            openSettingsWindow()
        }
        panel.contentView = container
        panel.setContentSize(contentSize)
        self.container = container
        return panel
    }

    /// Anchors the panel by its top-right corner so the capsule expands left and down
    /// without moving the part of the capsule that the pointer clicked.
    private func layoutPanel(animated: Bool = false) {
        guard let panel = statusPanel else { return }
        let target = frame(for: clampedSize(contentSize))
        guard panel.frame != target else { return }
        if animated, panel.isVisible {
            animate(panel: panel, to: target) {}
        } else {
            panel.setFrame(target, display: true)
        }
    }

    private func clampedSize(_ size: CGSize) -> NSSize {
        NSSize(width: max(size.width, 24), height: max(size.height, 24))
    }

    private func frame(for size: NSSize) -> NSRect {
        let anchor = resolvedAnchor(for: size)
        return NSRect(
            origin: NSPoint(x: anchor.x - size.width, y: anchor.y - size.height),
            size: size,
        )
    }

    private func animate(panel: NSPanel, to frame: NSRect, completion: @escaping @MainActor () -> Void) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.animationDuration
            // Brisk at the start, settling gently. A plain linear animation feels mechanical
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
            panel.animator().setFrame(frame, display: true)
        } completionHandler: {
            MainActor.assumeIsolated {
                completion()
            }
        }
    }

    private func resolvedAnchor(for size: NSSize) -> NSPoint {
        let screens = NSScreen.screens
        let saved = loadAnchor() ?? screens.first.map {
            NSPoint(x: $0.visibleFrame.maxX - Self.screenMargin, y: $0.visibleFrame.maxY - Self.screenMargin)
        } ?? NSPoint(x: Self.screenMargin, y: Self.screenMargin)
        guard let visible = (screens.first { $0.frame.contains(saved) } ?? screens.first)?.visibleFrame else {
            return saved
        }
        return NSPoint(
            x: min(max(saved.x, visible.minX + size.width + Self.screenMargin), visible.maxX - Self.screenMargin),
            y: min(max(saved.y, visible.minY + size.height + Self.screenMargin), visible.maxY - Self.screenMargin),
        )
    }

    private func contentSizeChanged(_ size: CGSize) {
        let newSize = CGSize(width: ceil(size.width), height: ceil(size.height))
        guard newSize != contentSize else { return }
        contentSize = newSize
        if !navigator.isExpanded {
            collapsedContentSize = newSize
        }
        layoutPanel(animated: navigator.isExpanded && !isCollapsing)
    }

    private func toggleExpansion() {
        if navigator.isExpanded {
            if isCollapsing {
                // Clicked again mid-collapse: keep it open instead of finishing the collapse
                expansionGeneration += 1
                isCollapsing = false
                layoutPanel(animated: true)
            } else {
                collapse()
            }
        } else {
            expansionGeneration += 1
            navigator.isExpanded = true
        }
    }

    private func collapse() {
        guard navigator.isExpanded, !isCollapsing, let panel = statusPanel else { return }
        expansionGeneration += 1
        let generation = expansionGeneration
        isCollapsing = true
        let target = frame(for: clampedSize(collapsedContentSize))
        if panel.isVisible {
            animate(panel: panel, to: target) {
                guard generation == self.expansionGeneration else { return }
                self.isCollapsing = false
                self.navigator.isExpanded = false
                self.container?.controlFrames = [:]
            }
        } else {
            isCollapsing = false
            navigator.isExpanded = false
            container?.controlFrames = [:]
            panel.setFrame(target, display: true)
        }
    }

    private func collapseIfExpanded() {
        guard navigator.isExpanded, !isCollapsing else { return }
        collapse()
    }

    private func activate(_ control: NavigatorControl) {
        switch control {
            case .layoutMode(let mode): applyLayoutMode(mode)
            case .workspace(let name):
                focusWorkspace(named: name)
                collapse()
            case .overflowSpaces: showOverflowSpacesMenu()
        }
    }

    private func applyLayoutMode(_ mode: WorkspaceLayoutMode) {
        guard let token: RunSessionGuard = .isServerEnabled else { return }
        Task.startUnstructured { @MainActor in
            try? await runLightSession(.menuBarButton, token) {
                mode.apply(to: globalFocus.workspace)
            }
        }
    }

    private func focusWorkspace(named name: String) {
        guard let token: RunSessionGuard = .isServerEnabled else { return }
        Task.startUnstructured { @MainActor in
            try? await runLightSession(.menuBarButton, token) {
                _ = Workspace.get(byName: name).focusWorkspace()
            }
        }
    }

    private func showOverflowSpacesMenu() {
        let spaces = TrayMenuModel.shared.workspaces.filter { !$0.apps.isEmpty }
        guard !spaces.isEmpty else { return }
        let target = SpacesMenuTarget { [weak self] name in
            self?.focusWorkspace(named: name)
            self?.collapse()
        }
        let menu = NSMenu()
        for space in spaces {
            let item = NSMenuItem(
                title: space.name,
                action: #selector(SpacesMenuTarget.select(_:)),
                keyEquivalent: "",
            )
            item.target = target
            item.representedObject = space.name
            item.state = space.isFocused ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private func statusPanelDidMove() {
        guard let statusPanel else { return }
        saveAnchor(NSPoint(x: statusPanel.frame.maxX, y: statusPanel.frame.maxY))
        layoutPanel(animated: true)
    }

    private func loadAnchor() -> NSPoint? {
        UserDefaults.standard.string(forKey: Self.anchorDefaultsKey).flatMap(NSPointFromString)
    }

    private func saveAnchor(_ point: NSPoint) {
        UserDefaults.standard.set(NSStringFromPoint(point), forKey: Self.anchorDefaultsKey)
    }

    /// Collapses the panel when the click is outside of it. Global monitors see clicks that
    /// are delivered to other apps, local monitors see clicks that stay inside AirSpace.
    private func installEventMonitors() {
        guard eventMonitors.isEmpty else { return }
        if let monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown],
            handler: { _ in
                MainActor.assumeIsolated {
                    WindowNavigatorPanelController.shared.collapseIfExpanded()
                }
            },
        ) {
            eventMonitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown],
            handler: { event in
                MainActor.assumeIsolated {
                    let controller = WindowNavigatorPanelController.shared
                    if event.window !== controller.statusPanel {
                        controller.collapseIfExpanded()
                    }
                }
                return event
            },
        ) {
            eventMonitors.append(monitor)
        }
    }
}

@MainActor
private final class WindowNavigatorModel: ObservableObject {
    @Published var isExpanded = false
    @Published var size: WindowNavigatorSize = .medium
}

@MainActor
private struct WindowNavigatorStatusView: View {
    @ObservedObject var navigator: WindowNavigatorModel

    @EnvironmentObject private var viewModel: TrayMenuModel
    @Environment(\.colorScheme) private var colorScheme

    let onContentSizeChange: (CGSize) -> Void
    let onControlFramesChange: ([NavigatorControl: CGRect]) -> Void

    private static let maxSpaceChips = 8

    private var workspace: WorkspaceViewModel? { viewModel.workspaces.first(where: \.isFocused) }
    private var spacesWithApps: [WorkspaceViewModel] { viewModel.workspaces.filter { !$0.apps.isEmpty } }
    private var visibleSpaces: [WorkspaceViewModel] { Array(spacesWithApps.prefix(Self.maxSpaceChips)) }
    private var hiddenSpacesCount: Int { max(0, spacesWithApps.count - Self.maxSpaceChips) }
    private var scale: CGFloat { navigator.size.scale }
    private var foreground: Color { colorScheme == .dark ? .white : .black }

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            capsule
                .padding(8)
                .fixedSize()
                .onGeometryChange(for: CGSize.self) { $0.size } action: { onContentSizeChange($0) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .onPreferenceChange(NavigatorControlFramesKey.self) { onControlFramesChange($0) }
        .animation(.easeOut(duration: 0.18), value: navigator.isExpanded)
    }

    private var capsule: some View {
        HStack(spacing: 6 * scale) {
            if navigator.isExpanded {
                expandedControls
            }
            if let workspace {
                Image(systemName: workspace.mode.icon)
                    .font(.system(size: 14 * scale, weight: .semibold))
                    .rotationEffect(.degrees(workspace.mode == .verticalAccordion ? 90 : 0))
                    .foregroundStyle(foreground.opacity(0.85))
                    .frame(width: 18 * scale, height: 18 * scale)
                    .accessibilityLabel(workspace.mode.title)

                Text(spaceAbbreviation(of: workspace.name))
                    .font(.system(size: 19 * scale, weight: .bold, design: .rounded))
                    .foregroundStyle(foreground)
                    .padding(.horizontal, 8 * scale)
                    .padding(.vertical, 3 * scale)
                    .background(foreground.opacity(0.10), in: Capsule())
            } else {
                Text(aeroSpaceAppName)
                    .font(.system(size: 15 * scale, weight: .semibold, design: .rounded))
                    .foregroundStyle(foreground)
            }
        }
        .padding(.horizontal, 9 * scale)
        .padding(.vertical, 4 * scale)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.85), in: Capsule())
        .overlay(Capsule().strokeBorder(foreground.opacity(0.12), lineWidth: 1))
    }

    private var expandedControls: some View {
        HStack(spacing: 6 * scale) {
            ForEach(WorkspaceLayoutMode.allCases, id: \.self) { mode in
                layoutModeButton(mode)
            }
            divider
            if !visibleSpaces.isEmpty {
                ForEach(visibleSpaces, id: \.name) { space in
                    spaceChip(space)
                }
                if hiddenSpacesCount > 0 {
                    overflowSpacesChip
                }
                divider
            }
            if !viewModel.focusedWorkspaceIcons.isEmpty {
                ForEach(Array(viewModel.focusedWorkspaceIcons.prefix(3).enumerated()), id: \.offset) { _, icon in
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24 * scale, height: 24 * scale)
                }
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(foreground.opacity(0.15))
            .frame(width: 1, height: 16 * scale)
            .padding(.horizontal, 2 * scale)
    }

    private func layoutModeButton(_ mode: WorkspaceLayoutMode) -> some View {
        let isCurrent = workspace?.mode == mode
        return Image(systemName: mode.icon)
            .font(.system(size: 12 * scale, weight: .semibold))
            .rotationEffect(.degrees(mode == .verticalAccordion ? 90 : 0))
            .foregroundStyle(foreground.opacity(isCurrent ? 1 : 0.65))
            .frame(width: 24 * scale, height: 22 * scale)
            .background(
                foreground.opacity(isCurrent ? 0.16 : 0.06),
                in: RoundedRectangle(cornerRadius: 6 * scale, style: .continuous),
            )
            .contentShape(Rectangle())
            .accessibilityLabel(mode.title)
            .accessibilityAddTraits(.isButton)
            .background(controlFrameReader(.layoutMode(mode)))
    }

    private func spaceChip(_ space: WorkspaceViewModel) -> some View {
        Text(spaceAbbreviation(of: space.name))
            .font(.system(size: 13 * scale, weight: .bold, design: .rounded))
            .foregroundStyle(foreground.opacity(space.isFocused ? 1 : 0.7))
            .padding(.horizontal, 6 * scale)
            .padding(.vertical, 2 * scale)
            .background(foreground.opacity(space.isFocused ? 0.16 : 0.06), in: Capsule())
            .contentShape(Rectangle())
            .accessibilityLabel(space.name)
            .accessibilityAddTraits(.isButton)
            .background(controlFrameReader(.workspace(space.name)))
    }

    private var overflowSpacesChip: some View {
        Text("+\(hiddenSpacesCount)")
            .font(.system(size: 12 * scale, weight: .semibold, design: .rounded))
            .foregroundStyle(foreground.opacity(0.7))
            .padding(.horizontal, 6 * scale)
            .padding(.vertical, 2 * scale)
            .background(foreground.opacity(0.06), in: Capsule())
            .contentShape(Rectangle())
            .accessibilityLabel(L("More spaces"))
            .accessibilityAddTraits(.isButton)
            .background(controlFrameReader(.overflowSpaces))
    }

    private func controlFrameReader(_ control: NavigatorControl) -> some View {
        GeometryReader { geometry in
            Color.clear.preference(
                key: NavigatorControlFramesKey.self,
                value: [control: geometry.frame(in: .global)],
            )
        }
    }
}

private struct NavigatorControlFramesKey: PreferenceKey {
    static let defaultValue: [NavigatorControl: CGRect] = [:]

    static func reduce(value: inout [NavigatorControl: CGRect], nextValue: () -> [NavigatorControl: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

@MainActor
private final class SpacesMenuTarget: NSObject {
    private let onSelect: (String) -> Void

    init(onSelect: @escaping (String) -> Void) {
        self.onSelect = onSelect
    }

    @objc func select(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        onSelect(name)
    }
}

private final class WindowNavigatorStatusPanel: NSPanelHud {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Lets clicks fall through to `WindowNavigatorStatusContentView`. `NSHostingView` otherwise
/// consumes mouse events even when the SwiftUI content has no gesture attached.
private final class StatusHostingView: NSHostingView<AnyView> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private final class WindowNavigatorStatusContentView: NSView {
    var onToggleExpansion: (() -> Void)?
    var onActivateControl: ((NavigatorControl) -> Void)?
    var onDragEnd: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    /// Frames of the SwiftUI controls in window (top-left origin) coordinates
    var controlFrames: [NavigatorControl: CGRect] = [:]

    /// Matches SwiftUI's top-left origin so the reported control frames can be hit-tested as is
    override var isFlipped: Bool { true }

    private var dragStartMouseLocation = NSPoint.zero
    private var dragStartWindowOrigin = NSPoint.zero
    private var isDraggingWindow = false
    private var isPressingControl = false

    override func mouseDown(with event: NSEvent) {
        guard let window = unsafe self.window else { return }
        let point = convert(event.locationInWindow, from: nil)
        if let control = controlFrames.first(where: { $0.value.contains(point) })?.key {
            isPressingControl = true
            onActivateControl?(control)
            return
        }
        isPressingControl = false
        isDraggingWindow = false
        dragStartMouseLocation = NSEvent.mouseLocation
        dragStartWindowOrigin = window.frame.origin
    }

    /// The window follows the pointer only after the pointer travels far enough. A short press
    /// stays a click and opens the navigator; moving is a separate intent.
    override func mouseDragged(with event: NSEvent) {
        guard let window = unsafe self.window else { return }
        let location = NSEvent.mouseLocation
        let delta = NSPoint(
            x: location.x - dragStartMouseLocation.x,
            y: location.y - dragStartMouseLocation.y,
        )
        if !isDraggingWindow, hypot(delta.x, delta.y) < 3 { return }
        isDraggingWindow = true
        window.setFrameOrigin(NSPoint(
            x: dragStartWindowOrigin.x + delta.x,
            y: dragStartWindowOrigin.y + delta.y,
        ))
    }

    override func mouseUp(with event: NSEvent) {
        if isPressingControl {
            isPressingControl = false
            return
        }
        if isDraggingWindow {
            isDraggingWindow = false
            onDragEnd?()
        } else {
            onToggleExpansion?()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        let settingsItem = NSMenuItem(title: L("Settings"), action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: L("Quit AirSpace"), action: #selector(quit), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func openSettings() {
        onOpenSettings?()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
