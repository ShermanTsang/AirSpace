@testable import AppBundle
import Testing

@MainActor
@Suite(.serializedGlobally)
struct WorkspaceCreationTargetTest {
    init() { setUpWorkspacesForTests() }

    @Test func testExistingWorkspaceIsNeverMoved() throws {
        defer { gcMonitors() }
        try $hasSecondaryMonitorForTests.withValue(true) {
            gcMonitors()
            let secondary = try #require(globalSortedMonitorInfos.last)
            let existing = Workspace.get(byName: "existing")
            let requested = Workspace.get(byName: "existing", createOn: secondary)
            #expect(requested === existing)
            #expect(existing.workspaceMonitorInfo.displayKey == mainMonitorInfo.displayKey)
        }
    }

    @Test func testNewWorkspaceIsCreatedOnRequestedDisplay() throws {
        defer { gcMonitors() }
        try $hasSecondaryMonitorForTests.withValue(true) {
            gcMonitors()
            let secondary = try #require(globalSortedMonitorInfos.last)
            let workspace = Workspace.get(byName: "created-on-secondary", createOn: secondary)
            #expect(workspace.workspaceMonitorInfo.displayKey == secondary.displayKey)
        }
    }

    @Test func testForceAssignmentWinsOverCreateOn() throws {
        defer {
            config.workspaceToMonitorForceAssignment = [:]
            gcMonitors()
        }
        try $hasSecondaryMonitorForTests.withValue(true) {
            gcMonitors()
            let secondary = try #require(globalSortedMonitorInfos.last)
            config.workspaceToMonitorForceAssignment = ["forced": [.main]]
            let workspace = Workspace.get(byName: "forced", createOn: secondary)
            #expect(workspace.workspaceMonitorInfo.displayKey == mainMonitorInfo.displayKey)
        }
    }
}
