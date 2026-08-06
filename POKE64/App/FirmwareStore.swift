import CryptoKit
import Foundation

enum FirmwareSlot: String, CaseIterable, Identifiable {
    case basic
    case kernal
    case chargen
    case drive1541II

    var id: String { rawValue }

    var title: String {
        switch self {
        case .basic: return "BASIC ROM"
        case .kernal: return "KERNAL ROM"
        case .chargen: return "Character ROM"
        case .drive1541II: return "1541-II drive ROM"
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
        case .drive1541II:
            return "Optional drive firmware; compatible replacements such as JiffyDOS are accepted"
        }
    }

    var requiredSize: Int {
        switch self {
        case .basic, .kernal: return 8_192
        case .chargen: return 4_096
        case .drive1541II: return 16_384
        }
    }

    var isRequiredForBoot: Bool {
        switch self {
        case .basic, .kernal, .chargen: return true
        case .drive1541II: return false
        }
    }

    var storedFilename: String {
        switch self {
        case .basic: return "poke64-basic.bin"
        case .kernal: return "poke64-kernal.bin"
        case .chargen: return "poke64-chargen.bin"
        case .drive1541II: return "poke64-dos1541ii.bin"
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
        status(for: .drive1541II).isValid
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
            "video:\(C64VideoSettings.configurationFingerprint)",
            "audio:\(C64AudioSettings.configurationFingerprint)"
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

    static func writeVicerc() throws {
        let vice = try viceDirectory()
        let configURL = vice.appendingPathComponent("vicerc", isDirectory: false)

        let basic = try fileURL(for: .basic)
        let kernal = try fileURL(for: .kernal)
        let chargen = try fileURL(for: .chargen)
        let drive = try fileURL(for: .drive1541II)

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

        let driveInstalled = FileManager.default.fileExists(atPath: drive.path)

        // Temporary compatibility mode: use VICE virtual-device traps for
        // reliable D64 autostart until the dedicated Disk Drives panel owns
        // drive models, ROM selection and True Drive Emulation.
        lines.append("Drive8TrueEmulation=0")
        lines.append("Drive9TrueEmulation=0")
        lines.append("TrapDevice8=1")
        lines.append("TrapDevice9=1")
        // Do not expose VICE's host-filesystem device when no disk image is
        // mounted. Runtime disk attachment switches the unit to its virtual
        // disk-image backend; an empty unit must answer DEVICE NOT PRESENT.
        lines.append("FileSystemDevice8=0")
        lines.append("FileSystemDevice9=0")
        lines.append("FileSystemDevice10=0")
        lines.append("FileSystemDevice11=0")
        if driveInstalled {
            // Retain the imported 1541-II ROM for the future drive backend.
            lines.append("DosName1541ii=\"\(escapedVicercPath(drive.path))\"")
        }

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
