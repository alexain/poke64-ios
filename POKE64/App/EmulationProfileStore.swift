import Foundation

struct EmulationProfileSnapshot: Codable, Equatable {
    var machineModel: String

    var reuSize: String
    var reuPersistentMemory: Bool
    var reuImageName: String?

    var tapeAutoShowControls: Bool
    var tapeResetCounterOnInsert: Bool
    var tapeResetWithCPU: Bool
    var tapeAutostartBasicLoad: Bool

    var printerEnabled: Bool
    var printerDevice: Int
    var printerExportFormat: String
    var printerDotIntensity: String

    var videoAspectRatio: String
    var videoCrop: String
    var videoCropDelay: Bool
    var videoPalette: String
    var videoFilter: String
    var videoBrightness: Int
    var videoContrast: Int
    var videoSaturation: Int
    var videoGamma: Int
    var videoTint: Int
    var crtFilterEnabled: Bool?
    var crtPresetID: UUID?

    var sidEngine: String
    var sidModel: String
    var reSIDSampling: String
    var audioSampleRate: String
    var audioLeakLevel: Int
    var datasetteSoundLevel: Int

    var drive8Model: String
    var drive9Enabled: Bool
    var drive9Model: String
    var trueDriveEmulation: Bool
    var driveWriteProtection: Bool
    var driveSoundLevel: Int

    var virtualModemEnabled: Bool
    var virtualModemBaud: Int

