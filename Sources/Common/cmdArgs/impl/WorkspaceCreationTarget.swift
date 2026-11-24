/// Where a command creates a workspace that doesn't exist yet.
public enum WorkspaceCreationTarget: String, CaseIterable, Equatable, Sendable {
    /// Create the workspace on the main display. This matches upstream AeroSpace behavior.
    case main

    /// Create the workspace on the display of the workspace the command acts on.
    ///
    /// For `workspace` it's the focused workspace's display, and for `move-node-to-workspace`
    /// it's the display of the window being moved. `workspace-to-monitor-force-assignment`
    /// still takes precedence over both values.
    case focused
}

func parseWorkspaceCreationTarget(_ raw: String) -> ResOrStr<WorkspaceCreationTarget> {
    parseEnum(raw, WorkspaceCreationTarget.self)
}
