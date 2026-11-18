import SwiftUI

/// Quick access to the most common settings from the menu bar dropdown
@MainActor
func quickSettingsMenu() -> some View {
    Menu {
        QuickSettingsMenuContent()
    } label: {
        Label("Settings", systemImage: "gearshape")
    }
}

private struct QuickSettingsMenuContent: View {
    @ObservedObject private var model = SettingsViewModel.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Toggle("Start at login", isOn: model.binding(\.startAtLogin) { .bool(["start-at-login"], $0) })
        Toggle("Auto-reload config", isOn: model.binding(\.autoReloadConfig) { .bool(["auto-reload-config"], $0) })
        Toggle("Focus follows mouse", isOn: model.binding(\.focusFollowsMouse) { .bool(["focus-follows-mouse", "enabled"], $0) })
        Divider()
        Button("All Settings…") { openWindow(id: settingsWindowId) }
    }
}
