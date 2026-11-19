#if os(iOS)
import SwiftUI
import UIKit

/// The Home Screen icon: Benchy, or one of the alternates. Each is an Icon Composer
/// document with light, dark and tinted forms (tools/icons/build_icons.py); the
/// previews here are rendered from the same files.
struct AppIconPicker: View {
    struct Option: Identifiable {
        /// The alternate icon's name, or nil for the primary icon.
        let iconName: String?
        let title: String
        let preview: String
        var id: String { iconName ?? "default" }
    }

    static let options: [Option] = [
        Option(iconName: nil, title: "Benchy", preview: "IconPreview-AppIcon"),
        Option(iconName: "AppIcon-Mesh", title: String(localized: "Mesh", comment: "Name of the wireframe app icon"), preview: "IconPreview-AppIcon-Mesh"),
    ]

    @State private var current: String?
    @State private var failure: String?

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            ForEach(Self.options) { option in
                let selected = current == option.iconName
                Button {
                    choose(option)
                } label: {
                    VStack(spacing: Spacing.snug) {
                        Image(option.preview)
                            .resizable()
                            .scaledToFit()
                            .frame(width: Size.iconPreview, height: Size.iconPreview)
                        Text(option.title)
                            .font(.caption)
                            .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        Image(systemName: selected ? Symbol.choiceOn : Symbol.choiceOff)
                            .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(option.title) icon")
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.vertical, Spacing.xs)
        .onAppear { current = UIApplication.shared.alternateIconName }
        .errorAlert("Couldn't Change the Icon", message: $failure)
    }

    private func choose(_ option: Option) {
        guard option.iconName != current else { return }
        Task { @MainActor in
            do {
                try await UIApplication.shared.setAlternateIconName(option.iconName)
                current = option.iconName
            } catch {
                failure = String(localized: "iOS didn't accept the change. Try again in a moment.")
            }
        }
    }
}
#endif
