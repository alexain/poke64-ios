import CryptoKit
import Foundation

enum FirmwareSlot: String, CaseIterable, Identifiable {
    case basic
    case kernal
    case chargen
    case drive1541
    case drive1541II
    case drive1571
    case drive1581

    var id: String { rawValue }

    var title: String {
        switch self {
        case .basic: return "BASIC ROM"
        case .kernal: return "KERNAL ROM"
        case .chargen: return "Character ROM"
        case .drive1541: return "1541 drive ROM"
        case .drive1541II: return "1541-II drive ROM"
        case .drive1571: return "1571 drive ROM"
        case .drive1581: return "1581 drive ROM"
        }
    }

    var detail: String {
        switch self {
        case .basic:
            return "C64 BASIC firmware"
        case .kernal:
            return "C64 KERNAL firmware, including compatible replacements such as JiffyDOS"
        case .chargen:
            return "C64 character generator firmware"
        case .drive1541:
            return "Optional 1541 firmware; compatible replacements such as JiffyDOS are accepted"
        case .drive1541II:
            return "Optional 1541-II firmware; compatible replacements such as JiffyDOS are accepted"
        case .drive1571:
            return "Optional 1571 firmware for D71 media and compatible replacements"
        case .drive1581:
            return "Optional 1581 firmware for D81 media and compatible replacements"
        }
    }

    var requiredSize: Int {
        switch self {
        case .basic, .kernal: return 8_192
        case .chargen: return 4_096
        case .drive1541, .drive1541II: return 16_384
        case .drive1571, .drive1581: return 32_768
        }
    }

    var isRequiredForBoot: Bool {
        switch self {
        case .basic, .kernal, .chargen: return true
        case .drive1541, .drive1541II, .drive1571, .drive1581: return false
        }
    }

    var storedFilename: String {
        switch self {
        case .basic: return "poke64-basic.bin"
        case .kernal: return "poke64-kernal.bin"
        case .chargen: return "poke64-chargen.bin"
        case .drive1541: return "poke64-dos1541.bin"
        case .drive1541II: return "poke64-dos1541ii.bin"
        case .drive1571: return "poke64-dos1571.bin"
        case .drive1581: return "poke64-dos1581.bin"
        }
    }
}

struct FirmwareStatus: Identifiable {
    let slot: FirmwareSlot
    let fileURL: URL
    let fileSize: Int?
    let sha256: String?
    let validationError: String?

    var id: FirmwareSlot { slot }
    var isInstalled: Bool { fileSize != nil }
    var isValid: Bool { isInstalled && validationError == nil }
}

enum FirmwareStoreError: LocalizedError {
    case invalidSize(slot: FirmwareSlot, actual: Int)
    case unreadableFile
    case invalidOpenROMsResponse
    case openROMsDownloadFailed(String)
    case previousFirmwareUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidSize(let slot, let actual):
            return "\(slot.title) must be exactly \(slot.requiredSize) bytes. The selected file is \(actual) bytes."
        case .unreadableFile:
            return "The selected firmware file could not be read."
        case .invalidOpenROMsResponse:
            return "The OpenROMs download returned an invalid response."
        case .openROMsDownloadFailed(let message):
            return "OpenROMs could not be installed: \(message)"
        case .previousFirmwareUnavailable:
            return "No complete previous firmware profile is available to restore."
        }
    }
}

enum FirmwareStore {
    static let openROMsRevision = "ad178dbe4d48cd6a317737a8e0e7e662f7e33d32"
    static let openROMsDisplayRevision = String(openROMsRevision.prefix(7))

    private struct OpenROMsResource {
        let slot: FirmwareSlot
        let filename: String

        var url: URL {
            URL(
                string: "https://raw.githubusercontent.com/MEGA65/open-roms/\(openROMsRevision)/bin/\(filename)"
            )!
        }
    }

    private static let openROMsResources = [
        OpenROMsResource(slot: .basic, filename: "basic_generic.rom"),
        OpenROMsResource(slot: .kernal, filename: "kernal_generic.rom"),
        OpenROMsResource(slot: .chargen, filename: "chargen_openroms.rom")
    ]

