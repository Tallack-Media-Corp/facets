import SwiftUI

extension EnvironmentValues {
    /// Opens a model in the viewer: full screen, zooming from its card, on iPhone and
    /// iPad; a window of its own on the Mac.
    @Entry var openModel: (ModelFileRef) -> Void = { _ in }
}

extension View {
    /// Lets the views inside open models with `openModel`. The viewer is presented
    /// over the tab rather than pushed onto it: a pushed viewer has to hide the tab
    /// bar, and an interactive back swipe on iOS 26 can leave the bar missing for a
    /// moment, or the viewer's toolbar behind on the library.
    func presentsModels() -> some View {
        modifier(ModelPresenter())
    }
}

private struct ModelPresenter: ViewModifier {
    @Environment(\.zoomNamespace) private var zoom
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif
    @State private var viewing: ModelFileRef?

    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .environment(\.openModel) { viewing = $0 }
            .fullScreenCover(item: $viewing) { file in
                NavigationStack {
                    ViewerScreen(file: file, showsCloseButton: true)
                }
                .toastHost(clearance: 80)
                .zoomDestination(id: file.url, in: zoom)
            }
        #else
        content
            .environment(\.openModel) { openWindow(value: $0) }
        #endif
    }
}

/// A row or card that opens a model. Reads `openModel` where it sits, so it works
/// inside the view that applies `presentsModels()`.
struct OpenModelButton<Label: View>: View {
    let file: ModelFileRef
    @ViewBuilder let label: () -> Label
    @Environment(\.openModel) private var openModel

    var body: some View {
        Button {
            openModel(file)
        } label: {
            label().contentShape(.rect)
        }
        .foregroundStyle(Color.primary)
    }
}
