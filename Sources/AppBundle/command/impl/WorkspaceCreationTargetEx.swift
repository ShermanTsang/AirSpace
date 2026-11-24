import Common

extension WorkspaceCreationTarget {
    @MainActor
    func resolveMonitor(_ focus: LiveFocus) -> MonitorInfo {
        switch self {
            case .main: mainMonitorInfo
            case .focused: focus.workspace.workspaceMonitorInfo
        }
    }
}
