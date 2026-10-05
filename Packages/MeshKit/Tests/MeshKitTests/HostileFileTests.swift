import Foundation
import Testing
@testable import MeshKit

/// Damaged and deliberately hostile files (Hostile/): each one once crashed the
/// reader, the print estimate or Quick Look. Each must now load safely or fail
/// with an error, quickly.
struct HostileFileTests {
    private func url(_ name: String) throws -> URL {
        try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Hostile"))
    }

    @Test(arguments: ["bigidx.obj", "fanout.3mf", "huge.stl", "inf.stl", "meta_trunc.3mf", "nan.stl", "naninput.stl",
                      "pred_big.3mf", "pred_nan.3mf", "tet_1e20.stl", "tet_1e39.stl", "zip64neg.3mf"])
    func loadsOrFailsCleanly(_ name: String) throws {
        let start = Date()
        if let model = try? ModelLoader.load(try url(name)) {
            // Whatever loads has a finite size and a sane (or no) estimate.
            let bounds = model.bounds(of: model.parts)
            #expect(bounds.min.x.isFinite && bounds.max.z.isFinite)
            if let estimate = model.shapeEstimate(plateID: nil, hidden: [], density: 1.24) {
                #expect(estimate.seconds >= 0 && estimate.grams.isFinite)
            }
            #expect(model.estimates.allSatisfy { ($0.seconds ?? 0) >= 0 })
        }
        #expect(Date().timeIntervalSince(start) < 5)
    }

    @Test func damagedCoordinatesDropOnlyTheirTriangles() throws {
        // One good triangle and one at z = 1e39.
        let model = try ModelLoader.load(try url("tet_1e39.stl"))
        #expect(model.triangleCount >= 1)
        #expect(model.bounds(of: model.parts).size.z < 1e6)
    }

    @Test func componentFanOutIsBounded() throws {
        let model = try ModelLoader.load(try url("fanout.3mf"))
        #expect(model.parts.count <= 100_000)
    }
}
