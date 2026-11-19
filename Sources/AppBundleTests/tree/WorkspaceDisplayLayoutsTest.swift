@testable import AppBundle
import Common
import Foundation
import Testing

@MainActor
@Suite(.serializedGlobally)
struct WorkspaceDisplayLayoutsTest {
    init() { setUpWorkspacesForTests() }

    @Test func appliesRememberedLayoutAndRestoresDefault() {
        let layouts = WorkspaceDisplayLayouts(defaults: nil)
        let workspace = Workspace.get(byName: "display-layout")
        let monitor = workspace.workspaceMonitorInfo
        let root = workspace.rootTilingContainer
        layouts.remember(.verticalAccordion, workspace: workspace.name, display: monitor.displayKey)
        layouts.apply(to: workspace, on: monitor)
        #expect(root.layout == .accordion)
        #expect(root.orientation == .v)
        layouts.forget(workspace: workspace.name, display: monitor.displayKey)
        layouts.apply(to: workspace, on: monitor)
        #expect(root.layout == config.defaultRootContainerLayout)
        let expected: Orientation = switch config.defaultRootContainerOrientation {
            case .horizontal: .h
            case .vertical: .v
            case .auto: monitor.width >= monitor.height ? .h : .v
        }
        #expect(root.orientation == expected)
    }

    @Test func lockedLayoutTakesPrecedence() async {
        let workspace = Workspace.get(byName: "display-locked")
        let root = workspace.rootTilingContainer
        root.layout = .tiles
        root.changeOrientation(.h)
        await WorkspaceLocks.shared.toggle(workspace)
        let layouts = WorkspaceDisplayLayouts(defaults: nil)
        layouts.remember(.verticalAccordion, workspace: workspace.name, display: workspace.workspaceMonitorInfo.displayKey)
        layouts.apply(to: workspace, on: workspace.workspaceMonitorInfo)
        #expect(root.layout == .tiles)
        #expect(root.orientation == .h)
        await WorkspaceLocks.shared.toggle(workspace)
    }

    @Test func remembersPerWorkspaceAndDisplayAcrossRestarts() {
        let suite = "WorkspaceDisplayLayoutsTest.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let layouts = WorkspaceDisplayLayouts(defaults: defaults)
        layouts.remember(.horizontalTiles, workspace: "1", display: "external")
        layouts.remember(.verticalAccordion, workspace: "1", display: "internal")
        layouts.remember(.verticalTiles, workspace: "2", display: "external")
        layouts.remember(.horizontalAccordion, workspace: "2", display: nil)

        let reopened = WorkspaceDisplayLayouts(defaults: defaults)
        #expect(reopened.remembered(workspace: "1", display: "external") == .horizontalTiles)
        #expect(reopened.remembered(workspace: "1", display: "internal") == .verticalAccordion)
        #expect(reopened.remembered(workspace: "2", display: "external") == .verticalTiles)
        #expect(reopened.remembered(workspace: "2", display: nil) == nil)
        reopened.forget(workspace: "1", display: "external")
        let afterReset = WorkspaceDisplayLayouts(defaults: defaults)
        #expect(afterReset.remembered(workspace: "1", display: "external") == nil)
        #expect(afterReset.remembered(workspace: "1", display: "internal") == .verticalAccordion)
    }
}
