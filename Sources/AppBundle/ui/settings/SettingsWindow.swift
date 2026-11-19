import AppKit
import Combine
import Common
import SwiftUI

public let settingsWindowId = "\(aeroSpaceAppName).settingsView"

@MainActor
public func getSettingsWindow(viewModel: TrayMenuModel) -> some Scene {
    SwiftUI.Window(L("Settings"), id: settingsWindowId) {
        SettingsView()
            .environmentObject(viewModel)
            .frame(minWidth: 760, minHeight: 560)
            .onAppear {
                // AeroSpace is an agent app (LSUIElement). Make sure the window can take keyboard focus
                NSApp.setActivationPolicy(.accessory)
                NSApp.activate(ignoringOtherApps: true)
            }
    }
    .windowResizability(.contentMinSize)
    .defaultSize(width: 860, height: 660)
}

private enum SettingsCategory: String, CaseIterable, Identifiable {
    case general, layout, gaps, apps, automation, advanced

    var id: String { rawValue }

    var title: String {
        switch self {
            case .general: L("General")
            case .layout: L("Layout")
            case .gaps: L("Gaps")
            case .apps: L("Applications")
            case .automation: L("Rules & Automation")
            case .advanced: L("Advanced")
        }
    }

    var icon: String {
        switch self {
            case .general: "gearshape"
            case .layout: "rectangle.split.2x2"
            case .gaps: "rectangle.inset.filled"
            case .apps: "square.grid.2x2"
            case .automation: "keyboard.badge.ellipsis"
            case .advanced: "slider.horizontal.3"
        }
    }
}

private struct SettingsView: View {
    @ObservedObject private var model = SettingsViewModel.shared
    @EnvironmentObject private var trayModel: TrayMenuModel
    @State private var selection: SettingsCategory? = .general
    @AppStorage("airspace.language") private var language = AppLanguage.system.rawValue

