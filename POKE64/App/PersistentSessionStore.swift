import Foundation

struct PersistentSessionMediaDescriptor: Codable, Equatable {
    let id: UUID
    let title: String
    let originalFilename: String
    let mediaType: LibraryMediaType
    let libraryItemID: UUID?
    let sessionFilename: String?
}

struct PersistentSessionDiskDescriptor: Codable, Equatable {
    let unit: Int
    let media: PersistentSessionMediaDescriptor
}

struct PersistentSessionMetadata: Codable, Equatable {
    static let schemaVersion = 1

    let version: Int
    let savedAt: Date
    let appVersion: String
    let configurationFingerprint: String
    let emulationProfileID: UUID?
    let firmwareProfileID: UUID?
    let disks: [PersistentSessionDiskDescriptor]
    let tape: PersistentSessionMediaDescriptor?
    let cartridge: PersistentSessionMediaDescriptor?
    let activeProgram: PersistentSessionMediaDescriptor?
    let stateByteCount: Int
}

struct PersistentSessionArchive {
    let metadata: PersistentSessionMetadata
    let state: Data
}

enum PersistentSessionStoreError: LocalizedError {
    case invalidArchive
    case mediaUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .invalidArchive:
            return "The saved POKE64 session is incomplete or damaged."
        case .mediaUnavailable(let name):
            return "The saved session media is no longer available: \(name)"
        }
    }
}

enum PersistentSessionStore {
    private static let stateFilename = "autosuspend.state"
    private static let metadataFilename = "session.json"
    private static let mediaDirectoryName = "Media"

    static var currentAppVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    static func load() throws -> PersistentSessionArchive? {
        let root = try sessionDirectory(create: false)
        let stateURL = root.appendingPathComponent(stateFilename, isDirectory: false)
        let metadataURL = root.appendingPathComponent(metadataFilename, isDirectory: false)

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: stateURL.path),
              fileManager.fileExists(atPath: metadataURL.path) else {
            return nil
        }

        let metadataData = try Data(contentsOf: metadataURL)
        let metadata = try JSONDecoder().decode(PersistentSessionMetadata.self, from: metadataData)
        guard metadata.version == PersistentSessionMetadata.schemaVersion else {
            throw PersistentSessionStoreError.invalidArchive
        }

        let state = try Data(contentsOf: stateURL, options: [.mappedIfSafe])
        guard !state.isEmpty, state.count == metadata.stateByteCount else {
            throw PersistentSessionStoreError.invalidArchive
        }

        return PersistentSessionArchive(metadata: metadata, state: state)
    }

    static func save(state: Data, metadata: PersistentSessionMetadata) throws {
        guard !state.isEmpty, state.count == metadata.stateByteCount else {
            throw PersistentSessionStoreError.invalidArchive
        }

        let root = try sessionDirectory(create: true)
        let stateURL = root.appendingPathComponent(stateFilename, isDirectory: false)
        let metadataURL = root.appendingPathComponent(metadataFilename, isDirectory: false)

        // Commit the binary snapshot first and the metadata last. A launch can
        // therefore only observe metadata for a completely written state file.
        try state.write(to: stateURL, options: [.atomic])

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(metadata).write(to: metadataURL, options: [.atomic])

        try removeUnusedSessionMedia(referencedBy: metadata)
    }

    static func descriptor(for media: MediaReference) throws -> PersistentSessionMediaDescriptor {
        if let libraryItemID = media.libraryItemID {
            return PersistentSessionMediaDescriptor(
                id: media.id,
                title: media.title,
                originalFilename: media.originalFilename,
                mediaType: media.mediaType,
                libraryItemID: libraryItemID,
                sessionFilename: nil
            )
        }

        let filename = "\(media.id.uuidString.lowercased()).\(media.mediaType.rawValue)"
        let destination = try sessionMediaDirectory(create: true)
            .appendingPathComponent(filename, isDirectory: false)
        let temporary = destination.appendingPathExtension("tmp")
        let fileManager = FileManager.default

        try? fileManager.removeItem(at: temporary)
        try fileManager.copyItem(at: media.url, to: temporary)
        try? fileManager.removeItem(at: destination)
        try fileManager.moveItem(at: temporary, to: destination)

        return PersistentSessionMediaDescriptor(
            id: media.id,
            title: media.title,
            originalFilename: media.originalFilename,
            mediaType: media.mediaType,
            libraryItemID: nil,
            sessionFilename: filename
        )
    }

    static func mediaURL(for descriptor: PersistentSessionMediaDescriptor) throws -> URL {
        guard descriptor.libraryItemID == nil,
              let sessionFilename = descriptor.sessionFilename else {
            throw PersistentSessionStoreError.mediaUnavailable(descriptor.originalFilename)
        }

        let url = try sessionMediaDirectory(create: false)
            .appendingPathComponent(sessionFilename, isDirectory: false)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw PersistentSessionStoreError.mediaUnavailable(descriptor.originalFilename)
        }
        return url
    }

    static func clear() {
        guard let root = try? sessionDirectory(create: false) else { return }
        try? FileManager.default.removeItem(at: root)
    }

    private static func sessionDirectory(create: Bool) throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: create
        )
        let root = appSupport
            .appendingPathComponent("POKE64", isDirectory: true)
            .appendingPathComponent("Session", isDirectory: true)
        if create {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }
        return root
    }

    private static func sessionMediaDirectory(create: Bool) throws -> URL {
        let directory = try sessionDirectory(create: create)
            .appendingPathComponent(mediaDirectoryName, isDirectory: true)
        if create {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    private static func removeUnusedSessionMedia(referencedBy metadata: PersistentSessionMetadata) throws {
        let descriptors = metadata.disks.map(\.media)
            + [metadata.tape, metadata.cartridge, metadata.activeProgram].compactMap { $0 }
        let referenced = Set(descriptors.compactMap(\.sessionFilename))

        guard let directory = try? sessionMediaDirectory(create: false),
              let contents = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
              ) else {
            return
        }

        for url in contents where !referenced.contains(url.lastPathComponent) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
