@testable import AppBundle
import Foundation
import Testing

@MainActor
@Suite(.serializedGlobally)
struct WorkspaceLocksTest {
    init() { setUpWorkspacesForTests() }

    @Test func snapshotPersistsAndMatchesReopenedWindows() {
        let suite = "WorkspaceLocksTest.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let workspace = Workspace.get(byName: "locked")
        let first = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let second = TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        let locks = WorkspaceLocks(defaults: defaults)
        locks.capture(workspace, titles: [first.windowId: "First", second.windowId: "Second"])

        let reopened = WorkspaceLocks(defaults: defaults)
        #expect(reopened.contains("locked"))
        #expect(reopened.placement(for: first.app, title: "Second", id: 20)?.slot == 1)
        #expect(reopened.placement(for: first.app, title: "Changed", id: 21) == nil)
        #expect(reopened.placement(for: first.app, title: "First", id: 22)?.slot == 0)
    }

    @Test func restoreRebuildsSavedOrder() {
        let workspace = Workspace.get(byName: "locked")
        let root = workspace.rootTilingContainer
        let first = TestWindow.new(id: 1, parent: root)
        let second = TestWindow.new(id: 2, parent: root)
        let locks = WorkspaceLocks(defaults: nil)
        locks.capture(workspace, titles: [first.windowId: "First", second.windowId: "Second"])
        first.unbindFromParent()
        second.unbindFromParent()
        let reopenedSecond = TestWindow.new(id: 20, parent: workspace.rootTilingContainer)
        let reopenedFirst = TestWindow.new(id: 21, parent: workspace.rootTilingContainer)
        let secondPlacement = locks.placement(for: reopenedSecond.app, title: "Second", id: 20)!
        locks.restore(secondPlacement, window: reopenedSecond, in: workspace)
        let firstPlacement = locks.placement(for: reopenedFirst.app, title: "First", id: 21)!
        locks.restore(firstPlacement, window: reopenedFirst, in: workspace)
        #expect(workspace.rootTilingContainer.allLeafWindowsRecursive.map(\.windowId) == [21, 20])
    }
}
