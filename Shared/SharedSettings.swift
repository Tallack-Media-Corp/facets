import Foundation

/// The few settings the Quick Look extensions need from the app, kept in the App
/// Group they share (`FacetsAppGroup` in each Info.plist, from FACETS_BUNDLE_ID).
/// Where there's no group (the Mac app), these read and write nothing.
enum SharedSettings {
    private static let pureBlackKey = "display.pureBlack"

    private static var defaults: UserDefaults? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "FacetsAppGroup") as? String, !group.isEmpty else { return nil }
        return UserDefaults(suiteName: group)
    }

    /// Pure Black in Dark Mode, for the Quick Look preview's backdrop.
    static var pureBlack: Bool {
        get { defaults?.bool(forKey: pureBlackKey) ?? false }
        set { defaults?.set(newValue, forKey: pureBlackKey) }
    }

    #if DEBUG
    /// Shows the preview's too-large fallback whatever the file, for the Simulator, which
    /// sets no memory limit. Set from the shell (`defaults write` in the group container).
    static var forceTooLarge: Bool { defaults?.bool(forKey: "debug.forceTooLarge") ?? false }
    #endif
}
