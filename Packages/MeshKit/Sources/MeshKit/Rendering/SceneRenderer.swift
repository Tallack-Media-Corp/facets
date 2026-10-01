import Metal
import simd

/// How a model is drawn. Colours are linear RGBA.
public struct RenderAppearance: Sendable, Equatable {
    public var baseColor: SIMD4<Float>
    /// Use the colours a 3MF assigns (filaments, materials) instead of the base colour.
    public var usesFileColors = true
    public var showsGrid = true
    public var wireframe = false
    public var gridColor = SIMD4<Float>(0.5, 0.5, 0.5, 0.5)
    /// Build items (`ModelPart.objectID`) the user switched off.
    public var hiddenObjects: Set<Int> = []
    /// Show only one slicer plate; nil shows everything.
    public var plateID: Int?
    /// A printer bed drawn on the grid, from `Model3D.bedFit`.
    public var bed: BedFit?
    /// Outline colour when the model is too big for the bed (linear).
    public var warningColor = RenderAppearance.defaultColor

    public init(baseColor: SIMD4<Float> = RenderAppearance.defaultColor) {
        self.baseColor = baseColor
    }

    /// Filament Orange (#F2782E), in linear light.
    public static let defaultColor = parseColor("#F2782E") ?? SIMD4(0.89, 0.19, 0.03, 1)

    /// An sRGB hex colour ("#RRGGBB") as linear RGBA, for `baseColor`.
    public static func linearColor(hex: String) -> SIMD4<Float>? {
        parseColor(hex)
    }

    /// Grid colour for a light or dark backdrop.
    public static func gridColor(dark: Bool) -> SIMD4<Float> {
        dark ? SIMD4(0.80, 0.83, 0.90, 0.15) : SIMD4(0.08, 0.09, 0.11, 0.26)
    }
}

private struct FrameUniforms {
    var view: simd_float4x4
    var projection: simd_float4x4
    var gridColor: SIMD4<Float>
}

private struct GridUniforms {
    var color: SIMD4<Float>
    var params: SIMD4<Float>
    var rect: SIMD4<Float>
    var bed: SIMD4<Float>
    var bedColor: SIMD4<Float>
}

private struct PartUniforms {
    var model: simd_float4x4
    var color: SIMD4<Float>
    var options: SIMD4<Float>
}

/// Owns a model's GPU buffers and encodes it, with the build plate grid, into a
/// render pass. Used by the interactive view and by snapshots; not thread-safe, so
/// each owner keeps its own.
public final class SceneRenderer {
    private struct GPUGeometry {
        let positions: MTLBuffer
        let indices: MTLBuffer?
        let count: Int
    }

    public let context: RenderContext
    public private(set) var model: Model3D?
    public var appearance = RenderAppearance() {
        didSet {
            if appearance.plateID != oldValue.plateID || appearance.hiddenObjects != oldValue.hiddenObjects || appearance.bed != oldValue.bed {
                rebuildGrid()
            }
        }
    }

    private var geometries: [ObjectIdentifier: GPUGeometry] = [:]
    private var grid: (buffer: MTLBuffer, step: Float)?
    private var gridBounds = Bounds.empty

    public init(context: RenderContext) {
        self.context = context
    }

    /// Uploads the model's geometry; shared meshes upload once.
    public func setModel(_ model: Model3D?) {
        self.model = model
        geometries.removeAll()
        if let model {
            for part in model.parts {
                let key = ObjectIdentifier(part.geometry)
                guard geometries[key] == nil else { continue }
                let geometry = part.geometry
                guard !geometry.positions.isEmpty,
                      let positions = geometry.positions.withUnsafeBytes({ context.device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }) else { continue }
                var indexBuffer: MTLBuffer?
                if let indices = geometry.indices, !indices.isEmpty {
                    indexBuffer = indices.withUnsafeBytes { context.device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }
                }
                let count = geometry.indices?.count ?? geometry.vertexCount
                geometries[key] = GPUGeometry(positions: positions, indices: indexBuffer, count: count)
            }
        }
        rebuildGrid()
    }

    /// The parts on screen after the plate and visibility filters.
    public var visibleParts: [ModelPart] {
        model?.visibleParts(plateID: appearance.plateID, hidden: appearance.hiddenObjects) ?? []
    }

    /// What the camera should frame: the visible parts, or the plate's when all are hidden.
    public var focusBounds: Bounds {
        guard let model else { return .empty }
        let visible = model.bounds(of: visibleParts)
        if !visible.isEmpty { return visible }
        let plate = model.plates.first { $0.id == appearance.plateID }
        return model.bounds(of: model.parts(on: plate))
    }

    /// Radius that covers the model and the grid, for the depth range.
    public var sceneRadius: Float {
        var bounds = focusBounds
        if appearance.showsGrid { bounds = bounds.union(gridBounds) }
        return max(bounds.radius, 0.01)
    }

