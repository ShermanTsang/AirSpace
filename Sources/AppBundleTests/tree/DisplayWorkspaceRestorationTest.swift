@testable import AppBundle
import Common
import Foundation
import Testing

@MainActor
@Suite(.serializedGlobally)
struct DisplayWorkspaceRestorationTest {
    init() { setUpWorkspacesForTests() }

    @Test func reconnectRestoresOccupiedSpaceAndVisibleSelection() throws {
        defer { gcMonitors() }
        let space = Workspace.get(byName: "external-restore")
        TestWindow.new(id: 801, parent: space.rootTilingContainer)
        try $hasSecondaryMonitorForTests.withValue(true) {
            gcMonitors()
            let external = try #require(globalSortedMonitorInfos.last)
            #expect(moveWorkspace(space, to: external, showOnDestination: true))
            DisplayWorkspaceRestoration.shared.capture()
        }
        gcMonitors()
        #expect(space.workspaceMonitorInfo.displayKey == mainMonitorInfo.displayKey)
        try $hasSecondaryMonitorForTests.withValue(true) {
            gcMonitors()
            DisplayWorkspaceRestoration.shared.restore()
            let external = try #require(globalSortedMonitorInfos.last)
            #expect(space.workspaceMonitorInfo.displayKey == external.displayKey)
            #expect(external.visibleWorkspace == space)
            let other = Workspace.get(byName: "other-visible", createOn: external)
            #expect(external.setVisibleWorkspace(other))
            DisplayWorkspaceRestoration.shared.restore()
            #expect(external.visibleWorkspace == other)
        }
    }

    @Test func savedSnapshotRestoresAfterNewInstance() throws {
        let suite = "DisplayWorkspaceRestorationTest.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); gcMonitors() }
        let space = Workspace.get(byName: "external-restart")
        TestWindow.new(id: 803, parent: space.rootTilingContainer)
        try $hasSecondaryMonitorForTests.withValue(true) {
            gcMonitors()
            let external = try #require(globalSortedMonitorInfos.last)
            #expect(moveWorkspace(space, to: external, showOnDestination: true))
            DisplayWorkspaceRestoration(defaults: defaults).capture()
        }
        gcMonitors()
        try $hasSecondaryMonitorForTests.withValue(true) {
            gcMonitors()
            let reopened = DisplayWorkspaceRestoration(defaults: defaults)
            reopened.restore()
            let external = try #require(globalSortedMonitorInfos.last)
            #expect(space.workspaceMonitorInfo.displayKey == external.displayKey)
            #expect(external.visibleWorkspace == space)
        }
    }

    @Test func explicitMoveCancelsPendingRestore() throws {
        defer { gcMonitors() }
        let space = Workspace.get(byName: "external-cancel")
        TestWindow.new(id: 802, parent: space.rootTilingContainer)
        try $hasSecondaryMonitorForTests.withValue(true) {
            gcMonitors()
            let external = try #require(globalSortedMonitorInfos.last)
            #expect(moveWorkspace(space, to: external, showOnDestination: true))
        }
        gcMonitors()
        #expect(moveWorkspace(space, to: mainMonitorInfo, showOnDestination: false))
        $hasSecondaryMonitorForTests.withValue(true) {
            gcMonitors()
            DisplayWorkspaceRestoration.shared.restore()
            #expect(space.workspaceMonitorInfo.displayKey == mainMonitorInfo.displayKey)
        }
    }
}
