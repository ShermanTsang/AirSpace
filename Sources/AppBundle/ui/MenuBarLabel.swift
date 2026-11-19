import Common
import SwiftUI

@MainActor
struct MenuBarLabel: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var viewModel: TrayMenuModel

    private let itemSize: CGFloat = 40

    private var foreground: Color { colorScheme == .dark ? .white : .black }

    var body: some View {
        let workspace = viewModel.workspaces.first(where: \.isFocused)
        let abbreviation = workspace.map { spaceAbbreviation(of: $0.name) } ?? aeroSpaceAppName
        let label = Text(workspace?.name ?? aeroSpaceAppName)

        // On older versions, MenuBarExtra only supports the plain text label.
        if #available(macOS 14, *), let image = ImageRenderer(content: capsule(abbreviation: abbreviation)).cgImage {
            Image(image, scale: 2, label: label)
        } else {
            Text(abbreviation).accessibilityLabel(label)
        }
    }

    private func capsule(abbreviation: String) -> some View {
        HStack(spacing: 6) {
            Text(abbreviation)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(foreground)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(foreground.opacity(0.10), in: Capsule())

            ForEach(Array(viewModel.focusedWorkspaceIcons.enumerated()), id: \.offset) { _, icon in
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: itemSize, height: itemSize)
            }

            if viewModel.lastReloadConfigContainedWarnings {
                Image(systemName: "exclamationmark.triangle.fill")
                    .resizable()
                    .scaledToFit()
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(foreground)
                    .frame(width: 26, height: 26)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(foreground.opacity(0.15), in: Capsule())
        .overlay(Capsule().strokeBorder(foreground.opacity(0.18), lineWidth: 1))
    }
}

/// Shows short names as-is and uses the first character for longer names.
func spaceAbbreviation(of name: String) -> String {
    guard let first = name.first else { return name }
    return name.count <= 2 ? name : String(first).uppercased()
}
