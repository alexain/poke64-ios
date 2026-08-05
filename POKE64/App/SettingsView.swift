import SwiftUI

enum SettingsPanel: String, CaseIterable, Identifiable {
    case system
    case graphics
    case audio
    case tape
    case diskDrives
    case printer
    case firmware
    case networking
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .graphics: "Graphics"
        case .audio: "Audio"
        case .tape: "Tape"
        case .diskDrives: "Disk Drives"
        case .printer: "Printer"
        case .firmware: "Firmware / ROMs"
        case .networking: "Networking"
        case .about: "About"
        }
    }

    var icon: String {
        switch self {
        case .system: "cpu"
        case .graphics: "display"
        case .audio: "waveform"
        case .tape: "rectangle.stack"
        case .diskDrives: "externaldrive"
        case .printer: "printer"
        case .firmware: "memorychip"
        case .networking: "network"
        case .about: "info.circle"
        }
    }

    var summary: String {
        switch self {
        case .system:
            "C64 model, timing and machine hardware."
        case .graphics:
            "Display geometry, palette and CRT presentation."
        case .audio:
            "SID model, emulation engine and audio output."
        case .tape:
            "Datasette behavior and tape transport options."
        case .diskDrives:
            "Drive units, models and True Drive Emulation."
        case .printer:
            "Commodore printer emulation and PDF output."
        case .firmware:
            "BASIC, KERNAL, character and drive ROMs."
        case .networking:
            "Virtual modem, Telnet and BBS connectivity."
        case .about:
            "Version, credits, licenses and project links."
        }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selection: SettingsPanel

    init(initialPanel: SettingsPanel = .system) {
        _selection = State(initialValue: initialPanel)
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsPanel.allCases) { panel in
                Button {
                    selection = panel
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(panel.title)
                            Text(panel.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    } icon: {
                        Image(systemName: panel.icon)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(
                    selection == panel
                        ? Color.accentColor.opacity(0.16)
                        : Color.clear
                )
                .padding(.vertical, 3)
            }
            .navigationTitle("Settings")
            .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 340)
        } detail: {
            SettingsPanelDetail(panel: selection)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }
}

private struct SettingsPanelDetail: View {
    let panel: SettingsPanel

    var body: some View {
        Group {
            switch panel {
            case .system:
                SettingsPlaceholderView(
                    panel: panel,
                    plannedFeatures: [
                        "C64 model and regional timing",
                        "CPU and VIC-II configuration",
                        "CIA and machine-level compatibility options"
                    ]
                )
            case .graphics:
                SettingsPlaceholderView(
                    panel: panel,
                    plannedFeatures: [
                        "Palette and display adjustments",
                        "Aspect ratio, cropping and integer scaling",
                        "Metal CRT shader presets"
                    ]
                )
            case .audio:
                SettingsPlaceholderView(
                    panel: panel,
                    plannedFeatures: [
                        "SID 6581 and 8580 models",
                        "SID emulation engine and filters",
                        "Dual-SID configuration"
                    ]
                )
            case .tape:
                SettingsPlaceholderView(
                    panel: panel,
                    plannedFeatures: [
                        "Datasette configuration",
                        "Tape counter and transport behavior",
                        "Autostart and loading options"
                    ]
                )
            case .diskDrives:
                SettingsPlaceholderView(
                    panel: panel,
                    plannedFeatures: [
                        "Units 8, 9, 10 and 11",
                        "Drive model and firmware selection",
                        "True Drive Emulation and drive sounds"
                    ]
                )
            case .printer:
                SettingsPlaceholderView(
                    panel: panel,
                    plannedFeatures: [
                        "MPS-801, MPS-802 and MPS-803",
                        "Dot-matrix PDF rendering",
                        "Print queue, paper and ribbon options"
                    ]
                )
            case .firmware:
                FirmwareSettingsView()
            case .networking:
                SettingsPlaceholderView(
                    panel: panel,
                    plannedFeatures: [
                        "Hayes-compatible virtual modem",
                        "Telnet and raw TCP",
                        "BBS directory and connection status"
                    ]
                )
            case .about:
                AboutSettingsView()
            }
        }
        .navigationTitle(panel.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SettingsPlaceholderView: View {
    let panel: SettingsPanel
    let plannedFeatures: [String]

    var body: some View {
        Form {
            Section {
                Label(panel.summary, systemImage: panel.icon)
                    .font(.headline)
            }

            Section("Planned") {
                ForEach(plannedFeatures, id: \.self) { feature in
                    Label(feature, systemImage: "circle.dashed")
                }
            }

            Section {
                Text("This panel establishes the settings structure and will be implemented incrementally in upcoming releases.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct AboutSettingsView: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "Development"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? "Development"
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image("AppIconPreview")
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .accessibilityLabel("POKE64 app icon")

                    VStack(alignment: .leading, spacing: 4) {
                        Text("POKE64")
                            .font(.title2.weight(.semibold))
                        Text("Native Commodore 64 emulator for iPad")
                            .foregroundStyle(.secondary)
                        Text("Version \(version) (\(build))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }

            Section("Technology") {
                LabeledContent("Emulation", value: "VICE x64sc / libretro")
                LabeledContent("Interface", value: "SwiftUI + UIKit")
                LabeledContent("Video", value: "Metal")
                LabeledContent("Audio", value: "AVAudioEngine")
            }

            Section("Created by") {
                Text("Created by Alessandro Capano in 2026.")
                Link("www.alexain.it/poke64", destination: URL(string: "https://www.alexain.it/poke64")!)
            }

            Section("Credits and licenses") {
                Text("POKE64 is an independent open-source project. It is not affiliated with Commodore, VICE, RetroArch or libretro.")
                Text("See LICENSE and THIRD_PARTY_NOTICES.md in the repository for complete licensing information.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
