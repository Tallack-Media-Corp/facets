import SwiftUI
#if os(iOS)
import UIKit
typealias PlatformImage = UIImage
#else
import AppKit
typealias PlatformImage = NSImage
#endif

/// Where iOS and macOS differ in name only. Anything with real behaviour differences
/// stays `#if os(macOS)` at the point of use.
extension Image {
    init(platformImage image: PlatformImage) {
        #if os(iOS)
        self.init(uiImage: image)
        #else
        self.init(nsImage: image)
        #endif
    }
}

extension PlatformImage {
    static func from(_ cgImage: CGImage) -> PlatformImage {
        #if os(iOS)
        UIImage(cgImage: cgImage)
        #else
        NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width / 2, height: cgImage.height / 2))
        #endif
    }
}

extension Color {
    /// Behind inset grouped lists and grids.
    static var groupedBackground: Color {
        #if os(iOS)
        Color(.systemGroupedBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }
}

/// Bookmarks that keep the user's permission across launches. On the Mac's sandbox
/// that takes a security-scoped bookmark; iOS bookmarks carry it already.
enum Bookmark {
    #if os(macOS)
    static let creation: URL.BookmarkCreationOptions = [.withSecurityScope]
    static let resolution: URL.BookmarkResolutionOptions = [.withSecurityScope]
    #else
    static let creation: URL.BookmarkCreationOptions = []
    static let resolution: URL.BookmarkResolutionOptions = []
    #endif

    static func make(_ url: URL) throws -> Data {
        try url.bookmarkData(options: creation)
    }

    static func resolve(_ data: Data, isStale: inout Bool) throws -> URL {
        try URL(resolvingBookmarkData: data, options: resolution, bookmarkDataIsStale: &isStale)
    }
}

extension URL {
    /// Runs `body` inside the URL's security scope, for a file the user picked or a
    /// bookmark resolved. Short uses only; one held while a folder or model stays
    /// open starts and stops on its own.
    func withSecurityScope<T>(_ body: () throws -> T) rethrows -> T {
        let scoped = startAccessingSecurityScopedResource()
        defer { if scoped { stopAccessingSecurityScopedResource() } }
        return try body()
    }

    /// The same, across awaits, on the caller's actor.
    nonisolated(nonsending) func withSecurityScope<T>(_ body: () async throws -> T) async rethrows -> T {
        let scoped = startAccessingSecurityScopedResource()
        defer { if scoped { stopAccessingSecurityScopedResource() } }
        return try await body()
    }
}

/// VoiceOver, on either platform.
@MainActor
enum Spoken {
    static var isVoiceOverRunning: Bool {
        #if os(iOS)
        UIAccessibility.isVoiceOverRunning
        #else
        NSWorkspace.shared.isVoiceOverEnabled
        #endif
    }

    /// Reads out a change that happened out of sight.
    static func announce(_ text: String) {
        #if os(iOS)
        UIAccessibility.post(notification: .announcement, argument: text)
        #else
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [
            .announcement: text,
            .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ])
        #endif
    }
}

extension ToolbarItemPlacement {
    /// The bottom toolbar on iPhone and iPad; the window toolbar on the Mac.
    static var bottomControls: ToolbarItemPlacement {
        #if os(iOS)
        .bottomBar
        #else
        .automatic
        #endif
    }
}

extension View {
    /// Actions on a whole list (Restore All, Delete All), one at each end: the bottom
    /// toolbar on iPhone and iPad. On the Mac, a bar under the list: a page pushed in
    /// the Settings window has no toolbar of its own, and the title bar put them as
    /// loose pills beside the back button.
    func listActions<Leading: View, Trailing: View>(shown: Bool, @ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) -> some View {
        let leading = leading()
        let trailing = trailing()
        #if os(iOS)
        return toolbar {
            if shown {
                ToolbarItem(placement: .bottomBar) { leading }
                ToolbarSpacer(.flexible, placement: .bottomBar)
                ToolbarItem(placement: .bottomBar) { trailing }
            }
        }
        #else
        return safeAreaInset(edge: .bottom, spacing: 0) {
            if shown {
                HStack {
                    leading
                    Spacer()
                    trailing
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
        }
        #endif
    }

    /// The number pad for measurements on iPhone and iPad.
    func decimalKeyboard() -> some View {
        #if os(iOS)
        keyboardType(.decimalPad)
        #else
        self
        #endif
    }

    /// Hides the tab bar under a pushed screen on iPhone and iPad; the Mac has none.
    func hidesTabBar() -> some View {
        #if os(iOS)
        toolbar(.hidden, for: .tabBar)
        #else
        self
        #endif
    }
}

#if os(macOS)
/// iOS-only modifiers as no-ops on the Mac, so shared views read the same.
enum NavigationBarItem {
    enum TitleDisplayMode { case automatic, inline, large }
}

extension View {
    func navigationBarTitleDisplayMode(_ mode: NavigationBarItem.TitleDisplayMode) -> some View { self }
}

extension ToolbarItemPlacement {
    static var topBarLeading: ToolbarItemPlacement { .navigation }
    static var topBarTrailing: ToolbarItemPlacement { .primaryAction }
}
#endif

extension View {
    /// Toolbar menus show just their glyph, as on iOS: on the Mac a drop-down
    /// chevron squeezes into the same glass capsule and pushes the glyph aside.
    func toolbarMenuIndicator() -> some View {
        #if os(macOS)
        menuIndicator(.hidden)
        #else
        self
        #endif
    }
}
