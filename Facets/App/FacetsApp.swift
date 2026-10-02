import CoreSpotlight
import SwiftUI

@main
struct FacetsApp: App {
    // Files and settings are the same in every window.
    @State private var library = FileLibrary()
    @State private var recents = RecentsStore()
    @State private var locations = LocationsStore()
    @State private var settings = ViewerSettings()

    var body: some Scene {
        WindowGroup {
            SceneRoot()
                .environment(library)
                .environment(recents)
                .environment(locations)
                .environment(settings)
                .task { library.purgeExpired() }
        }
        .commands { ViewerCommands() }
    }
}

/// One window's worth of app: its own tab, open model and toasts, so two iPad
/// windows don't mirror each other.
private struct SceneRoot: View {
    @State private var router = Router()
    @State private var toasts = ToastCenter()
    @Environment(FileLibrary.self) private var library
    @Environment(\.scenePhase) private var scenePhase
    private let pending = PendingOpen.shared

    var body: some View {
        RootView()
            .environment(router)
            .environment(toasts)
            // Files, Mail, Messages and the share sheet hand files over here.
            .onOpenURL { url in
                router.open(url, library: library)
            }
            // A library model picked from a Spotlight search.
            .onContinueUserActivity(CSSearchableItemActionType) { activity in
                if let url = SpotlightIndexer.url(for: activity) {
                    router.presented = ModelFileRef(url: url, isExternal: false)
                }
            }
            // A model a Shortcut asked to open: the window in front takes it.
            .onChange(of: pending.file) { claimPendingOpen() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { claimPendingOpen() }
                if phase == .background { SpotlightIndexer.reindex() }
            }
            .task { SpotlightIndexer.reindex() }
            #if DEBUG
            .task { openFromLaunchEnvironment() }
            #endif
    }

    private func claimPendingOpen() {
        guard scenePhase == .active, let file = pending.file else { return }
        pending.file = nil
        router.presented = file
    }

    #if DEBUG
    /// Launch options for screenshots and quick checks:
    /// `FACETS_OPEN=<path below Documents>` opens a library file,
    /// `FACETS_TAB=library|browse|recents|settings|search` picks the screen.
    private func openFromLaunchEnvironment() {
        let env = ProcessInfo.processInfo.environment
        switch env["FACETS_TAB"] {
        case "browse":
            UserDefaults.standard.set("Browse", forKey: "library.section")
            router.tab = .library
        case "library":
            UserDefaults.standard.set("Library", forKey: "library.section")
            router.tab = .library
        case "recents": router.tab = .recents
        case "settings": router.tab = .settings
        case "search": router.tab = .search
        default: break
        }
        if let path = env["FACETS_OPEN"], !path.isEmpty {
            router.open(library.root.appending(path: path), library: library)
        }
    }
    #endif
}
