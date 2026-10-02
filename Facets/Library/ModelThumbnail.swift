import SwiftUI

/// A model's rendered picture on a soft card, with a cube while it renders.
struct ModelThumbnail: View {
    let url: URL
    var size: Int64?
    var modified: Date?
    var cornerRadius: CGFloat = 14
    /// The studio backdrop behind the model: on for cards, off in list rows, where
    /// the row's own background is enough.
    var showsBackdrop = true

    @Environment(\.displayScale) private var displayScale
    /// Optional: a context-menu preview is drawn outside the app's environment.
    @Environment(ViewerSettings.self) private var settings: ViewerSettings?
    @State private var image: PlatformImage?
    @State private var failed = false

    var body: some View {
        GeometryReader { geometry in
            let pixels = Self.pixelSize(for: geometry.size, scale: displayScale)
            let look = ThumbnailStore.Look(colorHex: settings?.colorHex ?? Palette.filamentOrange, usesFileColors: settings?.usesFileColors ?? true)
            let key = ThumbnailStore.key(for: url, size: size, modified: modified, pixelSize: pixels, look: look)
            ZStack {
                if showsBackdrop {
                    Rectangle().fill(Palette.tileGradient(pureBlack: settings?.pureBlack ?? false))
                }
                if let image = image ?? ThumbnailStore.shared.cached(key) {
                    Image(platformImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(geometry.size.width * (showsBackdrop ? 0.08 : 0.02))
                } else {
                    Image(systemName: failed ? "exclamationmark.triangle" : "cube.transparent")
                        .font(.system(size: max(14, geometry.size.width * (showsBackdrop ? 0.28 : 0.45)), weight: .light))
                        .foregroundStyle(.tertiary)
                        .symbolEffect(.pulse, isActive: !failed)
                }
            }
            // Fill the slot, so the picture and placeholder sit in its centre.
            .frame(width: geometry.size.width, height: geometry.size.height)
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

extension Palette {
    /// The viewer's studio backdrop in miniature, so white and grey models still read.
    static func tileGradient(pureBlack: Bool) -> LinearGradient {
        let tile = tile(pureBlack: pureBlack)
        return LinearGradient(colors: [Color(tile.top), Color(tile.floor)], startPoint: .top, endPoint: .bottom)
    }
}
