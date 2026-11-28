import AppKit
import Common

@MainActor var currentlyManipulatedWithMouseWindowId: OpaqueWindowId? = nil

/// How the manipulated window is being changed. A move must settle the window on the display under the
/// pointer when the button is released; a resize must not move the window to another display just
/// because the pointer ended up on the edge of the screen.
enum MouseManipulation {
    case move
    case resize
}

@MainActor var currentMouseManipulation: MouseManipulation? = nil

var isLeftMouseButtonDown: Bool { NSEvent.pressedMouseButtons == 1 }

@MainActor
func isManipulatedWithMouse(_ window: Window) async throws -> Bool {
    try await (!window.isHiddenInCorner && // Don't allow to resize/move windows of hidden workspaces
        isLeftMouseButtonDown &&
        (currentlyManipulatedWithMouseWindowId == nil || window.windowId == currentlyManipulatedWithMouseWindowId))
        .andAsync { @Sendable @MainActor in try await getNativeFocusedWindow(.cancellable) == window }
}

/// Same motivation as in monitorFrameNormalized
var mouseLocation: Point { NSEvent.mouseLocation.asMyPoint.withYAxisFlipped }