    /// `pixelsPerPoint` keeps the grid lines the same thickness on every screen.
    /// `verticalShift` (the fraction of the view a sheet covers from the bottom) fits
    /// the picture into the part left uncovered.
    public func encode(into encoder: MTLRenderCommandEncoder, camera: OrbitCamera, aspect: Float, pixelsPerPoint: Float = 1, verticalShift: Float = 0) {
        guard model != nil else { return }
        var frame = FrameUniforms(
            view: camera.viewMatrix,
            projection: Self.shift(verticalShift) * camera.projectionMatrix(aspect: aspect, sceneRadius: sceneRadius + simd_distance(camera.target, focusBounds.center)),
            gridColor: appearance.gridColor
        )

        encoder.setRenderPipelineState(context.meshPipeline)
        encoder.setDepthStencilState(context.depthWrite)
        encoder.setCullMode(.none)
        encoder.setTriangleFillMode(appearance.wireframe ? .lines : .fill)
        encoder.setVertexBytes(&frame, length: MemoryLayout<FrameUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&frame, length: MemoryLayout<FrameUniforms>.stride, index: 1)

        for part in visibleParts {
            guard let gpu = geometries[ObjectIdentifier(part.geometry)] else { continue }
            var color = appearance.baseColor
            if appearance.usesFileColors, let fileColor = part.color { color = fileColor }
            var uniforms = PartUniforms(model: part.transform, color: color, options: SIMD4(appearance.wireframe ? 1 : 0, 0, 0, 0))
            encoder.setVertexBuffer(gpu.positions, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<PartUniforms>.stride, index: 2)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<PartUniforms>.stride, index: 2)
            if let indices = gpu.indices {
                encoder.drawIndexedPrimitives(type: .triangle, indexCount: gpu.count, indexType: .uint32, indexBuffer: indices, indexBufferOffset: 0)
            } else {
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: gpu.count)
            }
        }
        encoder.setTriangleFillMode(.fill)

        if appearance.showsGrid, let grid {
            let center = gridBounds.center, half = gridBounds.size / 2
            let bed = appearance.bed
            var uniforms = GridUniforms(
                color: appearance.gridColor,
                params: SIMD4(grid.step, 0.9 * pixelsPerPoint, bed == nil ? 0 : (bed!.fits ? 1 : 2), 0),
                rect: SIMD4(center.x, center.y, half.x, half.y),
                bed: bed.map { SIMD4($0.min.x, $0.min.y, $0.max.x, $0.max.y) } ?? .zero,
                bedColor: appearance.warningColor
            )
            encoder.setRenderPipelineState(context.gridPipeline)
            encoder.setDepthStencilState(context.depthReadOnly)
            encoder.setVertexBuffer(grid.buffer, offset: 0, index: 0)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<GridUniforms>.stride, index: 3)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        }
    }

    /// Fits the picture into the top `1 - amount` of the view: scaled down by the
    /// covered fraction and moved up, sitting slightly low so the chips at the top
    /// stay clear.
    private static func shift(_ amount: Float) -> simd_float4x4 {
        var m = matrix_identity_float4x4
        let scale = 1 - amount
        m.columns.0.x = scale
        m.columns.1.y = scale
        m.columns.3.y = amount * 0.85
        return m
    }

    /// A millimetre grid on a soft plate under the model, sized to it. The lines are
    /// drawn in the fragment shader, so they stay crisp and fade out at the edges.
    private func rebuildGrid() {
        grid = nil
        gridBounds = .empty
        var bounds = focusBounds
        guard !bounds.isEmpty else { return }
        // The plate has to reach past the bed outline, or the outline would fade out.
        if let bed = appearance.bed {
            bounds = bounds.union(Bounds(min: SIMD3(bed.min, bounds.min.z), max: SIMD3(bed.max, bounds.min.z)))
        }
        let size = bounds.size
        let span = max(size.x, size.y, 1)
        let step: Float = [0.5, 1, 2, 5, 10, 20, 50, 100].first { span / $0 <= 16 } ?? 100
        let margin = max(step * 3, span * 0.45)
        let minX = bounds.min.x - margin, maxX = bounds.max.x + margin
        let minY = bounds.min.y - margin, maxY = bounds.max.y + margin
        // A hair below the model so its base doesn't fight the plate.
        let z = bounds.min.z - span * 0.0005
        let corners: [Float] = [
            minX, minY, z, maxX, minY, z, maxX, maxY, z,
            minX, minY, z, maxX, maxY, z, minX, maxY, z,
        ]
        guard let buffer = corners.withUnsafeBytes({ context.device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }) else { return }
        grid = (buffer, step)
        gridBounds = Bounds(min: SIMD3(minX, minY, z), max: SIMD3(maxX, maxY, z))
    }
}
