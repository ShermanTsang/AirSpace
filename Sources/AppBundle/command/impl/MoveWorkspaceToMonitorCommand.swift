import AppKit
import Common

struct MoveWorkspaceToMonitorCommand: Command {
    let args: MoveWorkspaceToMonitorCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = true

    func run(_ env: CmdEnv, _ io: CmdIo) -> BinaryExitCode {
        guard let target = args.resolveTargetOrReportError(env, io) else { return .fail }
        let workspace = target.workspace

        switch args.target.val.resolve(workspace.workspaceMonitorInfo, wrapAround: args.wrapAround) {
            case .success(let targetMonitor):
                if moveWorkspace(workspace, to: targetMonitor, showOnDestination: true) {
                    return .succ
                }
                return .fail(io.err(
                    "Can't move workspace '\(workspace.name)' to monitor '\(targetMonitor.name)'. workspace-to-monitor-force-assignment doesn't allow it",
                ))
            case .failure(let msg):
                return .fail(io.err(msg))
        }
    }
}

@MainActor func moveWorkspace(_ workspace: Workspace, to destination: MonitorInfo, showOnDestination: Bool) -> Bool {
    let source = workspace.workspaceMonitorInfo
    guard source.rect.topLeftCorner != destination.rect.topLeftCorner else { return true }
    let wasVisible = workspace.isVisible
    let moved = showOnDestination ? destination.setVisibleWorkspace(workspace) : destination.bindWorkspace(workspace)
    guard moved else { return false }
    if wasVisible {
        let replacement = getStubWorkspace(for: source, excluding: workspace.name)
        check(source.setVisibleWorkspace(replacement), "Fallback workspace must be compatible with its display")
    }
    return true
}