    static var current: EmulationProfileSnapshot {
        let defaults = UserDefaults.standard

        return EmulationProfileSnapshot(
            machineModel: defaults.string(forKey: C64MachineModel.defaultsKey)
                ?? C64MachineModel.defaultModel.rawValue,
            reuSize: defaults.string(forKey: C64REUSize.defaultsKey)
                ?? C64REUSize.defaultValue.rawValue,
            reuPersistentMemory: boolValue(
                defaults,
                key: C64REUSettings.persistentMemoryKey,
                defaultValue: C64REUSettings.defaultPersistentMemory
            ),
            reuImageName: FirmwareStore.importedREUImageInfo()?.filename,
            tapeAutoShowControls: boolValue(
                defaults,
                key: C64TapeSettings.autoShowControlsKey,
                defaultValue: C64TapeSettings.defaultAutoShowControls
            ),
            tapeResetCounterOnInsert: boolValue(
                defaults,
                key: C64TapeSettings.resetCounterOnInsertKey,
                defaultValue: C64TapeSettings.defaultResetCounterOnInsert
            ),
            tapeResetWithCPU: boolValue(
                defaults,
                key: C64TapeSettings.resetWithCPUKey,
                defaultValue: C64TapeSettings.defaultResetWithCPU
            ),
            tapeAutostartBasicLoad: boolValue(
                defaults,
                key: C64TapeSettings.autostartBasicLoadKey,
                defaultValue: C64TapeSettings.defaultAutostartBasicLoad
            ),
            printerEnabled: boolValue(
                defaults,
                key: C64PrinterSettings.enabledKey,
                defaultValue: C64PrinterSettings.defaultEnabled
            ),
            printerDevice: intValue(
                defaults,
                key: C64PrinterSettings.deviceKey,
                defaultValue: C64PrinterSettings.defaultDevice
            ),
            printerExportFormat: defaults.string(forKey: C64PrinterSettings.exportFormatKey)
                ?? C64PrinterSettings.defaultExportFormat.rawValue,
            printerDotIntensity: defaults.string(forKey: C64PrinterSettings.dotIntensityKey)
                ?? C64PrinterSettings.defaultDotIntensity.rawValue,
            videoAspectRatio: defaults.string(forKey: C64VideoAspectRatio.defaultsKey)
                ?? C64VideoAspectRatio.defaultValue.rawValue,
            videoCrop: defaults.string(forKey: C64VideoCrop.defaultsKey)
                ?? C64VideoCrop.defaultValue.rawValue,
            videoCropDelay: boolValue(
                defaults,
                key: C64VideoSettings.cropDelayKey,
                defaultValue: C64VideoSettings.defaultCropDelay
            ),
            videoPalette: defaults.string(forKey: C64VideoPalette.defaultsKey)
                ?? C64VideoPalette.defaultValue.rawValue,
            videoFilter: defaults.string(forKey: C64VideoFilter.defaultsKey)
                ?? C64VideoFilter.defaultValue.rawValue,
            videoBrightness: intValue(
                defaults,
                key: C64VideoSettings.brightnessKey,
                defaultValue: C64VideoSettings.defaultBrightness
            ),
            videoContrast: intValue(
                defaults,
                key: C64VideoSettings.contrastKey,
                defaultValue: C64VideoSettings.defaultContrast
            ),
            videoSaturation: intValue(
                defaults,
                key: C64VideoSettings.saturationKey,
                defaultValue: C64VideoSettings.defaultSaturation
            ),
            videoGamma: intValue(
                defaults,
                key: C64VideoSettings.gammaKey,
                defaultValue: C64VideoSettings.defaultGamma
            ),
            videoTint: intValue(
                defaults,
                key: C64VideoSettings.tintKey,
                defaultValue: C64VideoSettings.defaultTint
            ),
            crtFilterEnabled: boolValue(
                defaults,
                key: C64CRTSettings.enabledKey,
                defaultValue: C64CRTSettings.defaultEnabled
            ),
            crtPresetID: C64CRTPresetStore.activePresetID,
            sidEngine: defaults.string(forKey: C64SIDEngine.defaultsKey)
                ?? C64SIDEngine.defaultValue.rawValue,
            sidModel: defaults.string(forKey: C64SIDModel.defaultsKey)
                ?? C64SIDModel.defaultValue.rawValue,
            reSIDSampling: defaults.string(forKey: C64ReSIDSampling.defaultsKey)
                ?? C64ReSIDSampling.defaultValue.rawValue,
            audioSampleRate: defaults.string(forKey: C64AudioSampleRate.defaultsKey)
                ?? C64AudioSampleRate.defaultValue.rawValue,
            audioLeakLevel: intValue(
                defaults,
                key: C64AudioSettings.audioLeakLevelKey,
                defaultValue: C64AudioSettings.defaultAudioLeakLevel
            ),
            datasetteSoundLevel: intValue(
                defaults,
                key: C64AudioSettings.datasetteSoundLevelKey,
                defaultValue: C64AudioSettings.defaultDatasetteSoundLevel
            ),
            drive8Model: defaults.string(forKey: C64DriveModel.drive8DefaultsKey)
                ?? C64DriveModel.defaultValue.rawValue,
            drive9Enabled: boolValue(
                defaults,
                key: C64DriveSettings.drive9EnabledKey,
                defaultValue: C64DriveSettings.defaultDrive9Enabled
            ),
            drive9Model: defaults.string(forKey: C64DriveModel.drive9DefaultsKey)
                ?? C64DriveModel.defaultValue.rawValue,
            trueDriveEmulation: boolValue(
                defaults,
                key: C64DriveSettings.trueDriveEmulationKey,
                defaultValue: C64DriveSettings.defaultTrueDriveEmulation
            ),
            driveWriteProtection: boolValue(
                defaults,
                key: C64DriveSettings.writeProtectionKey,
                defaultValue: C64DriveSettings.defaultWriteProtection
            ),
            driveSoundLevel: intValue(
                defaults,
                key: C64DriveSettings.soundLevelKey,
                defaultValue: C64DriveSettings.defaultSoundLevel
            ),
            virtualModemEnabled: boolValue(
                defaults,
                key: C64VirtualModemSettings.enabledKey,
                defaultValue: C64VirtualModemSettings.defaultEnabled
            ),
            virtualModemBaud: intValue(
                defaults,
                key: C64VirtualModemSettings.baudKey,
                defaultValue: C64VirtualModemSettings.defaultBaud
            )
        )
    }

