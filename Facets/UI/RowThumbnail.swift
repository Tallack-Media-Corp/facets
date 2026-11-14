import SwiftUI

/// The picture at the start of a list row (a model's thumbnail, a folder), one size
/// and shape in every list: the library, Recents and Recently Deleted.
struct RowThumbnail<Content: View>: View {
    /// Grows with the text, up to a point, so the picture still reads beside big type.
    @ScaledMetric(relativeTo: .headline) private var size: CGFloat = 52
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(width: min(size, 88), height: min(size, 88))
            .clipShape(.rect(cornerRadius: 10))
    }
}
