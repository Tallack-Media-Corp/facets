import SwiftUI

/// The sample that ships with Facets, so there's something to open before you have
/// files of your own (and for App Review): #3DBenchy by Creative Tools, public domain
/// (CC0), as a two-colour project built from its dual-print files
/// (tools/samples/build_benchy_sample.py).
enum SampleModels {
    static var benchy: URL? {
        Bundle.main.url(forResource: "3DBenchy", withExtension: "3mf")
    }

    static let credit = "#3DBenchy by Creative Tools (3DBenchy.com), public domain (CC0). The two-colour version is made from its dual-print files."

    /// Inside the app bundle, whose path changes with every update: not for Recents.
    static func isSample(_ url: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix(Bundle.main.bundleURL.standardizedFileURL.path + "/")
    }
}

/// Opens the sample: in the viewer over the current tab on iPhone and iPad, in a
/// window of its own on the Mac. Works where `openModel` isn't set (Settings).
struct OpenSampleButton: View {
    var title = "Open the Sample"
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #else
    @Environment(Router.self) private var router
    #endif

    var body: some View {
        if let url = SampleModels.benchy {
            Button(title, systemImage: "sailboat") {
                let file = ModelFileRef(url: url, isExternal: true)
                #if os(macOS)
                openWindow(value: file)
                #else
                router.zoomSource = nil
                router.presented = file
                #endif
            }
        }
    }
}
