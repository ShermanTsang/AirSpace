@testable import AppBundle
import Common
import Testing

@MainActor
@Suite(.serializedGlobally)
struct MoveNodeToWorkspaceCommandTest {
    init() { setUpWorkspacesForTests() }

    @Test func testParse() {
        testParseSingleCommandSucc("move-node-to-workspace next", MoveNodeToWorkspaceCmdArgs(target: .relative(.next)))
        assertEquals(parseCommand("move-node-to-workspace --fail-if-noop next").errorOrNil, "--fail-if-noop is incompatible with (next|prev)")
        assertEquals(parseCommand("move-node-to-workspace --stdin foo").errorOrNil, "--stdin and --no-stdin require using (next|prev) argument")
        testParseSingleCommandSucc("move-node-to-workspace --stdin next", MoveNodeToWorkspaceCmdArgs(target: .relative(.next)).with(\.commonState.explicitStdinFlag, true))
        testParseSingleCommandSucc("move-node-to-workspace --no-stdin next", MoveNodeToWorkspaceCmdArgs(target: .relative(.next)).with(\.commonState.explicitStdinFlag, false))
        testParseSingleCommandSucc(
            "move-node-to-workspace --create-on main foo",
            MoveNodeToWorkspaceCmdArgs(target: .direct(.parse("foo").getOrDie()), createOn: .main),
        )
        assertEquals(parseCommand("move-node-to-workspace --create-on focused next").errorOrNil, "--create-on is incompatible with (next|prev)")
        assertEquals(MoveNodeToWorkspaceCmdArgs(rawArgs: []).createOn, .focused)
    }

    @Test func testParseDoubleDash() {
        testParseSingleCommandSucc("move-node-to-workspace -- foo", MoveNodeToWorkspaceCmdArgs(workspace: "foo"))
        assertEquals(parseCommand("move-node-to-workspace -- prev").errorOrNil, "ERROR: 'prev' is a reserved workspace name")
        assertEquals(parseCommand("move-node-to-workspace --").errorOrNil, "ERROR: Argument \'(<workspace-name>|next|prev)\' is mandatory")
        testParseSingleCommandSucc(
            "move-node-to-workspace --focus-follows-window -- foo",
            MoveNodeToWorkspaceCmdArgs(workspace: "foo").with(\.focusFollowsWindow, true),
        )
    }

    @Test func testSimple() async {
        let workspaceA = Workspace.get(byName: "a")
        workspaceA.rootTilingContainer.apply {
            _ = TestWindow.new(id: 1, parent: $0).focusWindow()
        }

        await parseCommand("move-node-to-workspace b").cmdOrDie.run(.defaultEnv, .emptyStdin)
        #expect(workspaceA.isEffectivelyEmpty)
        assertEquals((Workspace.get(byName: "b").rootTilingContainer.children.singleOrNil() as? Window)?.windowId, 1)
    }

    @Test func testEmptyWorkspaceSubject() async {
        let workspaceA = Workspace.get(byName: "a")
        workspaceA.rootTilingContainer.apply {
            _ = TestWindow.new(id: 1, parent: $0).focusWindow()
        }

        await parseCommand("move-node-to-workspace b").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(globalFocus.workspace.name, "a")
    }

    @Test func testAnotherWindowSubject() async {
        Workspace.get(byName: "a").rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
            _ = TestWindow.new(id: 2, parent: $0).focusWindow()
        }

