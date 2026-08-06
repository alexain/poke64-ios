import SwiftUI

enum C64MachineModel: String, CaseIterable, Identifiable {
    case c64PAL = "C64 PAL"
    case c64NTSC = "C64 NTSC"
    case c64cPAL = "C64C PAL"
    case c64cNTSC = "C64C NTSC"

    static let defaultsKey = "poke64.machineModel"
    static let defaultModel: C64MachineModel = .c64PAL

    var id: String { rawValue }

    var title: String { rawValue }

    var region: String {
        switch self {
        case .c64PAL, .c64cPAL:
            return "PAL"
        case .c64NTSC, .c64cNTSC:
            return "NTSC"
        }
    }

    var timingSummary: String {
        switch self {
        case .c64PAL, .c64cPAL:
            return "approximately 50 Hz"
        case .c64NTSC, .c64cNTSC:
            return "approximately 59.94 Hz"
        }
    }

    var hardwareSummary: String {
        switch self {
        case .c64PAL, .c64NTSC:
            return "Original C64 hardware profile"
        case .c64cPAL, .c64cNTSC:
            return "Later C64C hardware profile"
        }
    }

    static var selected: C64MachineModel {
        get {
            guard let value = UserDefaults.standard.string(forKey: defaultsKey),
                  let model = C64MachineModel(rawValue: value) else {
                return defaultModel
            }
            return model
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
        }
    }
}


enum C64VideoAspectRatio: String, CaseIterable, Identifiable {
    case automatic = "auto"
    case pal
    case ntsc
    case raw

    static let defaultsKey = "poke64.video.aspectRatio"
    static let defaultValue: C64VideoAspectRatio = .automatic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic:
            return "Automatic"
        case .pal:
            return "PAL pixels"
        case .ntsc:
            return "NTSC pixels"
        case .raw:
            return "Raw pixels"
        }
    }
}

enum C64VideoCrop: String, CaseIterable, Identifiable {
    case disabled
    case small
    case medium
    case maximum
    case automatic = "auto"

    static let defaultsKey = "poke64.video.crop"
    static let defaultValue: C64VideoCrop = .disabled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .disabled:
            return "Full borders"
        case .small:
            return "Small crop"
        case .medium:
            return "Medium crop"
        case .maximum:
            return "Maximum crop"
        case .automatic:
            return "Automatic"
        }
    }
}

enum C64VideoPalette: String, CaseIterable, Identifiable {
    case internalPalette = "default"
    case vice
    case colodore
    case communityColors = "community-colors"
    case peptoPAL = "pepto-pal"
    case peptoNTSC = "pepto-ntsc"
    case theC64 = "the64"
    case rgb

    static let defaultsKey = "poke64.video.palette"
    static let defaultValue: C64VideoPalette = .internalPalette

    var id: String { rawValue }

    var title: String {
        switch self {
        case .internalPalette:
            return "Internal (adjustable)"
        case .vice:
            return "VICE Default"
        case .colodore:
            return "Colodore"
        case .communityColors:
            return "Community Colors"
        case .peptoPAL:
            return "Pepto PAL"
        case .peptoNTSC:
            return "Pepto NTSC"
        case .theC64:
            return "TheC64"
        case .rgb:
            return "RGB"
        }
    }

    var supportsColorAdjustments: Bool {
        self == .internalPalette
    }
}

enum C64VideoFilter: String, CaseIterable, Identifiable {
    case disabled
    case sharpPAL = "enabled_noblur"
    case lowBlur = "enabled_lowblur"
    case mediumBlur = "enabled_medblur"
    case authenticPAL = "enabled"

    static let defaultsKey = "poke64.video.filter"
    static let defaultValue: C64VideoFilter = .disabled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .disabled:
            return "Off"
        case .sharpPAL:
            return "Sharp PAL"
        case .lowBlur:
            return "Low Blur"
        case .mediumBlur:
            return "Medium Blur"
        case .authenticPAL:
            return "Authentic PAL"
        }
    }
}

enum C64VideoSettings {
    static let cropDelayKey = "poke64.video.cropDelay"
    static let brightnessKey = "poke64.video.brightness"
    static let contrastKey = "poke64.video.contrast"
    static let saturationKey = "poke64.video.saturation"
    static let gammaKey = "poke64.video.gamma"
    static let tintKey = "poke64.video.tint"

