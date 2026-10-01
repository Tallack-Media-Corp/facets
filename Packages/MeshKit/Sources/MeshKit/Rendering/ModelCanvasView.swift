#if canImport(UIKit)
import MetalKit
import SwiftUI
import UIKit

/// The interactive 3D view: one finger orbits, two fingers pan, pinch zooms, twist
/// turns, double tap frames the model. Draws only when something changes, so an idle
/// model costs no GPU time.
@MainActor
public final class ModelCanvasView: MTKView, MTKViewDelegate, UIGestureRecognizerDelegate {
    public private(set) var renderer: SceneRenderer?
    public private(set) var camera = OrbitCamera()

    public var appearance = RenderAppearance() {
        didSet {
            guard appearance != oldValue else { return }
            renderer?.appearance = appearance
            if appearance.plateID != oldValue.plateID {
                frameModel(animated: true)
            }
            setNeedsDisplay()
        }
    }

    /// Called while the user moves the camera, for hiding chrome or dismissing hints.
    public var onInteraction: (() -> Void)?

    /// How much of the view's height a sheet covers from the bottom (0 to 1). The
    /// model glides up to stay centred in what's left.
    public var bottomObscured: CGFloat = 0 {
        didSet {
            guard bottomObscured != oldValue else { return }
            if UIAccessibility.isReduceMotionEnabled || window == nil {
                verticalShift = Float(bottomObscured)
                setNeedsDisplay()
            } else {
                startDisplayLink()
            }
        }
    }
    private var verticalShift: Float = 0

    private var needsFit = true
    private var displayLink: CADisplayLink?
    private var velocity = SIMD2<Float>.zero
    private var animation: (from: OrbitCamera, to: OrbitCamera, start: CFTimeInterval, duration: CFTimeInterval)?

    public init() {
        let context = RenderContext.shared
        super.init(frame: .zero, device: context?.device)
        if let context { renderer = SceneRenderer(context: context) }
        colorPixelFormat = RenderContext.colorFormat
        depthStencilPixelFormat = RenderContext.depthFormat
        sampleCount = RenderContext.sampleCount
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        isOpaque = false
        backgroundColor = .clear
        isPaused = true
        enableSetNeedsDisplay = true
        autoResizeDrawable = true
        delegate = self
        isMultipleTouchEnabled = true
        installGestures()
        isAccessibilityElement = true
        accessibilityTraits = [.image, .allowsDirectInteraction]
        accessibilityLabel = "3D model"
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    public func setModel(_ model: Model3D?) {
        renderer?.setModel(model)
        renderer?.appearance = appearance
        camera = OrbitCamera()
        needsFit = true
        layoutIfNeeded()
        if bounds.width > 0 { frameModel(animated: false) }
        setNeedsDisplay()
    }

    /// Frames what's visible without changing the viewing angle.
    public func frameModel(animated: Bool) {
        guard let renderer, bounds.width > 0, bounds.height > 0 else { needsFit = true; return }
        var next = camera
        next.fitTightly(renderer.visibleParts, aspect: aspect, fill: 0.72, recenter: false)
        move(to: next, animated: animated)
        needsFit = false
    }

    public func show(_ preset: OrbitCamera.Preset, animated: Bool = true) {
        guard let renderer else { return }
        var next = camera
        next.apply(preset)
        next.fitTightly(renderer.visibleParts, aspect: aspect, fill: 0.72, recenter: false)
        move(to: next, animated: animated)
    }

    public func resetView() {
        show(.isometric)
    }

    private var aspect: Float {
        Float(max(bounds.width, 1) / max(bounds.height, 1))
    }

    private func move(to next: OrbitCamera, animated: Bool) {
        velocity = .zero
        if animated, !UIAccessibility.isReduceMotionEnabled, window != nil {
            animation = (camera, next, CACurrentMediaTime(), 0.4)
            startDisplayLink()
        } else {
            animation = nil
            camera = next
            setNeedsDisplay()
        }
    }

    // MARK: Drawing

    public override func layoutSubviews() {
        super.layoutSubviews()
        if needsFit, bounds.width > 0, renderer?.model != nil {
            frameModel(animated: false)
        }
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        setNeedsDisplay()
    }

    public func draw(in view: MTKView) {
        guard let renderer,
              let pass = currentRenderPassDescriptor,
              let drawable = currentDrawable,
              let commands = renderer.context.queue.makeCommandBuffer(),
              let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return }
        let size = drawableSize
        renderer.encode(into: encoder, camera: camera, aspect: Float(size.width / max(size.height, 1)), pixelsPerPoint: Float(contentScaleFactor), verticalShift: verticalShift)
        encoder.endEncoding()
        commands.present(drawable)
        commands.commit()
    }

    // MARK: Gestures

