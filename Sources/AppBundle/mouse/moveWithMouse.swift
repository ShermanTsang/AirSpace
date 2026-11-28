import AppKit
import Common

@MainActor
private var moveWithMouseTask: Task<(), any Error>? = nil

func movedObs(_: AXObserver, ax: AXUIElement, notif: CFString, _: UnsafeMutableRawPointer?) {
    let nativeWindowId = ax.containingNativeWindowId()
    let notif = notif as String
    let pid = ax.pid
    Task.startUnstructured { @MainActor in
        guard let token: RunSessionGuard = .isServerEnabled else { return }
        guard let nativeWindowId,
              let pid,
              let window = Window.get(byNativeId: nativeWindowId, pid: pid),
              try await isManipulatedWithMouse(window)
        else {
            scheduleCancellableCompleteRefreshSession(.ax(notif))
            return
        }
        moveWithMouseTask?.cancel()
        moveWithMouseTask = Task.startUnstructured {
            try checkCancellation()
            try await runLightSession(.ax(notif), token) {
                try await moveWithMouse(window)
            }
        }
    }
}

@MainActor
private func moveWithMouse(_ window: Window) async throws { // todo cover with tests
    resetClosedWindowsCache()
    // The button may be released while the AX notification and the focus checks are still in flight.
    // Then the mouse-up handler settles the window; a stale step must not restart the drag.
    guard isLeftMouseButtonDown else { return }
    // A resize moves the window as well (top/left edges), and those moved notifications must not be
    // treated as dragging. Otherwise mouse-up would settle a resized window on another display.
    guard currentMouseManipulation != .resize else { return }
    switch window.windowParentCases {
        case .floatingWindowsContainer:
            try await moveFloatingWindow(window)
        case .macosFullscreenWindowsContainer, .macosMinimizedWindowsContainer, .macosPopupWindowsContainer, .macosHiddenAppsWindowsContainer:
            return // Unconventional windows can't be moved with mouse
        case .tilingContainer:
            moveTilingWindow(window)
        case nil: return
    }
}

@MainActor
private func moveFloatingWindow(_ window: Window) async throws {
    // Keep the window out of layout until the button is released (resetManipulatedWithMouseIfPossible).
    // Otherwise a layout pass that runs after the centre crossed onto another monitor, but before the
    // rebinding below, pulls the window back onto its workspace's monitor, and macOS carries the drag on
    // from the wrong position. https://github.com/nikitabobko/AeroSpace/issues/347
    currentlyManipulatedWithMouseWindowId = window.windowId
    currentMouseManipulation = .move
    try await window.bindFloatingWindowToMonitorUnderCenter()
}

extension Window {
    /// Binds a floating window to the visible workspace of the monitor its centre is on
    @MainActor
    func bindFloatingWindowToMonitorUnderCenter(notifyIfLocked: Bool = true) async throws {
        guard let targetWorkspace = try await getCenter(.cancellable)?.monitorApproximation.visibleWorkspace else { return }
        guard targetWorkspace != nodeWorkspace else { return }
        if let locked = lockedWorkspaceForTransfer(self, to: targetWorkspace) {
            if notifyIfLocked { showWorkspaceLocked(locked) }
            return
        }
        bindAsFloatingWindow(to: targetWorkspace)
    }
}

@MainActor
private func moveTilingWindow(_ window: Window) {
    currentlyManipulatedWithMouseWindowId = window.windowId
    currentMouseManipulation = .move
    window.lastAppliedLayoutPhysicalRect = nil
    placeTilingWindowWithMouse(window, at: mouseLocation, isSettling: false)
}

/// Rebinds the window to the workspace under the pointer. Used both while dragging with the mouse and
/// once when the button is released, so a lost final `kAXMovedNotification` cannot send the window back
/// to the display it was dragged from.
@MainActor
func placeTilingWindowWithMouse(_ window: Window, at point: Point, isSettling: Bool) {
    let targetWorkspace = point.monitorApproximation.visibleWorkspace
    if targetWorkspace == window.nodeWorkspace {
        // Swapping while settling would reorder windows just because the pointer happened to rest over
        // another window when the drag ended.
        guard !isSettling, let swapTarget = findSwapTarget(for: window, at: point, in: targetWorkspace) else { return }
        swapWindows(mruDominant: window, swapTarget)
        return
    }
    if let locked = lockedWorkspaceForTransfer(window, to: targetWorkspace) {
        // The locked message was already shown while dragging. Don't show it again on release.
        if !isSettling { showWorkspaceLocked(locked) }
        return
    }
    let parent: TilingContainer
    let index: Int
    if let swapTarget = findSwapTarget(for: window, at: point, in: targetWorkspace),
       let (_parent, _index) = swapTarget.nearestAliveTilingParent(),
       let targetRect = swapTarget.lastAppliedLayoutPhysicalRect
    {
        parent = _parent
        index = point.getProjection(_parent.orientation) >= targetRect.center.getProjection(_parent.orientation)
            ? _index + 1
            : _index
    } else {
        parent = targetWorkspace.rootTilingContainer
        index = 0
    }
    window.bind(to: parent, adaptiveWeight: WEIGHT_AUTO, index: index)
}

@MainActor
private func findSwapTarget(for window: Window, at point: Point, in workspace: Workspace) -> Window? {
    point.findWindowRecursively(in: workspace.rootTilingContainer, virtual: false, fullscreenCoversAll: false)?
        .takeIf { $0 != window }
}

@MainActor
func swapWindows(mruDominant window1: Window, _ window2: Window) {
    if window1 == window2 { return }

    let binding2 = window2.unbindFromParent()
    let binding1 = window1.unbindFromParent()

    window2.bind(to: binding1.parent, adaptiveWeight: binding1.adaptiveWeight, index: binding1.index)
    window1.bind(to: binding2.parent, adaptiveWeight: binding2.adaptiveWeight, index: binding2.index)
}

extension Point {
    @MainActor
    func findWindowRecursively(
        in tree: TilingContainer,
        virtual: Bool,
        fullscreenCoversAll: Bool,
    ) -> Window? {
        if fullscreenCoversAll {
            if let window = tree.mostRecentWindowRecursive, window.isFullscreen {
                return window
            }
        }
        return _findWindowRecursively(in: tree, virtual: virtual)
    }

    @MainActor
    private func _findWindowRecursively(in tree: TilingContainer, virtual: Bool) -> Window? {
        let point = self
        let target: TreeNode? = switch tree.layout {
            case .tiles:
                tree.inhabitedChildren.first(where: {
                    (virtual ? $0.lastAppliedLayoutVirtualRect : $0.lastAppliedLayoutPhysicalRect)?.contains(point) == true
                })
            case .accordion:
                tree.mostRecentInhabitedChild
        }
        guard let target else { return nil }
        return switch target.tilingTreeNodeCasesOrDie() {
            case .window(let window): window
            case .tilingContainer(let container): _findWindowRecursively(in: container, virtual: virtual)
        }
    }
}
