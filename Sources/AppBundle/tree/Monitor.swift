import AppKit
import Common

@MainActor private var pointToMonitor: [Point: Monitor] = [:]

final class Monitor: TreeNode, NonLeafTreeNodeObject {
    fileprivate var _info: MonitorInfo
    var info: MonitorInfo { _info }

    @MainActor fileprivate init(_ info: MonitorInfo) {
        self._info = info
        super.init(parent: NilTreeNode.instance, adaptiveWeight: 0, index: 0)
    }

    override func getWeight(_ targetOrientation: Orientation) -> CGFloat {
        info.visibleRectPaddedByOuterGaps.getDimension(targetOrientation)
    }

    override func setWeight(_ targetOrientation: Orientation, _ newValue: CGFloat) {
        die("It's not possible to change weight of Monitor")
    }

    @MainActor static var all: [Monitor] { Array(pointToMonitor.values) }
}

@MainActor private func rearrangeMonitors() {
    let previousDisplays = Dictionary(uniqueKeysWithValues: Monitor.all.flatMap { monitor in
        monitor.children.flatMap { container in
            container.children.compactMap { child -> (ObjectIdentifier, String)? in
                guard let workspace = child as? Workspace else { return nil }
                return (ObjectIdentifier(workspace), monitorLayoutIdentity(monitor.info))
            }
        }
    })
    var newMonitorPoints = globalUnsortedMonitorInfos.grouped(by: { $0.rect.topLeftCorner }).mapValues { $0.singleOrNil().orDie() }

    var oldPointToMonitor = pointToMonitor
    pointToMonitor = [:]

    // Preserve each monitor's workspaces when displays move in the arrangement.
    for (newPoint, info) in Array(newMonitorPoints) {
        guard let key = info.displayKey,
              let match = oldPointToMonitor.first(where: { $0.value.info.displayKey == key }) else { continue }
        let monitor = match.value
        oldPointToMonitor.removeValue(forKey: match.key)
        newMonitorPoints.removeValue(forKey: newPoint)
        monitor._info = info
        pointToMonitor[newPoint] = monitor
    }

    var newPointToClosestOldPoint = [Point: Point]()
    var oldPointToClosestNewPoint = [Point: Point]()

    for point in newMonitorPoints.keys {
        newPointToClosestOldPoint[point] = oldPointToMonitor.keys.minBy { ($0 - point).vectorLength }
    }

    for point in oldPointToMonitor.keys {
        oldPointToClosestNewPoint[point] = newMonitorPoints.keys.minBy { ($0 - point).vectorLength }
    }

    for (newPoint, closestOldPoint) in newPointToClosestOldPoint {
        if oldPointToClosestNewPoint[closestOldPoint] == newPoint { // Closest points of each other
            pointToMonitor[newPoint] = oldPointToMonitor.removeValue(forKey: closestOldPoint)
            pointToMonitor[newPoint].orDie()._info = newMonitorPoints.removeValue(forKey: newPoint).orDie()
        }
    }

    var monitors = oldPointToMonitor.values.sortedBy { $0.info.rect.topLeftCorner.vectorLength } // [Monitor]
    let monitorInfos = newMonitorPoints.values.sortedBy { $0.rect.topLeftCorner.vectorLength } // [MonitorInfo]

    let mainMonitor = pointToMonitor[Point(x: 0, y: 0)] ?? pointToMonitor.first?.value
    while monitors.count > monitorInfos.count, let mainMonitor {
        let monitor = monitors.removeLast()
        for child in monitor.children {
            switch child.nodeCases {
                case .floatingWindowsContainer,
                     .macosFullscreenWindowsContainer,
                     .macosHiddenAppsWindowsContainer,
                     .macosMinimizedWindowsContainer,
                     .macosPopupWindowsContainer,
                     .monitor,
                     .tilingContainer,
                     .window,
                     .workspace: illegalChildParentRelation(child: child, parent: monitor)
                case .workspacesContainer(let it):
                    for workspace in it.children {
                        workspace.bind(to: mainMonitor.getWorkspacesContainerOrCreate(), adaptiveWeight: 1, index: INDEX_BIND_LAST)
                    }
            }
        }
    }

    for j in monitors.indices {
        monitors[j]._info = monitorInfos.getOrNil(atIndex: j).orDie()
        pointToMonitor[monitors[j].info.rect.topLeftCorner] = monitors[j]
    }

    var i = monitors.count
    while let monitorInfo = monitorInfos.getOrNil(atIndex: i) {
        let monitor = Monitor(monitorInfo)
        monitors.append(monitor)
        pointToMonitor[monitor.info.rect.topLeftCorner] = monitor
        i += 1
    }
    for monitor in Monitor.all {
        for container in monitor.children {
            for case let workspace as Workspace in container.children {
                if let previous = previousDisplays[ObjectIdentifier(workspace)], previous != monitorLayoutIdentity(monitor.info) {
                    WorkspaceDisplayLayouts.shared.apply(to: workspace, on: monitor.info)
                }
            }
        }
    }
}

private func monitorLayoutIdentity(_ info: MonitorInfo) -> String {
    "\(info.displayKey ?? "unknown")|\(info.width)|\(info.height)"
}

/// Compares cached monitor geometry with a fresh snapshot. `monitorLayoutIdentity` deliberately
/// excludes `visibleRect` because Dock/menu bar changes must not reset user display layouts, but the
/// cached `MonitorInfo` still has to be refreshed when the usable area changes.
func monitorInfoMatches(_ cached: MonitorInfo, _ fresh: MonitorInfo) -> Bool {
    cached.displayKey == fresh.displayKey &&
        cached.name == fresh.name &&
        cached.rect == fresh.rect &&
        cached.visibleRect == fresh.visibleRect &&
        cached.isMain == fresh.isMain
}

extension MonitorInfo {
    @MainActor var visibleWorkspace: Workspace { // todo revisit this API
        let monitor = toMonitorOrRearrangeMonitors()
        return monitor.getWorkspacesContainerOrCreate().getVisibleWorkspaceOrCreate(parent: monitor)
    }

    @MainActor func toMonitorOrRearrangeMonitors() -> Monitor {
        if let existing = pointToMonitor[rect.topLeftCorner] {
            return existing
        }
        rearrangeMonitors() // If monitor configuration changed
        // Normally, recursion should happen only once more because we must take the value from the cache
        // (Unless, monitor configuration data race happens)
        return self.toMonitorOrRearrangeMonitors()
    }

    @MainActor func setVisibleWorkspace(_ workspace: Workspace) -> Bool { // todo revisit this API (new name: setVisibleWorkspace)
        let container = toMonitorOrRearrangeMonitors().getWorkspacesContainerOrCreate()
        return container.setVisibleWorkspace(workspace)
    }

    @MainActor func bindWorkspace(_ workspace: Workspace) -> Bool {
        return toMonitorOrRearrangeMonitors().getWorkspacesContainerOrCreate().bindWorkspace(workspace)
    }
}

@MainActor func gcMonitors() {
    let infos = globalUnsortedMonitorInfos
    if pointToMonitor.count != infos.count || infos.contains(where: { info in
        guard let monitor = pointToMonitor[info.rect.topLeftCorner] else { return true }
        return !monitorInfoMatches(monitor.info, info)
    }) {
        rearrangeMonitors()
    }
}
