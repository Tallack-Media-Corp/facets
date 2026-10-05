import SwiftUI

struct RootView: View {
    @Environment(Router.self) private var router
    @Environment(LocationsStore.self) private var locations
    @Environment(\.horizontalSizeClass) private var sizeClass
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            Tab("Library", systemImage: "square.grid.2x2", value: Router.Tab.library) {
                LibraryTab()
            }
            Tab("Recents", systemImage: "clock", value: Router.Tab.recents) {
                RecentsView()
            }
            #if os(iOS)
            Tab("Settings", systemImage: "gearshape", value: Router.Tab.settings) {
                SettingsView()
            }
            #endif
            #if os(macOS)
            // Browse, as the Finder lists folders: each location its own sidebar item.
            TabSection("Locations") {
                ForEach(locations.locations) { location in
                    Tab(location.name, systemImage: location.isCloud ? "icloud" : "folder", value: Router.Tab.location(location.id)) {
                        LocationTab(location: location)
                    }
                    .contextMenu {
                        Button("Remove from Sidebar", systemImage: "minus.circle", role: .destructive) {
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
        // iPhone's tab bar is at the bottom; iPad's is at the top.
        .toastHost(clearance: sizeClass == .compact ? 88 : 24)
        .fullScreenCover(item: $router.presented) { file in
            NavigationStack {
                ViewerScreen(file: file, showsCloseButton: true)
            }
            // The zoom transition's own dismissal (pinch in, or drag) fires on a
            // pinch that starts near the screen's edge; in the viewer a pinch is
            // always zoom. The close button is the way out.
            .interactiveDismissDisabled()
            .toastHost(clearance: 80)
            .zoomDestination(id: file.url, in: router.zoomSource)
        }
        #else
        .tabViewStyle(.sidebarAdaptable)
        .tabViewSidebarBottomBar {
            SidebarFoot()
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        }
        .toastHost(clearance: 24)
        // On the Mac a model from Finder or another app opens in a window of its own.
        // Initial too: a file that launched the app arrives before this window is
        // watching, and would otherwise sit unopened.
        .onChange(of: router.presented, initial: true) { _, file in
            guard let file else { return }
            openWindow(value: file)
            router.presented = nil
        }
        #endif
    }
}
