import AppKit

func workspaceLockedMessage(_ name: String) -> String { L("This space is locked (%@)", name) }

@MainActor
func showWorkspaceLocked(_ workspace: Workspace) {
    let alert = NSAlert()
    alert.messageText = workspaceLockedMessage(workspace.name)
    alert.informativeText = L("Please unlock the space before moving windows.")
    alert.alertStyle = .informational
    alert.addButton(withTitle: L("OK"))
    alert.runModal()
}
