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
