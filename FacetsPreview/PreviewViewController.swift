import MeshKit
import QuickLook
#if os(iOS)
import UIKit

/// Quick Look for STL, 3MF and OBJ: long-press a model in Files, or tap one in Mail or
/// Messages, and it turns in 3D right there.
final class PreviewViewController: UIViewController, QLPreviewingController {
    private let canvas = ModelCanvasView()
    private let backdrop = CAGradientLayer()
    private let plateBar = PlateBar()

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
        plateBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(plateBar)
        NSLayoutConstraint.activate([
            plateBar.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            plateBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -Spacing.lg),
        ])
        plateBar.onChange = { [weak self] id in self?.canvas.renderAppearance.plateID = id }
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
        try checkPreviewSize(url)
        let model = try await Task.detached(priority: .userInitiated) {
            try ModelLoader.load(url)
        }.value
        canvas.renderAppearance.plateID = model.plates.first?.id
        canvas.setModel(model)
        plateBar.show(model.plates)
    }
}

/// "‹ Plate 2 of 4 ›" under a multi-plate project: it says there's more than one, and
/// where Quick Look lets the preview be touched, the arrows step through them.
private final class PlateBar: UIVisualEffectView, PlateStepping {
    var onChange: ((Int) -> Void)?
    var steps = PlateSteps()
    private let label = UILabel()
    private let backButton = UIButton(type: .system)
    private let forwardButton = UIButton(type: .system)

    init() {
        super.init(effect: UIGlassEffect())
        cornerConfiguration = .capsule()
        isHidden = true
        label.font = UIFont.preferredFont(forTextStyle: .subheadline).withTraits(.traitBold)
        label.adjustsFontForContentSizeCategory = true
        for (button, symbol, name, by) in [(backButton, PlateSteps.previousSymbol, PlateSteps.previousName, -1), (forwardButton, PlateSteps.nextSymbol, PlateSteps.nextName, 1)] {
            button.setImage(UIImage(systemName: symbol), for: .normal)
            button.accessibilityLabel = name
            button.addAction(UIAction { [weak self] _ in self?.step(by) }, for: .primaryActionTriggered)
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: Size.minTapTarget),
                button.heightAnchor.constraint(equalToConstant: Size.minTapTarget),
            ])
        }
        let stack = UIStackView(arrangedSubviews: [backButton, label, forwardButton])
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func render() {
        isHidden = !steps.isNeeded
        label.text = steps.title
        label.accessibilityLabel = steps.accessibilityTitle
        backButton.isEnabled = steps.canGoBack
        forwardButton.isEnabled = steps.canGoForward
    }
}

private extension UIFont {
    func withTraits(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
        fontDescriptor.withSymbolicTraits(traits).map { UIFont(descriptor: $0, size: 0) } ?? self
    }
}
#else
import AppKit
import Quartz

/// Quick Look for STL, 3MF and OBJ in the Finder: press Space on a model and it turns
/// in 3D, on Quick Look's own background.
final class PreviewViewController: NSViewController, QLPreviewingController {
    private let canvas = ModelCanvasView()
    private let plateBar = PlateBar()

    override func loadView() {
        let stage = StageView()
        stage.onAppearanceChange = { [weak self] dark in
            self?.canvas.renderAppearance.gridColor = RenderAppearance.gridColor(dark: dark)
        }
        canvas.frame = stage.bounds
        canvas.autoresizingMask = [.width, .height]
        stage.addSubview(canvas)
        plateBar.translatesAutoresizingMaskIntoConstraints = false
        stage.addSubview(plateBar)
        NSLayoutConstraint.activate([
            plateBar.centerXAnchor.constraint(equalTo: stage.centerXAnchor),
            plateBar.bottomAnchor.constraint(equalTo: stage.bottomAnchor, constant: -Spacing.lg),
        ])
        plateBar.onChange = { [weak self] id in self?.canvas.renderAppearance.plateID = id }
        view = stage
        preferredContentSize = NSSize(width: 800, height: 600)
    }

    func preparePreviewOfFile(at url: URL) async throws {
        try checkPreviewSize(url)
        let model = try await Task.detached(priority: .userInitiated) {
            try ModelLoader.load(url)
        }.value
        canvas.renderAppearance.plateID = model.plates.first?.id
        canvas.setModel(model)
        plateBar.show(model.plates)
    }
}

