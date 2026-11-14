import Foundation
import MeshKit

/// Reading a model through a file coordinator, which downloads one that's only in
/// iCloud (or a storage provider) first.
enum CoordinatedRead {
    static func model(at url: URL) throws -> Model3D {
        var coordinatorError: NSError?
        var result: Result<Model3D, Error> = .failure(ModelError.emptyFile)
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinatorError) { readURL in
            result = Result { try ModelLoader.load(readURL) }
        }
        if let coordinatorError { throw coordinatorError }
        return try result.get()
    }
}
