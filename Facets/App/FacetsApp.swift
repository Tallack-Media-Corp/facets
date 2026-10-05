import CoreSpotlight
import SwiftUI
import UniformTypeIdentifiers

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
                .task(priority: .background) { await ThumbnailStore.shared.pruneStale() }
                .task { await library.connectToICloud() }
        }
        #if os(macOS)
        .defaultSize(width: 1100, height: 760)
        #endif
        .commands {
            ViewerCommands()
            #if os(macOS)
            OpenCommands(library: library, locations: locations)
            #endif
        }

        #if os(macOS)
        // A model opened from Finder, another app, Spotlight or a Shortcut.
        WindowGroup("Model", for: ModelFileRef.self) { $file in
            if let file {
                ModelWindow(file: file)
                    .environment(library)
                    .environment(recents)
                    .environment(locations)
                    .environment(settings)
            }
        }
        .defaultSize(width: 900, height: 700)
        // A restored window would hold a bare URL without the user's permission to it.
        .restorationBehavior(.disabled)

        // Facets › Settings… (⌘,), where a Mac keeps its settings, not a sidebar tab.
        Settings {
            SettingsWindow()
                .environment(library)
                .environment(settings)
        }
        #endif
    }
}

#if os(macOS)
extension FocusedValues {
    /// The front window's router, so menu commands can change what it shows.
    @Entry var sceneRouter: Router?
}

/// File › Open… (⌘O): any model on the Mac, in a window of its own. File › Add
/// Location… (⇧⌘O): a folder to browse, in the sidebar. Help: the project on GitHub.
private struct OpenCommands: Commands {
    let library: FileLibrary
    let locations: LocationsStore
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.sceneRouter) private var router

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Open…") {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = UTType.models
                panel.allowsMultipleSelection = true
                guard panel.runModal() == .OK else { return }
                for url in panel.urls {
                    openWindow(value: ModelFileRef(url: url, isExternal: !library.contains(url)))
                }
            }
            .keyboardShortcut("o")
            Button("Add Location…") {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.prompt = "Add"
                panel.message = "Choose a folder to browse its STL, 3MF and OBJ files without importing them."
                guard panel.runModal() == .OK, let url = panel.url, let location = try? locations.add(url) else { return }
                router?.tab = .location(location.id)
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
        }
        // Replaces the stock "Facets Help", which has no help book behind it.
        CommandGroup(replacing: .help) {
            Link("Facets on GitHub", destination: AppInfo.sourceURL)
            Link("Report a Problem…", destination: AppInfo.sourceURL.appending(path: "issues"))
            Link("Privacy Policy", destination: AppInfo.sourceURL.appending(path: "blob/main/PRIVACY.md"))
        }
    }
}

/// The Settings window, with a toast centre of its own for Recently Deleted.
private struct SettingsWindow: View {
    @State private var toasts = ToastCenter()

    var body: some View {
        SettingsView()
            .formStyle(.grouped)
            .frame(minWidth: 460, idealWidth: 520, minHeight: 480, idealHeight: 640)
            .toastHost(clearance: 24)
            .environment(toasts)
    }
}

/// A viewer window, with the per-window state a viewer expects around it.
private struct ModelWindow: View {
    let file: ModelFileRef
    @State private var router = Router()
    @State private var toasts = ToastCenter()
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationStack {
            ViewerScreen(file: file)
        }
        .formStyle(.grouped)
        // The toast host reads the toast centre, so it goes inside it.
        .toastHost(clearance: 24)
        .environment(router)
        .environment(toasts)
        // "Find in Files…" and "Open Another File…" ask the router for a file; here
        // that's another window.
        .onChange(of: router.presented) { _, next in
            guard let next else { return }
            openWindow(value: next)
            router.presented = nil
        }
    }
}
#endif

/// One window's worth of app: its own tab, open model and toasts, so two iPad
/// windows don't mirror each other.
private struct SceneRoot: View {
    @State private var router = Router()
    @State private var toasts = ToastCenter()
    @Environment(FileLibrary.self) private var library
    @Environment(ViewerSettings.self) private var settings
    @Environment(\.scenePhase) private var scenePhase
    private let pending = PendingOpen.shared

    var body: some View {
        RootView()
            // Inset grouped settings and sheets on the Mac too, not two-column forms.
            .formStyle(.grouped)
            .environment(router)
            .environment(toasts)
            #if os(macOS)
            .focusedSceneValue(\.sceneRouter, router)
            #endif
            // Files, Mail, Messages and the share sheet hand files over here.
            .onOpenURL { url in
                router.open(url, library: library)
            }
            // An open window takes the file rather than the app making a new one
            // (on the Mac, the model then gets a window of its own).
            .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
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
    /// `FACETS_OPEN=<path below Documents>` opens a library file (`sample`, the sample),
    /// `FACETS_TAB=library|browse|recents|settings|search` picks the screen,
    /// `FACETS_BED=<preset id>|none` the printer.
    private func openFromLaunchEnvironment() {
        let env = ProcessInfo.processInfo.environment
        if let bed = env["FACETS_BED"] {
            settings.bedID = bed == "none" ? nil : bed
        }
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
        if env["FACETS_OPEN"] == "sample", let url = SampleModels.benchy {
            router.presented = ModelFileRef(url: url, isExternal: true)
        } else if let path = env["FACETS_OPEN"], !path.isEmpty {
            router.open(library.root.appending(path: path), library: library)
        }
    }
    #endif
}