    var body: some View {
        HStack(spacing: 0) {
            List(SettingsCategory.allCases, selection: $selection) { category in
                Label(category.title, systemImage: category.icon)
                    .tag(category)
            }
            .listStyle(.sidebar)
            .frame(width: 196)
            .frame(maxHeight: .infinity)

            Divider()

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    @ViewBuilder private var detail: some View {
        switch selection ?? .general {
            case .general: generalPage
            case .layout: layoutPage
            case .gaps: gapsPage
            case .apps: appsPage
            case .automation: automationPage
            case .advanced: advancedPage
        }
    }

    // MARK: pages

    private var generalPage: some View {
        SettingsPage(
            title: L("General"),
            subtitle: L("How AirSpace starts, responds to config changes, and follows the pointer."),
        ) {
            Picker(L("Language"), selection: $language) {
                ForEach(AppLanguage.allCases) { option in
                    Text(option.displayName).tag(option.rawValue)
                }
            }
            SettingsCard {
                Circle()
                    .fill(trayModel.isEnabled ? Color.green : Color.orange)
                    .frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(trayModel.isEnabled ? L("AirSpace is active") : L("AirSpace is paused"))
                        .font(.headline)
                    Text(trayModel.isEnabled ? L("Windows are tiled and shortcuts are available.") : L("Windows keep their current positions and shortcuts are disabled."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Button(trayModel.isEnabled ? L("Pause") : L("Resume")) {
                    Task.startUnstructured {
                        try await runLightSession(.menuBarButton, .forceRun) {
                            _ = await EnableCommand(
                                args: EnableCmdArgs(rawArgs: [], targetState: .toggle),
                            ).run(.defaultEnv, .emptyStdin)
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(trayModel.isEnabled ? .orange : .accentColor)
            }
            SettingsToggleCard(
                icon: "power",
                title: L("Start at login"),
                subtitle: L("Launch AirSpace automatically when you sign in."),
                isOn: model.binding(\.startAtLogin) { .bool(["start-at-login"], $0) },
            )
            SettingsToggleCard(
                icon: "arrow.triangle.2.circlepath",
                title: L("Auto-reload config"),
                subtitle: L("Apply edits to the config file as soon as they are saved."),
                isOn: model.binding(\.autoReloadConfig) { .bool(["auto-reload-config"], $0) },
            )
            SettingsToggleCard(
                icon: "rectangle.stack.badge.clock",
                title: L("Restore window spaces on restart"),
                subtitle: L("Return open windows to their previous spaces when AirSpace starts."),
                isOn: model.binding(\.restoreWindowWorkspaces) { .bool(["restore-window-workspaces"], $0) },
            )
            SettingsToggleCard(
                icon: "eye",
                title: L("Unhide macOS hidden apps"),
                subtitle: L("Show windows of hidden apps when AirSpace focuses them."),
                isOn: model.binding(\.automaticallyUnhideMacosHiddenApps) { .bool(["automatically-unhide-macos-hidden-apps"], $0) },
            )
            SettingsToggleCard(
                icon: "cursorarrow.rays",
                title: L("Focus follows mouse"),
                subtitle: L("Move focus to the window under the pointer without clicking."),
                isOn: model.binding(\.focusFollowsMouse) { .bool(["focus-follows-mouse", "enabled"], $0) },
            )
            SettingsInfoCard(
                icon: "menubar.rectangle",
                title: L("Menu bar"),
                text: L("The menu bar shows the current space and up to three window icons on macOS 14 or later."),
            )
            errorBanner
        }
    }

    private var layoutPage: some View {
        SettingsPage(
            title: L("Layout"),
            subtitle: L("Choose how new workspaces arrange windows. Changes apply to the next layout pass."),
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L("Default layout"))
                    .font(.subheadline.weight(.medium))
                HStack(spacing: 12) {
                    LayoutChoiceCard(
                        layout: .tiles,
                        title: L("Tiles"),
                        subtitle: L("Each window gets its own share of the space."),
                        isSelected: model.state.defaultRootContainerLayout == .tiles,
                    ) {
                        model.binding(\.defaultRootContainerLayout) { .string(["default-root-container-layout"], $0.rawValue) }
                            .wrappedValue = .tiles
                    }
                    LayoutChoiceCard(
                        layout: .accordion,
                        title: L("Accordion"),
                        subtitle: L("Windows stack; the focused window comes forward."),
                        isSelected: model.state.defaultRootContainerLayout == .accordion,
                    ) {
                        model.binding(\.defaultRootContainerLayout) { .string(["default-root-container-layout"], $0.rawValue) }
                            .wrappedValue = .accordion
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(L("Orientation"))
                    .font(.subheadline.weight(.medium))
                SettingsCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker(
                            L("Orientation"),
                            selection: model.binding(\.defaultRootContainerOrientation) { .string(["default-root-container-orientation"], $0.rawValue) },
                        ) {
                            Label(L("Auto"), systemImage: "wand.and.stars").tag(DefaultContainerOrientation.auto)
                            Label(L("Horizontal"), systemImage: "arrow.left.and.right").tag(DefaultContainerOrientation.horizontal)
                            Label(L("Vertical"), systemImage: "arrow.up.and.down").tag(DefaultContainerOrientation.vertical)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        Text(orientationCaption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            SettingsSliderCard(
                icon: "rectangle.stack",
                title: L("Accordion padding"),
                subtitle: L("Overlap between stacked windows. Only used by accordion containers."),
                value: model.binding(\.accordionPadding) { .int(["accordion-padding"], $0) },
                range: 0...500,
                unit: "px",
                isEnabled: model.state.defaultRootContainerLayout == .accordion,
            )

            SettingsToggleCard(
                icon: "rectangle.compress.vertical",
                title: L("Flatten nested containers"),
                subtitle: L("Collapse redundant containers with a single child so layouts stay simple."),
                isOn: model.binding(\.flattenContainersNormalization) { .bool(["enable-normalization-flatten-containers"], $0) },
            )
            SettingsToggleCard(
                icon: "arrow.triangle.branch",
                title: L("Alternate nested orientation"),
                subtitle: L("Nest containers with the opposite orientation to keep divisions readable."),
                isOn: model.binding(\.oppositeOrientationNormalization) { .bool(["enable-normalization-opposite-orientation-for-nested-containers"], $0) },
            )
            errorBanner
        }
    }

    private var orientationCaption: String {
        switch model.state.defaultRootContainerOrientation {
            case .auto: L("AirSpace picks the orientation that fits the monitor.")
            case .horizontal: L("Windows are arranged side by side.")
            case .vertical: L("Windows are stacked from top to bottom.")
        }
    }

    private var gapsPage: some View {
        SettingsPage(
            title: L("Gaps"),
            subtitle: L("Space between windows and around the edges of each monitor."),
        ) {
            GapsDiagram(
                innerHorizontal: Double(model.state.gapsInnerHorizontal ?? 0),
                innerVertical: Double(model.state.gapsInnerVertical ?? 0),
                outerLeft: Double(model.state.gapsOuterLeft ?? 0),
                outerTop: Double(model.state.gapsOuterTop ?? 0),
                outerRight: Double(model.state.gapsOuterRight ?? 0),
                outerBottom: Double(model.state.gapsOuterBottom ?? 0),
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(L("Inner gap presets"))
                    .font(.subheadline.weight(.medium))
                HStack(spacing: 8) {
                    ForEach([4, 8, 12, 16], id: \.self) { preset in
                        GapPresetChip(
                            value: preset,
                            isSelected: model.state.gapsInnerVertical == preset && model.state.gapsInnerHorizontal == preset,
                        ) {
                            setInnerGaps(preset)
                        }
                    }
                }
                Text(L("Presets set a single value for every monitor."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GapRow(
                icon: "arrow.left.and.right",
                title: L("Inner horizontal"),
                value: model.state.gapsInnerHorizontal,
                range: 0...500,
                onChange: { model.intBinding(\.gapsInnerHorizontal, path: ["gaps", "inner", "horizontal"], range: 0...500).wrappedValue = $0 },
            )
            GapRow(
                icon: "arrow.up.and.down",
                title: L("Inner vertical"),
                value: model.state.gapsInnerVertical,
                range: 0...500,
                onChange: { model.intBinding(\.gapsInnerVertical, path: ["gaps", "inner", "vertical"], range: 0...500).wrappedValue = $0 },
            )
            GapRow(
                icon: "arrow.left",
                title: L("Outer left"),
                value: model.state.gapsOuterLeft,
                range: -500...500,
                onChange: { model.intBinding(\.gapsOuterLeft, path: ["gaps", "outer", "left"], range: -500...500).wrappedValue = $0 },
            )
            GapRow(
                icon: "arrow.up",
                title: L("Outer top"),
                value: model.state.gapsOuterTop,
                range: -500...500,
                onChange: { model.intBinding(\.gapsOuterTop, path: ["gaps", "outer", "top"], range: -500...500).wrappedValue = $0 },
            )
            GapRow(
                icon: "arrow.down",
                title: L("Outer bottom"),
                value: model.state.gapsOuterBottom,
                range: -500...500,
                onChange: { model.intBinding(\.gapsOuterBottom, path: ["gaps", "outer", "bottom"], range: -500...500).wrappedValue = $0 },
            )
            GapRow(
                icon: "arrow.right",
                title: L("Outer right"),
                value: model.state.gapsOuterRight,
                range: -500...500,
                onChange: { model.intBinding(\.gapsOuterRight, path: ["gaps", "outer", "right"], range: -500...500).wrappedValue = $0 },
            )
            ConfigSectionButton(section: .gaps, icon: "display")
            errorBanner
        }
    }

    private var appsPage: some View {
        SettingsPage(
            title: L("Applications"),
            subtitle: L("Set per-app behavior. Changes apply right away to eligible windows and are saved for new windows."),
        ) {
            RunningApplicationsSettings()
            SettingsSectionHeader(L("Detailed rules"))
            ConfigSectionButton(section: .windowRules, icon: "list.bullet.rectangle")
        }
    }

    private var automationPage: some View {
        SettingsPage(
            title: L("Rules & Automation"),
            subtitle: L("Keyboard shortcuts, workspaces, monitors, and commands that run on events."),
        ) {
            SettingsSectionHeader(L("Keyboard"))
            ForEach(ConfigSection.shortcuts) { section in
                ConfigSectionButton(section: section, icon: "keyboard")
            }
            SettingsSectionHeader(L("Workspaces & monitors"))
            ForEach(ConfigSection.workspaces) { section in
                ConfigSectionButton(section: section, icon: "rectangle.3.group")
            }
            SettingsSectionHeader(L("Automation"))
            ForEach(ConfigSection.automation) { section in
                ConfigSectionButton(section: section, icon: "bolt")
            }
            errorBanner
        }
    }

    private var advancedPage: some View {
        SettingsPage(
            title: L("Advanced"),
            subtitle: L("The underlying config file, version, and app information."),
        ) {
            SettingsCard {
                SettingsIconTile(systemName: "doc.text")
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Configuration file")).font(.body.weight(.medium))
                    Text(configUrl.path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                    HStack(spacing: 8) {
                        Button(L("Open in Editor")) { openConfigInTextEditor() }
                            .buttonStyle(.bordered)
                        Button(L("Reload Now")) { reloadConfig() }
                            .buttonStyle(.bordered)
                        if trayModel.lastReloadConfigContainedWarnings {
                            Button(L("Show Warnings")) { showConfigWarnings() }
                                .buttonStyle(.bordered)
                                .tint(.orange)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            ConfigSectionButton(section: .version, icon: "number.circle")
            SettingsCard {
                Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                    .resizable()
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(aeroSpaceAppName) v\(aeroSpaceAppVersion)")
                        .font(.body.weight(.medium))
                    Text(gitShortHash)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 12)
                Button(L("Copy Version")) {
                    "\(aeroSpaceAppName) v\(aeroSpaceAppVersion) \(gitHash)".copyToClipboard()
                }
                .buttonStyle(.bordered)
            }
            HStack(spacing: 8) {
                Button(L("Sponsor AeroSpace")) {
                    NSWorkspace.shared.open(URL(string: "https://github.com/sponsors/nikitabobko").orDie())
                }
                .buttonStyle(.bordered)
                Spacer()
                Button("Quit \(aeroSpaceAppName)") {
                    Task.startUnstructured {
                        terminationHandler?.beforeTermination()
                        terminateApp()
                    }
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
            errorBanner
        }
    }

    @ViewBuilder private var errorBanner: some View {
        if let lastError = model.lastError {
            SettingsErrorBanner(message: lastError)
        }
    }

    private func setInnerGaps(_ value: Int) {
        model.intBinding(\.gapsInnerVertical, path: ["gaps", "inner", "vertical"], range: 0...500).wrappedValue = value
        model.intBinding(\.gapsInnerHorizontal, path: ["gaps", "inner", "horizontal"], range: 0...500).wrappedValue = value
    }

    private func reloadConfig() {
        guard let token: RunSessionGuard = .isServerEnabled else { return }
        Task.startUnstructured {
            try await runLightSession(.menuBarButton, token) {
                _ = await reloadConfig_nonCancellable()
            }
        }
    }

    private func showConfigWarnings() {
        guard let token: RunSessionGuard = .isServerEnabled else { return }
        Task.startUnstructured {
            try await runLightSession(.menuBarButton, token) {
                let args = ReloadConfigCmdArgs(rawArgs: []).with(\.warningsAsErrors, true)
                _ = await reloadConfig_nonCancellable(args: args)
            }
        }
    }
}

// MARK: - page scaffolding

private struct SettingsPage<Content: View>: View {
    let title: String
    let subtitle: String
    let content: Content

    init(title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.largeTitle.bold())
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, 6)
                content
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

private struct SettingsSectionHeader: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 6)
            .padding(.leading, 2)
    }
}

struct SettingsCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 12) { content }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07)),
            )
    }

    private var cardBackground: Color {
        Color(nsColor: .controlBackgroundColor)
    }
}

struct SettingsIconTile: View {
    let systemName: String
    var tint: Color = .accentColor

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 28, height: 28)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

struct SettingsRowLabel: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 12) {
            SettingsIconTile(systemName: icon, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct SettingsToggleCard: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        SettingsCard {
            SettingsRowLabel(icon: icon, title: title, subtitle: subtitle)
            Spacer(minLength: 12)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}

private struct SettingsSliderCard: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var unit: String = ""
    var isEnabled: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SettingsRowLabel(icon: icon, title: title, subtitle: subtitle)
                Spacer(minLength: 12)
                Text("\(value)\(unit.isEmpty ? "" : " \(unit)")")
                    .font(.system(.caption, design: .monospaced).weight(.medium))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.06), in: Capsule())
            }
            Slider(
                value: Binding(get: { Double(value) }, set: { value = Int($0.rounded()) }),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: 1,
            )
            .disabled(!isEnabled)
            .opacity(isEnabled ? 1 : 0.45)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07)),
        )
    }
}

private struct GapRow: View {
    let icon: String
    let title: String
    let value: Int?
    let range: ClosedRange<Int>
    let onChange: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SettingsRowLabel(icon: icon, title: title)
                Spacer(minLength: 12)
                if let value {
                    Text("\(value) px")
                        .font(.system(.caption, design: .monospaced).weight(.medium))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                } else {
                    Text(L("Per monitor"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }
            }
            if let value {
                Slider(
                    value: Binding(get: { Double(value) }, set: { onChange(Int($0.rounded())) }),
                    in: Double(range.lowerBound)...Double(range.upperBound),
                    step: 1,
                )
            } else {
                Text(L("This gap is set separately for each monitor. Use Gaps by Monitor below to change it."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07)),
        )
    }
}

private struct GapPresetChip: View {
    let value: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("\(value) px")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    isSelected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.05),
                    in: Capsule(),
                )
                .overlay(
                    Capsule().strokeBorder(isSelected ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.08)),
                )
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsInfoCard: View {
    let icon: String
    let title: String
    let text: String

    var body: some View {
        SettingsCard {
            SettingsIconTile(systemName: icon, tint: .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct SettingsErrorBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.red.opacity(0.2)),
        )
    }
}

