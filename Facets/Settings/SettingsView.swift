import SwiftUI

enum AppInfo {
    static let sourceURL = URL(string: "https://github.com/Tallack-Media-Corp/facets")!

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
}

struct SettingsView: View {
    @Environment(ViewerSettings.self) private var settings
    @Environment(FileLibrary.self) private var library

    /// Where the library is when it isn't in iCloud.
    static var deviceName: String {
        #if os(macOS)
        "On This Mac"
        #else
        UIDevice.current.userInterfaceIdiom == .pad ? "On This iPad" : "On This iPhone"
        #endif
    }
    @State private var cacheSize: Int64?

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section {
                    ModelColorPicker(hex: $settings.colorHex)
                    Toggle("Use Colours from 3MF Files", isOn: $settings.usesFileColors)
                } header: {
                    Text("Model Colour")
                } footer: {
                    Text("3MF projects from Bambu Studio, Orca Slicer and others carry filament colours. STL files always use the model colour.")
                }

                Section {
                    Toggle("Show Build Plate Grid", isOn: $settings.showsGrid)
                    Toggle("Pure Black in Dark Mode", isOn: $settings.pureBlack)
                    Picker("Units", selection: $settings.units) {
                        ForEach(MeasurementUnits.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Filament for Estimates", selection: $settings.material) {
                        ForEach(FilamentMaterial.allCases) { Text($0.title).tag($0) }
                    }
                } header: {
                    Text("Viewer")
                } footer: {
                    Text("The grid setting is where each model starts; the viewer's Display menu changes it for that model. Filament for Estimates sets the material used to estimate weight. Pure Black takes the viewer and thumbnail backgrounds to true black in dark mode, for OLED screens.")
                }

                Section {
                    Toggle("Check Fit Against a Printer", isOn: $settings.checksFit.animation())
                    if settings.checksFit {
                        NavigationLink {
                            PrinterBedPicker()
                        } label: {
                            LabeledContent("Printer Bed", value: settings.bed?.title ?? "None")
                        }
                    }
                } header: {
                    Text("Printer")
                } footer: {
                    Text(settings.checksFit
                         ? "The viewer outlines the printer's bed under each model and says whether it fits."
                         : "The viewer shows the model's dimensions only.")
                }

                #if os(iOS)
                Section("App Icon") {
                    AppIconPicker()
                }
                #endif

                Section {
                    LabeledContent("Library", value: library.location == .iCloud ? "iCloud Drive" : Self.deviceName)
                    #if os(macOS)
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([library.root])
                    }
                    #endif
                    NavigationLink {
                        RecentlyDeletedView()
                    } label: {
                        Label("Recently Deleted", systemImage: "trash")
                    }
                    Button("Clear Thumbnail Cache") {
                        Task {
                            await ThumbnailStore.shared.clear()
                            cacheSize = await ThumbnailStore.shared.diskUsage()
                        }
                    }
                } header: {
                    Text("Storage")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(library.location == .iCloud
                             ? "The library is the Facets folder in iCloud Drive, shared by your iPhone, iPad and Mac."
                             : "To share the library between your devices, sign in to iCloud and turn on iCloud Drive for Facets. Models here move to iCloud Drive when you do.")
                        if let cacheSize {
                            Text("Thumbnails use \(Format.fileSize(cacheSize)). They're redrawn when needed.")
                        }
                    }
                }

                Section {
                    LabeledContent("Version", value: AppInfo.version)
                    Link(destination: AppInfo.sourceURL) {
                        Label("Source Code on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("About Facets", systemImage: "info.circle")
                    }
                } header: {
                    Text("About")
                } footer: {
                    Text("Facets is free and open source. It makes no network connections of its own and collects nothing; your library syncs through your own iCloud Drive.")
                }
            }
            .navigationTitle("Settings")
            .task { cacheSize = await ThumbnailStore.shared.diskUsage() }
        }
    }
}

/// Filament-style swatches, plus the system picker for anything else.
private struct ModelColorPicker: View {
    @Binding var hex: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Every preset visible at once, wrapping as the row narrows or text grows.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44, maximum: 52), spacing: 4)], spacing: 4) {
                ForEach(ModelColorPreset.all) { preset in
                    let selected = preset.hex.caseInsensitiveCompare(hex) == .orderedSame
                    Button {
                        hex = preset.hex
                    } label: {
                        Circle()
                            .fill(Color(hex: preset.hex) ?? .gray)
                            .overlay(Circle().strokeBorder(.quaternary, lineWidth: 1))
                            .padding(selected ? 4 : 0)
                            .overlay {
                                if selected { Circle().strokeBorder(.tint, lineWidth: 2.5) }
                            }
                            .frame(width: 36, height: 36)
                            .frame(width: 44, height: 44)
                            .contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(preset.name)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.vertical, 2)
            ColorPicker("Custom Colour", selection: Binding(
                get: { Color(hex: hex) ?? .orange },
                set: { hex = $0.hexString }
            ), supportsOpacity: false)
        }
    }
}

private struct AboutView: View {
    @Environment(FileLibrary.self) private var library

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Facets")
                        .font(.title2.bold())
                    Text("A small, fast viewer for 3D printing files. Open STL, 3MF and OBJ models from anywhere on your iPhone or iPad, keep a library of them, and preview them right in the Files app.")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            Section("Opening Files") {
                Label("Tap an STL, 3MF or OBJ in Files, Mail or Messages and choose Facets.", systemImage: "doc")
                Label(library.location == .iCloud
                      ? "In the Files app, your library is the Facets folder in iCloud Drive."
                      : "In the Files app, your library is under \(SettingsView.deviceName) › Facets.", systemImage: "folder")
                Label("To look through a folder without importing, add it under Library › Browse.", systemImage: "folder.badge.plus")
                Label("Long-press a model in Files for a 3D Quick Look preview.", systemImage: "eye")
            }
            Section("Gestures") {
                Label("Drag to turn the model", systemImage: "hand.draw")
                Label("Pinch to zoom, two fingers to move", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                Label("Twist two fingers to spin", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                Label("Double tap to fit the model", systemImage: "hand.tap")
            }
            Section {
                OpenSampleButton()
            } header: {
                Text("Sample Model")
            } footer: {
                Text(SampleModels.credit)
            }
            Section("Licence") {
                Text("MIT Licence. The source code, issues and releases are on GitHub.")
                Text("The Benchy icon is drawn from #3DBenchy by Creative Tools, a public domain (CC0) model. 3DBenchy.com")
                    .foregroundStyle(.secondary)
                Link("github.com/Tallack-Media-Corp/facets", destination: AppInfo.sourceURL)
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}
