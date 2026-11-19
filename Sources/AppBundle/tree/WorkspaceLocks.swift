import AppKit
import Common

/// Snapshots use stable app identities and window titles, not process/window IDs.
/// IDs are kept only in memory to distinguish a reopened window from a second live copy.
@MainActor
final class WorkspaceLocks {
    static let shared = WorkspaceLocks(defaults: isUnitTest ? nil : .standard)
    private static let storageKey = "lockedWorkspaceLayouts.v1"

    private let defaults: UserDefaults?
    private var snapshots: [String: Snapshot]
    private var occupants: [String: [Int: OpaqueWindowId]] = [:]
    private var capturesInProgress: Set<String> = []

    init(defaults: UserDefaults?) {
        self.defaults = defaults
        snapshots = defaults?.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode([String: Snapshot].self, from: $0) } ?? [:]
    }

    var names: [String] { Array(snapshots.keys) }
    func contains(_ name: String) -> Bool { snapshots[name] != nil }

    func toggle(_ workspace: Workspace) async {
        guard capturesInProgress.insert(workspace.name).inserted else { return }
        defer { capturesInProgress.remove(workspace.name) }
        if contains(workspace.name) {
            snapshots[workspace.name] = nil
            occupants[workspace.name] = nil
            save()
            WorkspaceDisplayLayouts.shared.apply(to: workspace, on: workspace.workspaceMonitorInfo)
            return
        }
        var titles: [OpaqueWindowId: String] = [:]
        var frames: [OpaqueWindowId: LockedFloatingFrame] = [:]
        for window in workspace.lockableWindows {
            titles[window.windowId] = (try? await window.getTitle(.nonCancellable)) ?? ""
            if window.isFloating, let macWindow = window as? MacWindow {
                frames[window.windowId] = try? await macWindow.floatingFrameForWorkspaceLock(workspace)
            }
        }
        capture(workspace, titles: titles, frames: frames)
    }

    func capture(_ workspace: Workspace, titles: [OpaqueWindowId: String], frames: [OpaqueWindowId: LockedFloatingFrame] = [:]) {
        let name = workspace.name
        var slots: [Slot] = []
        var assignments: [Int: OpaqueWindowId] = [:]
        func add(_ window: Window, floating: Bool) -> Int {
            let index = slots.count
            slots.append(Slot(app: Self.appIdentity(window.app), title: titles[window.windowId] ?? "", floating: floating, frame: frames[window.windowId]))
            assignments[index] = window.windowId
            return index
        }
        func captureTree(_ container: TilingContainer, weight: CGFloat) -> Container {
            Container(horizontal: container.orientation == .h, layout: container.layout.rawValue, weight: weight, children: container.children.compactMap { child in
                let weight = child.getWeight(container.orientation)
                if let window = child as? Window { return .window(add(window, floating: false), weight: weight) }
                if let child = child as? TilingContainer { return .container(captureTree(child, weight: weight)) }
                return nil
            })
        }
        var root = captureTree(workspace.rootTilingContainer, weight: 1)
        let capturedIDs = Set(assignments.values)
        for window in workspace.lockableWindows where !capturedIDs.contains(window.windowId) {
            let wasFloating = window.isFloating || window.layoutReason == .macos(prevParentKind: .floatingWindowsContainer)
            let slot = add(window, floating: wasFloating)
            if !wasFloating { root.children.append(.window(slot, weight: 1)) }
        }
        snapshots[name] = Snapshot(root: root, slots: slots)
        occupants[name] = assignments
        save()
    }

    func updateRootLayout(_ workspace: Workspace) {
        guard snapshots[workspace.name] != nil else { return }
        let root = workspace.rootTilingContainer
        snapshots[workspace.name]?.root.layout = root.layout.rawValue
        snapshots[workspace.name]?.root.horizontal = root.orientation == .h
        save()
    }

    func applySavedRootLayout(_ root: TilingContainer, workspaceName: String) {
        guard let saved = snapshots[workspaceName]?.root else { return }
        root.layout = Layout(rawValue: saved.layout) ?? .tiles
        root.changeOrientation(saved.horizontal ? .h : .v)
    }

    func remembers(_ app: any AbstractApp) -> Bool {
        guard let identity = Self.appIdentity(app) else { return false }
        return snapshots.values.contains { $0.slots.contains { $0.app == identity } }
    }

    struct Placement {
        let workspace: String
        let slot: Int
    }

    func placement(for app: any AbstractApp, title: String, id: OpaqueWindowId) -> Placement? {
        guard let identity = Self.appIdentity(app) else { return nil }
        var matches: [(placement: Placement, isExact: Bool, isFree: Bool)] = []
        for name in snapshots.keys.sorted() {
            guard let snapshot = snapshots[name] else { continue }
            for (index, slot) in snapshot.slots.enumerated() where slot.app == identity {
                let placement = Placement(workspace: name, slot: index)
                let occupant = occupants[name]?[index]
                if occupant == id { return placement }
                matches.append((placement, !title.isEmpty && title == slot.title, occupant.flatMap { Window.get(byId: $0) } == nil))
            }
        }
        let exact = matches.filter { $0.isExact && $0.isFree }
        if let first = exact.first, exact.allSatisfy({ $0.placement.workspace == first.placement.workspace }) {
            return first.placement
        }
        // Titles can change at launch. Only fall back when the app had a single saved window.
        if matches.count == 1, let match = matches.first, match.isFree { return match.placement }
        return nil
    }

    func initialBinding(for placement: Placement, workspace: Workspace) -> BindingData {
        let floating = snapshots[placement.workspace]?.slots[placement.slot].floating == true
        return BindingData(
            parent: floating ? workspace.floatingWindowsContainer : workspace.rootTilingContainer,
            adaptiveWeight: WEIGHT_AUTO,
            index: INDEX_BIND_LAST,
        )
    }

    func restore(_ placement: Placement, window: Window, in workspace: Workspace, restoreFloatingFrame: Bool = true) {
        guard let snapshot = snapshots[placement.workspace] else { return }
        occupants[placement.workspace, default: [:]][placement.slot] = window.windowId
        let slot = snapshot.slots[placement.slot]
        if slot.floating {
            if !window.isFloating { window.bindAsFloatingWindow(to: workspace) }
            if restoreFloatingFrame { window.pendingLockedFloatingFrame = slot.frame }
            return
        }
        if !(window.parent is TilingContainer) {
            window.bind(to: workspace.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
        }
        let oldRoot = workspace.rootTilingContainer
        let existing = oldRoot.allLeafWindowsRecursive
        let byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.windowId, $0) })
        let live = (occupants[workspace.name] ?? [:]).compactMapValues { byID[$0] }
        let recent = workspace.mostRecentWindowRecursive
        oldRoot.unbindFromParent()
        _ = restoreTree(snapshot.root, under: workspace, live: live)
        for other in existing where other.nodeWorkspace == nil {
            other.bind(to: workspace.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
        }
        (recent ?? window).markAsMostRecentChild()
    }

    func restoreAfterNativeState(_ window: Window, in workspace: Workspace) -> Bool {
        guard let slot = occupants[workspace.name]?.first(where: { $0.value == window.windowId })?.key else { return false }
        restore(Placement(workspace: workspace.name, slot: slot), window: window, in: workspace)
        return true
    }

    private func restoreTree(_ saved: Container, under parent: NonLeafTreeNodeObject, live: [Int: Window]) -> TilingContainer {
        let container = TilingContainer(
            parent: parent,
            adaptiveWeight: saved.weight,
            saved.horizontal ? .h : .v,
            Layout(rawValue: saved.layout) ?? .tiles,
            index: INDEX_BIND_LAST,
        )
        for child in saved.children {
            switch child {
                case .window(let slot, let weight):
                    live[slot]?.bind(to: container, adaptiveWeight: weight, index: INDEX_BIND_LAST)
                case .container(let savedChild) where savedChild.hasLiveWindow(live):
                    _ = restoreTree(savedChild, under: container, live: live)
                case .container: break
            }
        }
        return container
    }

    private func save() {
        guard let defaults, let data = try? JSONEncoder().encode(snapshots) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private static func appIdentity(_ app: any AbstractApp) -> String? {
        if let id = app.rawAppBundleId, !id.isEmpty { return "bundle:\(id)" }
        return app.execPath.map { "exec:\($0)" }
    }

    struct Snapshot: Codable {
        var root: Container
        let slots: [Slot]
    }

    struct Slot: Codable {
        let app: String?
        let title: String
        let floating: Bool
        let frame: LockedFloatingFrame?
    }

    struct Container: Codable {
        var horizontal: Bool
        var layout: String
        let weight: CGFloat
        var children: [Child]

        func hasLiveWindow(_ live: [Int: Window]) -> Bool {
            children.contains { child in
                switch child {
                    case .window(let slot, _): live[slot] != nil
                    case .container(let container): container.hasLiveWindow(live)
                }
            }
        }
    }

    enum Child: Codable {
        case window(Int, weight: CGFloat)
        case container(Container)
    }
}

