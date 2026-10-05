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
    /// False for a model that's only in iCloud on this device: it can't be drawn
    /// here, so the picture comes from the library's shared thumbnails, with a cloud
    /// badge; with none yet, a cloud stands in.
    var isDownloaded = true

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
                if let image = image ?? (isDownloaded ? ThumbnailStore.shared.cached(key) : nil) {
                    Image(platformImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(geometry.size.width * (showsBackdrop ? 0.08 : 0.02))
                } else if !isDownloaded {
                    Image(systemName: "icloud.and.arrow.down")
                        .font(.system(size: max(14, geometry.size.width * (showsBackdrop ? 0.18 : 0.4)), weight: .light))
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: failed ? "exclamationmark.triangle" : "cube.transparent")
                        .font(.system(size: max(14, geometry.size.width * (showsBackdrop ? 0.28 : 0.45)), weight: .light))
                        .foregroundStyle(.tertiary)
                        .symbolEffect(.pulse, isActive: !failed)
                }
            }
            // Fill the slot, so the picture and placeholder sit in its centre.
            .frame(width: geometry.size.width, height: geometry.size.height)
            .overlay(alignment: .bottomTrailing) {
                // Pictured, but not on this device: it downloads when opened.
                if !isDownloaded, image != nil {
                    Image(systemName: "icloud")
                        .font(.system(size: max(9, geometry.size.width * (showsBackdrop ? 0.09 : 0.22)), weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(geometry.size.width * 0.05)
                }
            }
            .task(id: "\(key)|\(isDownloaded)") {
                image = nil
                failed = false
                var result: PlatformImage?
                if isDownloaded {
                    result = await ThumbnailStore.shared.thumbnail(for: url, size: size, modified: modified, pixelSize: pixels, look: look)
                } else {
                    result = await ThumbnailStore.shared.sharedThumbnail(for: url, modified: modified, pixelSize: pixels, look: look)
                    // No device has drawn it yet: fetch a reasonably small file once and
                    // draw it, which shares the picture with the others too. A folder
                    // under Browse belongs to another app or provider, so only small
                    // files there, and only with the setting on: scrolling it shouldn't
                    // pull down big projects. Cards off screen never ask.
                    if result == nil, let size, size <= fetchLimit {
                        result = await ThumbnailStore.shared.thumbnail(for: url, size: size, modified: modified, pixelSize: pixels, look: look)
                    }
                }
                guard !Task.isCancelled else { return }
                image = result
                failed = result == nil
            }
        }
        .clipShape(.rect(cornerRadius: cornerRadius))
        .accessibilityElement()
        .accessibilityLabel(isDownloaded ? "" : "In the cloud, downloads when opened")
        .accessibilityHidden(isDownloaded)
    }

    /// The largest cloud-only library file fetched just to draw its picture.
    static let fetchLimit: Int64 = 25_000_000
    /// The same in a Browse location, with Settings' "Download Small Models for
    /// Previews" on.
    static let browseFetchLimit: Int64 = 5_000_000

    private var fetchLimit: Int64 {
        if url.standardizedFileURL.path.hasPrefix(LibraryLocation.current.standardizedFileURL.path + "/") { return Self.fetchLimit }
        return settings?.fetchesBrowsePreviews == true ? Self.browseFetchLimit : 0
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