// MARK: - diagrams

private struct LayoutChoiceCard: View {
    let layout: Layout
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                LayoutDiagram(layout: layout, orientation: .horizontal)
                    .frame(height: 62)
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.body.weight(.semibold))
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 6)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.5))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? Color.accentColor.opacity(0.08) : Color.primary.opacity(isHovered ? 0.05 : 0.025),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous),
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.8) : Color.primary.opacity(0.08), lineWidth: isSelected ? 1.5 : 1),
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

private struct LayoutDiagram: View {
    let layout: Layout
    let orientation: DefaultContainerOrientation

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let gap: CGFloat = 3
            switch layout {
                case .tiles:
                    if orientation == .vertical {
                        VStack(spacing: gap) {
                            bar(width: width, height: (height - gap * 2) / 3, opacity: 0.45)
                            bar(width: width, height: (height - gap * 2) / 3, opacity: 0.3)
                            bar(width: width, height: (height - gap * 2) / 3, opacity: 0.22)
                        }
                    } else {
                        HStack(spacing: gap) {
                            bar(width: (width - gap * 2) / 3, height: height, opacity: 0.45)
                            bar(width: (width - gap * 2) / 3, height: height, opacity: 0.3)
                            bar(width: (width - gap * 2) / 3, height: height, opacity: 0.22)
                        }
                    }
                case .accordion:
                    let barWidth = width * 0.66
                    let offset = (width - barWidth) / 2
                    ZStack(alignment: .leading) {
                        bar(width: barWidth, height: height, opacity: 0.22).offset(x: offset)
                        bar(width: barWidth, height: height, opacity: 0.3).offset(x: offset / 2)
                        bar(width: barWidth, height: height, opacity: 0.45)
                    }
            }
        }
        .animation(.smooth(duration: 0.2), value: orientation)
    }

    private func bar(width: CGFloat, height: CGFloat, opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color.accentColor.opacity(opacity))
            .frame(width: max(0, width), height: max(0, height))
    }
}

