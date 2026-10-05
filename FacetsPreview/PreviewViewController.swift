import MeshKit
import QuickLook
#if os(iOS)
import UIKit

/// Quick Look for STL, 3MF and OBJ: long-press a model in Files, or tap one in Mail or
/// Messages, and it turns in 3D right there.
final class PreviewViewController: UIViewController, QLPreviewingController {
    private let canvas = ModelCanvasView()
    private let backdrop = CAGradientLayer()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.layer.insertSublayer(backdrop, at: 0)
        canvas.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(canvas)
        NSLayoutConstraint.activate([
            canvas.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            canvas.topAnchor.constraint(equalTo: view.topAnchor),
            canvas.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        updateColors()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (controller: PreviewViewController, _) in
            controller.updateColors()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        backdrop.frame = view.bounds
    }

    private func updateColors() {
        let dark = traitCollection.userInterfaceStyle == .dark
        // The app's Stage, Pure Black included, so Quick Look and the viewer match.
        let stage = Palette.stage(pureBlack: SharedSettings.pureBlack)
        backdrop.colors = [stage.top, stage.floor].map { $0.resolvedColor(with: traitCollection).cgColor }
        canvas.renderAppearance.gridColor = RenderAppearance.gridColor(dark: dark)
    }

    func preparePreviewOfFile(at url: URL) async throws {
        let model = try await Task.detached(priority: .userInitiated) {
            try ModelLoader.load(url)
        }.value
        canvas.renderAppearance.plateID = model.plates.first?.id
        canvas.setModel(model)
    }
}
#else
import AppKit
import Quartz

/// Quick Look for STL, 3MF and OBJ in the Finder: press Space on a model and it turns
/// in 3D, on the same stage as the app.
final class PreviewViewController: NSViewController, QLPreviewingController {
    private let canvas = ModelCanvasView()

    override func loadView() {
        let stage = StageView()
        stage.onAppearanceChange = { [weak self] dark in
            self?.canvas.renderAppearance.gridColor = RenderAppearance.gridColor(dark: dark)
        }
        canvas.frame = stage.bounds
        canvas.autoresizingMask = [.width, .height]
        stage.addSubview(canvas)
        view = stage
        preferredContentSize = NSSize(width: 800, height: 600)
    }

    func preparePreviewOfFile(at url: URL) async throws {
        let model = try await Task.detached(priority: .userInitiated) {
            try ModelLoader.load(url)
        }.value
        canvas.renderAppearance.plateID = model.plates.first?.id
        canvas.setModel(model)
    }
}

/// The app's Stage behind the model (Pure Black included), redrawn when the Mac
/// switches between light and dark.
private final class StageView: NSView {
    var onAppearanceChange: ((Bool) -> Void)? {
        didSet { updateColors() }
    }
    private let backdrop = CAGradientLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(backdrop)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        backdrop.frame = bounds
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let stage = Palette.stage(pureBlack: SharedSettings.pureBlack)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            // Layers run bottom to top on the Mac, so the floor comes first.
            backdrop.colors = [stage.floor.cgColor, stage.top.cgColor]
        }
        onAppearanceChange?(dark)
    }
}
#endif
