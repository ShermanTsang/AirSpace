@testable import AppBundle
import Foundation
import Testing

@MainActor
@Suite(.serializedGlobally)
struct WorkspaceRestorationTest {
    @Test func restoresDistinctTitlesAndRejectsAmbiguousWindows() throws {
        let suite = "WorkspaceRestorationTest.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let entries = [
            WorkspaceRestoration.Entry(app: "app", title: "One", workspace: "1"),
            WorkspaceRestoration.Entry(app: "app", title: "Two", workspace: "2"),
            WorkspaceRestoration.Entry(app: "other", title: "Same", workspace: "1"),
            WorkspaceRestoration.Entry(app: "other", title: "Same", workspace: "2"),
        ]
        defaults.set(try JSONEncoder().encode(entries), forKey: "workspace" + "Membership.v1")
        let restored = WorkspaceRestoration(defaults: defaults)
        #expect(restored.placement(app: "app", title: "Two") == "2")
        #expect(restored.placement(app: "app", title: "Two") == nil)
        #expect(restored.placement(app: "app", title: "Changed") == nil)
        #expect(restored.placement(app: "other", title: "Same") == nil)
    }

    @Test func configDefaultsToEnabledAndCanBeDisabled() {
        #expect(Config().restoreWindowWorkspaces)
        let parsed = parseConfig("restore-window-workspaces = false")
        #expect(parsed.errors.isEmpty)
        #expect(!parsed.config.restoreWindowWorkspaces)
    }
}