        await parseCommand("move-node-to-workspace b").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(globalFocus.windowOrNil?.windowId, 1)
    }

    @Test func testPreserveFloatingLayout() async {
        let workspaceA = Workspace.get(byName: "a").apply {
            assertTrue(TestWindow.new(id: 1, parent: $0.floatingWindowsContainer).focusWindow())
        }

        await parseCommand("move-node-to-workspace b").cmdOrDie.run(.defaultEnv, .emptyStdin)
        #expect(workspaceA.isEffectivelyEmpty)
        assertEquals((Workspace.get(byName: "b").floatingWindowsContainer.children.singleOrNil() as? Window)?.windowId, 1)
    }

    @Test func testSummonWindow() async {
        let workspaceA = Workspace.get(byName: "a").apply {
            $0.rootTilingContainer.apply {
                _ = TestWindow.new(id: 1, parent: $0).focusWindow()
            }
        }
        Workspace.get(byName: "b").rootTilingContainer.apply {
            TestWindow.new(id: 2, parent: $0)
        }

        assertEquals(globalFocus.workspace, workspaceA)

        await parseCommand("move-node-to-workspace --window-id 2 a").cmdOrDie
            .run(.defaultEnv, .emptyStdin)

        assertEquals(globalFocus.workspace, workspaceA)
        assertEquals(globalFocus.windowOrNil?.windowId, 1)
        assertEquals(Workspace.get(byName: "b").rootTilingContainer.children.count, 0)
        assertEquals(workspaceA.rootTilingContainer.children.count, 2)
    }

    @Test func testNoWindowIsFocused() async {
        let result = await parseCommand("move-node-to-workspace b").cmdOrDie
            .run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 2)
        assertEquals(result.stderr, [noWindowIsFocused])
    }

    @Test func testFailIfNoop_succWithMessage() async {
        Workspace.get(byName: "a").rootTilingContainer.apply {
            _ = TestWindow.new(id: 1, parent: $0).focusWindow()
        }

        let result = await parseCommand("move-node-to-workspace a").cmdOrDie
            .run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        assertEquals(result.stderr.count, 1)
        assertTrue(result.stderr.first?.contains("already belongs to workspace 'a'") == true)
        assertEquals(Workspace.get(byName: "a").rootTilingContainer.children.count, 1)
    }

    @Test func testFailIfNoop_fails() async {
        Workspace.get(byName: "a").rootTilingContainer.apply {
            _ = TestWindow.new(id: 1, parent: $0).focusWindow()
        }

        let result = await parseCommand("move-node-to-workspace --fail-if-noop a").cmdOrDie
            .run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 2)
        assertEquals(result.stderr, [])
        assertEquals(Workspace.get(byName: "a").rootTilingContainer.children.count, 1)
    }

    @Test func testFocusFollowsWindow() async {
        let workspaceA = Workspace.get(byName: "a")
        workspaceA.rootTilingContainer.apply {
            _ = TestWindow.new(id: 1, parent: $0).focusWindow()
        }
        assertEquals(globalFocus.workspace.name, "a")

        await parseCommand("move-node-to-workspace --focus-follows-window b").cmdOrDie
            .run(.defaultEnv, .emptyStdin)
        assertEquals(globalFocus.workspace.name, "b")
        assertEquals(globalFocus.windowOrNil?.windowId, 1)
        assertTrue(workspaceA.isEffectivelyEmpty)
    }

    @Test func testRelativeNext() async {
        Workspace.get(byName: "a").rootTilingContainer.apply {
            _ = TestWindow.new(id: 1, parent: $0).focusWindow()
        }
        // Make "b" alive so the relative target has somewhere to go
        _ = Workspace.get(byName: "b").rootTilingContainer

        await parseCommand("move-node-to-workspace next").cmdOrDie
            .run(.defaultEnv, .emptyStdin)

        assertTrue(Workspace.get(byName: "a").isEffectivelyEmpty)
        assertEquals((Workspace.get(byName: "b").rootTilingContainer.children.singleOrNil() as? Window)?.windowId, 1)
    }

    @Test func testRelativeNoNextWorkspace_failsToResolve() async {
        // "a" is the only alive workspace besides the focused one. Calling `prev` from the first workspace without
        // wrap-around has nowhere to go.
        Workspace.get(byName: "a").rootTilingContainer.apply {
            _ = TestWindow.new(id: 1, parent: $0).focusWindow()
        }

        let result = await parseCommand("move-node-to-workspace prev").cmdOrDie
            .run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 2)
        assertEquals(result.stderr, ["Rached the beginning of the supplied workspaces list"])
        // Window untouched
        assertEquals((Workspace.get(byName: "a").rootTilingContainer.children.singleOrNil() as? Window)?.windowId, 1)
    }

    @Test func testRelativeWrapAround() async {
        Workspace.get(byName: "a").rootTilingContainer.apply {
            _ = TestWindow.new(id: 1, parent: $0).focusWindow()
        }

        // Stdin-controlled list keeps the wrap behavior independent of which workspaces happen to be alive.
        await parseCommand("move-node-to-workspace --wrap-around --stdin prev").cmdOrDie
            .run(.defaultEnv, CmdStdin("a\nb\n"))

        assertTrue(Workspace.get(byName: "a").isEffectivelyEmpty)
        assertEquals((Workspace.get(byName: "b").rootTilingContainer.children.singleOrNil() as? Window)?.windowId, 1)
    }

    @Test func testRelativeStdin() async {
        Workspace.get(byName: "a").rootTilingContainer.apply {
            _ = TestWindow.new(id: 1, parent: $0).focusWindow()
        }

        // Workspaces listed via stdin: focus is "a", next should be the workspace listed after it.
        await parseCommand("move-node-to-workspace --stdin next").cmdOrDie
            .run(.defaultEnv, CmdStdin("a\nx\ny\n"))

        assertTrue(Workspace.get(byName: "a").isEffectivelyEmpty)
        assertEquals((Workspace.get(byName: "x").rootTilingContainer.children.singleOrNil() as? Window)?.windowId, 1)
    }

    @Test func testEmptyWorkspaceFollowsFocusedWindowMonitor() async throws {
        defer { gcMonitors() }
        try await $hasSecondaryMonitorForTests.withValue(true) {
            gcMonitors()
            let secondary = try #require(globalSortedMonitorInfos.last)
            let source = Workspace.get(byName: "source")
            source.rootTilingContainer.apply {
                _ = TestWindow.new(id: 601, parent: $0).focusWindow()
            }
            let empty = Workspace.get(byName: "empty", createOn: secondary)
            #expect(empty.workspaceMonitorInfo.displayKey == secondary.displayKey)

            await parseCommand("move-node-to-workspace empty").cmdOrDie
                .run(.defaultEnv, .emptyStdin)

            #expect(empty.workspaceMonitorInfo.displayKey == mainMonitorInfo.displayKey)
            #expect(empty.rootTilingContainer.children.contains { ($0 as? Window)?.windowId == 601 })
            #expect(source.isEffectivelyEmpty)
        }
    }

    @Test func testOccupiedWorkspaceKeepsItsMonitor() async throws {
        defer { gcMonitors() }
        try await $hasSecondaryMonitorForTests.withValue(true) {
            gcMonitors()
            let secondary = try #require(globalSortedMonitorInfos.last)
            let occupied = Workspace.get(byName: "occupied", createOn: secondary)
            TestWindow.new(id: 602, parent: occupied.rootTilingContainer)
            let source = Workspace.get(byName: "source")
            source.rootTilingContainer.apply {
                _ = TestWindow.new(id: 603, parent: $0).focusWindow()
            }

            await parseCommand("move-node-to-workspace occupied").cmdOrDie
                .run(.defaultEnv, .emptyStdin)

            #expect(occupied.workspaceMonitorInfo.displayKey == secondary.displayKey)
            #expect(occupied.rootTilingContainer.children.count == 2)
            #expect(occupied.rootTilingContainer.children.contains { ($0 as? Window)?.windowId == 603 })
        }
    }

    @Test func testCreateOnMainRehomesEmptyWorkspace() async throws {
        defer { gcMonitors() }
        try await $hasSecondaryMonitorForTests.withValue(true) {
            gcMonitors()
            let secondary = try #require(globalSortedMonitorInfos.last)
            let source = Workspace.get(byName: "source", createOn: secondary)
            source.rootTilingContainer.apply {
                _ = TestWindow.new(id: 604, parent: $0).focusWindow()
            }
            let empty = Workspace.get(byName: "empty", createOn: secondary)
            #expect(empty.workspaceMonitorInfo.displayKey == secondary.displayKey)

            await parseCommand("move-node-to-workspace --create-on main empty").cmdOrDie
                .run(.defaultEnv, .emptyStdin)

            #expect(empty.workspaceMonitorInfo.displayKey == mainMonitorInfo.displayKey)
            #expect(empty.rootTilingContainer.children.contains { ($0 as? Window)?.windowId == 604 })
        }
    }

    @Test func testVisibleWorkspaceKeepsItsMonitor() async throws {
        defer { gcMonitors() }
        try await $hasSecondaryMonitorForTests.withValue(true) {
            gcMonitors()
            let secondary = try #require(globalSortedMonitorInfos.last)
            let source = Workspace.get(byName: "source")
            source.rootTilingContainer.apply {
                _ = TestWindow.new(id: 605, parent: $0).focusWindow()
            }
            let visibleOnSecondary = secondary.visibleWorkspace
            #expect(visibleOnSecondary.isEffectivelyEmpty)
            #expect(visibleOnSecondary.workspaceMonitorInfo.displayKey == secondary.displayKey)

            await parseCommand("move-node-to-workspace \(visibleOnSecondary.name)").cmdOrDie
                .run(.defaultEnv, .emptyStdin)

            #expect(visibleOnSecondary.workspaceMonitorInfo.displayKey == secondary.displayKey)
            #expect(visibleOnSecondary.rootTilingContainer.children.contains { ($0 as? Window)?.windowId == 605 })
        }
    }

    @Test func testForceAssignedEmptyWorkspaceKeepsItsMonitor() async throws {
        defer {
            config.workspaceToMonitorForceAssignment = [:]
            gcMonitors()
        }
        try await $hasSecondaryMonitorForTests.withValue(true) {
            gcMonitors()
            let secondary = try #require(globalSortedMonitorInfos.last)
            config.workspaceToMonitorForceAssignment = ["pinned": [.secondary]]
            let pinned = Workspace.get(byName: "pinned")
            #expect(pinned.workspaceMonitorInfo.displayKey == secondary.displayKey)
            let source = Workspace.get(byName: "source")
            source.rootTilingContainer.apply {
                _ = TestWindow.new(id: 606, parent: $0).focusWindow()
            }

            await parseCommand("move-node-to-workspace pinned").cmdOrDie
                .run(.defaultEnv, .emptyStdin)

            #expect(pinned.workspaceMonitorInfo.displayKey == secondary.displayKey)
            #expect(pinned.rootTilingContainer.children.contains { ($0 as? Window)?.windowId == 606 })
        }
    }

    @Test func testLockedTransferDoesNotRehomeTarget() async throws {
        defer { gcMonitors() }
        try await $hasSecondaryMonitorForTests.withValue(true) {
            gcMonitors()
            let secondary = try #require(globalSortedMonitorInfos.last)
            let source = Workspace.get(byName: "source")
            source.rootTilingContainer.apply {
                _ = TestWindow.new(id: 607, parent: $0).focusWindow()
            }
            let lockedTarget = Workspace.get(byName: "locked-target", createOn: secondary)
            await WorkspaceLocks.shared.toggle(lockedTarget)
            #expect(lockedTarget.isLocked)

            let result = await parseCommand("move-node-to-workspace locked-target").cmdOrDie
                .run(.defaultEnv, .emptyStdin)

            #expect(result.exitCode.rawValue == 2)
            #expect(lockedTarget.workspaceMonitorInfo.displayKey == secondary.displayKey)
            #expect(lockedTarget.isEffectivelyEmpty)
            #expect(source.rootTilingContainer.children.contains { ($0 as? Window)?.windowId == 607 })
            await WorkspaceLocks.shared.toggle(lockedTarget)
        }
    }
}