private struct GapsDiagram: View {
    let innerHorizontal: Double
    let innerVertical: Double
    let outerLeft: Double
    let outerTop: Double
    let outerRight: Double
    let outerBottom: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SettingsIconTile(systemName: "rectangle.inset.filled")
                Text(L("Preview")).font(.body.weight(.medium))
                Spacer()
                Text("Inner \(Int(innerHorizontal))×\(Int(innerVertical)) · Outer \(Int(outerLeft))/\(Int(outerTop))/\(Int(outerBottom))/\(Int(outerRight))")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                let width = geo.size.width
                let height = geo.size.height
                let left = previewOuter(outerLeft)
                let top = previewOuter(outerTop)
                let right = previewOuter(outerRight)
                let bottom = previewOuter(outerBottom)
                let hGap = previewInner(innerHorizontal, along: width)
                let vGap = previewInner(innerVertical, along: height)
                let contentWidth = max(0, width - left - right)
                let contentHeight = max(0, height - top - bottom)
                let windowWidth = max(0, (contentWidth - hGap) / 2)
                let windowHeight = max(0, (contentHeight - vGap) / 2)
                VStack(spacing: vGap) {
                    HStack(spacing: hGap) {
                        previewWindow(width: windowWidth, height: windowHeight, opacity: 0.4)
                        previewWindow(width: windowWidth, height: windowHeight, opacity: 0.25)
                    }
                    HStack(spacing: hGap) {
                        previewWindow(width: windowWidth, height: windowHeight, opacity: 0.25)
                        previewWindow(width: windowWidth, height: windowHeight, opacity: 0.16)
                    }
                }
                .padding(EdgeInsets(top: top, leading: left, bottom: bottom, trailing: right))
            }
            .frame(height: 120)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07)),
        )
        .animation(.smooth(duration: 0.2), value: innerHorizontal)
        .animation(.smooth(duration: 0.2), value: innerVertical)
        .animation(.smooth(duration: 0.2), value: outerLeft)
        .animation(.smooth(duration: 0.2), value: outerTop)
        .animation(.smooth(duration: 0.2), value: outerRight)
        .animation(.smooth(duration: 0.2), value: outerBottom)
    }

    private func previewWindow(width: CGFloat, height: CGFloat, opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color.accentColor.opacity(opacity))
            .frame(width: max(0, width), height: max(0, height))
    }

    private func previewOuter(_ value: Double) -> CGFloat {
        CGFloat(min(max(value, 0), 24))
    }

    private func previewInner(_ value: Double, along size: CGFloat) -> CGFloat {
        min(CGFloat(min(max(value, 0), 24)), max(0, size / 6))
    }
}

