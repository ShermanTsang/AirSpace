import Common

struct MoveNodeToWorkspaceCommand: Command {
    let args: MoveNodeToWorkspaceCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache: Bool = true

    func run(_ env: CmdEnv, _ io: CmdIo) -> BinaryExitCode {
        guard let target = args.resolveTargetOrReportError(env, io) else { return .fail }
        guard let window = target.windowOrNil else { return .fail(io.err(noWindowIsFocused)) }
        let subjectWs = window.nodeWorkspace
        let targetWorkspace: Workspace
        switch args.target.val {
            case .relative(let nextPrev):
                guard let subjectWs else { return .fail(io.err("Window \(window.windowId) doesn't belong to any workspace")) }
                let ws = getNextPrevWorkspace(
                    current: subjectWs,
                    isNext: nextPrev == .next,
                    wrapAround: args.wrapAround,
                    stdin: args.useStdin ? io.readStdin() : nil,
                    target: target,
                )
                guard let ws = ws.getOrNil(appendErrorTo: &io.stderr) else { return .fail }
                targetWorkspace = ws
            case .direct(let name):
                let createOnMonitor = args.createOn.resolveMonitor(target)
                targetWorkspace = Workspace.get(byName: name.raw, createOn: createOnMonitor)
                // A workspace with no windows that isn't visible hasn't really been "created" from the
                // user's perspective. Let it follow the same display as a new workspace, otherwise a
                // window moved to it crosses displays just because the workspace was left there by an
                // earlier monitor layout. Don't touch the workspace if the transfer is going to be
                // rejected: a failed command must not have a display side effect.
                if window.membershipWorkspace != targetWorkspace,
                   lockedWorkspaceForTransfer(window, to: targetWorkspace) == nil {
                    moveIfEffectivelyUnused(targetWorkspace, to: createOnMonitor)
                }
        }
        return moveWindowToWorkspace(window, targetWorkspace, io, focusFollowsWindow: args.focusFollowsWindow, failIfNoop: args.failIfNoop)
    }
}

/// Moves an empty, hidden workspace to `monitor` before a window is bound to it.
/// Workspaces with windows, visible workspaces, locked workspaces and force-assigned workspaces keep
/// their display. `moveWorkspace` cancels a pending display-restoration snapshot for the workspace,
/// so this explicit user action wins over a later reconnect.
@MainActor
private func moveIfEffectivelyUnused(_ workspace: Workspace, to monitor: MonitorInfo) {
    guard workspace.isEffectivelyEmpty,
          !workspace.isVisible,
          !workspace.isLocked,
          workspace.forceAssignedMonitorInfo == nil,
          workspace.workspaceMonitorInfo.rect.topLeftCorner != monitor.rect.topLeftCorner
    else { return }
    _ = moveWorkspace(workspace, to: monitor, showOnDestination: false)
}

@MainActor
func moveWindowToWorkspace(_ window: Window, _ targetWorkspace: Workspace, _ io: CmdIo, focusFollowsWindow: Bool, failIfNoop: Bool, index: Int = INDEX_BIND_LAST) -> BinaryExitCode {
    if let locked = lockedWorkspaceForTransfer(window, to: targetWorkspace) {
        showWorkspaceLocked(locked)
        return .fail(io.err(workspaceLockedMessage(locked.name)))
    }
    if window.membershipWorkspace == targetWorkspace {
        return switch failIfNoop {
            case true: .fail
            case false:
                .succ(io.err("Window '\(window.windowId)' already belongs to workspace '\(targetWorkspace.name)'. Tip: use --fail-if-noop to exit with non-zero code"))
        }
    }
    let targetContainer: NonLeafTreeNodeObject = window.isFloating
        ? targetWorkspace.floatingWindowsContainer
        : targetWorkspace.rootTilingContainer
    window.minimizedWorkspaceName = nil
    window.pendingLockedFloatingFrame = nil
    window.bind(to: targetContainer, adaptiveWeight: WEIGHT_AUTO, index: index)
    return .from(bool: focusFollowsWindow ? window.focusWindow() : true)
}
