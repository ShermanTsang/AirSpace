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
    TrayMenuModel.shared.workspaces = Workspace.all.map {
        var seenPids = Set<Int32>()
        let workspaceApps = $0.allLeafWindowsRecursive.compactMap { window -> WorkspaceApp? in
            guard seenPids.insert(window.app.pid).inserted else { return nil }
            let runningApp = NSRunningApplication(processIdentifier: window.app.pid)
            return WorkspaceApp(name: window.app.name?.takeIf { !$0.isEmpty } ?? runningApp?.localizedName ?? "Unknown app", icon: runningApp?.icon)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let root = $0.children.filterIsInstance(of: TilingContainer.self).first
        let layout = root?.layout ?? config.defaultRootContainerLayout
        let orientation = root.map { $0.orientation == .h ? "Horizontal" : "Vertical" } ?? {
            switch config.defaultRootContainerOrientation {
                case .horizontal: "Horizontal"
                case .vertical: "Vertical"
                case .auto: "Auto"
            }
        }()
        return WorkspaceViewModel(
            name: $0.name,
            apps: workspaceApps,
            layoutName: layout == .tiles ? "Tiles" : "Accordion",
            orientationName: orientation,
            usesDefaultLayout: root == nil,
            isFocused: focus.workspace == $0,
            isEffectivelyEmpty: $0.isEffectivelyEmpty,
            isVisible: $0.isVisible,
        )
    }.sorted { lhs, rhs in
        if lhs.isEffectivelyEmpty != rhs.isEffectivelyEmpty { return !lhs.isEffectivelyEmpty }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}

struct WorkspaceApp {
    let name: String
    let icon: NSImage?
}

struct WorkspaceViewModel {
    let name: String
    let apps: [WorkspaceApp]
    let layoutName: String
    let orientationName: String
    let usesDefaultLayout: Bool
    let isFocused: Bool
    let isEffectivelyEmpty: Bool
    let isVisible: Bool
}
