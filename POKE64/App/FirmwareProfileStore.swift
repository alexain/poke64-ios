import Foundation

struct FirmwareProfile: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var firmwareFingerprint: String
    var installedSlots: [String]
    var openROMsRevision: String?
    let createdAt: Date
    var updatedAt: Date

    var installedFirmwareSlots: [FirmwareSlot] {
        installedSlots.compactMap(FirmwareSlot.init(rawValue:))
    }

    var isBootReady: Bool {
        let installed = Set(installedSlots)
        return FirmwareSlot.allCases
            .filter(\.isRequiredForBoot)
            .allSatisfy { installed.contains($0.rawValue) }
    }

    var compactSummary: String {
        var components: [String] = []
        if let openROMsRevision {
            components.append("OpenROMs \(String(openROMsRevision.prefix(7)))")
        } else {
            components.append(isBootReady ? "Boot ready" : "Incomplete")
        }

        let driveCount = installedFirmwareSlots.filter {
            switch $0 {
            case .drive1541, .drive1541II, .drive1571, .drive1581:
                return true
            default:
                return false
            }
        }.count
        if driveCount > 0 {
            components.append("\(driveCount) drive ROM\(driveCount == 1 ? "" : "s")")
        }
        if installedSlots.contains(FirmwareSlot.printerMPS803.rawValue) {
            components.append("MPS-803")
        }
        return components.joined(separator: " · ")
    }
}

enum FirmwareProfileStoreError: LocalizedError {
    case invalidName
    case profileNotFound
    case noFirmwareInstalled
    case profileFilesUnavailable(String)
    case profileInUse(String, [String])
    case storageFailure(String)

    var errorDescription: String? {
        switch self {
        case .invalidName:
            return "Enter a firmware profile name."
        case .profileNotFound:
            return "The selected firmware profile no longer exists."
        case .noFirmwareInstalled:
            return "Import at least one firmware ROM before creating a firmware profile."
        case .profileFilesUnavailable(let name):
            return "The firmware files stored for \"\(name)\" are unavailable."
        case .profileInUse(let name, let profileNames):
            let users = profileNames.joined(separator: ", ")
            return "The firmware profile \"\(name)\" is used by: \(users). Assign those emulation profiles to another firmware profile before deleting it."
        case .storageFailure(let message):
            return "The firmware profile could not be saved: \(message)"
        }
    }
}

private struct FirmwareProfileArchive: Codable {
    let version: Int
    var profiles: [FirmwareProfile]
}

enum FirmwareProfileStore {
    static let profilesKey = "poke64.firmwareProfiles.data"
    static let schemaVersion = 1
    static let initializedKey = "poke64.firmwareProfiles.initialized"
    static let activeProfileIDKey = "poke64.firmwareProfiles.activeID"
    private static let initialAutoPowerOnPendingKey = "poke64.firmwareProfiles.initialAutoPowerOnPending"

