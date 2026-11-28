@testable import AppBundle
import AppKit
import Testing

@MainActor
@Suite(.serializedGlobally)
struct MoveWithMouseTest {
    init() { setUpWorkspacesForTests() }

    /// A floating window whose centre is over the secondary test monitor
    private let rectOnSecondary = Rect(topLeftX: 2500, topLeftY: 300, width: 200, height: 200)

    @Test func layoutDoesNotMoveFloatingWindowThatFollowsThePointer() async throws {
        defer { gcMonitors() }
        try await $hasSecondaryMonitorForTests.withValue(true) { @MainActor in
            gcMonitors()
            let secondary = try #require(globalSortedMonitorInfos.last)
            let workspace = globalFocus.workspace
            let window = TestWindow.new(id: 1, parent: workspace.floatingWindowsContainer, rect: rectOnSecondary)
            #expect(rectOnSecondary.center.monitorApproximation.visibleWorkspace === secondary.visibleWorkspace)
            #expect(window.nodeWorkspace === workspace)

            currentlyManipulatedWithMouseWindowId = window.windowId
            defer {
                currentlyManipulatedWithMouseWindowId = nil
                currentMouseManipulation = nil
            }
            try await workspace.layoutWorkspace()
            #expect(window.setAxFrameCalls.isEmpty)

            currentlyManipulatedWithMouseWindowId = nil
            try await workspace.layoutWorkspace()
            // Without the dragged-window guard the layout would pull the window back to its workspace's monitor
            #expect(window.setAxFrameCalls.map(\.topLeft) == [Point(x: 580, y: 300)])
        }
    }

    @Test func floatingWindowBindsToTheMonitorUnderItsCentre() async throws {
        defer { gcMonitors() }
        try await $hasSecondaryMonitorForTests.withValue(true) { @MainActor in
            gcMonitors()
            let secondary = try #require(globalSortedMonitorInfos.last)
            let mainWorkspace = globalFocus.workspace
            let window = TestWindow.new(id: 2, parent: mainWorkspace.floatingWindowsContainer, rect: rectOnSecondary)

            try await window.bindFloatingWindowToMonitorUnderCenter(notifyIfLocked: false)

            #expect(window.nodeWorkspace === secondary.visibleWorkspace)
        }
    }

    @Test func floatingWindowStaysWhenItsCentreIsOnItsOwnMonitor() async throws {
        let workspace = globalFocus.workspace
        let window = TestWindow.new(
            id: 3,
            parent: workspace.floatingWindowsContainer,
            rect: Rect(topLeftX: 100, topLeftY: 100, width: 200, height: 200),
        )

        try await window.bindFloatingWindowToMonitorUnderCenter(notifyIfLocked: false)

        #expect(window.nodeWorkspace === workspace)
    }

    @Test func settlingTilingWindowFollowsThePointerAcrossMonitors() async throws {
        defer { gcMonitors() }
        try await $hasSecondaryMonitorForTests.withValue(true) { @MainActor in
            gcMonitors()
            let secondary = try #require(globalSortedMonitorInfos.last)
            let window = TestWindow.new(id: 4, parent: globalFocus.workspace.rootTilingContainer)

            placeTilingWindowWithMouse(window, at: secondary.rect.center, isSettling: true)

            #expect(window.nodeWorkspace === secondary.visibleWorkspace)
            #expect(window.parent === secondary.visibleWorkspace.rootTilingContainer)
        }
    }

    @Test func floatingWindowDoesNotTransferIntoLockedWorkspace() async throws {
        defer { gcMonitors() }
        try await $hasSecondaryMonitorForTests.withValue(true) { @MainActor in
            gcMonitors()
            let secondary = try #require(globalSortedMonitorInfos.last)
            let mainWorkspace = globalFocus.workspace
            let target = secondary.visibleWorkspace
            await WorkspaceLocks.shared.toggle(target)
            let window = TestWindow.new(id: 7, parent: mainWorkspace.floatingWindowsContainer, rect: rectOnSecondary)

            try await window.bindFloatingWindowToMonitorUnderCenter(notifyIfLocked: false)
            #expect(window.nodeWorkspace === mainWorkspace)

            await WorkspaceLocks.shared.toggle(target)
        }
    }

    @Test func settlingTilingWindowDoesNotSwapWithWindowUnderPointer() {
        let root = globalFocus.workspace.rootTilingContainer
        let dragged = TestWindow.new(id: 5, parent: root)
        let other = TestWindow.new(id: 6, parent: root)
        dragged.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 960, height: 1080)
        other.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 960, topLeftY: 0, width: 960, height: 1080)
        let pointOverOther = Point(x: 1200, y: 500)

        placeTilingWindowWithMouse(dragged, at: pointOverOther, isSettling: true)
        #expect(root.children.compactMap { ($0 as? Window)?.windowId } == [5, 6])

        placeTilingWindowWithMouse(dragged, at: pointOverOther, isSettling: false)
        #expect(root.children.compactMap { ($0 as? Window)?.windowId } == [6, 5])
    }
}