struct LockedFloatingFrame: Codable {
    let x: CGFloat
    let y: CGFloat
    let size: CGSize
}

extension Workspace {
    @MainActor var isLocked: Bool { WorkspaceLocks.shared.contains(name) }

    @MainActor var lockableWindows: [Window] {
        allLeafWindowsRecursive + macosMinimizedWindowsContainer.children.filterIsInstance(of: Window.self)
            .filter { $0.minimizedWorkspaceName == name }
    }

    @MainActor func unlockedAlternative() -> Workspace {
        let monitor = workspaceMonitorInfo.rect.topLeftCorner
        let candidates = Workspace.all.filter { !$0.isLocked && $0.workspaceMonitorInfo.rect.topLeftCorner == monitor }
        if let candidate = candidates.first(where: \.isVisible) ?? candidates.first { return candidate }
        // A newly created fallback need not be empty, but it must be unlocked and on this monitor.
        return (1 ... Int.max).lazy.map { Workspace.get(byName: String($0)) }.first {
            !$0.isLocked && !$0.isVisible && $0.isEffectivelyEmpty &&
                ($0.forceAssignedMonitorInfo == nil || $0.forceAssignedMonitorInfo?.rect.topLeftCorner == monitor)
                && workspaceMonitorInfo.bindWorkspace($0)
        }.orDie()
    }
}

extension Window {
    @MainActor var membershipWorkspace: Workspace? {
        nodeWorkspace ?? minimizedWorkspaceName.map { Workspace.get(byName: $0) }
    }
}

@MainActor func lockedWorkspaceForTransfer(_ window: Window, to target: Workspace) -> Workspace? {
    let source = window.membershipWorkspace
    guard source != target else { return nil }
    if target.isLocked { return target }
    return source?.isLocked == true ? source : nil
}