    static var factoryDefault: EmulationProfileSnapshot {
        EmulationProfileSnapshot(
            machineModel: C64MachineModel.defaultModel.rawValue,
            reuSize: C64REUSize.defaultValue.rawValue,
            reuPersistentMemory: C64REUSettings.defaultPersistentMemory,
            reuImageName: nil,
            tapeAutoShowControls: C64TapeSettings.defaultAutoShowControls,
            tapeResetCounterOnInsert: C64TapeSettings.defaultResetCounterOnInsert,
            tapeResetWithCPU: C64TapeSettings.defaultResetWithCPU,
            tapeAutostartBasicLoad: C64TapeSettings.defaultAutostartBasicLoad,
            printerEnabled: C64PrinterSettings.defaultEnabled,
            printerDevice: C64PrinterSettings.defaultDevice,
            printerExportFormat: C64PrinterSettings.defaultExportFormat.rawValue,
            printerDotIntensity: C64PrinterSettings.defaultDotIntensity.rawValue,
            videoAspectRatio: C64VideoAspectRatio.defaultValue.rawValue,
            videoCrop: C64VideoCrop.defaultValue.rawValue,
            videoCropDelay: C64VideoSettings.defaultCropDelay,
            videoPalette: C64VideoPalette.defaultValue.rawValue,
            videoFilter: C64VideoFilter.defaultValue.rawValue,
            videoBrightness: C64VideoSettings.defaultBrightness,
            videoContrast: C64VideoSettings.defaultContrast,
            videoSaturation: C64VideoSettings.defaultSaturation,
            videoGamma: C64VideoSettings.defaultGamma,
            videoTint: C64VideoSettings.defaultTint,
            crtFilterEnabled: C64CRTSettings.defaultEnabled,
            crtPresetID: C64CRTPresetStore.builtInPresetID,
            sidEngine: C64SIDEngine.defaultValue.rawValue,
            sidModel: C64SIDModel.defaultValue.rawValue,
            reSIDSampling: C64ReSIDSampling.defaultValue.rawValue,
            audioSampleRate: C64AudioSampleRate.defaultValue.rawValue,
            audioLeakLevel: C64AudioSettings.defaultAudioLeakLevel,
            datasetteSoundLevel: C64AudioSettings.defaultDatasetteSoundLevel,
            drive8Model: C64DriveModel.defaultValue.rawValue,
            drive9Enabled: C64DriveSettings.defaultDrive9Enabled,
            drive9Model: C64DriveModel.defaultValue.rawValue,
            trueDriveEmulation: C64DriveSettings.defaultTrueDriveEmulation,
            driveWriteProtection: C64DriveSettings.defaultWriteProtection,
            driveSoundLevel: C64DriveSettings.defaultSoundLevel,
            virtualModemEnabled: C64VirtualModemSettings.defaultEnabled,
            virtualModemBaud: C64VirtualModemSettings.defaultBaud
        )
    }

    func matchesCurrentConfiguration() -> Bool {
        let current = Self.current
        var normalized = self
        if normalized.crtFilterEnabled == nil {
            normalized.crtFilterEnabled = current.crtFilterEnabled
        }
        if normalized.crtPresetID == nil {
            normalized.crtPresetID = current.crtPresetID
        }
        return normalized == current
    }

    var machineTitle: String {
        C64MachineModel(rawValue: machineModel)?.title ?? machineModel
    }

    var compactSummary: String {
        var components = [machineTitle]

        let driveTitle = C64DriveModel(rawValue: drive8Model)?.rawValue ?? drive8Model
        components.append("Drive 8: \(driveTitle)")

        if let reu = C64REUSize(rawValue: reuSize), reu != .disabled {
            components.append("REU \(reu.capacityTitle)")
        }
        if virtualModemEnabled {
            components.append("Modem \(virtualModemBaud)")
        }
        if printerEnabled {
            components.append("Printer \(printerDevice)")
        }
        return components.joined(separator: " · ")
    }

