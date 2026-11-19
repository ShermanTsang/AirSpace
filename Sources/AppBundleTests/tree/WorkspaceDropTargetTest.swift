@testable import AppBundle
import Foundation
import Testing

struct WorkspaceDropTargetTest {
    private let listFrame = CGRect(x: 0, y: 50, width: 500, height: 160)
    private let frames = WorkspaceDropFrames(
        tiles: [
            "1": CGRect(x: 0, y: 40, width: 246, height: 78),
            "2": CGRect(x: 254, y: 40, width: 246, height: 78),
            "3": CGRect(x: 0, y: 126, width: 246, height: 78),
            "Z": CGRect(x: 0, y: 212, width: 246, height: 78),
        ],
        shortcuts: [
            "1": CGRect(x: 8, y: 8, width: 30, height: 24),
            "Z": CGRect(x: 42, y: 8, width: 30, height: 24),
        ],
        shortcutBar: CGRect(x: 0, y: 0, width: 500, height: 40),
    )

    @Test func targetsEitherColumn() {
        #expect(target(x: 270, y: 60) == "2")
        #expect(target(x: 24, y: 60, source: "2") == "1")
        #expect(target(x: 24, y: 150) == "3")
    }

    @Test func ignoresSourceAndGaps() {
        #expect(target(x: 24, y: 60) == nil)
        #expect(target(x: 250, y: 60) == nil)
        #expect(target(x: 24, y: 122) == nil)
    }

    @Test func ignoresTilesOutsideTheScrollViewport() {
        #expect(target(x: 270, y: 45) == nil)
        #expect(target(x: 24, y: 230) == nil)
        #expect(target(x: -1, y: 150) == nil)
    }

    @Test func targetsAnOffscreenSpaceFromTheShortcutBar() {
        #expect(target(x: 50, y: 20) == "Z")
        #expect(target(x: 24, y: 20) == nil)
    }

    @Test func floatingBarTakesPrecedenceOverTheTilesBeneathIt() {
        var floating = frames
        floating.shortcutBar = floating.shortcutBar.offsetBy(dx: 0, dy: 50)
        floating.shortcuts = floating.shortcuts.mapValues { $0.offsetBy(dx: 0, dy: 50) }
        #expect(floating.target(source: "1", location: CGPoint(x: 50, y: 70), listFrame: listFrame) == "Z")
        #expect(floating.target(source: "1", location: CGPoint(x: 270, y: 70), listFrame: listFrame) == nil)
    }

    private func target(x: CGFloat, y: CGFloat, source: String = "1") -> String? {
        frames.target(source: source, location: CGPoint(x: x, y: y), listFrame: listFrame)
    }
}
