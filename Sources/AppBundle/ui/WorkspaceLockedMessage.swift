import AppKit

func workspaceLockedMessage(_ name: String) -> String { "这个空间已经锁定（\(name)）" }

@MainActor
func showWorkspaceLocked(_ workspace: Workspace) {
    let alert = NSAlert()
    alert.messageText = workspaceLockedMessage(workspace.name)
    alert.informativeText = "请先解锁空间，再移动窗口。"
    alert.alertStyle = .informational
    alert.addButton(withTitle: "好")
    alert.runModal()
}
