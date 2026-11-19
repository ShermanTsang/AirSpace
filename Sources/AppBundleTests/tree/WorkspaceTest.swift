@testable import AppBundle
import Testing

@MainActor
@Suite(.serializedGlobally)
struct WorkspaceTest {
    init() { setUpWorkspacesForTests() }

    @Test func testGarbageCollectedWorkspaceIsUnbound() {
        let garbage = Workspace.get(byName: "a")
        Workspace.garbageCollectUnusedWorkspaces()
        #expect(garbage.parent == nil)
        #expect(Workspace.get(byName: "a") !== garbage)
    }

    @Test func testGarbageCollectAndForceAssignDontDuplicateWorkspaces() {
        config.workspaceToMonitorForceAssignment = ["a": [.main]]
        for _ in 1 ... 3 {
            Workspace.garbageCollectUnusedWorkspaces()
            Workspace.forceAssignWorkspaces()
        }
        let container = mainMonitorInfo.toMonitorOrRearrangeMonitors().getWorkspacesContainerOrCreate()
        #expect(container.children.filterIsInstance(of: Workspace.self).count { $0.name == "a" } == 1)
    }

    @Test func testTrayGroupKeepsFocusedOccupiedAndLockedSpacesOutOfIdleSection() async throws {
        let focused = globalFocus.workspace
        let idle = Workspace.get(byName: "idle")
        let occupied = Workspace.get(byName: "occupied")
        let locked = Workspace.get(byName: "locked")
        TestWindow.new(id: 42, parent: occupied.rootTilingContainer)
        await WorkspaceLocks.shared.toggle(locked)
        updateTrayText()
        let groups = TrayMenuModel.shared.workspaceGroups
        await WorkspaceLocks.shared.toggle(locked)

        let group = try #require(groups.singleOrNil())
        #expect(group.display.number == 1)
        #expect(group.display.id == WorkspaceDisplay.ID(mainMonitorInfo))
        #expect(group.workspaces.map(\.name) == [idle.name, locked.name, occupied.name, focused.name])
        #expect(group.workspaces.filter(\.isIdle).map(\.name) == [idle.name])
        #expect(group.workspaces.filter(\.isFocused).map(\.name) == [focused.name])
    }

    @Test func testTrayGroupsTrackSpaceMovesAndDisplayRemoval() throws {
        let assignments = config.workspaceToMonitorForceAssignment
        defer {
            config.workspaceToMonitorForceAssignment = assignments
            gcMonitors()
            _ = mainMonitorInfo.setVisibleWorkspace(globalFocus.workspace)
        }
        try $hasSecondaryMonitorForTests.withValue(true) {
            gcMonitors()
            let secondary = try #require(globalSortedMonitorInfos.last)
            let mainSpace = globalFocus.workspace
            let externalSpace = secondary.visibleWorkspace
            let hidden = Workspace.get(byName: "hidden")
            TestWindow.new(id: 42, parent: hidden.rootTilingContainer)

            #expect(moveWorkspace(hidden, to: secondary, showOnDestination: false))
            #expect(secondary.visibleWorkspace == externalSpace)
            #expect(mainMonitorInfo.visibleWorkspace == mainSpace)
            #expect(!hidden.isVisible)
            updateTrayText()
            #expect(TrayMenuModel.shared.workspaceGroups.map { $0.workspaces.map(\.name) } == [
                [mainSpace.name], [externalSpace, hidden].sorted().map(\.name),
            ])

            #expect(moveWorkspace(externalSpace, to: mainMonitorInfo, showOnDestination: false))
            #expect(mainMonitorInfo.visibleWorkspace == mainSpace)
            #expect(globalFocus.workspace == mainSpace)
            #expect(secondary.visibleWorkspace == hidden)
            #expect(!externalSpace.isVisible)

            #expect(moveWorkspace(mainSpace, to: secondary, showOnDestination: true))
            #expect(globalFocus.workspace == mainSpace)
            #expect(secondary.visibleWorkspace == mainSpace)
            #expect(mainMonitorInfo.visibleWorkspace != mainSpace)
            #expect(mainMonitorInfo.visibleWorkspace.isVisible)

            config.workspaceToMonitorForceAssignment = [mainSpace.name: [.secondary]]
            #expect(!moveWorkspace(mainSpace, to: mainMonitorInfo, showOnDestination: true))
            #expect(secondary.visibleWorkspace == mainSpace)
        }
        gcMonitors()
        updateTrayText()
        #expect(TrayMenuModel.shared.workspaceGroups.count == 1)
        #expect(TrayMenuModel.shared.workspaces.contains { $0.name == "hidden" && !$0.isIdle })
    }

    @Test func testMovingEmptyNumericSpaceDoesNotReuseItAsSourceFallback() throws {
        defer { gcMonitors() }
        try $hasSecondaryMonitorForTests.withValue(true) {
            gcMonitors()
            let secondary = try #require(globalSortedMonitorInfos.last)
            let focused = globalFocus.workspace
            let empty = secondary.visibleWorkspace
            #expect(empty.name == "1")
            #expect(moveWorkspace(empty, to: mainMonitorInfo, showOnDestination: false))
            #expect(empty.workspaceMonitorInfo.isMain)
            #expect(mainMonitorInfo.visibleWorkspace == focused)
            #expect(secondary.visibleWorkspace != empty)
        }
    }

    @Test func testUpdateTrayTextAfterGarbageCollection() {
        _ = Workspace.get(byName: "a")
        Workspace.garbageCollectUnusedWorkspaces()
        #expect(Workspace.get(byName: "a").focusWorkspace())
        updateTrayText()
        #expect(mainMonitorInfo.visibleWorkspace === globalFocus.workspace)
    }
}
