@testable import AppBundle
import Testing

@MainActor
@Suite(.serializedGlobally)
struct WorkspaceAppFocusTest {
    init() { setUpWorkspacesForTests() }

    @Test func selectsTheClickedFloatingWindowInsteadOfTheWorkspaceFocus() {
        let workspace = Workspace.get(byName: "target")
        let floating = TestWindow.new(id: 1, parent: workspace.floatingWindowsContainer)
        let tiled = TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        _ = tiled.focusWindow()
        let app = WorkspaceApp(id: floating.app.pid, name: "App", icon: nil, windowIDs: [floating.windowId])

        #expect(workspace.mostRecentWindowRecursive == tiled)
        #expect(workspace.windowToFocus(for: app) == floating)
    }

    @Test func prefersTheRecentMatchingWindowAndIgnoresMovedOrClosedWindows() {
        let workspace = Workspace.get(byName: "target")
        let first = TestWindow.new(id: 1, parent: workspace.floatingWindowsContainer)
        let second = TestWindow.new(id: 2, parent: workspace.floatingWindowsContainer)
        _ = second.focusWindow()
        let moved = TestWindow.new(id: 3, parent: Workspace.get(byName: "other").floatingWindowsContainer)
        TestWindow.new(id: 5, parent: workspace.floatingWindowsContainer)
        let app = WorkspaceApp(id: first.app.pid, name: "App", icon: nil, windowIDs: [4, moved.windowId, first.windowId, second.windowId])

        #expect(workspace.windowToFocus(for: app) == second)
        second.unbindFromParent()
        #expect(workspace.windowToFocus(for: app) == first)
        first.unbindFromParent()
        #expect(workspace.windowToFocus(for: app) == nil)
    }
}