    static let defaultCropDelay = true
    static let defaultBrightness = 1000
    static let defaultContrast = 1000
    static let defaultSaturation = 1000
    static let defaultGamma = 2800
    static let defaultTint = 1000

    static var configurationFingerprint: String {
        let defaults = UserDefaults.standard
        return [
            defaults.string(forKey: C64VideoAspectRatio.defaultsKey)
                ?? C64VideoAspectRatio.defaultValue.rawValue,
            defaults.string(forKey: C64VideoCrop.defaultsKey)
                ?? C64VideoCrop.defaultValue.rawValue,
            String(defaults.object(forKey: cropDelayKey) == nil
                ? defaultCropDelay
                : defaults.bool(forKey: cropDelayKey)),
            defaults.string(forKey: C64VideoPalette.defaultsKey)
                ?? C64VideoPalette.defaultValue.rawValue,
            defaults.string(forKey: C64VideoFilter.defaultsKey)
                ?? C64VideoFilter.defaultValue.rawValue,
            String(defaults.object(forKey: brightnessKey) == nil
                ? defaultBrightness
                : defaults.integer(forKey: brightnessKey)),
            String(defaults.object(forKey: contrastKey) == nil
                ? defaultContrast
                : defaults.integer(forKey: contrastKey)),
            String(defaults.object(forKey: saturationKey) == nil
                ? defaultSaturation
                : defaults.integer(forKey: saturationKey)),
            String(defaults.object(forKey: gammaKey) == nil
                ? defaultGamma
                : defaults.integer(forKey: gammaKey)),
            String(defaults.object(forKey: tintKey) == nil
                ? defaultTint
                : defaults.integer(forKey: tintKey))
        ].joined(separator: ":")
    }
}

enum C64SIDEngine: String, CaseIterable, Identifiable {
    case fastSID = "FastSID"
    case reSID = "ReSID"
    case reSIDFP = "ReSID-FP"

    static let defaultsKey = "poke64.audio.sidEngine"
    static let defaultValue: C64SIDEngine = .reSID

    var id: String { rawValue }

    var title: String { rawValue }

    var detail: String {
        switch self {
        case .fastSID:
            return "Lowest CPU usage"
        case .reSID:
            return "Accurate"
        case .reSIDFP:
            return "Highest accuracy"
        }
    }
}

enum C64SIDModel: String, CaseIterable, Identifiable {
    case automatic = "default"
    case mos6581 = "6581"
    case mos8580 = "8580"
    case mos8580RD = "8580RD"

    static let defaultsKey = "poke64.audio.sidModel"
    static let defaultValue: C64SIDModel = .automatic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic:
            return "Automatic"
        case .mos6581:
            return "MOS 6581"
        case .mos8580:
            return "MOS 8580"
        case .mos8580RD:
            return "MOS 8580 RD"
        }
    }
}

enum C64ReSIDSampling: String, CaseIterable, Identifiable {
    case fast
    case interpolation
    case fastResampling = "fast resampling"
    case resampling

    static let defaultsKey = "poke64.audio.residSampling"
    static let defaultValue: C64ReSIDSampling = .resampling

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fast:
            return "Fast"
        case .interpolation:
            return "Interpolation"
        case .fastResampling:
            return "Fast Resampling"
        case .resampling:
            return "Resampling"
        }
    }
}

enum C64AudioSampleRate: String, CaseIterable, Identifiable {
    case hz44100 = "44100"
    case hz48000 = "48000"
    case hz96000 = "96000"

    static let defaultsKey = "poke64.audio.sampleRate"
    static let defaultValue: C64AudioSampleRate = .hz48000

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hz44100:
            return "44,100 Hz"
        case .hz48000:
            return "48,000 Hz"
        case .hz96000:
            return "96,000 Hz"
        }
    }
}

enum C64AudioSettings {
    static let audioLeakLevelKey = "poke64.audio.leakLevel"
    static let datasetteSoundLevelKey = "poke64.audio.datasetteSoundLevel"

    static let defaultAudioLeakLevel = 0
    static let defaultDatasetteSoundLevel = 0