// MARK: - running applications

private struct RunningApplicationsSettings: View {
    @EnvironmentObject private var trayModel: TrayMenuModel
    @State private var apps: [NSRunningApplication] = []
    @State private var search = ""
    @State private var rules: [OrderedJson] = []
    @State private var error: String?
    @State private var busyAppID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            searchField
            if let error {
                SettingsErrorBanner(message: error)
            }
            if filteredApps.isEmpty {
                SettingsCard {
                    SettingsIconTile(systemName: "magnifyingglass", tint: .secondary)
                    Text("No running applications match “\(search)”.")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(filteredApps, id: \.processIdentifier) { app in
                    if let id = app.bundleIdentifier {
                        appRow(app, id: id)
                    }
                }
            }
            Text("Auto leaves the app to your other rules. Other rules can still affect the final layout; changing a mode may reformat the window rules section.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
        .onAppear { refresh() }
        .onChange(of: trayModel.configReloadEpoch) { _, _ in loadRules() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in refreshApps() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in refreshApps() }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(L("Search applications"), text: $search)
                .textFieldStyle(.plain)
            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08)),
        )
    }

    private func appRow(_ app: NSRunningApplication, id: String) -> some View {
        let windowCount = windowIDs(app).count
        return SettingsCard {
            Group {
                if let icon = app.icon {
                    Image(nsImage: icon).resizable().frame(width: 30, height: 30)
                } else {
                    SettingsIconTile(systemName: "app.dashed")
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(app.localizedName ?? id)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(windowCount == 1 ? "1 managed window" : "\(windowCount) managed windows")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if busyAppID == id {
                ProgressView().controlSize(.small)
            }
            Picker(
                L("Window mode"),
                selection: Binding(
                    get: { mode(for: id) },
                    set: { setMode($0, for: app) },
                ),
            ) {
                Text(L("Auto")).tag("default")
                Text(L("Float")).tag("floating")
                Text(L("Tile")).tag("tiling")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 168)
            .disabled(busyAppID != nil)
        }
    }

    private var filteredApps: [NSRunningApplication] {
        apps.filter {
            search.isEmpty ||
                ($0.localizedName ?? "").localizedCaseInsensitiveContains(search) ||
                ($0.bundleIdentifier ?? "").localizedCaseInsensitiveContains(search)
        }
    }

    private func refreshApps() {
        var seen = Set<String>()
        apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.bundleIdentifier.map { seen.insert($0).inserted } == true
        }.sorted { ($0.localizedName ?? "").localizedStandardCompare($1.localizedName ?? "") == .orderedAscending }
    }

    private func refresh() {
        refreshApps()
        loadRules()
    }

    private func loadRules() {
        do {
            let value = try ConfigFileEditor.readSection("on-window-detected").value
            rules = value?.asArrayOrNil ?? []
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Only rules with this exact shape belong to this control; leave complex rules untouched.
    private func managedMode(_ rule: OrderedJson, appID: String) -> String? {
        guard let dict = rule.asDictOrNil, dict.count == 3,
              let match = dict["if"]?.asDictOrNil, match.count == 1,
              match["app-id"] == .string(appID),
              dict["check-further-callbacks"] == .bool(true),
              let command = dict["run"]?.asArrayOrNil, command.count == 1,
              let value = command[0].asStringOrNil,
              value == "layout floating" || value == "layout tiling" else { return nil }
        return value == "layout floating" ? "floating" : "tiling"
    }

    private func mode(for id: String) -> String {
        rules.compactMap { managedMode($0, appID: id) }.first ?? "default"
    }

    private func windowIDs(_ app: NSRunningApplication) -> [OpaqueWindowId] {
        // Include all processes with the same bundle identifier.
        let pids = Set(NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == app.bundleIdentifier }.map(\.processIdentifier))
        return trayModel.workspaces.flatMap(\.apps).filter { pids.contains($0.id) }.flatMap(\.windowIDs)
    }

    private func setMode(_ mode: String, for app: NSRunningApplication) {
        guard let id = app.bundleIdentifier else { return }
        busyAppID = id
        Task.startUnstructured {
            defer { busyAppID = nil }
            do {
                let snapshot = try ConfigFileEditor.readSection("on-window-detected")
                var updated = snapshot.value?.asArrayOrNil ?? []
                updated.removeAll { managedMode($0, appID: id) != nil }
                if mode != "default" {
                    updated.insert(.dict([
                        "if": .dict(["app-id": .string(id)]),
                        "run": .array([.string("layout \(mode)")]),
                        "check-further-callbacks": .bool(true),
                    ]), at: 0)
                }
                try await ConfigFileEditor.saveSection("on-window-detected", value: updated.isEmpty ? nil : .array(updated), original: snapshot)
                rules = updated
                error = nil
                guard mode != "default" else { return }
                guard let token: RunSessionGuard = .isServerEnabled else {
                    error = L("Saved for new windows. Enable AirSpace to change existing windows.")
                    return
                }
                let ids = windowIDs(app)
                var failures = 0
                try await runLightSession(.menuBarButton, token) {
                    for windowID in ids {
                        var args = LayoutCmdArgs(rawArgs: [], toggleBetween: [mode == "floating" ? .floating : .tiling])
                        args.windowId = windowID
                        if await LayoutCommand(args: args).run(.defaultEnv, CmdIoImpl.emptyStdinIgnoringOut) != .succ {
                            failures += 1
                        }
                    }
                }
                if failures > 0 {
                    error = "Saved for new windows, but \(failures) existing windows could not be changed (for example, minimized or fullscreen windows)."
                }
            } catch {
                self.error = error.localizedDescription
                loadRules()
            }
        }
    }
}
