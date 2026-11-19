@testable import AppBundle
import Foundation
import Testing

struct WorkspaceDropTargetTest {
    private let listSize = CGSize(width: 500, height: 160)
    private let rows = [
        "1": CGRect(x: 0, y: -10, width: 500, height: 78),
        "2": CGRect(x: 0, y: 76, width: 500, height: 78),
        "3": CGRect(x: 0, y: 162, width: 500, height: 78),
    ]

    @Test func targetsAnotherVisibleRow() {
        #expect(target(x: 24, y: 100) == "2")
        #expect(target(x: 24, y: 5, source: "2") == "1")
    }

    @Test func ignoresSourceAndGaps() {
        #expect(target(x: 24, y: 40) == nil)
        #expect(target(x: 24, y: 70) == nil)
    }

    @Test func ignoresRowsOutsideTheScrollViewport() {
        #expect(target(x: 24, y: -5, source: "2") == nil)
        #expect(target(x: 24, y: 180) == nil)
        #expect(target(x: -1, y: 100) == nil)
    }

    private func target(x: CGFloat, y: CGFloat, source: String = "1") -> String? {
        workspaceDropTarget(source: source, location: CGPoint(x: x, y: y), listSize: listSize, rowFrames: rows)
    }
}