    static var configurationFingerprint: String {
        let defaults = UserDefaults.standard
        return [
            defaults.string(forKey: C64SIDEngine.defaultsKey)
                ?? C64SIDEngine.defaultValue.rawValue,
            defaults.string(forKey: C64SIDModel.defaultsKey)
                ?? C64SIDModel.defaultValue.rawValue,
            defaults.string(forKey: C64ReSIDSampling.defaultsKey)
                ?? C64ReSIDSampling.defaultValue.rawValue,
            defaults.string(forKey: C64AudioSampleRate.defaultsKey)
                ?? C64AudioSampleRate.defaultValue.rawValue,
            String(defaults.object(forKey: audioLeakLevelKey) == nil
                ? defaultAudioLeakLevel
                : defaults.integer(forKey: audioLeakLevelKey)),
            String(defaults.object(forKey: datasetteSoundLevelKey) == nil
                ? defaultDatasetteSoundLevel
                : defaults.integer(forKey: datasetteSoundLevelKey))
        ].joined(separator: ":")
    }
}

enum C64DriveModel: String, CaseIterable, Identifiable {
    case cbm1541 = "1541"
    case cbm1541II = "1541-II"
    case cbm1571 = "1571"
    case cbm1581 = "1581"

    static let drive8DefaultsKey = "poke64.drive.model"
    static let drive9DefaultsKey = "poke64.drive9.model"
    static let defaultsKey = drive8DefaultsKey
    static let defaultValue: C64DriveModel = .cbm1541II

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cbm1541:
            return "Commodore 1541"
        case .cbm1541II:
            return "Commodore 1541-II"
        case .cbm1571:
            return "Commodore 1571"
        case .cbm1581:
            return "Commodore 1581"
        }
    }

    var resourceValue: Int {
        switch self {
        case .cbm1541: return 1541
        case .cbm1541II: return 1542
        case .cbm1571: return 1571
        case .cbm1581: return 1581
        }
    }

    var firmwareSlot: FirmwareSlot {
        switch self {
        case .cbm1541: return .drive1541
        case .cbm1541II: return .drive1541II
        case .cbm1571: return .drive1571
        case .cbm1581: return .drive1581
        }
    }

    var mediaSummary: String {
        switch self {
        case .cbm1541, .cbm1541II:
            return "1541-family media such as D64 and G64"
        case .cbm1571:
            return "D64 and double-sided D71 media"
        case .cbm1581:
            return "3.5-inch D81 media"
        }
    }

    var supportsMechanicalSound: Bool {
        self != .cbm1581
    }

    static func defaultsKey(for unit: Int) -> String {
        unit == 9 ? drive9DefaultsKey : drive8DefaultsKey
    }

    static func selected(for unit: Int) -> C64DriveModel {
        guard let value = UserDefaults.standard.string(forKey: defaultsKey(for: unit)),
              let model = C64DriveModel(rawValue: value) else {
            return defaultValue
        }
        return model
    }

    static var selected: C64DriveModel {
        get { selected(for: 8) }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: drive8DefaultsKey) }
    }
}

enum C64DriveSettings {
    static let trueDriveEmulationKey = "poke64.drive.trueEmulation"
    static let drive9EnabledKey = "poke64.drive9.enabled"
    static let writeProtectionKey = "poke64.drive.writeProtection"
    static let soundLevelKey = "poke64.drive.soundLevel"

    static let defaultTrueDriveEmulation = false
    static let defaultDrive9Enabled = false
    static let defaultWriteProtection = false
    static let defaultSoundLevel = 20

    static var configurationFingerprint: String {
        let defaults = UserDefaults.standard
        return [
            defaults.string(forKey: C64DriveModel.drive8DefaultsKey)
                ?? C64DriveModel.defaultValue.rawValue,
            String(defaults.object(forKey: drive9EnabledKey) == nil
                ? defaultDrive9Enabled
                : defaults.bool(forKey: drive9EnabledKey)),
            defaults.string(forKey: C64DriveModel.drive9DefaultsKey)
                ?? C64DriveModel.defaultValue.rawValue,
            String(defaults.object(forKey: trueDriveEmulationKey) == nil
                ? defaultTrueDriveEmulation
                : defaults.bool(forKey: trueDriveEmulationKey)),
            String(defaults.object(forKey: writeProtectionKey) == nil
                ? defaultWriteProtection
                : defaults.bool(forKey: writeProtectionKey)),
            String(defaults.object(forKey: soundLevelKey) == nil
                ? defaultSoundLevel
                : defaults.integer(forKey: soundLevelKey))
        ].joined(separator: ":")
    }
}

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
            "Display geometry, palette and VIC-II filtering."
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
        VStack(spacing: 0) {
            settingsHeader

            Divider()

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
        }
    }

    private var settingsHeader: some View {
        HStack(spacing: 14) {
            Text("Settings")
                .font(.headline)

            Spacer()

            Button("Done") {
                dismiss()
            }
            .fontWeight(.semibold)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }
}

