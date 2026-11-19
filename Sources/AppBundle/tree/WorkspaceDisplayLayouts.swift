import Foundation
import Common

/// Sparse layout choices for a workspace on a particular physical display.
@MainActor
final class WorkspaceDisplayLayouts {
    static let shared = WorkspaceDisplayLayouts(defaults: isUnitTest ? nil : .standard)
    private static let storageKey = "workspaceDisplayLayouts.v1"
    private let defaults: UserDefaults?
    private var layouts: [String: [String: WorkspaceLayoutMode]]

    init(defaults: UserDefaults?) {
        self.defaults = defaults
        layouts = defaults?.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode([String: [String: WorkspaceLayoutMode]].self, from: $0) } ?? [:]
    }

    func remembered(workspace: String, display: String?) -> WorkspaceLayoutMode? {
        guard let display else { return nil }
        return layouts[workspace]?[display]
    }

    func remember(_ mode: WorkspaceLayoutMode, workspace: String, display: String?) {
        guard let display else { return }
        layouts[workspace, default: [:]][display] = mode
        save()
    }

    func forget(workspace: String, display: String?) {
        guard let display else { return }
        layouts[workspace]?[display] = nil
        if layouts[workspace]?.isEmpty == true { layouts[workspace] = nil }
        save()
    }

    func apply(to workspace: Workspace, on monitor: MonitorInfo) {
        guard !workspace.isLocked else { return }
        let root = workspace.rootTilingContainer
        if let mode = remembered(workspace: workspace.name, display: monitor.displayKey) {
            mode.applyLayout(to: root)
        } else {
            root.layout = config.defaultRootContainerLayout
            let orientation: Orientation = switch config.defaultRootContainerOrientation {
                case .horizontal: .h
                case .vertical: .v
                case .auto: monitor.width >= monitor.height ? .h : .v
            }
            root.changeOrientation(orientation)
        }
    }

    func clearForTests() {
        precondition(isUnitTest)
        layouts.removeAll()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(layouts) else { return }
        defaults?.set(data, forKey: Self.storageKey)
    }
}
