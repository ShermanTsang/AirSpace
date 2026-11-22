import SwiftUI

/// Quick access to the most common settings from the menu bar dropdown
// periphery:ignore - WIP: not wired into the menu bar yet
@MainActor
func quickSettingsMenu() -> some View {
    Menu {
        QuickSettingsMenuContent()
    } label: {
        Label(L("Settings"), systemImage: "gearshape")
    }
}

private struct QuickSettingsMenuContent: View {
    @ObservedObject private var model = SettingsViewModel.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Toggle(L("Start at login"), isOn: model.binding(\.startAtLogin) { .bool(["start-at-login"], $0) })
        Toggle(L("Auto-reload config"), isOn: model.binding(\.autoReloadConfig) { .bool(["auto-reload-config"], $0) })
        Toggle(L("Focus follows mouse"), isOn: model.binding(\.focusFollowsMouse) { .bool(["focus-follows-mouse", "enabled"], $0) })
        Divider()
        Button(L("All Settings…")) { openWindow(id: settingsWindowId) }
    }
}
