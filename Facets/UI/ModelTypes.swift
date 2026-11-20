import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Declared by the system; imported in Info.plist as well for older lookups.
    static let stlModel = UTType(importedAs: "public.standard-tesselated-geometry-format")
    /// Bambu Studio's identifier, which other 3MF apps on Apple platforms share.
    static let threeMFModel = UTType(importedAs: "com.bambulab.3mf")

    /// Wavefront OBJ, declared by the system.
    static let objModel = UTType(importedAs: "public.geometry-definition-format")

    static let models: [UTType] = [.stlModel, .threeMFModel, .objModel]
}

extension EnvironmentValues {
    /// Source for the zoom transition from a library card into the viewer.
    @Entry var zoomNamespace: Namespace.ID?
}

extension View {
    @ViewBuilder
    func zoomSource(id: some Hashable, in namespace: Namespace.ID?) -> some View {
        if let namespace {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    @ViewBuilder
    func zoomDestination(id: some Hashable, in namespace: Namespace.ID?) -> some View {
        #if os(iOS)
        if let namespace {
            navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            self
        }
        #else
        self
        #endif
    }
}

extension View {
    /// Where a drop will land while something is dragged over it: the dashed tint
    /// outline, round the whole page (the defaults) or a folder's card or row.
    func dropHighlight(_ isTargeted: Bool, cornerRadius: CGFloat = Radius.dropTarget, inset: CGFloat = Spacing.md) -> some View {
        overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(.tint, style: StrokeStyle(lineWidth: Stroke.outline, dash: Stroke.dropTargetDash))
                    .padding(inset)
                    .allowsHitTesting(false)
            }
        }
    }
}

extension View {
    /// Whether the drag over this view began inside Facets. On iOS that's a card from
    /// the folder on screen. Always false before iOS 27, which can't tell.
    @ViewBuilder
    func tracksLocalDrag(_ isLocal: Binding<Bool>) -> some View {
        #if os(iOS)
        if #available(iOS 27, *) {
            onDropSessionUpdated { isLocal.wrappedValue = $0.localSession != nil }
        } else {
            self
        }
        #else
        // shortcut: on the Mac a local drag may come from another window's folder, so the page keeps its outline.
        self
        #endif
    }

    /// A library card or row as a drag source, carrying its file URL: dropped on a folder's
    /// card or row it moves there (`FileLibrary.dropMoves`), out to the Finder, Files or a
    /// slicer it's the file. On the Mac a selected card brings the whole selection, with
    /// `.libraryDragContainer(selection:)` round the cards. On iOS a drag begun on a List
    /// row doesn't land on anything in the app (seen on iOS 27.0).
    @ViewBuilder
    func libraryDraggable(_ url: URL) -> some View {
        #if os(macOS)
        draggable(containerItemID: url)
        #else
        // The container drags are iOS 27 and later, and iOS has no multi-selection in
        // the library to carry, so a card or row drags itself.
        draggable(LibraryDragItem(url: url))
        #endif
    }

    /// Round the library's cards or rows on the Mac: a drag from a selected one carries
    /// the whole selection. Nothing on iOS (see `libraryDraggable(_:)`).
    @ViewBuilder
    func libraryDragContainer(selection: Set<URL>) -> some View {
        #if os(macOS)
        dragContainer(for: URL.self, itemID: \.self) { (urls: [URL]) in urls }
            .dragContainerSelection(Array(selection))
        #else
        self
        #endif
    }
}

#if os(iOS)
/// What a library card or row carries on iOS: the model file itself, listed first as the
/// preferred form, for another app (Files, a slicer) that can't open a path inside
/// Facets; and its file URL, which a drop in the library reads to move it (a folder
/// carries only that). The Mac's pasteboard hands
/// the Finder the file from the URL alone.
struct LibraryDragItem: Transferable {
    let url: URL

    func isModel(_ type: UTType) -> Bool {
        url.pathExtension.lowercased() == type.preferredFilenameExtension
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .stlModel) { SentTransferredFile($0.url) }
            .exportingCondition { $0.isModel(.stlModel) }
        FileRepresentation(exportedContentType: .threeMFModel) { SentTransferredFile($0.url) }
            .exportingCondition { $0.isModel(.threeMFModel) }
        FileRepresentation(exportedContentType: .objModel) { SentTransferredFile($0.url) }
            .exportingCondition { $0.isModel(.objModel) }
        ProxyRepresentation(exporting: \.url)
    }
}
#endif
