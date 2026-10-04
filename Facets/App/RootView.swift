import SwiftUI

struct RootView: View {
    @Environment(Router.self) private var router
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
            .toastHost(clearance: 80)
            .zoomDestination(id: file.url, in: router.zoomSource)
        }
        #else
        .tabViewStyle(.sidebarAdaptable)
        .toastHost(clearance: 24)
        // On the Mac a model from Finder or another app opens in a window of its own.
        .onChange(of: router.presented) { _, file in
            guard let file else { return }
            openWindow(value: file)
            router.presented = nil
        }
        #endif
    }
}
