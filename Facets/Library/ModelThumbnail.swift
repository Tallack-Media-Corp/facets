import SwiftUI

/// A model's rendered picture on a soft card, with a cube while it renders.
struct ModelThumbnail: View {
    let url: URL
    var size: Int64?
    var modified: Date?
    var cornerRadius: CGFloat = 14

    @Environment(\.displayScale) private var displayScale
    /// Optional: a context-menu preview is drawn outside the app's environment.
    @Environment(ViewerSettings.self) private var settings: ViewerSettings?
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        GeometryReader { geometry in
            let pixels = Self.pixelSize(for: geometry.size, scale: displayScale)
            let look = ThumbnailStore.Look(colorHex: settings?.colorHex ?? Palette.filamentOrange, usesFileColors: settings?.usesFileColors ?? true)
            let key = ThumbnailStore.key(for: url, size: size, modified: modified, pixelSize: pixels, look: look)
            ZStack {
                Rectangle().fill(.thumbnailBackground)
                if let image = image ?? ThumbnailStore.shared.cached(key) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(geometry.size.width * 0.08)
                } else {
                    Image(systemName: failed ? "exclamationmark.triangle" : "cube.transparent")
                        .font(.system(size: max(14, geometry.size.width * 0.28), weight: .light))
                        .foregroundStyle(.tertiary)
                        .symbolEffect(.pulse, isActive: !failed)
                }
            }
            .task(id: key) {
                image = nil
                failed = false
                let result = await ThumbnailStore.shared.thumbnail(for: url, size: size, modified: modified, pixelSize: pixels, look: look)
                guard !Task.isCancelled else { return }
                image = result
                failed = result == nil
            }
        }
        .clipShape(.rect(cornerRadius: cornerRadius))
        .accessibilityHidden(true)
    }

    /// Rounded up to a few fixed sizes so list and grid share cache entries.
    static func pixelSize(for size: CGSize, scale: CGFloat) -> Int {
        let wanted = Int(max(size.width, size.height) * scale)
        return [128, 256, 512].first { $0 >= wanted } ?? 512
    }
}

extension ShapeStyle where Self == LinearGradient {
    /// The viewer's studio backdrop in miniature, so white and grey models still read.
    static var thumbnailBackground: LinearGradient {
        LinearGradient(colors: [Color(Palette.tile.top), Color(Palette.tile.floor)], startPoint: .top, endPoint: .bottom)
    }
}
