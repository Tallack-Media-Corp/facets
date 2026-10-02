import Metal

/// The device and pipelines, built once per process and shared by every view and
/// snapshot. Metal devices and pipeline states are thread-safe.
public final class RenderContext: @unchecked Sendable {
    public static let colorFormat = MTLPixelFormat.bgra8Unorm_srgb
    public static let depthFormat = MTLPixelFormat.depth32Float
    public static let sampleCount = 4

    public let device: MTLDevice
    let queue: MTLCommandQueue
    let meshPipeline: MTLRenderPipelineState
    /// The cross-section: same mesh, cut at a height.
    let meshCutPipeline: MTLRenderPipelineState
    let gridPipeline: MTLRenderPipelineState
    let depthWrite: MTLDepthStencilState
    let depthReadOnly: MTLDepthStencilState

    /// Nil only where there's no Metal at all.
    public static let shared: RenderContext? = try? RenderContext()

    private init() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw ModelError.corrupt("Metal isn't available")
        }
        self.device = device
        self.queue = queue
        let library = try device.makeLibrary(source: ShaderSource.metal, options: nil)

        let mesh = MTLRenderPipelineDescriptor()
        mesh.label = "Mesh"
        mesh.vertexFunction = library.makeFunction(name: "mesh_vertex")
        mesh.fragmentFunction = library.makeFunction(name: "mesh_fragment")
        mesh.colorAttachments[0].pixelFormat = Self.colorFormat
        mesh.depthAttachmentPixelFormat = Self.depthFormat
        mesh.rasterSampleCount = Self.sampleCount
        meshPipeline = try device.makeRenderPipelineState(descriptor: mesh)
        mesh.label = "Mesh (cut)"
        mesh.fragmentFunction = library.makeFunction(name: "mesh_fragment_cut")
        meshCutPipeline = try device.makeRenderPipelineState(descriptor: mesh)

        let grid = MTLRenderPipelineDescriptor()
        grid.label = "Grid"
        grid.vertexFunction = library.makeFunction(name: "grid_vertex")
        grid.fragmentFunction = library.makeFunction(name: "grid_fragment")
        grid.colorAttachments[0].pixelFormat = Self.colorFormat
        grid.colorAttachments[0].isBlendingEnabled = true
        // The fragment returns premultiplied colour.
        grid.colorAttachments[0].sourceRGBBlendFactor = .one
        grid.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        grid.colorAttachments[0].sourceAlphaBlendFactor = .one
        grid.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        grid.depthAttachmentPixelFormat = Self.depthFormat
        grid.rasterSampleCount = Self.sampleCount
        gridPipeline = try device.makeRenderPipelineState(descriptor: grid)

        let write = MTLDepthStencilDescriptor()
        write.depthCompareFunction = .less
        write.isDepthWriteEnabled = true
        depthWrite = device.makeDepthStencilState(descriptor: write)!

        let read = MTLDepthStencilDescriptor()
        read.depthCompareFunction = .less
        read.isDepthWriteEnabled = false
        depthReadOnly = device.makeDepthStencilState(descriptor: read)!
    }
}