    static var statuses: [FirmwareStatus] {
        FirmwareSlot.allCases.map(status(for:))
    }

    static var isBootReady: Bool {
        statuses
            .filter { $0.slot.isRequiredForBoot }
            .allSatisfy(\.isValid)
    }

    static var hasDriveFirmware: Bool {
        [.drive1541, .drive1541II, .drive1571, .drive1581]
            .contains { status(for: $0).isValid }
    }

    static var hasInstalledSystemFirmware: Bool {
        [.basic, .kernal, .chargen].contains { status(for: $0).isInstalled }
    }

    static var isOpenROMsInstalled: Bool {
        guard isBootReady,
              let marker = try? String(contentsOf: openROMsMarkerURL(), encoding: .utf8) else {
            return false
        }
        return marker.trimmingCharacters(in: .whitespacesAndNewlines) == openROMsRevision
    }

    static var canRestorePreviousFirmware: Bool {
        do {
            return try [FirmwareSlot.basic, .kernal, .chargen].allSatisfy { slot in
                FileManager.default.fileExists(
                    atPath: try previousFirmwareDirectory()
                        .appendingPathComponent(slot.storedFilename, isDirectory: false)
                        .path
                )
            }
        } catch {
            return false
        }
    }

    static var activeProfileName: String {
        if isOpenROMsInstalled {
            return "MEGA65 OpenROMs"
        }
        return isBootReady ? "Custom firmware" : "Incomplete firmware"
    }

    static var configurationFingerprint: String {
        let firmware = statuses.map { status in
            [
                status.slot.rawValue,
                status.fileSize.map(String.init) ?? "missing",
                status.sha256 ?? "no-hash",
                status.validationError ?? "valid"
            ].joined(separator: ":")
        }
        .joined(separator: "|")

        return [
            firmware,
            "profile:\(activeProfileName)",
            "machine:\(C64MachineModel.selected.rawValue)",
            "reu:\(C64REUSettings.configurationFingerprint)",
            "video:\(C64VideoSettings.configurationFingerprint)",
            "audio:\(C64AudioSettings.configurationFingerprint)",
            "drive:\(C64DriveSettings.configurationFingerprint)"
        ].joined(separator: "|")
    }

    static func prepareDirectoriesAndConfiguration() {
        do {
            _ = try firmwareDirectory()
            try writeVicerc()
        } catch {
            NSLog("POKE64 firmware setup failed: %@", error.localizedDescription)
        }
    }

    static func status(for slot: FirmwareSlot) -> FirmwareStatus {
        let url: URL
        do {
            url = try fileURL(for: slot)
        } catch {
            return FirmwareStatus(
                slot: slot,
                fileURL: URL(fileURLWithPath: "/"),
                fileSize: nil,
                sha256: nil,
                validationError: error.localizedDescription
            )
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            return FirmwareStatus(slot: slot, fileURL: url, fileSize: nil, sha256: nil, validationError: nil)
        }

        do {
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            let error = data.count == slot.requiredSize
                ? nil
                : "Expected \(slot.requiredSize) bytes; found \(data.count)."
            return FirmwareStatus(
                slot: slot,
                fileURL: url,
                fileSize: data.count,
                sha256: sha256(data),
                validationError: error
            )
        } catch {
            return FirmwareStatus(
                slot: slot,
                fileURL: url,
                fileSize: nil,
                sha256: nil,
                validationError: error.localizedDescription
            )
        }
    }

