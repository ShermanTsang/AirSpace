import AppKit
import Common

public final class TrayMenuModel: ObservableObject {
    @MainActor public static let shared = TrayMenuModel()

    private init() {}

    @Published var focusedWorkspaceIcons: [NSImage] = []
    /// Is "layouting" enabled
    @Published var isEnabled: Bool = true
    @Published var workspaces: [WorkspaceViewModel] = []
    @Published var sponsorshipMessage: String = sponsorshipPrompts.randomElement().orDie()
    @Published var lastReloadConfigContainedWarnings: Bool = false
    @Published var axPermissionStatus: AxPermissionStatus = .waitingWithPrompt
    /// Incremented every time the config is successfully reloaded. Used by the Settings UI
    /// (see `SettingsViewModel`) to re-sync itself with the config that is actually active
    @Published var configReloadEpoch: Int = 0
}

enum AxPermissionStatus: Equatable {
    case granted
    case waiting
    case waitingWithPrompt
}

@MainActor func updateTrayText() {
    let focus = globalFocus
    TrayMenuModel.shared.focusedWorkspaceIcons = Array(focus.workspace.allLeafWindowsRecursive.lazy.compactMap {
        NSRunningApplication(processIdentifier: $0.app.pid)?.icon
    }.prefix(3))
    TrayMenuModel.shared.workspaces = Workspace.all.map { workspace in
        let apps = workspace.lockableWindows.grouped { $0.app.pid }.map { pid, windows in
            let runningApp = NSRunningApplication(processIdentifier: pid)
            let name = windows.first?.app.name?.takeIf { !$0.isEmpty } ?? runningApp?.localizedName ?? "Unknown app"
            return WorkspaceApp(id: pid, name: name, icon: runningApp?.icon, windowIDs: windows.map(\.windowId))
        }.sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
        let root = workspace.rootTilingContainer
        return WorkspaceViewModel(
            name: workspace.name,
            apps: apps,
            mode: WorkspaceLayoutMode(layout: root.layout, orientation: root.orientation),
            hasDisplayLayout: WorkspaceDisplayLayouts.shared.remembered(workspace: workspace.name, display: workspace.workspaceMonitorInfo.displayKey) != nil,
            canRememberDisplayLayout: workspace.workspaceMonitorInfo.displayKey != nil,
            isLocked: workspace.isLocked,
            isFocused: focus.workspace == workspace,
            isVisible: workspace.isVisible,
        )
    }
}

struct WorkspaceApp: Identifiable {
    let id: Int32
    let name: String
    let icon: NSImage?
    let windowIDs: [OpaqueWindowId]
}

struct WorkspaceViewModel {
    let name: String
    let apps: [WorkspaceApp]
    let mode: WorkspaceLayoutMode
    let hasDisplayLayout: Bool
    let canRememberDisplayLayout: Bool
    let isLocked: Bool
    let isFocused: Bool
    let isVisible: Bool

    var activityRank: Int { isFocused ? 0 : isVisible ? 1 : apps.isEmpty ? 3 : 2 }
}

enum WorkspaceLayoutMode: String, CaseIterable, Codable {
    case horizontalTiles, verticalTiles, horizontalAccordion, verticalAccordion

    init(layout: Layout, orientation: Orientation) {
        self = switch (layout, orientation) {
            case (.tiles, .h): .horizontalTiles
            case (.tiles, .v): .verticalTiles
            case (.accordion, .h): .horizontalAccordion
            case (.accordion, .v): .verticalAccordion
        }
    }

    var icon: String {
        switch self {
            case .horizontalTiles: "rectangle.split.2x1"
            case .verticalTiles: "rectangle.split.1x2"
            case .horizontalAccordion: "rectangle.stack"
            case .verticalAccordion: "rectangle.stack"
        }
    }

    var title: String {
        switch self {
            case .horizontalTiles: "Horizontal tiles"
            case .verticalTiles: "Vertical tiles"
            case .horizontalAccordion: "Horizontal accordion"
            case .verticalAccordion: "Vertical accordion"
        }
    }

    @MainActor func applyLayout(to root: TilingContainer) {
        root.layout = self == .horizontalTiles || self == .verticalTiles ? .tiles : .accordion
        root.changeOrientation(self == .horizontalTiles || self == .horizontalAccordion ? .h : .v)
    }

    @MainActor func apply(to workspace: Workspace) {
        let root = workspace.rootTilingContainer
        applyLayout(to: root)
        WorkspaceDisplayLayouts.shared.remember(self, workspace: workspace.name, display: workspace.workspaceMonitorInfo.displayKey)
        WorkspaceLocks.shared.updateRootLayout(workspace)
        resetClosedWindowsCache()
    }
}
