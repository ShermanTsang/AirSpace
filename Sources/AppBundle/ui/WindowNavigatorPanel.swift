import AppKit
import Combine
import Common
import SwiftUI

/// Keeps a compact spaces/windows status item visible outside the menu bar.
///
/// The status item is a small floating panel that mirrors `MenuBarLabel`. Clicking it opens
/// the full navigator in a popover. The panel never participates in tiling: AirSpace ignores
/// windows of its own process (see `MacApp.getOrRegister`), and the panel deliberately has no
/// `Window` counterpart.
@MainActor
final class WindowNavigatorPanelController {
    static let shared = WindowNavigatorPanelController()

    private static let freeOriginDefaultsKey = "airspace.windowNavigator.freeOrigin"

    private let statusPadding: CGFloat = 4
    private let screenMargin: CGFloat = 12
    private let menuSize = NSSize(width: 520, height: 600)

    private var statusPanel: WindowNavigatorStatusPanel?
    private var statusHostingView: NSHostingView<AnyView>?
    private var popover: NSPopover?
    private var lastPosition: WindowNavigatorPosition?
    private var configReloadSubscription: AnyCancellable?
    private var modelSubscriptions: Set<AnyCancellable> = []
    private var observers: [NSObjectProtocol] = []

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

        let model = TrayMenuModel.shared
        Publishers.MergeMany(
            model.$focusedWorkspaceIcons.map { _ in () }.eraseToAnyPublisher(),
            model.$workspaceGroups.map { _ in () }.eraseToAnyPublisher(),
            model.$compactMenuBarLabel.map { _ in () }.eraseToAnyPublisher(),
            model.$lastReloadConfigContainedWarnings.map { _ in () }.eraseToAnyPublisher(),
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] in
            MainActor.assumeIsolated {
                self?.resizeStatusPanel()
            }
        }
        .store(in: &modelSubscriptions)

        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main,
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.applyConfig()
            }
        })
    }

    private func applyConfig() {
        let navigatorConfig = config.windowNavigator
        guard navigatorConfig.enabled else {
            popover?.close()
            statusPanel?.orderOut(nil)
            lastPosition = nil
            return
        }
        let panel = statusPanel ?? makeStatusPanel()
        statusPanel = panel
        panel.isMovableByWindowBackground = navigatorConfig.position == .floating
        (panel.contentView as? WindowNavigatorStatusContentView)?.isDraggable = navigatorConfig.position == .floating
        if lastPosition != navigatorConfig.position {
            popover?.close()
            lastPosition = navigatorConfig.position
        }
        resizeStatusPanel()
        panel.orderFrontRegardless()
    }

    private func makeStatusPanel() -> WindowNavigatorStatusPanel {
        let panel = WindowNavigatorStatusPanel()
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false

        let content = WindowNavigatorStatusView()
            .environmentObject(TrayMenuModel.shared)
            .padding(statusPadding)
        let hostingView = StatusHostingView(rootView: AnyView(content))
        hostingView.autoresizingMask = [.width, .height]
        hostingView.frame = NSRect(origin: .zero, size: NSSize(width: 120, height: 46))

        let container = WindowNavigatorStatusContentView(frame: hostingView.frame)
        container.addSubview(hostingView)
        container.onTap = { [weak self] in
            self?.togglePopover()
        }
        container.onOpenSettings = {
            openSettingsWindow()
        }
        panel.contentView = container
        panel.setContentSize(hostingView.frame.size)
        statusHostingView = hostingView

        observers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main,
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.persistFreeOriginIfNeeded()
            }
        })
        return panel
    }

    private func resizeStatusPanel() {
        guard let panel = statusPanel, let hostingView = statusHostingView else { return }
        let fitting = hostingView.fittingSize
        let size = NSSize(width: max(fitting.width, 64), height: max(fitting.height, 40))
        if panel.frame.size != size {
            panel.setContentSize(size)
        }
        let frame = frame(for: config.windowNavigator.position, size: size)
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
        }
    }

    private func togglePopover() {
        if let popover, popover.isShown {
            popover.close()
            return
        }
        guard let statusPanel, let contentView = statusPanel.contentView else { return }
        let popover = self.popover ?? makePopover()
        self.popover = popover
        let edge: NSRectEdge = switch config.windowNavigator.position {
            case .dockLeft: .maxX
            case .dockRight: .minX
            case .floating: .maxY
        }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: contentView.bounds, of: contentView, preferredEdge: edge)
    }

    private func makePopover() -> NSPopover {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = menuSize
        let content = WorkspaceMenu(viewModel: TrayMenuModel.shared, presentation: .panel)
            .frame(width: menuSize.width, height: menuSize.height)
        popover.contentViewController = NSHostingController(rootView: content)
        return popover
    }

    private func frame(for position: WindowNavigatorPosition, size: NSSize) -> NSRect {
        guard let screen = targetScreen(for: position) else {
            return NSRect(origin: .zero, size: size)
        }
        let visible = screen.visibleFrame
        switch position {
            case .floating:
                var origin = loadFreeOrigin()
                    ?? NSPoint(x: visible.maxX - size.width - screenMargin, y: visible.maxY - size.height - screenMargin)
                origin.x = min(max(origin.x, visible.minX + screenMargin), visible.maxX - size.width - screenMargin)
                origin.y = min(max(origin.y, visible.minY + screenMargin), visible.maxY - size.height - screenMargin)
                return NSRect(origin: origin, size: size)
            case .dockLeft:
                return NSRect(
                    x: visible.minX + screenMargin,
                    y: visible.minY + screenMargin,
                    width: size.width,
                    height: size.height,
                )
            case .dockRight:
                return NSRect(
                    x: visible.maxX - size.width - screenMargin,
                    y: visible.minY + screenMargin,
                    width: size.width,
                    height: size.height,
                )
        }
    }

    private func targetScreen(for position: WindowNavigatorPosition) -> NSScreen? {
        let screens = NSScreen.screens
        guard position == .floating, let origin = loadFreeOrigin() else { return screens.first }
        return screens.first { $0.frame.contains(origin) } ?? screens.first
    }

    private func persistFreeOriginIfNeeded() {
        guard config.windowNavigator.position == .floating, let statusPanel else { return }
        UserDefaults.standard.set(NSStringFromPoint(statusPanel.frame.origin), forKey: Self.freeOriginDefaultsKey)
    }

    private func loadFreeOrigin() -> NSPoint? {
        guard let origin = UserDefaults.standard.string(forKey: Self.freeOriginDefaultsKey) else { return nil }
        return NSPointFromString(origin)
    }
}

@MainActor
private struct WindowNavigatorStatusView: View {
    var body: some View {
        MenuBarLabel()
            .padding(3)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
            .shadow(color: .black.opacity(0.20), radius: 8, y: 3)
            .fixedSize()
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
    var onTap: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var isDraggable = true

    override func mouseDown(with event: NSEvent) {
        guard let window = unsafe self.window else { return }
        guard isDraggable else {
            onTap?()
            return
        }
        let initialOrigin = window.frame.origin
        window.performDrag(with: event)
        if window.frame.origin == initialOrigin {
            onTap?()
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
