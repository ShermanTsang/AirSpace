import Foundation
import Common

/// Remembers occupied spaces and the visible space for each physical display.
@MainActor
final class DisplayWorkspaceRestoration {
    static let shared = DisplayWorkspaceRestoration(defaults: isUnitTest ? nil : .standard)
    private static let key = "displayWorkspaceRestoration.v1"

    struct Snapshot: Codable {
        var workspaces: [String]
        var visible: String?
    }

    private let defaults: UserDefaults?
    private var snapshots: [String: Snapshot]
    private var pending: Set<String>

    init(defaults: UserDefaults?) {
        self.defaults = defaults
        let saved = defaults?.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([String: Snapshot].self, from: $0) } ?? [:]
        snapshots = saved
        pending = Set(saved.keys)
    }

    func disconnect(_ monitor: Monitor) {
        guard config.restoreDisplayWorkspaces, let key = monitor.info.displayKey else { return }
        guard let container = monitor.children.compactMap({ $0 as? WorkspacesContainer }).first else { return }
        let claimedElsewhere = Set(pending.filter { $0 != key }.flatMap { snapshots[$0]?.workspaces ?? [] })
        let workspaces = container.children.compactMap { $0 as? Workspace }.filter {
            !$0.isEffectivelyEmpty && !claimedElsewhere.contains($0.name)
        }
        snapshots[key] = Snapshot(workspaces: workspaces.map(\.name), visible: container.visibleWorkspaceNameOrStale)
        pending.insert(key)
        save()
    }

    func forget(_ workspace: Workspace) {
        for key in Array(snapshots.keys) {
            snapshots[key]?.workspaces.removeAll { $0 == workspace.name }
            if snapshots[key]?.visible == workspace.name { snapshots[key]?.visible = nil }
        }
        save()
    }

    func restore() {
        guard config.restoreDisplayWorkspaces else { return }
        for monitor in Monitor.all {
            guard let key = monitor.info.displayKey, pending.contains(key), let snapshot = snapshots[key] else { continue }
            var restored: [String: Workspace] = [:]
            for name in snapshot.workspaces {
                guard let workspace = Workspace.getOrNil(byName: name), !workspace.isEffectivelyEmpty else { continue }
                if let assigned = workspace.forceAssignedMonitorInfo, assigned.displayKey != key { continue }
                if workspace.workspaceMonitorInfo.displayKey == key || moveWorkspace(workspace, to: monitor.info, showOnDestination: false, isAutomaticRestore: true) {
                    restored[name] = workspace
                }
            }
            if let visible = snapshot.visible.flatMap({ restored[$0] }) {
                _ = monitor.info.setVisibleWorkspace(visible)
            }
            pending.remove(key)
        }
    }

    func capture() {
        guard config.restoreDisplayWorkspaces else { return }
        for monitor in Monitor.all {
            guard let key = monitor.info.displayKey, !pending.contains(key),
                  let container = monitor.children.compactMap({ $0 as? WorkspacesContainer }).first else { continue }
            // Preserve pending ownership of spaces temporarily hosted on another display.
            let claimedElsewhere = Set(pending.filter { $0 != key }.flatMap { snapshots[$0]?.workspaces ?? [] })
            let spaces = container.children.compactMap { $0 as? Workspace }.filter {
                !$0.isEffectivelyEmpty && !claimedElsewhere.contains($0.name)
            }
            snapshots[key] = Snapshot(workspaces: spaces.map(\.name), visible: container.visibleWorkspaceNameOrStale)
        }
        save()
    }

    func clearForTests() {
        precondition(isUnitTest)
        snapshots.removeAll()
        pending.removeAll()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(snapshots) { defaults?.set(data, forKey: Self.key) }
    }
}