    func applyToUserDefaults() {
        let defaults = UserDefaults.standard

        defaults.set(machineModel, forKey: C64MachineModel.defaultsKey)
        defaults.set(reuSize, forKey: C64REUSize.defaultsKey)
        defaults.set(reuPersistentMemory, forKey: C64REUSettings.persistentMemoryKey)

        defaults.set(tapeAutoShowControls, forKey: C64TapeSettings.autoShowControlsKey)
        defaults.set(tapeResetCounterOnInsert, forKey: C64TapeSettings.resetCounterOnInsertKey)
        defaults.set(tapeResetWithCPU, forKey: C64TapeSettings.resetWithCPUKey)
        defaults.set(tapeAutostartBasicLoad, forKey: C64TapeSettings.autostartBasicLoadKey)

        defaults.set(printerEnabled, forKey: C64PrinterSettings.enabledKey)
        defaults.set(printerDevice, forKey: C64PrinterSettings.deviceKey)
        defaults.set(printerExportFormat, forKey: C64PrinterSettings.exportFormatKey)
        defaults.set(printerDotIntensity, forKey: C64PrinterSettings.dotIntensityKey)

        defaults.set(videoAspectRatio, forKey: C64VideoAspectRatio.defaultsKey)
        defaults.set(videoCrop, forKey: C64VideoCrop.defaultsKey)
        defaults.set(videoCropDelay, forKey: C64VideoSettings.cropDelayKey)
        defaults.set(videoPalette, forKey: C64VideoPalette.defaultsKey)
        defaults.set(videoFilter, forKey: C64VideoFilter.defaultsKey)
        defaults.set(videoBrightness, forKey: C64VideoSettings.brightnessKey)
        defaults.set(videoContrast, forKey: C64VideoSettings.contrastKey)
        defaults.set(videoSaturation, forKey: C64VideoSettings.saturationKey)
        defaults.set(videoGamma, forKey: C64VideoSettings.gammaKey)
        defaults.set(videoTint, forKey: C64VideoSettings.tintKey)
        if let crtFilterEnabled {
            defaults.set(crtFilterEnabled, forKey: C64CRTSettings.enabledKey)
        }
        if let crtPresetID {
            _ = C64CRTPresetStore.applyPreset(crtPresetID)
        }

        defaults.set(sidEngine, forKey: C64SIDEngine.defaultsKey)
        defaults.set(sidModel, forKey: C64SIDModel.defaultsKey)
        defaults.set(reSIDSampling, forKey: C64ReSIDSampling.defaultsKey)
        defaults.set(audioSampleRate, forKey: C64AudioSampleRate.defaultsKey)
        defaults.set(audioLeakLevel, forKey: C64AudioSettings.audioLeakLevelKey)
        defaults.set(datasetteSoundLevel, forKey: C64AudioSettings.datasetteSoundLevelKey)

        defaults.set(drive8Model, forKey: C64DriveModel.drive8DefaultsKey)
        defaults.set(drive9Enabled, forKey: C64DriveSettings.drive9EnabledKey)
        defaults.set(drive9Model, forKey: C64DriveModel.drive9DefaultsKey)
        defaults.set(trueDriveEmulation, forKey: C64DriveSettings.trueDriveEmulationKey)
        defaults.set(driveWriteProtection, forKey: C64DriveSettings.writeProtectionKey)
        defaults.set(driveSoundLevel, forKey: C64DriveSettings.soundLevelKey)

        defaults.set(virtualModemEnabled, forKey: C64VirtualModemSettings.enabledKey)
        defaults.set(virtualModemBaud, forKey: C64VirtualModemSettings.baudKey)
    }

    private static func boolValue(
        _ defaults: UserDefaults,
        key: String,
        defaultValue: Bool
    ) -> Bool {
        defaults.object(forKey: key) == nil ? defaultValue : defaults.bool(forKey: key)
    }

    private static func intValue(
        _ defaults: UserDefaults,
        key: String,
        defaultValue: Int
    ) -> Int {
        defaults.object(forKey: key) == nil ? defaultValue : defaults.integer(forKey: key)
    }
}

struct EmulationProfile: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var settings: EmulationProfileSnapshot
    var firmwareProfileID: UUID?
    let createdAt: Date
    var updatedAt: Date
}

enum EmulationProfileStoreError: LocalizedError {
    case invalidName
    case profileNotFound
    case reuImageUnavailable(String)
    case firmwareProfileUnavailable
    case builtInProfileProtected
    case storageFailure(String)

