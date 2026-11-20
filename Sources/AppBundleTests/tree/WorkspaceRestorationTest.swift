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

    @Test func singleEntryFallbackOnlyWhenTitleCannotIdentifyWindow() throws {
        let suite = "WorkspaceRestorationTest.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(
            try JSONEncoder().encode([WorkspaceRestoration.Entry(app: "app", title: "Old", workspace: "1")]),
            forKey: "workspace" + "Membership.v1",
        )
        let restored = WorkspaceRestoration(defaults: defaults)
        #expect(restored.placement(app: "app", title: "Brand New") == nil)
        #expect(restored.placement(app: "app", title: "") == "1")
        #expect(restored.placement(app: "app", title: "") == nil)

        let untitledSuite = suite + ".untitled"
        let untitledDefaults = UserDefaults(suiteName: untitledSuite)!
        defer { untitledDefaults.removePersistentDomain(forName: untitledSuite) }
        untitledDefaults.set(
            try JSONEncoder().encode([WorkspaceRestoration.Entry(app: "app", title: "", workspace: "2")]),
            forKey: "workspace" + "Membership.v1",
        )
        let untitled = WorkspaceRestoration(defaults: untitledDefaults)
        #expect(untitled.placement(app: "app", title: "Now Has A Title") == "2")
    }

    @Test func configDefaultsToEnabledAndCanBeDisabled() {
        #expect(Config().restoreWindowWorkspaces)
        let parsed = parseConfig("restore-window-workspaces = false")
        #expect(parsed.errors.isEmpty)
        #expect(!parsed.config.restoreWindowWorkspaces)
    }
}
