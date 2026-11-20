import Common
import Foundation

/// Persists workspace membership separately from explicitly locked layouts.
@MainActor
final class WorkspaceRestoration {
    static let shared = WorkspaceRestoration(defaults: isUnitTest ? nil : .standard)
    private static let key = "workspace" + "Membership.v1"

    struct Entry: Codable, Equatable {
        let app: String
        let title: String
        let workspace: String
    }

    private let defaults: UserDefaults?
    private var entries: [Entry]
    private var claimed: Set<Int> = []
    private var generation = 0

    init(defaults: UserDefaults?) {
        self.defaults = defaults
        entries = defaults?.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []
    }

    static func identity(_ app: any AbstractApp) -> String? {
        if let id = app.rawAppBundleId, !id.isEmpty { return "bundle:\(id)" }
        return app.execPath.map { "exec:\($0)" }
    }

    func placement(app: String, title: String) -> String? {
        let matches = entries.indices.filter { entries[$0].app == app }
        let exact = matches.filter { !title.isEmpty && entries[$0].title == title }
        // A single app entry may only be reused when the title cannot distinguish windows. Otherwise a
        // newly opened window with a different title would be restored into the old workspace.
        let candidates = exact.isEmpty && matches.count == 1 && (title.isEmpty || entries[matches[0]].title.isEmpty)
            ? matches
            : exact
        // Identical titles across workspaces cannot be assigned safely.
        guard let first = candidates.first, candidates.allSatisfy({ entries[$0].workspace == entries[first].workspace }),
              let free = candidates.first(where: { !claimed.contains($0) }) else { return nil }
        claimed.insert(free)
        return entries[free].workspace
    }

    func capture() async {
        guard config.restoreWindowWorkspaces, !isStartup else { return }
        generation += 1
        let current = generation
        let windows = MacWindow.allWindows.filter { $0.membershipWorkspace != nil }
        let memberships = Dictionary(uniqueKeysWithValues: windows.compactMap { window in
            window.membershipWorkspace.map { (window.windowId, $0.name) }
        })
        var snapshot: [Entry] = []
        for window in windows {
            guard let app = Self.identity(window.app), let workspace = window.membershipWorkspace?.name else { continue }
            // A single unreadable window must not prevent saving every other window.
            guard let title = try? await window.getTitle(.nonCancellable) else { continue }
            guard MacWindow.allWindowsMap[window.windowId] === window, window.membershipWorkspace?.name == workspace else { return }
            snapshot.append(Entry(app: app, title: title, workspace: workspace))
        }
        let latest = Dictionary(uniqueKeysWithValues: MacWindow.allWindows.compactMap { window in
            window.membershipWorkspace.map { (window.windowId, $0.name) }
        })
        guard current == generation, config.restoreWindowWorkspaces, memberships == latest else { return }
        entries = snapshot
        claimed.removeAll()
        if let data = try? JSONEncoder().encode(snapshot) { defaults?.set(data, forKey: Self.key) }
    }
}
