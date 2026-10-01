import SwiftUI

enum AppInfo {
    static let sourceURL = URL(string: "https://github.com/BTallack/facet")!

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
}

struct SettingsView: View {
    @Environment(ViewerSettings.self) private var settings
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

                Section("Viewer") {
                    Toggle("Show Build Plate Grid", isOn: $settings.showsGrid)
                    Picker("Units", selection: $settings.units) {
                        ForEach(MeasurementUnits.allCases) { Text($0.title).tag($0) }
                    }
                }

                Section {
                    Button("Clear Thumbnail Cache") {
                        Task {
                            await ThumbnailStore.shared.clear()
                            cacheSize = await ThumbnailStore.shared.diskUsage()
                        }
                    }
                } header: {
                    Text("Storage")
                } footer: {
                    if let cacheSize {
                        Text("Thumbnails use \(Format.fileSize(cacheSize)). They're redrawn when needed.")
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
                        Label("About Facet", systemImage: "info.circle")
                    }
                } header: {
                    Text("About")
                } footer: {
                    Text("Facet is free and open source. It has no network access and collects nothing.")
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
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
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
                                .contentShape(.circle)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(preset.name)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            ColorPicker("Custom Colour", selection: Binding(
                get: { Color(hex: hex) ?? .orange },
                set: { hex = $0.hexString }
            ), supportsOpacity: false)
        }
    }
}

private struct AboutView: View {
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Facet")
                        .font(.title2.bold())
                    Text("A small, fast viewer for 3D printing files. Open STL and 3MF models from anywhere on your iPhone or iPad, keep a library of them, and preview them right in the Files app.")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            Section("Opening Files") {
                Label("Tap an STL or 3MF in Files, Mail or Messages and choose Facet.", systemImage: "doc")
                Label("In the Files app, Facet's library is under On My iPhone › Facet.", systemImage: "folder")
                Label("Long-press a model in Files for a 3D Quick Look preview.", systemImage: "eye")
            }
            Section("Gestures") {
                Label("Drag to turn the model", systemImage: "hand.draw")
                Label("Pinch to zoom, two fingers to move", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                Label("Twist two fingers to spin", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                Label("Double tap to fit the model", systemImage: "hand.tap")
            }
            Section("Licence") {
                Text("MIT Licence. The source code, issues and releases are on GitHub.")
                Link("github.com/BTallack/facet", destination: AppInfo.sourceURL)
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}
