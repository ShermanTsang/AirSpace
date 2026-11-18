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
    @EnvironmentObject private var trayModel: TrayMenuModel

    var body: some View {
        Form {
            generalSection
            menuBarSection
            layoutSection
            gapsSection
            mouseSection
            structuredSections
            configFileSection
            Section("About") {
                Text("\(aeroSpaceAppName) v\(aeroSpaceAppVersion) \(gitShortHash)")
                Button("Copy version information") { "\(aeroSpaceAppName) v\(aeroSpaceAppVersion) \(gitHash)".copyToClipboard() }
                Button("Sponsor upstream AeroSpace on GitHub") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/sponsors/nikitabobko").orDie())
                }
                Button("Quit \(aeroSpaceAppName)") {
                    Task.startUnstructured {
                        terminationHandler?.beforeTermination()
                        terminateApp()
                    }
                }
            }
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
            Button(trayModel.isEnabled ? "Pause AirSpace" : "Enable AirSpace") {
                Task.startUnstructured {
                    try await runLightSession(.menuBarButton, .forceRun) {
                        _ = await EnableCommand(args: EnableCmdArgs(rawArgs: [], targetState: .toggle)).run(.defaultEnv, .emptyStdin)
                    }
                }
            }
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

    private var menuBarSection: some View {
        Section {
            Picker("Workspace display style", selection: Binding(
                get: { trayModel.experimentalUISettings.displayStyle },
                set: { trayModel.experimentalUISettings.displayStyle = $0 },
            )) {
                ForEach(MenuBarStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            Text("The focused workspace shows up to three window icons on macOS 14 or later.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Menu bar")
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
            ConfigSectionButton(section: .gaps)
        } header: {
            Text("Gaps (pixels)")
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

    private var structuredSections: some View {
        Group {
            Section("Applications") { ConfigSectionButton(section: .windowRules) }
            Section("Keyboard") { ForEach(ConfigSection.shortcuts) { ConfigSectionButton(section: $0) } }
            Section("Workspaces and Monitors") { ForEach(ConfigSection.workspaces) { ConfigSectionButton(section: $0) } }
            Section("Automation") { ForEach(ConfigSection.automation) { ConfigSectionButton(section: $0) } }
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
            ConfigSectionButton(section: .version)
            if trayModel.lastReloadConfigContainedWarnings {
                Button("Show configuration warnings") {
                    guard let token: RunSessionGuard = .isServerEnabled else { return }
                    Task.startUnstructured {
                        try await runLightSession(.menuBarButton, token) {
                            let args = ReloadConfigCmdArgs(rawArgs: []).with(\.warningsAsErrors, true)
                            _ = await reloadConfig_nonCancellable(args: args)
                        }
                    }
                }
            }
            HStack {
                Button("Open in Editor") { openConfigInTextEditor() }
                Button("Reload Now") { reloadConfig() }
            }
        } header: {
            Text("Config file")
        } footer: {
            Text("Quick changes apply immediately. In detailed editors, select Save & Apply to commit your changes.")
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
                Text("Set per monitor using Gaps by Monitor")
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
