import AppKit
import Common

@MainActor
private var resizeWithMouseTask: Task<(), any Error>? = nil

func resizedObs(_: AXObserver, ax: AXUIElement, notif: CFString, _: UnsafeMutableRawPointer?) {
    let notif = notif as String
    let nativeWindowId = ax.containingNativeWindowId()
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
        resizeWithMouseTask?.cancel()
        resizeWithMouseTask = Task.startUnstructured {
            try checkCancellation()
            try await runLightSession(.ax(notif), token) {
                try await resizeWithMouse(window)
            }
        }
    }
}

@MainActor
func resetManipulatedWithMouseIfPossible() async throws {
    let manipulation = currentMouseManipulation
    currentMouseManipulation = nil
    guard let windowId = currentlyManipulatedWithMouseWindowId else { return }
    defer {
        currentlyManipulatedWithMouseWindowId = nil
        for workspace in Workspace.all {
            workspace.resetResizeWeightBeforeResizeRecursive()
        }
        scheduleCancellableCompleteRefreshSession(.resetManipulatedWithMouse, optimisticallyPreLayoutWorkspaces: true)
    }
    guard manipulation == .move, let window = Window.get(byId: windowId) else { return }
    // The rebinding during the drag (moveWithMouse) can lag behind the pointer, and a lost final
    // notification would leave the window in the workspace of the display it was dragged from.
    // Settle it on the display under the pointer before the refresh lays the tree out again.
    switch window.windowParentCases {
        case .floatingWindowsContainer:
            try? await window.bindFloatingWindowToMonitorUnderCenter(notifyIfLocked: false)
        case .tilingContainer:
            placeTilingWindowWithMouse(window, at: mouseLocation, isSettling: true)
        case .macosFullscreenWindowsContainer, .macosMinimizedWindowsContainer, .macosPopupWindowsContainer,
             .macosHiddenAppsWindowsContainer, nil:
            break
    }
}

private let adaptiveWeightBeforeResizeWithMouseKey = TreeNodeUserDataKey<CGFloat>(key: "adaptiveWeightBeforeResizeWithMouseKey")

@MainActor
private func resizeWithMouse(_ window: Window) async throws { // todo cover with tests
    resetClosedWindowsCache()
    // The button may be released while the AX notification and the focus checks are still in flight.
    // Then the mouse-up handler clears the state; a stale step must not mark the window as resized.
    guard isLeftMouseButtonDown else { return }
    switch window.windowParentCases {
        case nil: return
        case .floatingWindowsContainer, .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer,
             .macosPopupWindowsContainer, .macosHiddenAppsWindowsContainer:
            return // Nothing to do for floating, or unconventional windows
        case .tilingContainer:
            // Resizing changes both size and position (e.g. when dragging the top or left edge), so the
            // same press also produces moved notifications. Latch the kind before the AX suspension
            // points so an interleaved moved notification doesn't turn the resize into a move and
            // settle the window on the display under the pointer at mouse-up.
            currentMouseManipulation = .resize
            guard let rect = try await window.getAxRect(.cancellable) else { return }
            guard let lastAppliedLayoutRect = window.lastAppliedLayoutPhysicalRect else { return }
            let (lParent, lOwnIndex, _) = window.closestParent(hasInhabitedChildrenInDirection: .left, withLayout: .tiles) ?? (nil, nil, nil)
            let (dParent, dOwnIndex, _) = window.closestParent(hasInhabitedChildrenInDirection: .down, withLayout: .tiles) ?? (nil, nil, nil)
            let (uParent, uOwnIndex, _) = window.closestParent(hasInhabitedChildrenInDirection: .up, withLayout: .tiles) ?? (nil, nil, nil)
            let (rParent, rOwnIndex, _) = window.closestParent(hasInhabitedChildrenInDirection: .right, withLayout: .tiles) ?? (nil, nil, nil)
            let table: [(CGFloat, TilingContainer?, Int?, Int?)] = [
                (lastAppliedLayoutRect.minX - rect.minX, lParent, 0,                        lOwnIndex),               // Horizontal, to the left of the window
                (rect.maxY - lastAppliedLayoutRect.maxY, dParent, dOwnIndex.map { $0 + 1 }, dParent?.children.count), // Vertical, to the down of the window
                (lastAppliedLayoutRect.minY - rect.minY, uParent, 0,                        uOwnIndex),               // Vertical, to the up of the window
                (rect.maxX - lastAppliedLayoutRect.maxX, rParent, rOwnIndex.map { $0 + 1 }, rParent?.children.count), // Horizontal, to the right of the window
            ]
            for (diff, parent, startIndex, untilIndex) in table {
                if let parent, let startIndex, let untilIndex, untilIndex - startIndex > 0 && abs(diff) > 5 { // 5 pixels should be enough to fight with accumulated floating precision error
                    let orientation = parent.orientation

                    window.parentsWithSelf.lazy
                        .prefix(while: { $0 != parent })
                        .filter {
                            let parent = $0.parent as? TilingContainer
                            return parent?.orientation == orientation && parent?.layout == .tiles
                        }
                        .forEach { $0.setWeight(orientation, $0.getWeightBeforeResize(orientation) + diff) }
                    let inhabitedSiblings = (parent.children.slice(startIndex ..< untilIndex) ?? [])
                        .filter { $0.tilingTreeNodeCasesOrDie().isInhabited }
                    guard let siblingDiff = diff.div(inhabitedSiblings.count) else { return }
                    for sibling in inhabitedSiblings {
                        sibling.setWeight(orientation, sibling.getWeightBeforeResize(orientation) - siblingDiff)
                    }
                }
            }
            currentlyManipulatedWithMouseWindowId = window.windowId
    }
}

extension TreeNode {
    @MainActor
    fileprivate func getWeightBeforeResize(_ orientation: Orientation) -> CGFloat {
        let currentWeight = getWeight(orientation) // Check assertions
        return getUserData(key: adaptiveWeightBeforeResizeWithMouseKey)
            ?? (lastAppliedLayoutVirtualRect?.getDimension(orientation) ?? currentWeight)
            .also { putUserData(key: adaptiveWeightBeforeResizeWithMouseKey, data: $0) }
    }

    fileprivate func resetResizeWeightBeforeResizeRecursive() {
        cleanUserData(key: adaptiveWeightBeforeResizeWithMouseKey)
        for child in children {
            child.resetResizeWeightBeforeResizeRecursive()
        }
    }
}
