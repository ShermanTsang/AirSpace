import AppKit
import Common
import Foundation

@MainActor
public enum SupportActions {
    public static func checkForUpdates() async {
        do {
            let response = try await WalnutClient.shared.checkForUpdate(
                versionCode: WalnutVersion.currentCode,
                locale: AppLanguage.selected.portalLocale,
            )
            if response.isAvailable {
                presentUpdate(response)
            } else {
                presentUpToDate()
            }
        } catch is CancellationError {
            return
        } catch {
            presentError(error.localizedDescription)
        }
    }

    /// Returns true when the action copied a value to the pasteboard.
    @discardableResult
    public static func perform(_ action: String, channel: WalnutClient.ContactChannel) -> Bool {
        switch action {
            case "call":
                open(channel.callURL)
            case "email":
                open(channel.emailURL)
            case "open":
                open(channel.openURL)
            case "qr":
                open(channel.qrURL)
            case "copy_value":
                return copy(channel.value)
            case "copy_link":
                return copy(channel.linkUrl)
            default:
                open(channel.openURL)
        }
        return false
    }

    private static func open(_ url: URL?) {
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }

    private static func copy(_ value: String?) -> Bool {
        guard let value = value?.nilIfBlank else { return false }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        return true
    }

    private static func presentUpdate(_ response: WalnutClient.ReleaseCheckResponse) {
        let alert = NSAlert()
        alert.alertStyle = response.forceUpdate == true ? .critical : .informational
        alert.messageText = response.forceUpdate == true
            ? L("A required update is available")
            : L("A new version is available")

        var lines: [String] = []
        if let version = response.version?.nilIfBlank {
            lines.append(L("Version %@ is available.", version))
        }
        if let note = response.releaseNote?.nilIfBlank {
            lines.append("")
            lines.append(String(note.prefix(1200)))
        }
        alert.informativeText = lines.joined(separator: "\n")

        let downloadURL = response.downloadURL
        alert.addButton(withTitle: downloadURL == nil ? L("OK") : L("Download"))
        if downloadURL != nil {
            alert.addButton(withTitle: L("Later"))
        }

        guard alert.runModal() == .alertFirstButtonReturn, let downloadURL else { return }
        NSWorkspace.shared.open(downloadURL)
    }

    private static func presentUpToDate() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L("You're up to date")
        alert.informativeText = L("AirSpace %@ is the latest version.", aeroSpaceAppVersion)
        alert.addButton(withTitle: L("OK"))
        alert.runModal()
    }

    private static func presentError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L("Unable to check for updates")
        alert.informativeText = message
        alert.addButton(withTitle: L("OK"))
        alert.runModal()
    }
}