/// "‹ Plate 2 of 4 ›" under a multi-plate project, as on iOS: a glass capsule, the
/// label in the subheadline style, arrows with the same 44pt targets.
private final class PlateBar: NSGlassEffectView, PlateStepping {
    var onChange: ((Int) -> Void)?
    var steps = PlateSteps()
    private let label = NSTextField(labelWithString: "")
    private lazy var backButton = button(PlateSteps.previousSymbol, PlateSteps.previousName, #selector(goBack))
    private lazy var forwardButton = button(PlateSteps.nextSymbol, PlateSteps.nextName, #selector(goForward))

    init() {
        super.init(frame: .zero)
        isHidden = true
        label.font = NSFont.preferredFont(forTextStyle: .subheadline).withTraits(.bold)
        let stack = NSStackView(views: [backButton, label, forwardButton])
        stack.spacing = 0
        contentView = stack
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// A capsule at whatever height the text gives it.
    override func layout() {
        super.layout()
        cornerRadius = bounds.height / 2
    }

    private func button(_ symbol: String, _ name: String, _ action: Selector) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: name) ?? NSImage(), target: self, action: action)
        button.isBordered = false
        button.setAccessibilityLabel(name)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: Size.minTapTarget),
            button.heightAnchor.constraint(equalToConstant: Size.minTapTarget),
        ])
        return button
    }

    @objc private func goBack() { step(-1) }
    @objc private func goForward() { step(1) }

    func render() {
        isHidden = !steps.isNeeded
        label.stringValue = steps.title
        label.setAccessibilityLabel(steps.accessibilityTitle)
        backButton.isEnabled = steps.canGoBack
        forwardButton.isEnabled = steps.canGoForward
    }
}

private extension NSFont {
    func withTraits(_ traits: NSFontDescriptor.SymbolicTraits) -> NSFont {
        NSFont(descriptor: fontDescriptor.withSymbolicTraits(traits), size: 0) ?? self
    }
}

/// No stage of our own on the Mac: the model sits on the Quick Look panel's own
/// translucent material, as the system's 3D preview does (it sets a clear
/// background), so it feels part of the Finder in light and dark. Only the grid
/// follows the appearance.
private final class StageView: NSView {
    var onAppearanceChange: ((Bool) -> Void)? {
        didSet { updateColors() }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        onAppearanceChange?(effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
    }
}
#endif

/// Which plate of a multi-plate project the preview shows.
struct PlateSteps {
    var plates: [Plate] = []
    private(set) var index = 0

    static let previousName = String(localized: "Previous Plate")
    static let nextName = String(localized: "Next Plate")
    static let previousSymbol = "chevron.left"
    static let nextSymbol = "chevron.right"

    var isNeeded: Bool { plates.count > 1 }
    var canGoBack: Bool { index > 0 }
    var canGoForward: Bool { index < plates.count - 1 }
    /// A page indicator, so by position; the plate's own name is spoken too.
    var title: String {
        String(localized: "Plate \(index + 1) of \(plates.count)", comment: "Quick Look: which plate of a multi-plate project is shown")
    }
    var accessibilityTitle: String {
        guard plates.indices.contains(index), let name = plates[index].name, !name.isEmpty else { return title }
        return String(localized: "Plate \(index + 1) of \(plates.count), \(name)", comment: "Quick Look, VoiceOver: which plate is shown, then its name")
    }

    /// Moves by one plate; the new plate's id, or nil at either end.
    mutating func step(_ by: Int) -> Int? {
        let next = index + by
        guard plates.indices.contains(next) else { return nil }
        index = next
        return plates[next].id
    }
}

/// What both platforms' plate bars share: showing a project's plates and stepping
/// through them. Each bar only draws `steps` in `render()`.
@MainActor
protocol PlateStepping: AnyObject {
    var steps: PlateSteps { get set }
    var onChange: ((Int) -> Void)? { get }
    func render()
}

extension PlateStepping {
    func show(_ plates: [Plate]) {
        steps = PlateSteps(plates: plates)
        render()
    }

    func step(_ by: Int) {
        guard let id = steps.step(by) else { return }
        render()
        onChange?(id)
    }
}

/// Past the preview's limits (`QuickLookLimits`), it says the model is too large
/// instead of being stopped mid-load.
private func checkPreviewSize(_ url: URL) throws {
    guard QuickLookLimits.check(url, for: .preview).fits else { throw ModelError.tooLarge }
}