    private func installGestures() {
        let orbit = UIPanGestureRecognizer(target: self, action: #selector(handleOrbit(_:)))
        orbit.maximumNumberOfTouches = 1
        orbit.delegate = self
        addGestureRecognizer(orbit)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.minimumNumberOfTouches = 2
        pan.delegate = self
        addGestureRecognizer(pan)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.delegate = self
        addGestureRecognizer(pinch)

        let twist = UIRotationGestureRecognizer(target: self, action: #selector(handleTwist(_:)))
        twist.delegate = self
        addGestureRecognizer(twist)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        // Pan, pinch and twist combine; the one-finger orbit stands alone.
        let multi: (UIGestureRecognizer) -> Bool = {
            $0 is UIPinchGestureRecognizer || $0 is UIRotationGestureRecognizer
                || (($0 as? UIPanGestureRecognizer)?.minimumNumberOfTouches ?? 0) >= 2
        }
        return multi(gestureRecognizer) && multi(other)
    }

    private func interrupt() {
        animation = nil
        velocity = .zero
        onInteraction?()
    }

    @objc private func handleOrbit(_ gesture: UIPanGestureRecognizer) {
        let scale = Float.pi / Float(max(min(bounds.width, bounds.height), 1)) * 1.1
        switch gesture.state {
        case .began:
            interrupt()
        case .changed:
            let t = gesture.translation(in: self)
            gesture.setTranslation(.zero, in: self)
            camera.orbit(dx: Float(t.x) * scale, dy: Float(t.y) * scale)
            setNeedsDisplay()
        case .ended:
            let v = gesture.velocity(in: self)
            velocity = SIMD2(Float(v.x), Float(v.y)) * scale
            if simd_length(velocity) > 0.3, !UIAccessibility.isReduceMotionEnabled { startDisplayLink() } else { velocity = .zero }
        default:
            break
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        if gesture.state == .began { interrupt() }
        guard gesture.state == .changed else { return }
        let t = gesture.translation(in: self)
        gesture.setTranslation(.zero, in: self)
        // Scale so the point under the fingers stays under them at the target's depth.
        let k = 2 * tan(camera.fieldOfView / 2) / Float(max(bounds.height, 1))
        camera.pan(dx: Float(t.x) * k, dy: Float(t.y) * k)
        setNeedsDisplay()
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        if gesture.state == .began { interrupt() }
        guard gesture.state == .changed, let renderer else { return }
        camera.zoom(by: Float(gesture.scale), sceneRadius: renderer.focusBounds.radius)
        gesture.scale = 1
        setNeedsDisplay()
    }

    @objc private func handleTwist(_ gesture: UIRotationGestureRecognizer) {
        if gesture.state == .began { interrupt() }
        guard gesture.state == .changed else { return }
        camera.yaw += Float(gesture.rotation)
        gesture.rotation = 0
        setNeedsDisplay()
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        interrupt()
        frameModel(animated: true)
    }

    // MARK: Motion

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        let targetShift = Float(bottomObscured)
        if abs(verticalShift - targetShift) > 0.001 {
            verticalShift += (targetShift - verticalShift) * 0.2
        } else {
            verticalShift = targetShift
        }
        if let animation {
            let t = min((link.timestamp - animation.start) / animation.duration, 1)
            let eased = Float(1 - pow(1 - t, 3))
            camera = animation.from.interpolated(to: animation.to, eased)
            if t >= 1 {
                camera = animation.to
                self.animation = nil
            }
        } else if simd_length(velocity) > 0.02 {
            let dt = Float(min(link.targetTimestamp - link.timestamp, 1.0 / 30))
            camera.orbit(dx: velocity.x * dt, dy: velocity.y * dt)
            velocity *= pow(0.02, dt)
        } else {
            velocity = .zero
        }
        setNeedsDisplay()
        if animation == nil, velocity == .zero, verticalShift == targetShift { stopDisplayLink() }
    }

    public override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil { stopDisplayLink() }
    }
}

/// Lets SwiftUI drive the camera of a `ModelCanvas` (reset, presets).
@MainActor
public final class ModelCanvasController {
    weak var view: ModelCanvasView?

    public init() {}

    public func resetView() { view?.resetView() }
    public func show(_ preset: OrbitCamera.Preset) { view?.show(preset) }
    public func frameModel() { view?.frameModel(animated: true) }
}

/// SwiftUI wrapper around `ModelCanvasView`.
public struct ModelCanvas: UIViewRepresentable {
    let model: Model3D?
    let appearance: RenderAppearance
    let controller: ModelCanvasController?
    let onInteraction: (() -> Void)?
    let bottomObscured: CGFloat

    public init(model: Model3D?, appearance: RenderAppearance, controller: ModelCanvasController? = nil, bottomObscured: CGFloat = 0, onInteraction: (() -> Void)? = nil) {
        self.model = model
        self.appearance = appearance
        self.controller = controller
        self.bottomObscured = bottomObscured
        self.onInteraction = onInteraction
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public final class Coordinator {
        var modelID: UUID?
    }

    public func makeUIView(context: Context) -> ModelCanvasView {
        let view = ModelCanvasView()
        view.appearance = appearance
        view.setModel(model)
        context.coordinator.modelID = model?.id
        controller?.view = view
        view.onInteraction = onInteraction
        return view
    }

    public func updateUIView(_ view: ModelCanvasView, context: Context) {
        if context.coordinator.modelID != model?.id {
            context.coordinator.modelID = model?.id
            view.appearance = appearance
            view.setModel(model)
        } else {
            view.appearance = appearance
        }
        controller?.view = view
        view.onInteraction = onInteraction
        view.bottomObscured = bottomObscured
    }
}
#endif
