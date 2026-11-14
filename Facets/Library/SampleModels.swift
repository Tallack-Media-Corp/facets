import SwiftUI

/// The sample that ships with Facets, so there's something to open before you have
/// files of your own (and for App Review): #3DBenchy by Creative Tools, public domain
/// (CC0), as a two-colour project built from its dual-print files
/// (tools/samples/build_benchy_sample.py).
enum SampleModels {
    static var benchy: URL? {
        Bundle.main.url(forResource: "3DBenchy", withExtension: "3mf")
    }

    static var credit: String { String(localized: "#3DBenchy by Creative Tools (3DBenchy.com), public domain (CC0). The two-colour version is made from its dual-print files.") }

    /// Inside the app bundle, whose path changes with every update: not for Recents.
    static func isSample(_ url: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix(Bundle.main.bundleURL.standardizedFileURL.path + "/")
    }
}

/// Opens the sample: in the viewer over the current tab on iPhone and iPad, in a
/// window of its own on the Mac. Works where `openModel` isn't set (Settings).
struct OpenSampleButton: View {
    var title = String(localized: "Open the Sample")

    var body: some View {
        if let url = SampleModels.benchy {
            SampleButton(title: title, file: ModelFileRef(url: url, isExternal: true))
                // No card to zoom from: it opens as a file from elsewhere does.
                .environment(\.zoomNamespace, nil)
                .presentsModels()
        }
    }
}

private struct SampleButton: View {
    let title: String
    let file: ModelFileRef
    @Environment(\.openModel) private var openModel

    var body: some View {
        Button(title, systemImage: "sailboat") { openModel(file) }
    }
}
