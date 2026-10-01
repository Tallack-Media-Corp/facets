import SwiftUI

struct RootView: View {
    @Environment(Router.self) private var router

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
        .fullScreenCover(item: $router.presented) { file in
            NavigationStack {
                ViewerScreen(file: file, showsCloseButton: true)
            }
        }
    }
}