    var errorDescription: String? {
        switch self {
        case .invalidName:
            return "Enter a profile name."
        case .profileNotFound:
            return "The selected emulation profile no longer exists."
        case .reuImageUnavailable(let filename):
            return "The REU image stored with this profile is unavailable: \(filename)."
        case .firmwareProfileUnavailable:
            return "The firmware profile associated with this emulation profile is unavailable."
        case .builtInProfileProtected:
            return "The built-in Default profile cannot be renamed or deleted."
        case .storageFailure(let message):
            return "The emulation profile could not be saved: \(message)"
        }
    }
}

private struct EmulationProfileArchive: Codable {
    let version: Int
    var profiles: [EmulationProfile]
}

enum EmulationProfileStore {
    static let profilesKey = "poke64.emulationProfiles.data"
    static let schemaVersion = 1
    static let initializedKey = "poke64.emulationProfiles.initialized"
    static let selectedProfileIDKey = "poke64.emulationProfiles.selectedID"
    static let powerOnProfileIDKey = "poke64.emulationProfiles.powerOnProfileID"
    static let firmwareReferenceMigrationKey = "poke64.emulationProfiles.firmwareReferenceMigration.v1"
    static let builtInDefaultProfileID = UUID(uuidString: "00000000-0000-4000-8000-000000000064")!

    // Legacy keys from the earlier startup-default implementation.
    private static let legacyDefaultProfileIDKey = "poke64.emulationProfiles.defaultID"
    private static let legacyApplyDefaultProfileAtLaunchKey = "poke64.emulationProfiles.applyDefaultAtLaunch"

