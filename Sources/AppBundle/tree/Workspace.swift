import AppKit
import Common

@MainActor private var workspaceNameToWorkspace: [String: Workspace] = [:]

final class Workspace: TreeNode, NonLeafTreeNodeObject, Hashable, Comparable {
    let name: String
    nonisolated private let nameLogicalSegments: StringLogicalSegments

    @MainActor private init(_ name: String, on monitor: MonitorInfo) {
        self.name = name
        self.nameLogicalSegments = name.toLogicalSegments()
        let container = monitor.toMonitorOrRearrangeMonitors().getWorkspacesContainerOrCreate()
        super.init(parent: container, adaptiveWeight: 0, index: 0)
        check(forceAssignedMonitorInfo?.toMonitorOrRearrangeMonitors().getWorkspacesContainerOrCreate().bindWorkspace(self) != false)
    }

    @MainActor static var all: [Workspace] {
        workspaceNameToWorkspace.values.sorted()
    }

    @MainActor static func get(byName name: String) -> Workspace {
        get(byName: name, createOn: mainMonitorInfo)
    }

    /// `createOn` only affects a workspace that doesn't exist yet. An existing workspace is never
    /// moved to another display, and `workspace-to-monitor-force-assignment` still wins over `createOn`.
    @MainActor static func get(byName name: String, createOn monitor: MonitorInfo) -> Workspace {
        if let existing = workspaceNameToWorkspace[name] {
            return existing
        } else {
            let workspace = Workspace(name, on: monitor)
            workspaceNameToWorkspace[name] = workspace
            return workspace
        }
    }

    /// Looks up an existing workspace without creating one.
    /// A newly created workspace binds itself to the main display, so callers that are validating
    /// a stale name (menu snapshot, drop target) must not use `get(byName:)`.
    @MainActor static func getOrNil(byName name: String) -> Workspace? {
        workspaceNameToWorkspace[name]
    }

    nonisolated static func < (lhs: Workspace, rhs: Workspace) -> Bool {
        lhs.nameLogicalSegments < rhs.nameLogicalSegments
    }

    override func getWeight(_ targetOrientation: Orientation) -> CGFloat {
        workspaceMonitorInfo.visibleRectPaddedByOuterGaps.getDimension(targetOrientation)
    }

    override func setWeight(_ targetOrientation: Orientation, _ newValue: CGFloat) {
        die("It's not possible to change weight of Workspace")
    }

    @MainActor
    var description: String {
        let description = [
            ("name", name),
            ("isVisible", String(isVisible)),
            ("isEffectivelyEmpty", String(isEffectivelyEmpty)),
            ("doKeepAlive", String(config.persistentWorkspaces.contains(name))),
        ].map { "\($0.0): \(String(describing: $0.1).singleQuoted)" }.joined(separator: ", ")
        return "Workspace(\(description))"
    }

    @MainActor static func forceAssignWorkspaces() {
        for wsName in config.workspaceToMonitorForceAssignment.keys {
            let ws = Workspace.get(byName: wsName)
            check(ws.forceAssignedMonitorInfo?.bindWorkspace(ws) != false)
        }
    }

    @MainActor static func garbageCollectUnusedWorkspaces() {
        for name in Set(config.persistentWorkspaces).union(WorkspaceLocks.shared.names) {
            _ = get(byName: name) // Make sure that all persistent workspaces are "cached"
        }
        let focus = globalFocus
        let garbage = workspaceNameToWorkspace.values.filter { workspace in
            !config.persistentWorkspaces.contains(workspace.name) && !workspace.isLocked &&
                workspace.isEffectivelyEmpty &&
                !workspace.isVisible &&
                workspace.name != focus.workspace.name
        }
        for workspace in garbage {
            workspaceNameToWorkspace.removeValue(forKey: workspace.name)
            workspace.unbindFromParent()
        }
    }

    nonisolated static func == (lhs: Workspace, rhs: Workspace) -> Bool {
        check((lhs === rhs) == (lhs.name == rhs.name), "lhs: \(lhs) rhs: \(rhs)")
        return lhs === rhs
    }

    nonisolated func hash(into hasher: inout Hasher) { hasher.combine(name) }
}
