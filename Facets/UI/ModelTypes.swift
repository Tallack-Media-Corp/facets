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
        if let namespace {
            navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            self
        }
    }
}
