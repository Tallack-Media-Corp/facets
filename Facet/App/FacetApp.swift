import SwiftUI

@main
struct FacetApp: App {
    @State private var library = FileLibrary()
    @State private var recents = RecentsStore()
    @State private var settings = ViewerSettings()
    @State private var router = Router()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
                .environment(recents)
                .environment(settings)
                .environment(router)
                // Files, Mail, Messages and the share sheet hand files over here.
                .onOpenURL { url in
                    router.open(url, library: library)
                }
                #if DEBUG
                .task { openFromLaunchEnvironment() }
                #endif
        }
    }

    #if DEBUG
    /// `FACET_OPEN=<path below Documents>` opens a library file at launch, for
    /// screenshots and quick checks.
    private func openFromLaunchEnvironment() {
        guard let path = ProcessInfo.processInfo.environment["FACET_OPEN"], !path.isEmpty else { return }
        router.open(library.root.appending(path: path), library: library)
    }
    #endif
}