    static func importFirmware(from source: URL, into slot: FirmwareSlot) throws {
        let data: Data
        do {
            data = try Data(contentsOf: source, options: [.mappedIfSafe])
        } catch {
            throw FirmwareStoreError.unreadableFile
        }

        guard data.count == slot.requiredSize else {
            throw FirmwareStoreError.invalidSize(slot: slot, actual: data.count)
        }

        let destination = try fileURL(for: slot)
        let temporary = destination.appendingPathExtension("tmp")
        try? FileManager.default.removeItem(at: temporary)
        try data.write(to: temporary, options: [.atomic])
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporary, to: destination)
        if slot.isRequiredForBoot {
            try clearOpenROMsMarker()
        }
        try writeVicerc()
    }

    static func remove(_ slot: FirmwareSlot) throws {
        let destination = try fileURL(for: slot)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        if slot.isRequiredForBoot {
            try clearOpenROMsMarker()
        }
        try writeVicerc()
    }

    static func installOpenROMs() async throws {
        var downloaded: [FirmwareSlot: Data] = [:]

        do {
            for resource in openROMsResources {
                let (data, response) = try await URLSession.shared.data(from: resource.url)
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode) else {
                    throw FirmwareStoreError.invalidOpenROMsResponse
                }
                guard data.count == resource.slot.requiredSize else {
                    throw FirmwareStoreError.invalidSize(
                        slot: resource.slot,
                        actual: data.count
                    )
                }
                downloaded[resource.slot] = data
            }
        } catch let error as FirmwareStoreError {
            throw error
        } catch {
            throw FirmwareStoreError.openROMsDownloadFailed(error.localizedDescription)
        }

        let requiredSlots: [FirmwareSlot] = [.basic, .kernal, .chargen]
        var previousData: [FirmwareSlot: Data] = [:]
        for slot in requiredSlots {
            guard let url = try? fileURL(for: slot),
                  let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
                continue
            }
            previousData[slot] = data
        }

        if isBootReady && !isOpenROMsInstalled {
            try savePreviousFirmwareProfile()
        }

        do {
            for slot in requiredSlots {
                guard let data = downloaded[slot] else {
                    throw FirmwareStoreError.invalidOpenROMsResponse
                }
                try replaceFirmwareData(data, in: slot)
            }
            try openROMsRevision.write(
                to: openROMsMarkerURL(),
                atomically: true,
                encoding: .utf8
            )
            try writeVicerc()
        } catch {
            for slot in requiredSlots {
                let destination = try fileURL(for: slot)
                try? FileManager.default.removeItem(at: destination)
                if let data = previousData[slot] {
                    try? data.write(to: destination, options: .atomic)
                }
            }
            try? clearOpenROMsMarker()
            try? writeVicerc()
            throw error
        }
    }

    static func restorePreviousFirmware() throws {
        guard canRestorePreviousFirmware else {
            throw FirmwareStoreError.previousFirmwareUnavailable
        }

        for slot in [FirmwareSlot.basic, .kernal, .chargen] {
            let source = try previousFirmwareDirectory()
                .appendingPathComponent(slot.storedFilename, isDirectory: false)
            let data = try Data(contentsOf: source, options: [.mappedIfSafe])
            guard data.count == slot.requiredSize else {
                throw FirmwareStoreError.invalidSize(slot: slot, actual: data.count)
            }
            try replaceFirmwareData(data, in: slot)
        }

        try clearOpenROMsMarker()
        try writeVicerc()
    }

    private static func sanitizeDriveConfiguration() {
        let defaults = UserDefaults.standard
        let drive9Enabled = defaults.object(forKey: C64DriveSettings.drive9EnabledKey) == nil
            ? C64DriveSettings.defaultDrive9Enabled
            : defaults.bool(forKey: C64DriveSettings.drive9EnabledKey)
        let requested = defaults.object(forKey: C64DriveSettings.trueDriveEmulationKey) == nil
            ? C64DriveSettings.defaultTrueDriveEmulation
            : defaults.bool(forKey: C64DriveSettings.trueDriveEmulationKey)
        let drive8Ready = status(for: C64DriveModel.selected(for: 8).firmwareSlot).isValid
        let drive9Ready = !drive9Enabled
            || status(for: C64DriveModel.selected(for: 9).firmwareSlot).isValid

        if requested && (!drive8Ready || !drive9Ready) {
            defaults.set(false, forKey: C64DriveSettings.trueDriveEmulationKey)
        }
    }

    static func writeVicerc() throws {
        sanitizeDriveConfiguration()
        let vice = try viceDirectory()
        let configURL = vice.appendingPathComponent("vicerc", isDirectory: false)

        let basic = try fileURL(for: .basic)
        let kernal = try fileURL(for: .kernal)
        let chargen = try fileURL(for: .chargen)
        let drive1541 = try fileURL(for: .drive1541)
        let drive1541II = try fileURL(for: .drive1541II)
        let drive1571 = try fileURL(for: .drive1571)
        let drive1581 = try fileURL(for: .drive1581)

        var lines = ["[C64SC]"]
        if FileManager.default.fileExists(atPath: basic.path) {
            lines.append("BasicName=\"\(escapedVicercPath(basic.path))\"")
        }
        if FileManager.default.fileExists(atPath: kernal.path) {
            lines.append("KernalName=\"\(escapedVicercPath(kernal.path))\"")
        }
        if FileManager.default.fileExists(atPath: chargen.path) {
            lines.append("ChargenName=\"\(escapedVicercPath(chargen.path))\"")
        }

        let defaults = UserDefaults.standard
        let drive8Model = C64DriveModel.selected(for: 8)
        let drive9Model = C64DriveModel.selected(for: 9)
        let drive9Enabled = defaults.object(forKey: C64DriveSettings.drive9EnabledKey) == nil
            ? C64DriveSettings.defaultDrive9Enabled
            : defaults.bool(forKey: C64DriveSettings.drive9EnabledKey)
        let drive8FirmwareIsValid = status(for: drive8Model.firmwareSlot).isValid
        let drive9FirmwareIsValid = !drive9Enabled
            || status(for: drive9Model.firmwareSlot).isValid
        let trueDriveRequested = defaults.object(forKey: C64DriveSettings.trueDriveEmulationKey) == nil
            ? C64DriveSettings.defaultTrueDriveEmulation
            : defaults.bool(forKey: C64DriveSettings.trueDriveEmulationKey)
        let trueDriveEnabled = trueDriveRequested
            && drive8FirmwareIsValid
            && drive9FirmwareIsValid
        let writeProtected = defaults.object(forKey: C64DriveSettings.writeProtectionKey) == nil
            ? C64DriveSettings.defaultWriteProtection
            : defaults.bool(forKey: C64DriveSettings.writeProtectionKey)

        let reuSize = C64REUSize.selected
        if let sizeInKilobytes = reuSize.sizeInKilobytes {
            let persistentMemory = C64REUSettings.persistentMemoryEnabled
            let reuFilename = persistentMemory
                ? escapedVicercPath(try reuImageURL().path)
                : ""
            lines.append("REUfilename=\"\(reuFilename)\"")
            lines.append("REUImageWrite=\(persistentMemory ? 1 : 0)")
            lines.append("REUsize=\(sizeInKilobytes)")
            lines.append("REU=1")
        } else {
            lines.append("REUfilename=\"\"")
            lines.append("REUImageWrite=0")
            lines.append("REU=0")
        }

        // VICE validates a drive model against its configured ROM. Write the
        // ROM resources before drive types so configuration loading never tries
        // to enable a model while it still points at a missing default ROM.
        let driveROMs: [(URL, String)] = [
            (drive1541, "DosName1541"),
            (drive1541II, "DosName1541ii"),
            (drive1571, "DosName1571"),
            (drive1581, "DosName1581")
        ]
        for (url, resource) in driveROMs where FileManager.default.fileExists(atPath: url.path) {
            lines.append("\(resource)=\"\(escapedVicercPath(url.path))\"")
        }

        lines.append("Drive8Type=\(drive8Model.resourceValue)")
        lines.append("Drive9Type=\(drive9Enabled ? drive9Model.resourceValue : 0)")
        lines.append("Drive8TrueEmulation=\(trueDriveEnabled ? 1 : 0)")
        lines.append("Drive9TrueEmulation=\(drive9Enabled && trueDriveEnabled ? 1 : 0)")
        lines.append("TrapDevice8=\(trueDriveEnabled ? 0 : 1)")
        lines.append("TrapDevice9=\(drive9Enabled ? (trueDriveEnabled ? 0 : 1) : 0)")
        lines.append("AttachDevice8d0Readonly=\(writeProtected ? 1 : 0)")
        lines.append("AttachDevice8d1Readonly=\(writeProtected ? 1 : 0)")
        lines.append("AttachDevice9d0Readonly=\(writeProtected ? 1 : 0)")
        lines.append("AttachDevice9d1Readonly=\(writeProtected ? 1 : 0)")

        let storedSoundLevel = defaults.object(forKey: C64DriveSettings.soundLevelKey) == nil
            ? C64DriveSettings.defaultSoundLevel
            : defaults.integer(forKey: C64DriveSettings.soundLevelKey)
        let soundLevel = min(100, max(0, ((storedSoundLevel + 2) / 5) * 5))
        let driveSoundEnabled = trueDriveEnabled
            && (drive8Model.supportsMechanicalSound
                || (drive9Enabled && drive9Model.supportsMechanicalSound))
            && soundLevel > 0
        lines.append("DriveSoundEmulation=\(driveSoundEnabled ? 1 : 0)")
        lines.append("DriveSoundEmulationVolume=\(driveSoundEnabled ? soundLevel * 20 : 0)")

        // Never expose VICE's host-filesystem device as an empty IEC drive.
        lines.append("FileSystemDevice8=0")
        lines.append("FileSystemDevice9=0")
        lines.append("FileSystemDevice10=0")
        lines.append("FileSystemDevice11=0")

        lines.append("")
        try lines.joined(separator: "\n").write(to: configURL, atomically: true, encoding: .utf8)
    }

    static func applicationSupportSystemDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let system = base.appendingPathComponent("System", isDirectory: true)
        try FileManager.default.createDirectory(at: system, withIntermediateDirectories: true)
        return system
    }

    private static func viceDirectory() throws -> URL {
        let vice = try applicationSupportSystemDirectory()
            .appendingPathComponent("vice", isDirectory: true)
        try FileManager.default.createDirectory(at: vice, withIntermediateDirectories: true)
        return vice
    }

    private static func firmwareDirectory() throws -> URL {
        let firmware = try viceDirectory()
            .appendingPathComponent("POKE64", isDirectory: true)
            .appendingPathComponent("Firmware", isDirectory: true)
        try FileManager.default.createDirectory(at: firmware, withIntermediateDirectories: true)
        return firmware
    }

    private static func reuImageURL() throws -> URL {
        let directory = try viceDirectory()
            .appendingPathComponent("POKE64", isDirectory: true)
            .appendingPathComponent("REU", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory.appendingPathComponent("persistent-memory.reu", isDirectory: false)
    }

    private static func fileURL(for slot: FirmwareSlot) throws -> URL {
        try firmwareDirectory().appendingPathComponent(slot.storedFilename, isDirectory: false)
    }

    private static func openROMsMarkerURL() throws -> URL {
        try firmwareDirectory()
            .appendingPathComponent("openroms-profile.txt", isDirectory: false)
    }

    private static func previousFirmwareDirectory() throws -> URL {
        let directory = try firmwareDirectory()
            .appendingPathComponent("PreviousProfile", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        return directory
    }

    private static func savePreviousFirmwareProfile() throws {
        let directory = try previousFirmwareDirectory()
        try? FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )

        for slot in [FirmwareSlot.basic, .kernal, .chargen] {
            let source = try fileURL(for: slot)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            let destination = directory.appendingPathComponent(
                slot.storedFilename,
                isDirectory: false
            )
            try FileManager.default.copyItem(at: source, to: destination)
        }
    }

    private static func replaceFirmwareData(_ data: Data, in slot: FirmwareSlot) throws {
        guard data.count == slot.requiredSize else {
            throw FirmwareStoreError.invalidSize(slot: slot, actual: data.count)
        }
        let destination = try fileURL(for: slot)
        let temporary = destination.appendingPathExtension("tmp")
        try? FileManager.default.removeItem(at: temporary)
        try data.write(to: temporary, options: [.atomic])
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporary, to: destination)
    }

    private static func clearOpenROMsMarker() throws {
        let marker = try openROMsMarkerURL()
        if FileManager.default.fileExists(atPath: marker.path) {
            try FileManager.default.removeItem(at: marker)
        }
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func escapedVicercPath(_ path: String) -> String {
        path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
