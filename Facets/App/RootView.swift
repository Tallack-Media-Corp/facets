import SwiftUI

struct RootView: View {
    @Environment(Router.self) private var router
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            Tab("Library", systemImage: "square.grid.2x2", value: Router.Tab.library) {
                LibraryTab()
            }
            Tab("Recents", systemImage: "clock", value: Router.Tab.recents) {
                RecentsView()
            }
            Tab("Settings", systemImage: "gearshape", value: Router.Tab.settings) {
                SettingsView()
            }
            Tab(value: Router.Tab.search, role: .search) {
                SearchView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        // iPhone's tab bar is at the bottom; iPad's is at the top.
        .toastHost(clearance: sizeClass == .compact ? 88 : 24)
        .fullScreenCover(item: $router.presented) { file in
            NavigationStack {
                ViewerScreen(file: file, showsCloseButton: true)
            }
            .toastHost(clearance: 80)
        }
    }
}
