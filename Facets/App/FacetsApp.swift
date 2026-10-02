import CoreSpotlight
import SwiftUI

@main
struct FacetsApp: App {
    @State private var library = FileLibrary()
    @State private var recents = RecentsStore()
    @State private var locations = LocationsStore()
    @State private var toasts = ToastCenter()
    @State private var settings = ViewerSettings()
    @State private var router = Router.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
                .environment(recents)
                .environment(locations)
                .environment(toasts)
                .task { library.purgeExpired() }
                .environment(settings)
                .environment(router)
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
                .task { SpotlightIndexer.reindex() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background { SpotlightIndexer.reindex() }
                }
                #if DEBUG
                .task { openFromLaunchEnvironment() }
                #endif
        }
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
