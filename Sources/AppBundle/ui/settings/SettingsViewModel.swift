import Combine
import Foundation
import SwiftUI

/// The values the visual editor knows how to read and write.
/// Everything else in the config file is left untouched by the editor
struct SettingsState: Equatable {
    var startAtLogin: Bool
    var autoReloadConfig: Bool
    var automaticallyUnhideMacosHiddenApps: Bool
    var defaultRootContainerLayout: Layout
    var defaultRootContainerOrientation: DefaultContainerOrientation
    var accordionPadding: Int
    var flattenContainersNormalization: Bool
    var oppositeOrientationNormalization: Bool
    /// `nil` when the value is per-monitor. Such values can only be edited in the config file
    var gapsInnerVertical: Int?
    var gapsInnerHorizontal: Int?
    var gapsOuterLeft: Int?
    var gapsOuterTop: Int?
    var gapsOuterBottom: Int?
    var gapsOuterRight: Int?
    var focusFollowsMouse: Bool

    init(config: Config) {
        startAtLogin = config.startAtLogin
        autoReloadConfig = config.autoReloadConfig
        automaticallyUnhideMacosHiddenApps = config.automaticallyUnhideMacosHiddenApps
        defaultRootContainerLayout = config.defaultRootContainerLayout
        defaultRootContainerOrientation = config.defaultRootContainerOrientation
        accordionPadding = config.accordionPadding
        flattenContainersNormalization = config.enableNormalizationFlattenContainers
        oppositeOrientationNormalization = config.enableNormalizationOppositeOrientationForNestedContainers
        gapsInnerVertical = config.gaps.inner.vertical.constantValue
        gapsInnerHorizontal = config.gaps.inner.horizontal.constantValue
        gapsOuterLeft = config.gaps.outer.left.constantValue
        gapsOuterTop = config.gaps.outer.top.constantValue
        gapsOuterBottom = config.gaps.outer.bottom.constantValue
        gapsOuterRight = config.gaps.outer.right.constantValue
        focusFollowsMouse = config.focusFollowsMouse.enabled
    }
}

/// Backs the Settings window and the quick settings in the menu bar.
///
/// Every change is written to the config file and hot-reloaded immediately: the UI never keeps
/// state of its own. Rapid changes (e.g. dragging a stepper) are debounced into a single write
@MainActor
final class SettingsViewModel: ObservableObject {
    static let shared = SettingsViewModel()

    @Published private(set) var state: SettingsState
    /// The last write/reload failure, if any. Cleared on the next successful write
    @Published private(set) var lastError: String? = nil

    private var pendingEdits: [TomlPatcher.Edit] = []
    private var flushTask: Task<Void, Never>? = nil
    private var isFlushing = false
    private var configReloadedSubscription: AnyCancellable? = nil

    private init() {
        state = SettingsState(config: config)
        // Keep the UI in sync with the config file when it's reloaded, no matter who triggered it
        configReloadedSubscription = TrayMenuModel.shared.$configReloadEpoch
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.refreshFromActiveConfig()
                }
            }
    }

    /// Re-syncs the UI with the config that is actually active (e.g. after an external config
    /// edit was hot-reloaded, or after our own write failed)
    func refreshFromActiveConfig() {
        // Don't clobber the values the user just changed while their write is still in flight
        guard pendingEdits.isEmpty && !isFlushing else { return }
        state = SettingsState(config: config)
    }

    func binding<Value: Equatable>(
        _ keyPath: WritableKeyPath<SettingsState, Value>,
        edit: @escaping (Value) -> TomlPatcher.Edit,
    ) -> Binding<Value> {
        Binding(
            get: { self.state[keyPath: keyPath] },
            set: { self.set(keyPath, to: $0, edit: edit($0)) },
        )
    }

    /// Binding for an `Int?` gap value. Per-monitor values (`nil`) render as disabled controls
    func intBinding(
        _ keyPath: WritableKeyPath<SettingsState, Int?>,
        path: [String],
        range: ClosedRange<Int>,
    ) -> Binding<Int> {
        Binding(
            get: { self.state[keyPath: keyPath] ?? range.lowerBound },
            set: { newValue in
                let clamped = min(max(newValue, range.lowerBound), range.upperBound)
                self.set(keyPath, to: Optional(clamped), edit: .int(path, clamped))
            },
        )
    }

    private func set<Value: Equatable>(_ keyPath: WritableKeyPath<SettingsState, Value>, to newValue: Value, edit: TomlPatcher.Edit) {
        guard state[keyPath: keyPath] != newValue else { return }
        state[keyPath: keyPath] = newValue
        pendingEdits.removeAll { $0.path == edit.path }
        pendingEdits.append(edit)
        scheduleFlush()
    }

    private func scheduleFlush() {
        flushTask?.cancel()
        flushTask = Task.startUnstructured {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self.flushEdits()
        }
    }

    private func flushEdits() {
        guard !pendingEdits.isEmpty else { return }
        guard !isFlushing else {
            scheduleFlush() // Retry after the in-flight write finishes
            return
        }
        isFlushing = true
        let edits = pendingEdits
        pendingEdits.removeAll()
        Task.startUnstructured {
            defer {
                self.isFlushing = false
                if !self.pendingEdits.isEmpty { self.flushEdits() }
            }
            do {
                try await ConfigFileEditor.applyEdits(edits)
                self.lastError = nil
            } catch {
                self.lastError = error.localizedDescription
                self.state = SettingsState(config: config) // Revert the UI to the config that is actually active
            }
        }
    }
}
