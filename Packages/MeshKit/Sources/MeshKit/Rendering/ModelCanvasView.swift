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

    /// What a single tap on the model does.
    public enum Tool: Sendable, Equatable {
        /// Nothing: taps are ignored (a double tap still frames the model).
        case none
        /// Picks points, snapping to a nearby corner of the face.
        case measure
        /// Picks a face, for laying it flat.
        case face
    }

    public var tool: Tool = .none

    /// A tap landed on the model while a tool is active. For `.measure` the point is
    /// snapped to a corner within reach of the finger.
    public var onSurfaceTap: ((SurfaceHit, SIMD3<Float>) -> Void)?

    /// Points drawn over the model (world space): a dot each, and a line between each
    /// pair in turn. Used for measuring.
    public var markers: [SIMD3<Float>] = [] {
        didSet {
            guard markers != oldValue else { return }
            updateMarkers()
        }
    }
    private let markerHalo = CAShapeLayer()
    private let markerLine = CAShapeLayer()
    private let markerDots = CAShapeLayer()

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
        // No direct interaction: it would hand VoiceOver's swipes to the model and
        // hide the camera actions below.
        accessibilityTraits = [.image]
        accessibilityLabel = "3D model"
        installAccessibilityActions()
        installMarkerLayers()
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

    /// Swaps in a rearranged version of the same model (turned or laid flat), keeping
    /// the viewing angle and easing to the new framing.
    public func replaceModel(_ model: Model3D?) {
        renderer?.setModel(model)
        renderer?.appearance = appearance
        frameModel(animated: true)
        setNeedsDisplay()
    }

    /// Frames what's visible without changing the viewing angle.
    public func frameModel(animated: Bool) {
        guard let renderer, bounds.width > 0, bounds.height > 0 else { needsFit = true; return }
        var next = camera
        next.fitTightly(renderer.visibleParts, aspect: aspect, fill: 0.72, recenter: false, including: bedCorners)
        move(to: next, animated: animated)
        needsFit = false
    }

    public func show(_ preset: OrbitCamera.Preset, animated: Bool = true) {
        guard let renderer else { return }
        var next = camera
        next.apply(preset)
        next.fitTightly(renderer.visibleParts, aspect: aspect, fill: 0.72, recenter: false, including: bedCorners)
        move(to: next, animated: animated)
    }

    /// The bed's corners, when framing should show the whole bed: the model doesn't
    /// fit (so the overhang is in view), or it covers much of the bed. A small part
    /// on a big bed is framed on its own, or it would be a speck.
    private var bedCorners: [SIMD3<Float>] {
        guard let renderer, appearance.showsGrid, let bed = appearance.bed else { return [] }
        let footprint = renderer.focusBounds
        guard !footprint.isEmpty else { return [] }
        let bedSpan = max(bed.max.x - bed.min.x, bed.max.y - bed.min.y)
        let modelSpan = max(footprint.size.x, footprint.size.y)
        guard !bed.fits || modelSpan > bedSpan * 0.5 else { return [] }
        let z = footprint.min.z
        return [SIMD3(bed.min.x, bed.min.y, z), SIMD3(bed.max.x, bed.min.y, z), SIMD3(bed.max.x, bed.max.y, z), SIMD3(bed.min.x, bed.max.y, z)]
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

    // MARK: VoiceOver

    /// VoiceOver users can't drag or pinch, so the camera moves by action instead:
    /// swipe up or down on the model to pick one.
    private func installAccessibilityActions() {
        func action(_ name: String, _ perform: @escaping @MainActor (ModelCanvasView) -> Void) -> UIAccessibilityCustomAction {
            UIAccessibilityCustomAction(name: name) { [weak self] _ in
                guard let self else { return false }
                perform(self)
                // The view changed out of sight: say what happened.
                UIAccessibility.post(notification: .announcement, argument: name)
                return true
            }
        }
        let step = Float.pi / 6
        accessibilityCustomActions = [
            action("Turn left") { $0.nudge(yaw: step, pitch: 0) },
            action("Turn right") { $0.nudge(yaw: -step, pitch: 0) },
            action("Tilt up") { $0.nudge(yaw: 0, pitch: step / 2) },
            action("Tilt down") { $0.nudge(yaw: 0, pitch: -step / 2) },
            action("Front view") { $0.show(.front) },
            action("Top view") { $0.show(.top) },
            action("Isometric view") { $0.show(.isometric) },
            action("Fit to screen") { $0.frameModel(animated: true) },
        ]
    }

    private func nudge(yaw: Float, pitch: Float) {
        var next = camera
        next.orbit(dx: yaw, dy: pitch)
        move(to: next, animated: true)
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
        if !markers.isEmpty { updateMarkers() }
    }

    // MARK: Picking and markers

    private var viewProjection: simd_float4x4? {
        guard let renderer, bounds.width > 0, bounds.height > 0 else { return nil }
        return renderer.viewProjection(camera: camera, aspect: aspect, verticalShift: verticalShift)
    }

    /// Where a world point lands on screen, in points; nil behind the camera.
    public func screenPoint(of world: SIMD3<Float>) -> CGPoint? {
        guard let viewProjection else { return nil }
        let clip = viewProjection * SIMD4(world, 1)
        guard clip.w > 0 else { return nil }
        let ndc = SIMD2(clip.x, clip.y) / clip.w
        return CGPoint(x: CGFloat((ndc.x + 1) / 2) * bounds.width, y: CGFloat((1 - ndc.y) / 2) * bounds.height)
    }

    /// The ray from the eye through a point on screen.
    private func ray(through point: CGPoint) -> (origin: SIMD3<Float>, direction: SIMD3<Float>)? {
        guard let viewProjection else { return nil }
        let inverse = viewProjection.inverse
        let x = Float(point.x / bounds.width) * 2 - 1
        let y = 1 - Float(point.y / bounds.height) * 2
        let near = inverse * SIMD4(x, y, 0, 1)
        let far = inverse * SIMD4(x, y, 1, 1)
        guard near.w != 0, far.w != 0 else { return nil }
        let a = SIMD3(near.x, near.y, near.z) / near.w
        let b = SIMD3(far.x, far.y, far.z) / far.w
        let direction = b - a
        guard simd_length(direction) > 0 else { return nil }
        return (a, simd_normalize(direction))
    }

    /// What's under a point on screen; respects the cross-section, so a cut-away top
    /// can't be picked.
    public func surface(at point: CGPoint) -> SurfaceHit? {
        guard let renderer, let model = renderer.model, let ray = ray(through: point) else { return nil }
        let appearance = renderer.appearance
        guard let cut = appearance.sectionHeight else {
            return model.hit(origin: ray.origin, direction: ray.direction, plateID: appearance.plateID, hidden: appearance.hiddenObjects)
        }
        // Step past hits in the removed part until one lies below the cut.
        var origin = ray.origin
        for _ in 0..<32 {
            guard let hit = model.hit(origin: origin, direction: ray.direction, plateID: appearance.plateID, hidden: appearance.hiddenObjects) else { return nil }
            if hit.point.z <= cut + 0.001 { return hit }
            origin = hit.point + ray.direction * max(renderer.focusBounds.radius * 1e-5, 1e-4)
        }
        return nil
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard tool != .none else { return }
        let location = gesture.location(in: self)
        guard let hit = surface(at: location) else { return }
        var point = hit.point
        if tool == .measure {
            // A corner within a fingertip wins: measuring edge to edge is the usual job.
            var best: CGFloat = 22
            for corner in hit.corners {
                guard let screen = screenPoint(of: corner) else { continue }
                let d = hypot(screen.x - location.x, screen.y - location.y)
                if d < best {
                    best = d
                    point = corner
                }
            }
        }
        onSurfaceTap?(hit, point)
    }

    private func installMarkerLayers() {
        for layer in [markerHalo, markerLine, markerDots] {
            layer.fillColor = nil
            layer.lineCap = .round
            layer.lineJoin = .round
            layer.actions = ["path": NSNull(), "position": NSNull(), "bounds": NSNull()]
            self.layer.addSublayer(layer)
        }
        // Ink on a halo: the model is often the accent colour, so the accent alone
        // would vanish against it.
        markerHalo.lineWidth = 6
        markerLine.lineWidth = 2
        markerDots.lineWidth = 2.5
        updateMarkerColors()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: ModelCanvasView, _: UITraitCollection) in
            view.updateMarkerColors()
        }
    }

    private func updateMarkerColors() {
        let ink = UIColor.label.resolvedColor(with: traitCollection).cgColor
        let halo = UIColor.systemBackground.resolvedColor(with: traitCollection).withAlphaComponent(0.85).cgColor
        markerHalo.strokeColor = halo
        markerLine.strokeColor = ink
        markerDots.strokeColor = ink
        markerDots.fillColor = halo
    }

    private func updateMarkers() {
        markerHalo.frame = bounds
        markerLine.frame = bounds
        markerDots.frame = bounds
        let screen = markers.map { screenPoint(of: $0) }
        let line = UIBezierPath()
        var index = 0
        while index + 1 < screen.count {
            if let a = screen[index], let b = screen[index + 1] {
                line.move(to: a)
                line.addLine(to: b)
            }
            index += 2
        }
        let dots = UIBezierPath()
        for case let point? in screen {
            dots.append(UIBezierPath(ovalIn: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)))
        }
        markerHalo.path = line.cgPath
        markerLine.path = line.cgPath
        markerDots.path = dots.cgPath
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

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.require(toFail: doubleTap)
        addGestureRecognizer(tap)
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
    let tool: ModelCanvasView.Tool
    let markers: [SIMD3<Float>]
    let onSurfaceTap: ((SurfaceHit, SIMD3<Float>) -> Void)?

    public init(model: Model3D?, appearance: RenderAppearance, controller: ModelCanvasController? = nil, bottomObscured: CGFloat = 0, tool: ModelCanvasView.Tool = .none, markers: [SIMD3<Float>] = [], onSurfaceTap: ((SurfaceHit, SIMD3<Float>) -> Void)? = nil, onInteraction: (() -> Void)? = nil) {
        self.model = model
        self.appearance = appearance
        self.controller = controller
        self.bottomObscured = bottomObscured
        self.tool = tool
        self.markers = markers
        self.onSurfaceTap = onSurfaceTap
        self.onInteraction = onInteraction
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public final class Coordinator {
        var modelID: UUID?
        var sourceID: UUID?
    }

    public func makeUIView(context: Context) -> ModelCanvasView {
        let view = ModelCanvasView()
        view.appearance = appearance
        view.setModel(model)
        context.coordinator.modelID = model?.id
        context.coordinator.sourceID = model?.sourceID
        controller?.view = view
        view.onInteraction = onInteraction
        return view
    }

    public func updateUIView(_ view: ModelCanvasView, context: Context) {
        if context.coordinator.modelID != model?.id {
            let sameFile = model != nil && context.coordinator.sourceID == model?.sourceID
            context.coordinator.modelID = model?.id
            context.coordinator.sourceID = model?.sourceID
            view.appearance = appearance
            if sameFile {
                // Turned or laid flat: keep the camera's angle and reframe.
                view.replaceModel(model)
            } else {
                view.setModel(model)
            }
        } else {
            view.appearance = appearance
        }
        controller?.view = view
        view.onInteraction = onInteraction
        view.bottomObscured = bottomObscured
        view.tool = tool
        view.markers = markers
        view.onSurfaceTap = onSurfaceTap
    }
}
#endif
