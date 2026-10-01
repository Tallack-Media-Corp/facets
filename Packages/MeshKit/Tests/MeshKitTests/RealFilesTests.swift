import Foundation
import Testing
@testable import MeshKit

/// Reads every STL and 3MF in `MESHKIT_SAMPLES` (a folder) when it's set. The samples
/// stay outside the repository.
@Suite struct RealFilesTests {
    @Test func readsSamples() throws {
        guard let folder = ProcessInfo.processInfo.environment["MESHKIT_SAMPLES"] else { return }
        let urls = try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: folder), includingPropertiesForKeys: nil)
            .filter(ModelLoader.isSupported)
        for url in urls {
            let start = Date()
            do {
                let model = try ModelLoader.load(url)
                let size = model.bounds.size
                print(String(format: "%6.2fs  %@  %@  parts %d  objects %d  plates %d  tris %d  size %.1f×%.1f×%.1f  vol %.1f cm³",
                             Date().timeIntervalSince(start), url.lastPathComponent, model.format.rawValue, model.parts.count, model.objects.count,
                             model.plates.count, model.triangleCount, size.x, size.y, size.z, model.volume / 1000))
            } catch {
                Issue.record("\(url.lastPathComponent): \(error)")
            }
        }
    }
}
