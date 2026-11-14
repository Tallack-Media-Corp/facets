import SwiftUI

/// A list row with a picture: the library's list and search results, Recents and
/// Recently Deleted. The picture, a title, a caption, optionally where the item is
/// (a search hit's folder) and something at the end (Restore). One behaviour for all:
/// the title takes one line, three at accessibility text sizes; VoiceOver reads the
/// words as one item without the picture; the whole row takes the tap.
struct ThumbnailRow<Thumbnail: View, Caption: View, Accessory: View>: View {
    let title: String
    /// A search hit's folder, lined up under the title.
    var location: String?
    @ViewBuilder let thumbnail: Thumbnail
    @ViewBuilder let caption: Caption
    @ViewBuilder let accessory: Accessory

    /// The picture grows with the text, up to a point, so it still reads beside big type.
    @ScaledMetric(relativeTo: .headline) private var scaledSide = Size.rowThumbnail
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var side: CGFloat { min(scaledSide, Size.rowThumbnailMax) }
    private var lineLimit: Int { dynamicTypeSize.isAccessibilitySize ? 3 : 1 }
    private var hasAccessory: Bool { Accessory.self != EmptyView.self }

    var body: some View {
        HStack(spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.hair) {
                HStack(spacing: Spacing.md) {
                    RowThumbnail(side: side) { thumbnail }
                        .accessibilityHidden(true)
                    // At accessibility sizes names wrap rather than truncate.
                    VStack(alignment: .leading, spacing: Spacing.rowText) {
                        Text(title)
                            .font(.headline)
                            .lineLimit(lineLimit)
                        caption
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(lineLimit)
                    }
                    Spacer(minLength: hasAccessory ? Spacing.sm : 0)
                }
                if let location {
                    Label(location, systemImage: Symbol.folder)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        // Under the title at every text size: the picture's width and the gap.
                        .padding(.leading, side + Spacing.md)
                }
            }
            .contentShape(.rect)
            .accessibilityElement(children: .combine)
            accessory
        }
    }
}

extension ThumbnailRow where Accessory == EmptyView {
    init(title: String, location: String? = nil, @ViewBuilder thumbnail: () -> Thumbnail, @ViewBuilder caption: () -> Caption) {
        self.init(title: title, location: location, thumbnail: thumbnail, caption: caption, accessory: { EmptyView() })
    }
}

/// The picture at the start of a `ThumbnailRow` (a model's thumbnail, a folder): one
/// size and shape in every list. The row sizes it, so text beneath can line up.
struct RowThumbnail<Content: View>: View {
    let side: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(width: side, height: side)
            .clipShape(.rect(cornerRadius: Radius.rowThumb))
    }
}
