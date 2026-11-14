import SwiftUI

struct RootView: View {
    @Environment(Router.self) private var router
    @Environment(LocationsStore.self) private var locations

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            Tab("Library", systemImage: Symbol.library, value: Router.Tab.library) {
                LibraryTab()
            }
            Tab("Recents", systemImage: Symbol.recents, value: Router.Tab.recents) {
                RecentsView()
            }
            #if os(iOS)
            Tab("Settings", systemImage: Symbol.settings, value: Router.Tab.settings) {
                SettingsView()
            }
            #endif
            #if os(macOS)
            // Browse, as the Finder lists folders: each location its own sidebar item.
            TabSection("Locations") {
                ForEach(locations.locations) { location in
                    Tab(location.name, systemImage: location.isCloud ? Symbol.cloudFolder : Symbol.folder, value: Router.Tab.location(location.id)) {
                        LocationTab(location: location)
                    }
                    .contextMenu {
                        RowAction.remove("Remove from Sidebar") {
                            if router.tab == .location(location.id) { router.tab = .library }
                            locations.remove(location)
                        }
                    }
                }
            }
            #endif
            Tab(value: Router.Tab.search, role: .search) {
                SearchView()
            }
        }
        #if os(iOS)
        .tabBarMinimizeBehavior(.onScrollDown)
        #else
        .tabViewStyle(.sidebarAdaptable)
        .tabViewSidebarBottomBar { SidebarFoot() }
        #endif
        .toastHost()
        #if os(iOS)
        .fullScreenCover(item: $router.presented) { file in
            ViewerScreen(file: file, showsCloseButton: true)
            // The zoom transition's own dismissal (pinch in, or drag) fires on a
            // pinch that starts near the screen's edge; in the viewer a pinch is
            // always zoom. The close button is the way out.
            .interactiveDismissDisabled()
            .toastHost(aboveBottomToolbar: true)
            .zoomDestination(id: file.url, in: router.zoomSource)
        }
        #else
        // On the Mac a model from Finder or another app opens in a window of its own.
        .opensPresentedModelsInWindows(router)
        #endif
    }
}
