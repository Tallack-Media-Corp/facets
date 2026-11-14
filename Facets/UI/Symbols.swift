/// Every SF Symbol the app shows, one constant per concept, so a control, its menu
/// item and its tip always show the same glyph. Where one glyph serves two concepts
/// (a ruler for size, units and Measure), each has its own constant so they can
/// change apart.
enum Symbol {
    // MARK: Places

    /// The library: its tab, and its root in the Move sheet.
    static let library = "square.grid.2x2"
    static let recents = "clock"
    /// Settings, everywhere (the tab, the Mac sidebar's gear).
    static let settings = "gearshape"
    static let search = "magnifyingglass"
    static let folder = "folder"
    /// The large glyph on a folder tile.
    static let folderTile = "folder.fill"
    /// A Browse location in iCloud Drive.
    static let cloudFolder = "icloud"
    /// A file or folder that's gone: moved, deleted or out of reach.
    static let missing = "questionmark.folder"

    // MARK: Library

    /// The library's Add menu (and its tip). Not for Save to Library.
    static let add = "plus"
    static let importFiles = "square.and.arrow.down"
    /// New Folder and Add Location share a glyph for now; two names, so they can part.
    static let newFolder = "folder.badge.plus"
    static let addLocation = "folder.badge.plus"
    static let openFile = "doc.badge.ellipsis"
    static let viewOptions = "ellipsis"
    static let iconsLayout = "square.grid.2x2"
    static let listLayout = "list.bullet"
    /// An empty library or folder.
    static let noModels = "cube.transparent"
    static let noRecents = "clock"
    static let nothingDeleted = "trash"
    static let share = "square.and.arrow.up"
    /// Save to Library: into your library. Not a plus, which means the Add menu.
    static let saveToLibrary = "tray.and.arrow.down"
    /// What Save to Library becomes once saved, and any other "done" state in place.
    static let saved = "checkmark"
    static let rename = "pencil"
    static let duplicate = "plus.square.on.square"
    static let move = "folder"
    static let delete = "trash"
    /// The toast after a delete.
    static let deleted = "trash.fill"
    /// Takes something off a list without touching the file.
    static let remove = "minus.circle"
    static let restore = "arrow.uturn.backward"
    /// A Recents entry opened from another app.
    static let fromAnotherApp = "arrow.up.forward.app"
    static let recentlyDeleted = "trash"
    static let sampleModel = "sailboat"
    /// A model, where the system shows one (Spotlight, Shortcuts).
    static let model = "cube"

    // MARK: Feedback

    /// A toast that went well.
    static let success = "checkmark.circle.fill"
    /// A small warning beside words: a warning toast, a printer the model doesn't fit,
    /// a Recents entry that's gone.
    static let warning = "exclamationmark.triangle.fill"
    /// Something that didn't work: a model that won't open or draw.
    static let failed = "exclamationmark.triangle"
    /// A printer the model fits.
    static let fits = "checkmark.circle"
    /// A picture still drawing.
    static let thumbnailPlaceholder = "cube.transparent"
    /// Not on this device: it downloads when opened.
    static let notDownloaded = "icloud.and.arrow.down"
    static let inCloud = "icloud"

    // MARK: Cards and sheets

    /// Close a card or viewer, or cancel a sheet.
    static let close = "xmark"
    /// A sheet's Done.
    static let done = "checkmark"
    /// The chosen row in a list of choices.
    static let chosen = "checkmark"
    static let choiceOn = "checkmark.circle.fill"
    static let choiceOff = "circle"
    /// Opens a chip's menu.
    static let chipMenu = "chevron.down"

    // MARK: Viewer

    static let fit = "viewfinder"
    static let presetViews = "move.3d"
    static let tools = "wrench.and.screwdriver"
    /// The Display menu: wireframe, grid, printer. Always this view-options glyph.
    static let display = "slider.horizontal.3"
    static let info = "info.circle"
    static let wireframe = "cube.transparent"
    static let grid = "grid"
    /// The size readout (its tip, and the dimensions shortcut).
    static let modelSize = "ruler"
    /// A file's units in question: the unit card and the readout's caption.
    static let units = "ruler"
    static let plate = "square.stack.3d.up"
    static let gestureTurn = "hand.draw"
    static let gestureFit = "hand.tap"

    // MARK: Viewer tools

    static let measure = "ruler"
    static let layFlat = "rotate.right"
    static let crossSection = "square.split.1x2"
    static let autoOrient = "wand.and.sparkles"
    /// Auto found nothing better.
    static let alreadyBest = "checkmark"
    static let turn = "arrow.clockwise"
    static let tipOver = "arrow.down.forward"
    static let roll = "arrow.turn.right.down"
    static let resetOrientation = "arrow.uturn.backward"
    static let cutLow = "square.bottomhalf.filled"
    static let cutHigh = "square.fill"

    // MARK: Preset views

    static let isometric = "cube"
    static let front = "square.bottomhalf.filled"
    static let back = "square.tophalf.filled"
    static let left = "square.lefthalf.filled"
    static let right = "square.righthalf.filled"
    static let top = "arrow.down.to.line"
    static let bottom = "arrow.up.to.line"

    // MARK: About

    static let sourceCode = "chevron.left.forwardslash.chevron.right"
    static let about = "info.circle"
    static let document = "doc"
    static let quickLook = "eye"
    static let gestureMove = "arrow.up.and.down.and.arrow.left.and.right"
    static let gestureSpin = "arrow.trianglehead.2.clockwise.rotate.90"
    static let doubleClick = "cursorarrow.click.2"
}
