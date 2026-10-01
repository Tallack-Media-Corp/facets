import CoreGraphics
import Metal

/// Renders a model to an image off screen: library thumbnails and the Quick Look
/// thumbnail extension. Transparent background, no grid, isometric.
public final class ModelSnapshotter {
    private let renderer: SceneRenderer

    public init?() {
        guard let context = RenderContext.shared else { return nil }
        renderer = SceneRenderer(context: context)
    }

    /// A multi-plate project shows its first plate, as the slicer does, unless the
    /// appearance names one.
    public func image(of model: Model3D, pixelSize: Int, appearance: RenderAppearance = RenderAppearance()) -> CGImage? {
        let size = max(16, min(pixelSize, 2048))
        let context = renderer.context
        var appearance = appearance
        appearance.showsGrid = false
        appearance.wireframe = false
        if appearance.plateID == nil { appearance.plateID = model.plates.first?.id }
        renderer.appearance = appearance
        renderer.setModel(model)
        defer { renderer.setModel(nil) }

        var camera = OrbitCamera()
        camera.apply(.isometric)
        camera.fitTightly(renderer.visibleParts, aspect: 1)

        let msaa = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: RenderContext.colorFormat, width: size, height: size, mipmapped: false)
        msaa.textureType = .type2DMultisample
        msaa.sampleCount = RenderContext.sampleCount
        msaa.usage = .renderTarget
        msaa.storageMode = .private

        let resolve = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: RenderContext.colorFormat, width: size, height: size, mipmapped: false)
        resolve.usage = [.renderTarget, .shaderRead]
        resolve.storageMode = .shared

        let depth = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: RenderContext.depthFormat, width: size, height: size, mipmapped: false)
        depth.textureType = .type2DMultisample
        depth.sampleCount = RenderContext.sampleCount
        depth.usage = .renderTarget
        depth.storageMode = .private

        guard let colorTexture = context.device.makeTexture(descriptor: msaa),
              let resolveTexture = context.device.makeTexture(descriptor: resolve),
              let depthTexture = context.device.makeTexture(descriptor: depth),
              let commands = context.queue.makeCommandBuffer() else { return nil }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = colorTexture
        pass.colorAttachments[0].resolveTexture = resolveTexture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .multisampleResolve
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.depthAttachment.texture = depthTexture
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.storeAction = .dontCare
        pass.depthAttachment.clearDepth = 1

        guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        renderer.encode(into: encoder, camera: camera, aspect: 1)
        encoder.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        guard commands.status == .completed else { return nil }

        let bytesPerRow = size * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * size)
        resolveTexture.getBytes(&pixels, bytesPerRow: bytesPerRow, from: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0)
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGImage(
            width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
            space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )
    }
}