    static var selectedProfileID: UUID? {
        get {
            guard let raw = UserDefaults.standard.string(forKey: selectedProfileIDKey) else {
                return nil
            }
            return UUID(uuidString: raw)
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.uuidString, forKey: selectedProfileIDKey)
            } else {
                UserDefaults.standard.removeObject(forKey: selectedProfileIDKey)
            }
        }
    }

    static var powerOnProfileID: UUID? {
        get {
            guard let raw = UserDefaults.standard.string(forKey: powerOnProfileIDKey) else {
                return nil
            }
            return UUID(uuidString: raw)
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.uuidString, forKey: powerOnProfileIDKey)
            } else {
                UserDefaults.standard.removeObject(forKey: powerOnProfileIDKey)
            }
        }
    }

    static func isBuiltInProfile(_ profileID: UUID) -> Bool {
        profileID == builtInDefaultProfileID
    }

    static func loadProfiles() -> [EmulationProfile] {
        seedProfilesIfNeeded()
        guard let data = UserDefaults.standard.data(forKey: profilesKey),
              let archive = try? JSONDecoder().decode(EmulationProfileArchive.self, from: data),
              archive.version == schemaVersion else {
            return []
        }

        var profiles = archive.profiles
        migrateFirmwareReferencesIfNeeded(&profiles)
        ensureBuiltInDefaultProfile(in: &profiles)
        clearLegacyStartupDefaultSettings()

        if selectedProfileID == nil
            || !profiles.contains(where: { $0.id == selectedProfileID }) {
            selectedProfileID = builtInDefaultProfileID
        }
        if let powerOnProfileID,
           !profiles.contains(where: { $0.id == powerOnProfileID }) {
            self.powerOnProfileID = nil
        }
        return profiles
    }

    @discardableResult
    static func createProfile(named rawName: String) throws -> EmulationProfile {
        let name = try validatedName(rawName)
        var profiles = loadProfiles()
        let now = Date()
        let profile = EmulationProfile(
            id: UUID(),
            name: uniqueName(name, excluding: nil, profiles: profiles),
            settings: .current,
            firmwareProfileID: FirmwareProfileStore.activeProfileID,
            createdAt: now,
            updatedAt: now
        )

        try captureREUImage(for: profile)
        profiles.append(profile)
        try saveProfiles(profiles)
        selectedProfileID = profile.id
        return profile
    }

    @discardableResult
    static func createBlankProfile(named rawName: String) throws -> EmulationProfile {
        let name = try validatedName(rawName)
        var profiles = loadProfiles()
        let now = Date()
        let profile = EmulationProfile(
            id: UUID(),
            name: uniqueName(name, excluding: nil, profiles: profiles),
            settings: .factoryDefault,
            firmwareProfileID: FirmwareProfileStore.activeProfileID,
            createdAt: now,
            updatedAt: now
        )

        profiles.append(profile)
        try saveProfiles(profiles)
        return profile
    }

    @discardableResult
    static func updateProfile(_ profileID: UUID) throws -> EmulationProfile {
        var profiles = loadProfiles()
        guard let index = profiles.firstIndex(where: { $0.id == profileID }) else {
            throw EmulationProfileStoreError.profileNotFound
        }

        profiles[index].settings = .current
        profiles[index].firmwareProfileID = FirmwareProfileStore.activeProfileID
        profiles[index].updatedAt = Date()
        try captureREUImage(for: profiles[index])
        try saveProfiles(profiles)
        selectedProfileID = profileID
        return profiles[index]
    }

    @discardableResult
    static func renameProfile(_ profileID: UUID, to rawName: String) throws -> EmulationProfile {
        let name = try validatedName(rawName)
        var profiles = loadProfiles()
        guard let index = profiles.firstIndex(where: { $0.id == profileID }) else {
            throw EmulationProfileStoreError.profileNotFound
        }
        guard !isBuiltInProfile(profileID) else {
            throw EmulationProfileStoreError.builtInProfileProtected
        }

        profiles[index].name = uniqueName(name, excluding: profileID, profiles: profiles)
        profiles[index].updatedAt = Date()
        try saveProfiles(profiles)
        return profiles[index]
    }

    @discardableResult
    static func duplicateProfile(_ profileID: UUID) throws -> EmulationProfile {
        var profiles = loadProfiles()
        guard let source = profiles.first(where: { $0.id == profileID }) else {
            throw EmulationProfileStoreError.profileNotFound
        }

        let now = Date()
        let duplicate = EmulationProfile(
            id: UUID(),
            name: uniqueName("\(source.name) Copy", excluding: nil, profiles: profiles),
            settings: source.settings,
            firmwareProfileID: source.firmwareProfileID,
            createdAt: now,
            updatedAt: now
        )

        if source.settings.reuImageName != nil {
            let sourceURL = try reuAssetURL(for: source.id)
            let destinationURL = try reuAssetURL(for: duplicate.id)
            guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                throw EmulationProfileStoreError.reuImageUnavailable(
                    source.settings.reuImageName ?? "REU image"
                )
            }
            try replaceFile(at: destinationURL, withCopyOf: sourceURL)
        }

        profiles.append(duplicate)
        try saveProfiles(profiles)
        return duplicate
    }

    static func deleteProfile(_ profileID: UUID) throws {
        guard !isBuiltInProfile(profileID) else {
            throw EmulationProfileStoreError.builtInProfileProtected
        }

        var profiles = loadProfiles()
        guard profiles.contains(where: { $0.id == profileID }) else {
            throw EmulationProfileStoreError.profileNotFound
        }
        let deletedSelectedProfile = selectedProfileID == profileID
        profiles.removeAll { $0.id == profileID }
        try saveProfiles(profiles)

        let assetURL = try reuAssetURL(for: profileID)
        try? FileManager.default.removeItem(at: assetURL)

        if powerOnProfileID == profileID {
            powerOnProfileID = nil
        }
        if deletedSelectedProfile {
            try applyProfile(builtInDefaultProfileID)
        }
    }

    @discardableResult
    static func applyPowerOnProfileIfConfigured() throws -> Bool {
        guard let powerOnProfileID else { return false }
        let profiles = loadProfiles()
        guard profiles.contains(where: { $0.id == powerOnProfileID }) else {
            self.powerOnProfileID = nil
            return false
        }
        try applyProfile(powerOnProfileID)
        return true
    }

    @discardableResult
    static func attachFirmwareProfileToBuiltInDefaultIfNeeded(_ firmwareProfileID: UUID) throws -> Bool {
        let firmwareProfiles = FirmwareProfileStore.loadProfiles()
        guard firmwareProfiles.contains(where: { $0.id == firmwareProfileID && $0.isBootReady }) else {
            throw EmulationProfileStoreError.firmwareProfileUnavailable
        }

        var profiles = loadProfiles()
        guard let index = profiles.firstIndex(where: { $0.id == builtInDefaultProfileID }) else {
            throw EmulationProfileStoreError.profileNotFound
        }

        if let currentFirmwareID = profiles[index].firmwareProfileID,
           firmwareProfiles.contains(where: { $0.id == currentFirmwareID && $0.isBootReady }) {
            return false
        }

        profiles[index].firmwareProfileID = firmwareProfileID
        profiles[index].updatedAt = Date()
        try saveProfiles(profiles)
        return true
    }

    @discardableResult
    static func resetBuiltInDefaultToInitialSettings() throws -> EmulationProfile {
        var profiles = loadProfiles()
        guard let index = profiles.firstIndex(where: { $0.id == builtInDefaultProfileID }) else {
            throw EmulationProfileStoreError.profileNotFound
        }

        let retainedFirmwareProfileID = profiles[index].firmwareProfileID
        profiles[index].settings = .factoryDefault
        profiles[index].firmwareProfileID = retainedFirmwareProfileID
        profiles[index].updatedAt = Date()

        if let assetURL = try? reuAssetURL(for: builtInDefaultProfileID) {
            try? FileManager.default.removeItem(at: assetURL)
        }
        try saveProfiles(profiles)

        if selectedProfileID == builtInDefaultProfileID {
            try applyProfile(builtInDefaultProfileID)
        }
        return profiles[index]
    }

    static func profileNamesReferencingFirmwareProfile(_ firmwareProfileID: UUID) -> [String] {
        loadProfiles()
            .filter { $0.firmwareProfileID == firmwareProfileID }
            .map(\.name)
            .sorted()
    }

    static func profileNamesReferencingCRTPreset(_ crtPresetID: UUID) -> [String] {
        loadProfiles()
            .filter { $0.settings.crtPresetID == crtPresetID }
            .map(\.name)
            .sorted()
    }

    static func applyProfile(_ profileID: UUID) throws {
        guard let profile = loadProfiles().first(where: { $0.id == profileID }) else {
            throw EmulationProfileStoreError.profileNotFound
        }

        if let firmwareProfileID = profile.firmwareProfileID {
            guard FirmwareProfileStore.loadProfiles().contains(where: { $0.id == firmwareProfileID }) else {
                throw EmulationProfileStoreError.firmwareProfileUnavailable
            }
            try FirmwareProfileStore.applyProfile(firmwareProfileID)
        }

        let reuAsset: URL?
        if let imageName = profile.settings.reuImageName {
            let assetURL = try reuAssetURL(for: profile.id)
            guard FileManager.default.fileExists(atPath: assetURL.path) else {
                throw EmulationProfileStoreError.reuImageUnavailable(imageName)
            }
            reuAsset = assetURL
        } else {
            reuAsset = nil
        }

        profile.settings.applyToUserDefaults()

        if let reuAsset, let imageName = profile.settings.reuImageName {
            _ = try FirmwareStore.importREUImage(from: reuAsset, displayName: imageName)
        } else if FirmwareStore.importedREUImageInfo() != nil
                    || C64REUSettings.importedImageName != nil {
            try FirmwareStore.removeImportedREUImage()
        } else {
            FirmwareStore.prepareDirectoriesAndConfiguration()
        }

        selectedProfileID = profile.id
    }

    static func matchesCurrentConfiguration(_ profile: EmulationProfile) -> Bool {
        guard profile.settings.matchesCurrentConfiguration() else { return false }
        guard let firmwareProfileID = profile.firmwareProfileID else { return true }
        return FirmwareProfileStore.activeProfileID == firmwareProfileID
            && !FirmwareProfileStore.activeProfileIsModified
    }

    private static func seedProfilesIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: initializedKey) else { return }

        FirmwareProfileStore.prepareIfNeeded()
        let now = Date()
        let profiles = [
            makeBuiltInDefaultProfile(createdAt: now)
        ]

        let archive = EmulationProfileArchive(version: schemaVersion, profiles: profiles)
        if let data = try? JSONEncoder().encode(archive) {
            defaults.set(data, forKey: profilesKey)
        }
        selectedProfileID = builtInDefaultProfileID
        clearLegacyStartupDefaultSettings()
        defaults.set(true, forKey: initializedKey)
        defaults.set(true, forKey: firmwareReferenceMigrationKey)
    }

    private static func makeBuiltInDefaultProfile(
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) -> EmulationProfile {
        EmulationProfile(
            id: builtInDefaultProfileID,
            name: "Default",
            settings: .factoryDefault,
            firmwareProfileID: FirmwareProfileStore.activeProfileID,
            createdAt: createdAt,
            updatedAt: updatedAt ?? createdAt
        )
    }

    private static func ensureBuiltInDefaultProfile(in profiles: inout [EmulationProfile]) {
        if let index = profiles.firstIndex(where: { $0.id == builtInDefaultProfileID }) {
            var existing = profiles.remove(at: index)
            let needsSave = index != 0 || existing.name != "Default"
            existing.name = "Default"
            profiles.insert(existing, at: 0)
            if needsSave {
                try? saveProfiles(profiles)
            }
            return
        }

        FirmwareProfileStore.prepareIfNeeded()
        profiles.insert(makeBuiltInDefaultProfile(), at: 0)
        try? saveProfiles(profiles)
    }

    private static func clearLegacyStartupDefaultSettings() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: legacyDefaultProfileIDKey)
        defaults.removeObject(forKey: legacyApplyDefaultProfileAtLaunchKey)
    }

    private static func migrateFirmwareReferencesIfNeeded(_ profiles: inout [EmulationProfile]) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: firmwareReferenceMigrationKey) else { return }

        FirmwareProfileStore.prepareIfNeeded()
        let migrationFirmwareProfileID = FirmwareProfileStore.loadProfiles().first?.id
        var changed = false
        for index in profiles.indices where profiles[index].firmwareProfileID == nil {
            profiles[index].firmwareProfileID = migrationFirmwareProfileID
            changed = true
        }

        if changed {
            try? saveProfiles(profiles)
        }
        defaults.set(true, forKey: firmwareReferenceMigrationKey)
    }

    private static func saveProfiles(_ profiles: [EmulationProfile]) throws {
        do {
            let archive = EmulationProfileArchive(version: schemaVersion, profiles: profiles)
            let data = try JSONEncoder().encode(archive)
            UserDefaults.standard.set(data, forKey: profilesKey)
        } catch {
            throw EmulationProfileStoreError.storageFailure(error.localizedDescription)
        }
    }

    private static func captureREUImage(for profile: EmulationProfile) throws {
        let assetURL = try reuAssetURL(for: profile.id)
        if profile.settings.reuImageName != nil {
            try FirmwareStore.copyImportedREUImage(to: assetURL)
        } else {
            try? FileManager.default.removeItem(at: assetURL)
        }
    }

    private static func profilesDirectory() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = appSupport
            .appendingPathComponent("POKE64", isDirectory: true)
            .appendingPathComponent("Profiles", isDirectory: true)
            .appendingPathComponent("REU", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private static func reuAssetURL(for profileID: UUID) throws -> URL {
        try profilesDirectory()
            .appendingPathComponent("\(profileID.uuidString.lowercased()).reu", isDirectory: false)
    }

    private static func replaceFile(at destination: URL, withCopyOf source: URL) throws {
        let temporary = destination.appendingPathExtension("tmp")
        try? FileManager.default.removeItem(at: temporary)
        try FileManager.default.copyItem(at: source, to: temporary)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporary, to: destination)
    }

    private static func validatedName(_ rawName: String) throws -> String {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw EmulationProfileStoreError.invalidName }
        return String(name.prefix(64))
    }

    private static func uniqueName(
        _ requestedName: String,
        excluding excludedID: UUID?,
        profiles: [EmulationProfile]
    ) -> String {
        let usedNames = Set(
            profiles
                .filter { $0.id != excludedID }
                .map { $0.name.lowercased() }
        )
        guard usedNames.contains(requestedName.lowercased()) else {
            return requestedName
        }

        var index = 2
        while usedNames.contains("\(requestedName) \(index)".lowercased()) {
            index += 1
        }
        return "\(requestedName) \(index)"
    }
}
