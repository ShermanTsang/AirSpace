@testable import AppBundle
import AppKit
import Common
import Testing

@MainActor
struct MonitorTest {
    private struct MockMonitorInfo: MonitorInfo {
        var monitorAppKitNsScreenScreensId = 1
        var name = "Test Monitor"
        var displayKey: String? = "test-display"
        var rect: Rect
        var visibleRect: Rect
        var isMain = true
        var width: CGFloat { rect.width }
        var height: CGFloat { rect.height }
    }

    private var fullRect: Rect {
        Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080)
    }

    @Test func cachedMonitorInfoIsStaleWhenVisibleRectChanges() {
        let cached = MockMonitorInfo(rect: fullRect, visibleRect: fullRect)
        #expect(monitorInfoMatches(cached, cached))

        // Dock moved to the bottom: same display, same resolution, smaller visible area.
        let docked = MockMonitorInfo(
            rect: fullRect,
            visibleRect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1000),
        )
        #expect(!monitorInfoMatches(cached, docked))
    }

    @Test func cachedMonitorInfoIsStaleWhenDisplayMoves() {
        let cached = MockMonitorInfo(rect: fullRect, visibleRect: fullRect)
        let moved = MockMonitorInfo(
            rect: Rect(topLeftX: -1920, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: -1920, topLeftY: 0, width: 1920, height: 1080),
        )
        #expect(!monitorInfoMatches(cached, moved))
    }
}