    static var activeProfileID: UUID? {
        get {
            guard let raw = UserDefaults.standard.string(forKey: activeProfileIDKey) else {
                return nil
            }
            return UUID(uuidString: raw)
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.uuidString, forKey: activeProfileIDKey)
            } else {
                UserDefaults.standard.removeObject(forKey: activeProfileIDKey)
            }
        }
    }

    static var initialAutoPowerOnPending: Bool {
        UserDefaults.standard.bool(forKey: initialAutoPowerOnPendingKey)
    }

    static func consumeInitialAutoPowerOnPending() {
        UserDefaults.standard.removeObject(forKey: initialAutoPowerOnPendingKey)
    }

    static var activeProfile: FirmwareProfile? {
        guard let activeProfileID else { return nil }
        return loadProfiles().first { $0.id == activeProfileID }
    }

    static var activeProfileIsModified: Bool {
        guard let activeProfile else { return false }
        return activeProfile.firmwareFingerprint != FirmwareStore.firmwareFingerprint
    }

    static func prepareIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: initializedKey) else { return }

        do {
            var profiles: [FirmwareProfile] = []
            if FirmwareStore.hasAnyInstalledFirmware {
                let now = Date()
                let profile = makeProfile(
                    id: UUID(),
                    name: FirmwareStore.detectedProfileName,
                    createdAt: now,
                    updatedAt: now
                )
                try FirmwareStore.copyActiveFirmware(to: try profileDirectory(for: profile.id))
                profiles.append(profile)
                activeProfileID = profile.id
            }
            try saveProfiles(profiles)
            defaults.set(true, forKey: initializedKey)
        } catch {
            NSLog("POKE64 firmware profile migration failed: %@", error.localizedDescription)
        }
    }

    static func loadProfiles() -> [FirmwareProfile] {
        prepareIfNeeded()
        guard let data = UserDefaults.standard.data(forKey: profilesKey),
              let archive = try? JSONDecoder().decode(FirmwareProfileArchive.self, from: data),
              archive.version == schemaVersion else {
            return []
        }
        return archive.profiles
    }

    @discardableResult
    static func ensureInitialBootProfileIfNeeded() throws -> FirmwareProfile? {
        guard FirmwareStore.isBootReady else { return nil }

        var profiles = loadProfiles()
        if let readyProfile = profiles.first(where: \.isBootReady) {
            if try EmulationProfileStore.attachFirmwareProfileToBuiltInDefaultIfNeeded(readyProfile.id) {
                UserDefaults.standard.set(true, forKey: initialAutoPowerOnPendingKey)
            }
            return nil
        }

        let now = Date()
        let profile = makeProfile(
            id: UUID(),
            name: uniqueName(
                FirmwareStore.detectedProfileName,
                excluding: nil,
                profiles: profiles
            ),
            createdAt: now,
            updatedAt: now
        )
        try FirmwareStore.copyActiveFirmware(to: try profileDirectory(for: profile.id))
        profiles.append(profile)
        try saveProfiles(profiles)
        activeProfileID = profile.id

        _ = try EmulationProfileStore.attachFirmwareProfileToBuiltInDefaultIfNeeded(profile.id)
        UserDefaults.standard.set(true, forKey: initialAutoPowerOnPendingKey)
        return profile
    }

    @discardableResult
    static func createProfile(named rawName: String) throws -> FirmwareProfile {
        guard FirmwareStore.hasAnyInstalledFirmware else {
            throw FirmwareProfileStoreError.noFirmwareInstalled
        }

        let name = try validatedName(rawName)
        var profiles = loadProfiles()
        let now = Date()
        let profile = makeProfile(
            id: UUID(),
            name: uniqueName(name, excluding: nil, profiles: profiles),
            createdAt: now,
            updatedAt: now
        )

        try FirmwareStore.copyActiveFirmware(to: try profileDirectory(for: profile.id))
        profiles.append(profile)
        try saveProfiles(profiles)
        activeProfileID = profile.id
        return profile
    }

    @discardableResult
    static func updateProfile(_ profileID: UUID) throws -> FirmwareProfile {
        var profiles = loadProfiles()
        guard let index = profiles.firstIndex(where: { $0.id == profileID }) else {
            throw FirmwareProfileStoreError.profileNotFound
        }

        try FirmwareStore.copyActiveFirmware(to: try profileDirectory(for: profileID))
        profiles[index].firmwareFingerprint = FirmwareStore.firmwareFingerprint
        profiles[index].installedSlots = currentInstalledSlots()
        profiles[index].openROMsRevision = FirmwareStore.openROMsRevisionMarker
        profiles[index].updatedAt = Date()
        try saveProfiles(profiles)
        activeProfileID = profileID
        return profiles[index]
    }

    @discardableResult
    static func renameProfile(_ profileID: UUID, to rawName: String) throws -> FirmwareProfile {
        let name = try validatedName(rawName)
        var profiles = loadProfiles()
        guard let index = profiles.firstIndex(where: { $0.id == profileID }) else {
            throw FirmwareProfileStoreError.profileNotFound
        }

        profiles[index].name = uniqueName(name, excluding: profileID, profiles: profiles)
        profiles[index].updatedAt = Date()
        try saveProfiles(profiles)
        return profiles[index]
    }

    @discardableResult
    static func duplicateProfile(_ profileID: UUID) throws -> FirmwareProfile {
        var profiles = loadProfiles()
        guard let source = profiles.first(where: { $0.id == profileID }) else {
            throw FirmwareProfileStoreError.profileNotFound
        }

        let sourceDirectory = try profileDirectory(for: source.id)
        guard FileManager.default.fileExists(atPath: sourceDirectory.path) else {
            throw FirmwareProfileStoreError.profileFilesUnavailable(source.name)
        }

        let now = Date()
        let duplicate = FirmwareProfile(
            id: UUID(),
            name: uniqueName("\(source.name) Copy", excluding: nil, profiles: profiles),
            firmwareFingerprint: source.firmwareFingerprint,
            installedSlots: source.installedSlots,
            openROMsRevision: source.openROMsRevision,
            createdAt: now,
            updatedAt: now
        )
        try copyDirectory(
            from: sourceDirectory,
            to: try profileDirectory(for: duplicate.id)
        )
        profiles.append(duplicate)
        try saveProfiles(profiles)
        return duplicate
    }

    static func deleteProfile(_ profileID: UUID) throws {
        var profiles = loadProfiles()
        guard let profile = profiles.first(where: { $0.id == profileID }) else {
            throw FirmwareProfileStoreError.profileNotFound
        }

        let references = EmulationProfileStore.profileNamesReferencingFirmwareProfile(profileID)
        guard references.isEmpty else {
            throw FirmwareProfileStoreError.profileInUse(profile.name, references)
        }

        profiles.removeAll { $0.id == profileID }
        try saveProfiles(profiles)
        try? FileManager.default.removeItem(at: try profileDirectory(for: profileID))

        if activeProfileID == profileID {
            activeProfileID = nil
        }
    }

    static func applyProfile(_ profileID: UUID) throws {
        guard let profile = loadProfiles().first(where: { $0.id == profileID }) else {
            throw FirmwareProfileStoreError.profileNotFound
        }

        let directory = try profileDirectory(for: profile.id)
        guard FileManager.default.fileExists(atPath: directory.path) else {
            throw FirmwareProfileStoreError.profileFilesUnavailable(profile.name)
        }

        try FirmwareStore.replaceActiveFirmware(from: directory)
        activeProfileID = profile.id
    }

    static func matchesCurrentFirmware(_ profile: FirmwareProfile) -> Bool {
        profile.firmwareFingerprint == FirmwareStore.firmwareFingerprint
    }

    private static func makeProfile(
        id: UUID,
        name: String,
        createdAt: Date,
        updatedAt: Date
    ) -> FirmwareProfile {
        FirmwareProfile(
            id: id,
            name: name,
            firmwareFingerprint: FirmwareStore.firmwareFingerprint,
            installedSlots: currentInstalledSlots(),
            openROMsRevision: FirmwareStore.openROMsRevisionMarker,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private static func currentInstalledSlots() -> [String] {
        FirmwareStore.statuses
            .filter(\.isInstalled)
            .map { $0.slot.rawValue }
            .sorted()
    }

    private static func saveProfiles(_ profiles: [FirmwareProfile]) throws {
        do {
            let archive = FirmwareProfileArchive(version: schemaVersion, profiles: profiles)
            UserDefaults.standard.set(try JSONEncoder().encode(archive), forKey: profilesKey)
        } catch {
            throw FirmwareProfileStoreError.storageFailure(error.localizedDescription)
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
            .appendingPathComponent("Firmware", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func profileDirectory(for profileID: UUID) throws -> URL {
        try profilesDirectory()
            .appendingPathComponent(profileID.uuidString.lowercased(), isDirectory: true)
    }

    private static func copyDirectory(from source: URL, to destination: URL) throws {
        let temporary = destination.appendingPathExtension("tmp")
        try? FileManager.default.removeItem(at: temporary)
        try FileManager.default.copyItem(at: source, to: temporary)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporary, to: destination)
    }

    private static func validatedName(_ rawName: String) throws -> String {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw FirmwareProfileStoreError.invalidName }
        return String(name.prefix(64))
    }

    private static func uniqueName(
        _ requestedName: String,
        excluding excludedID: UUID?,
        profiles: [FirmwareProfile]
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
