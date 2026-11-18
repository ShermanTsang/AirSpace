import Common
import SwiftUI

public let settingsWindowId = "\(aeroSpaceAppName).settingsView"

@MainActor
public func getSettingsWindow(viewModel: TrayMenuModel) -> some Scene {
    SwiftUI.Window("Settings", id: settingsWindowId) {
        SettingsView()
            .environmentObject(viewModel)
            .frame(minWidth: 520, minHeight: 480)
            .onAppear {
                // AeroSpace is an agent app (LSUIElement). Make sure the window can take keyboard focus
                NSApp.setActivationPolicy(.accessory)
                NSApp.activate(ignoringOtherApps: true)
            }
    }
    .windowResizability(.contentMinSize)
    .defaultSize(width: 560, height: 700)
}

private struct SettingsView: View {
    @ObservedObject private var model = SettingsViewModel.shared

    var body: some View {
        Form {
            generalSection
            layoutSection
            gapsSection
            mouseSection
            configFileSection
            if let lastError = model.lastError {
                Section {
                    Label(lastError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var generalSection: some View {
        Section {
            Toggle(
                "Start at login",
                isOn: model.binding(\.startAtLogin) { .bool(["start-at-login"], $0) },
            )
            Toggle(
                "Auto-reload config on change",
                isOn: model.binding(\.autoReloadConfig) { .bool(["auto-reload-config"], $0) },
            )
            Toggle(
                "Automatically unhide macOS hidden apps",
                isOn: model.binding(\.automaticallyUnhideMacosHiddenApps) { .bool(["automatically-unhide-macos-hidden-apps"], $0) },
            )
        } header: {
            Text("General")
        }
    }

    private var layoutSection: some View {
        Section {
            Picker(
                "Default layout",
                selection: model.binding(\.defaultRootContainerLayout) { .string(["default-root-container-layout"], $0.rawValue) },
            ) {
                Text("Tiles").tag(Layout.tiles)
                Text("Accordion").tag(Layout.accordion)
            }
            Picker(
                "Default orientation",
                selection: model.binding(\.defaultRootContainerOrientation) { .string(["default-root-container-orientation"], $0.rawValue) },
            ) {
                Text("Auto").tag(DefaultContainerOrientation.auto)
                Text("Horizontal").tag(DefaultContainerOrientation.horizontal)
                Text("Vertical").tag(DefaultContainerOrientation.vertical)
            }
            IntSettingRow(
                title: "Accordion padding",
                value: model.binding(\.accordionPadding) { .int(["accordion-padding"], $0) },
                range: 0...500,
            )
            Toggle(
                "Normalization: flatten containers",
                isOn: model.binding(\.flattenContainersNormalization) { .bool(["enable-normalization-flatten-containers"], $0) },
            )
            Toggle(
                "Normalization: opposite orientation for nested containers",
                isOn: model.binding(\.oppositeOrientationNormalization) { .bool(["enable-normalization-opposite-orientation-for-nested-containers"], $0) },
            )
        } header: {
            Text("Layout")
        }
    }

    private var gapsSection: some View {
        Section {
            gapRow("Inner vertical", \.gapsInnerVertical, ["gaps", "inner", "vertical"], 0...500)
            gapRow("Inner horizontal", \.gapsInnerHorizontal, ["gaps", "inner", "horizontal"], 0...500)
            gapRow("Outer left", \.gapsOuterLeft, ["gaps", "outer", "left"], -500...500)
            gapRow("Outer top", \.gapsOuterTop, ["gaps", "outer", "top"], -500...500)
            gapRow("Outer bottom", \.gapsOuterBottom, ["gaps", "outer", "bottom"], -500...500)
            gapRow("Outer right", \.gapsOuterRight, ["gaps", "outer", "right"], -500...500)
        } header: {
            Text("Gaps (pixels)")
        } footer: {
            Text("Per-monitor gaps can be edited in the config file.")
        }
    }

    private var mouseSection: some View {
        Section {
            Toggle(
                "Focus follows mouse",
                isOn: model.binding(\.focusFollowsMouse) { .bool(["focus-follows-mouse", "enabled"], $0) },
            )
        } header: {
            Text("Mouse")
        }
    }

    private var configFileSection: some View {
        Section {
            LabeledContent("File") {
                Text(configUrl.path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            HStack {
                Button("Open in Editor") { openConfigInTextEditor() }
                Button("Reload Now") { reloadConfig() }
            }
        } header: {
            Text("Config file")
        } footer: {
            Text("Changes are applied immediately. The editor patches your config file in place, keeping comments and the settings it doesn't manage.")
        }
    }

    private func gapRow(
        _ title: String,
        _ keyPath: WritableKeyPath<SettingsState, Int?>,
        _ path: [String],
        _ range: ClosedRange<Int>,
    ) -> some View {
        IntSettingRow(
            title: title,
            value: model.intBinding(keyPath, path: path, range: range),
            range: range,
            isPerMonitor: model.state[keyPath: keyPath] == nil,
        )
    }

    private func reloadConfig() {
        guard let token: RunSessionGuard = .isServerEnabled else { return }
        Task.startUnstructured {
            try await runLightSession(.menuBarButton, token) {
                _ = await reloadConfig_nonCancellable()
            }
        }
    }
}

private struct IntSettingRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var isPerMonitor: Bool = false

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            if isPerMonitor {
                Text("Set per monitor in the config file")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                TextField("", value: $value, format: .number)
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 64)
                Stepper("", value: $value, in: range)
                    .labelsHidden()
            }
        }
    }
}