private struct SettingsPanelDetail: View {
    let panel: SettingsPanel

    var body: some View {
        Group {
            switch panel {
            case .system:
                SystemSettingsView()
            case .graphics:
                VideoSettingsView()
            case .audio:
                AudioSettingsView()
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
                DiskDriveSettingsView()
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

private struct SystemSettingsView: View {
    @AppStorage(C64MachineModel.defaultsKey)
    private var selectedModelRawValue = C64MachineModel.defaultModel.rawValue

    private var selectedModel: C64MachineModel {
        C64MachineModel(rawValue: selectedModelRawValue) ?? .defaultModel
    }

    var body: some View {
        Form {
            Section {
                Picker("Machine model", selection: $selectedModelRawValue) {
                    ForEach(C64MachineModel.allCases) { model in
                        Text(model.title).tag(model.rawValue)
                    }
                }
                .pickerStyle(.menu)

                LabeledContent("Video standard", value: selectedModel.region)
                LabeledContent("Timing", value: selectedModel.timingSummary)
                LabeledContent("Profile", value: selectedModel.hardwareSummary)
            } header: {
                Text("Machine")
            } footer: {
                Text("Changing the machine model restarts the C64 when Settings is closed. PAL and NTSC also change the core timing and video geometry.")
            }

            Section("Compatibility") {
                Label(
                    "Start with C64 PAL unless software specifically requires NTSC or the later C64C profile.",
                    systemImage: "info.circle"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            Section {
                Button("Restore System Defaults") {
                    selectedModelRawValue = C64MachineModel.defaultModel.rawValue
                }
                .disabled(selectedModel == .defaultModel)
            }
        }
    }
}


private struct VideoSettingsView: View {
    @AppStorage(C64VideoAspectRatio.defaultsKey)
    private var aspectRatioRawValue = C64VideoAspectRatio.defaultValue.rawValue

    @AppStorage(C64VideoCrop.defaultsKey)
    private var cropRawValue = C64VideoCrop.defaultValue.rawValue

    @AppStorage(C64VideoSettings.cropDelayKey)
    private var cropDelay = C64VideoSettings.defaultCropDelay

    @AppStorage(C64VideoPalette.defaultsKey)
    private var paletteRawValue = C64VideoPalette.defaultValue.rawValue

    @AppStorage(C64VideoFilter.defaultsKey)
    private var filterRawValue = C64VideoFilter.defaultValue.rawValue

    @AppStorage(C64VideoSettings.brightnessKey)
    private var brightness = C64VideoSettings.defaultBrightness

    @AppStorage(C64VideoSettings.contrastKey)
    private var contrast = C64VideoSettings.defaultContrast

    @AppStorage(C64VideoSettings.saturationKey)
    private var saturation = C64VideoSettings.defaultSaturation

    @AppStorage(C64VideoSettings.gammaKey)
    private var gamma = C64VideoSettings.defaultGamma

    @AppStorage(C64VideoSettings.tintKey)
    private var tint = C64VideoSettings.defaultTint

    private var selectedCrop: C64VideoCrop {
        C64VideoCrop(rawValue: cropRawValue) ?? .defaultValue
    }

    private var selectedPalette: C64VideoPalette {
        C64VideoPalette(rawValue: paletteRawValue) ?? .defaultValue
    }

    var body: some View {
        Form {
            Section {
                Picker("Pixel aspect ratio", selection: $aspectRatioRawValue) {
                    ForEach(C64VideoAspectRatio.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                .pickerStyle(.menu)

                Picker("Borders", selection: $cropRawValue) {
                    ForEach(C64VideoCrop.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                .pickerStyle(.menu)

                Toggle("Automatic crop delay", isOn: $cropDelay)
                    .disabled(selectedCrop != .automatic)
            } header: {
                Text("Display Geometry")
            } footer: {
                Text("Automatic uses the selected PAL or NTSC machine model. Crop changes the video geometry while preserving the core-provided display ratio.")
            }

            Section {
                Picker("Palette", selection: $paletteRawValue) {
                    ForEach(C64VideoPalette.allCases) { palette in
                        Text(palette.title).tag(palette.rawValue)
                    }
                }
                .pickerStyle(.menu)

                Picker("VIC-II filter", selection: $filterRawValue) {
                    ForEach(C64VideoFilter.allCases) { filter in
                        Text(filter.title).tag(filter.rawValue)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("VIC-II Appearance")
            } footer: {
                Text("The VIC-II filter is VICE's PAL emulation filter. Metal CRT shaders will be added separately in a future release.")
            }

            Section {
                VideoAdjustmentSlider(
                    title: "Brightness",
                    value: $brightness,
                    range: 20...2000,
                    step: 20,
                    valueText: Self.percentageText
                )
                VideoAdjustmentSlider(
                    title: "Contrast",
                    value: $contrast,
                    range: 20...2000,
                    step: 20,
                    valueText: Self.percentageText
                )
                VideoAdjustmentSlider(
                    title: "Saturation",
                    value: $saturation,
                    range: 20...2000,
                    step: 20,
                    valueText: Self.percentageText
                )
                VideoAdjustmentSlider(
                    title: "Gamma",
                    value: $gamma,
                    range: 1000...4000,
                    step: 50,
                    valueText: Self.gammaText
                )
                VideoAdjustmentSlider(
                    title: "Tint",
                    value: $tint,
                    range: 20...2000,
                    step: 20,
                    valueText: Self.percentageText
                )
            } header: {
                Text("Advanced Color")
            } footer: {
                Text(selectedPalette.supportsColorAdjustments
                    ? "Color adjustments apply to VICE's internal palette."
                    : "Select Internal (adjustable) to enable these controls.")
            }
            .disabled(!selectedPalette.supportsColorAdjustments)

            Section {
                Button("Restore Video Defaults") {
                    restoreDefaults()
                }
                .disabled(isUsingDefaults)
            } footer: {
                Text("Video changes are applied when Settings is closed and the C64 restarts.")
            }
        }
    }

    private var isUsingDefaults: Bool {
        aspectRatioRawValue == C64VideoAspectRatio.defaultValue.rawValue
            && cropRawValue == C64VideoCrop.defaultValue.rawValue
            && cropDelay == C64VideoSettings.defaultCropDelay
            && paletteRawValue == C64VideoPalette.defaultValue.rawValue
            && filterRawValue == C64VideoFilter.defaultValue.rawValue
            && brightness == C64VideoSettings.defaultBrightness
            && contrast == C64VideoSettings.defaultContrast
            && saturation == C64VideoSettings.defaultSaturation
            && gamma == C64VideoSettings.defaultGamma
            && tint == C64VideoSettings.defaultTint
    }

    private func restoreDefaults() {
        aspectRatioRawValue = C64VideoAspectRatio.defaultValue.rawValue
        cropRawValue = C64VideoCrop.defaultValue.rawValue
        cropDelay = C64VideoSettings.defaultCropDelay
        paletteRawValue = C64VideoPalette.defaultValue.rawValue
        filterRawValue = C64VideoFilter.defaultValue.rawValue
        brightness = C64VideoSettings.defaultBrightness
        contrast = C64VideoSettings.defaultContrast
        saturation = C64VideoSettings.defaultSaturation
        gamma = C64VideoSettings.defaultGamma
        tint = C64VideoSettings.defaultTint
    }

    private static func percentageText(_ value: Int) -> String {
        "\(value / 10)%"
    }

    private static func gammaText(_ value: Int) -> String {
        String(format: "%.2f", Double(value) / 1000.0)
    }
}

private struct VideoAdjustmentSlider: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let valueText: (Int) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text(valueText(value))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { value = Int($0.rounded()) }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: Double(step)
            )
        }
        .padding(.vertical, 2)
    }
}

private struct AudioSettingsView: View {
    @AppStorage(C64SIDEngine.defaultsKey)
    private var sidEngineRawValue = C64SIDEngine.defaultValue.rawValue

    @AppStorage(C64SIDModel.defaultsKey)
    private var sidModelRawValue = C64SIDModel.defaultValue.rawValue

    @AppStorage(C64ReSIDSampling.defaultsKey)
    private var residSamplingRawValue = C64ReSIDSampling.defaultValue.rawValue

    @AppStorage(C64AudioSampleRate.defaultsKey)
    private var sampleRateRawValue = C64AudioSampleRate.defaultValue.rawValue

    @AppStorage(C64AudioSettings.audioLeakLevelKey)
    private var audioLeakLevel = C64AudioSettings.defaultAudioLeakLevel

    @AppStorage(C64AudioSettings.datasetteSoundLevelKey)
    private var datasetteSoundLevel = C64AudioSettings.defaultDatasetteSoundLevel

    private var selectedEngine: C64SIDEngine {
        C64SIDEngine(rawValue: sidEngineRawValue) ?? .defaultValue
    }

    var body: some View {
        Form {
            Section {
                Picker("Emulation engine", selection: $sidEngineRawValue) {
                    ForEach(C64SIDEngine.allCases) { engine in
                        Text(engine.title).tag(engine.rawValue)
                    }
                }
                .pickerStyle(.menu)

                Picker("SID model", selection: $sidModelRawValue) {
                    ForEach(C64SIDModel.allCases) { model in
                        Text(model.title).tag(model.rawValue)
                    }
                }
                .pickerStyle(.menu)

                LabeledContent("Engine profile", value: selectedEngine.detail)
            } header: {
                Text("SID")
            } footer: {
                Text("Automatic selects the traditional 6581 for C64 models and the later 8580 for C64C models. ReSID-FP is the most accurate option; FastSID is intended for lower-powered hardware.")
            }

            Section {
                Picker("ReSID sampling", selection: $residSamplingRawValue) {
                    ForEach(C64ReSIDSampling.allCases) { sampling in
                        Text(sampling.title).tag(sampling.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .disabled(selectedEngine == .fastSID)

                Picker("Sample rate", selection: $sampleRateRawValue) {
                    ForEach(C64AudioSampleRate.allCases) { rate in
                        Text(rate.title).tag(rate.rawValue)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("Audio Quality")
            } footer: {
                Text(selectedEngine == .fastSID
                    ? "ReSID sampling is unavailable while FastSID is selected. 48,000 Hz is recommended for normal iPad playback."
                    : "Resampling provides the highest ReSID quality. 48,000 Hz is recommended for normal iPad playback.")
            }

            Section {
                AudioLevelSlider(
                    title: "VIC-II audio leak",
                    value: $audioLeakLevel,
                    range: 0...10,
                    step: 1,
                    valueText: { $0 == 0 ? "Off" : "Level \($0)" }
                )

                AudioLevelSlider(
                    title: "Datasette sound",
                    value: $datasetteSoundLevel,
                    range: 0...100,
                    step: 5,
                    valueText: { $0 == 0 ? "Off" : "\($0)%" }
                )
            } header: {
                Text("Emulated Sounds")
            } footer: {
                Text("VIC-II audio leak simulates video-chip interference. Datasette sound is audible only when a compatible TAP image is active.")
            }

            Section {
                Button("Restore Audio Defaults") {
                    restoreDefaults()
                }
                .disabled(isUsingDefaults)
            } footer: {
                Text("Audio changes are applied when Settings is closed and the C64 restarts.")
            }
        }
    }

    private var isUsingDefaults: Bool {
        sidEngineRawValue == C64SIDEngine.defaultValue.rawValue
            && sidModelRawValue == C64SIDModel.defaultValue.rawValue
            && residSamplingRawValue == C64ReSIDSampling.defaultValue.rawValue
            && sampleRateRawValue == C64AudioSampleRate.defaultValue.rawValue
            && audioLeakLevel == C64AudioSettings.defaultAudioLeakLevel
            && datasetteSoundLevel == C64AudioSettings.defaultDatasetteSoundLevel
    }

    private func restoreDefaults() {
        sidEngineRawValue = C64SIDEngine.defaultValue.rawValue
        sidModelRawValue = C64SIDModel.defaultValue.rawValue
        residSamplingRawValue = C64ReSIDSampling.defaultValue.rawValue
        sampleRateRawValue = C64AudioSampleRate.defaultValue.rawValue
        audioLeakLevel = C64AudioSettings.defaultAudioLeakLevel
        datasetteSoundLevel = C64AudioSettings.defaultDatasetteSoundLevel
    }
}

private struct AudioLevelSlider: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let valueText: (Int) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text(valueText(value))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { value = Int($0.rounded()) }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: Double(step)
            )
        }
        .padding(.vertical, 2)
    }
}

private struct DiskDriveSettingsView: View {
    @AppStorage(C64DriveModel.drive8DefaultsKey)
    private var drive8ModelRawValue = C64DriveModel.defaultValue.rawValue

    @AppStorage(C64DriveSettings.drive9EnabledKey)
    private var drive9Enabled = C64DriveSettings.defaultDrive9Enabled

    @AppStorage(C64DriveModel.drive9DefaultsKey)
    private var drive9ModelRawValue = C64DriveModel.defaultValue.rawValue

    @AppStorage(C64DriveSettings.trueDriveEmulationKey)
    private var trueDriveEmulation = C64DriveSettings.defaultTrueDriveEmulation

    @AppStorage(C64DriveSettings.writeProtectionKey)
    private var writeProtection = C64DriveSettings.defaultWriteProtection

    @AppStorage(C64DriveSettings.soundLevelKey)
    private var driveSoundLevel = C64DriveSettings.defaultSoundLevel

    private var drive8Model: C64DriveModel {
        C64DriveModel(rawValue: drive8ModelRawValue) ?? .defaultValue
    }

    private var drive9Model: C64DriveModel {
        C64DriveModel(rawValue: drive9ModelRawValue) ?? .defaultValue
    }

    private var drive8FirmwareStatus: FirmwareStatus {
        FirmwareStore.status(for: drive8Model.firmwareSlot)
    }

    private var drive9FirmwareStatus: FirmwareStatus {
        FirmwareStore.status(for: drive9Model.firmwareSlot)
    }

    private var canEnableTrueDrive: Bool {
        drive8FirmwareStatus.isValid
            && (!drive9Enabled || drive9FirmwareStatus.isValid)
    }

    private var anyEnabledDriveSupportsSound: Bool {
        drive8Model.supportsMechanicalSound
            || (drive9Enabled && drive9Model.supportsMechanicalSound)
    }

    var body: some View {
        Form {
            Section {
                Toggle(
                    "True Drive Emulation",
                    isOn: $trueDriveEmulation
                )
                .disabled(!canEnableTrueDrive)

                LabeledContent(
                    "Active backend",
                    value: trueDriveEmulation ? "Hardware-level drives" : "Fast virtual drives"
                )
            } header: {
                Text("Drive Emulation")
            } footer: {
                Text(trueDriveEmulation
                    ? "True Drive Emulation applies to every enabled drive. It executes each selected model's ROM and is required for complete JiffyDOS compatibility, accurate timing and mechanical drive sound."
                    : "Fast virtual drive mode applies to every enabled drive and uses VICE traps for convenient loading. It does not execute drive firmware, so drive-side JiffyDOS commands are unavailable.")
            }

            Section {
                driveModelPicker(
                    title: "Drive model",
                    selection: $drive8ModelRawValue
                )

                LabeledContent("Typical media", value: drive8Model.mediaSummary)
            } header: {
                Text("Drive 8")
            } footer: {
                Text("Drive 8 is always enabled. Its model is independent, while the emulation backend is shared by all enabled drives.")
            }

            Section {
                Toggle("Enable Drive 9", isOn: $drive9Enabled)

                driveModelPicker(
                    title: "Drive model",
                    selection: $drive9ModelRawValue
                )
                .disabled(!drive9Enabled)

                LabeledContent(
                    "Active backend",
                    value: drive9Enabled
                        ? (trueDriveEmulation ? "Hardware-level drive" : "Fast virtual drive")
                        : "Disabled"
                )

                if drive9Enabled {
                    LabeledContent("Typical media", value: drive9Model.mediaSummary)
                }
            } header: {
                Text("Drive 9")
            } footer: {
                Text("Drive 9 is optional. Its model can be configured independently, while the emulation backend is shared by all enabled drives.")
            }

            Section {
                firmwareRow(
                    units: drive9Enabled && drive9Model == drive8Model ? [8, 9] : [8],
                    model: drive8Model,
                    status: drive8FirmwareStatus
                )

                if drive9Enabled && drive9Model != drive8Model {
                    firmwareRow(
                        units: [9],
                        model: drive9Model,
                        status: drive9FirmwareStatus
                    )
                }

                if !canEnableTrueDrive {
                    Label(
                        "Import every required drive ROM in Firmware / ROMs before enabling True Drive Emulation.",
                        systemImage: "info.circle"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            } header: {
                Text("Drive Firmware")
            } footer: {
                Text("Drive ROMs are shared by model, not assigned separately to unit 8 or 9. Two enabled drives using the same model must therefore use the same ROM. POKE64 accepts standard or compatible replacement firmware; for JiffyDOS, use matching C64 KERNAL and drive ROMs.")
            }

            Section {
                Toggle("Default write protection", isOn: $writeProtection)
            } header: {
                Text("Media Safety")
            } footer: {
                Text("When enabled, newly attached images in Drive 8 and Drive 9 are opened read-only. Existing files are not modified by this setting.")
            }

            Section {
                AudioLevelSlider(
                    title: "Mechanical drive sound",
                    value: $driveSoundLevel,
                    range: 0...100,
                    step: 5,
                    valueText: { $0 == 0 ? "Off" : "\($0)%" }
                )
                .disabled(!trueDriveEmulation || !anyEnabledDriveSupportsSound)
            } header: {
                Text("Drive Sound")
            } footer: {
                if !anyEnabledDriveSupportsSound {
                    Text("The VICE libretro drive-sound option supports 1541-family and 1571 drives, not the 1581.")
                } else if !trueDriveEmulation {
                    Text("Mechanical drive sound requires True Drive Emulation and a compatible disk image.")
                } else {
                    Text("Mechanical drive sound is shared by the enabled 1541-family and 1571 drives.")
                }
            }

            Section("Compatibility") {
                Label(
                    "Drive configuration changes apply when Settings is closed and the C64 restarts.",
                    systemImage: "arrow.clockwise"
                )
                .font(.callout)
                .foregroundStyle(.secondary)

                if trueDriveEmulation {
                    Label(
                        "JiffyDOS requires matching custom C64 KERNAL and drive ROMs.",
                        systemImage: "bolt.horizontal.circle"
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            }

            Section {
                Button("Restore Drive Defaults") {
                    restoreDefaults()
                }
                .disabled(isUsingDefaults)
            }
        }
        .onChange(of: drive8ModelRawValue) { _, _ in
            sanitizeTrueDriveSelection()
        }
        .onChange(of: drive9ModelRawValue) { _, _ in
            sanitizeTrueDriveSelection()
        }
        .onChange(of: drive9Enabled) { _, _ in
            sanitizeTrueDriveSelection()
        }
        .onChange(of: trueDriveEmulation) { _, enabled in
            if enabled && !canEnableTrueDrive {
                trueDriveEmulation = false
            }
        }
    }

    private func driveModelPicker(
        title: String,
        selection: Binding<String>
    ) -> some View {
        Picker(title, selection: selection) {
            ForEach(C64DriveModel.allCases) { model in
                Text(model.title).tag(model.rawValue)
            }
        }
        .pickerStyle(.menu)
    }

    @ViewBuilder
    private func firmwareRow(
        units: [Int],
        model: C64DriveModel,
        status: FirmwareStatus
    ) -> some View {
        let unitLabel = units.count == 1
            ? "Drive \(units[0])"
            : "Drives \(units.map { String($0) }.joined(separator: " and "))"

        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(unitLabel) · \(model.firmwareSlot.title)")
                    .font(.body.weight(.medium))
                Text(model.firmwareSlot.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Shared by every enabled drive using \(model.title).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if status.isValid {
                Label("Installed", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else if status.isInstalled {
                Label("Invalid", systemImage: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                Label("Missing", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var isUsingDefaults: Bool {
        drive8ModelRawValue == C64DriveModel.defaultValue.rawValue
            && drive9Enabled == C64DriveSettings.defaultDrive9Enabled
            && drive9ModelRawValue == C64DriveModel.defaultValue.rawValue
            && trueDriveEmulation == C64DriveSettings.defaultTrueDriveEmulation
            && writeProtection == C64DriveSettings.defaultWriteProtection
            && driveSoundLevel == C64DriveSettings.defaultSoundLevel
    }

    private func sanitizeTrueDriveSelection() {
        if trueDriveEmulation && !canEnableTrueDrive {
            trueDriveEmulation = false
        }
    }

    private func restoreDefaults() {
        drive8ModelRawValue = C64DriveModel.defaultValue.rawValue
        drive9Enabled = C64DriveSettings.defaultDrive9Enabled
        drive9ModelRawValue = C64DriveModel.defaultValue.rawValue
        trueDriveEmulation = C64DriveSettings.defaultTrueDriveEmulation
        writeProtection = C64DriveSettings.defaultWriteProtection
        driveSoundLevel = C64DriveSettings.defaultSoundLevel
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
