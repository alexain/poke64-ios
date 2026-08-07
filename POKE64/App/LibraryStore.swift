import Combine
import CryptoKit
import Foundation

/// Media formats currently exposed by the first persistent-library implementation.
enum LibraryMediaType: String, Codable, CaseIterable, Hashable {
    case d64
    case d71
    case d81
    case g64
    case prg
    case crt
    case tap
    case t64

    init?(fileExtension: String) {
        self.init(rawValue: fileExtension.lowercased())
    }

    var displayName: String {
        rawValue.uppercased()
    }

    var systemImage: String {
        switch self {
        case .d64, .d71, .d81, .g64:
            return "externaldrive.fill"
        case .prg:
            return "doc.text.fill"
        case .crt:
            return "shippingbox.fill"
        case .tap, .t64:
            return "recordingtape"
        }
    }

    static var supportedExtensionsDescription: String {
        allCases.map(\.displayName).joined(separator: ", ")
    }

    var isDiskImage: Bool {
        switch self {
        case .d64, .d71, .d81, .g64:
            return true
        case .prg, .crt, .tap, .t64:
            return false
        }
    }

    var driveRequirementDescription: String? {
        switch self {
        case .d64, .g64:
            return "Commodore 1541, 1541-II or 1571"
        case .d71:
            return "Commodore 1571"
        case .d81:
            return "Commodore 1581"
        case .prg, .crt, .tap, .t64:
            return nil
        }
    }

}

struct LibraryMediaSetDescriptor: Hashable {
    let key: String
    let displayName: String
    let memberLabel: String
    let sortOrder: Int

    static func detect(in filename: String) -> LibraryMediaSetDescriptor? {
        let stem = URL(fileURLWithPath: filename)
            .deletingPathExtension()
            .lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let markerPattern = #"(?i)(?:^|[\s._(\[])(?:disk|disc|side)[\s._-]*([0-9]+|[a-z])"#
        guard let markerExpression = try? NSRegularExpression(pattern: markerPattern),
              let markerMatch = markerExpression.firstMatch(
                in: stem,
                range: NSRange(stem.startIndex..<stem.endIndex, in: stem)
              ),
              let markerRange = Range(markerMatch.range(at: 0), in: stem) else {
            return nil
        }

        let base = String(stem[..<markerRange.lowerBound])
            .trimmingCharacters(in: CharacterSet(charactersIn: " ._-()[]"))
        guard !base.isEmpty else { return nil }

        let suffix = String(stem[markerRange.lowerBound...])
        let diskMember = captureMember(
            in: suffix,
            pattern: #"(?i)(?:disk|disc)[\s._-]*([0-9]+|[a-z])"#
        )
        let sideMember = captureMember(
            in: suffix,
            pattern: #"(?i)side[\s._-]*([0-9]+|[a-z])"#
        )
        guard diskMember != nil || sideMember != nil else { return nil }

        let normalizedKey = base
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
        guard !normalizedKey.isEmpty else { return nil }

        var labels: [String] = []
        if let diskMember { labels.append("Disk \(diskMember)") }
        if let sideMember { labels.append("Side \(sideMember)") }

        let diskOrder = memberOrder(diskMember)
        let sideOrder = memberOrder(sideMember)
        let sortOrder: Int
        if diskMember != nil {
            sortOrder = diskOrder * 100 + sideOrder
        } else {
            sortOrder = 10_000 + sideOrder
        }

        return LibraryMediaSetDescriptor(
            key: normalizedKey,
            displayName: base,
            memberLabel: labels.joined(separator: " · "),
            sortOrder: sortOrder
        )
    }

    private static func captureMember(
        in text: String,
        pattern: String
    ) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: text,
                range: NSRange(text.startIndex..<text.endIndex, in: text)
              ),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range]).uppercased()
    }

    private static func memberOrder(_ member: String?) -> Int {
        guard let member else { return 0 }
        if let numeric = Int(member) { return numeric }
        guard let scalar = member.unicodeScalars.first else { return Int.max / 4 }
        return Int(scalar.value) - 64
    }
}

enum LibraryArtworkKind: String, Codable, CaseIterable, Hashable {
    case cover
    case screenshot

    var displayName: String {
        switch self {
        case .cover: return "Cover"
        case .screenshot: return "Screenshot"
        }
    }
}

struct LibraryItem: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    let originalFilename: String
    let storedFilename: String
    let mediaType: LibraryMediaType
    let fileSize: Int64
    let sha256: String?
    let importedAt: Date
    var lastOpenedAt: Date?
    var isFavorite: Bool
    var notes: String? = nil
    var coverArtworkFilename: String? = nil
    var screenshotArtworkFilename: String? = nil

    var mediaSetDescriptor: LibraryMediaSetDescriptor? {
        guard mediaType.isDiskImage else { return nil }
        return LibraryMediaSetDescriptor.detect(in: originalFilename)
    }
}

struct LibraryImportInspection {
    let data: Data
    let originalFilename: String
    let mediaType: LibraryMediaType
    let fileSize: Int64
    let sha256: String
    let exactDuplicate: LibraryItem?
    let filenameConflict: LibraryItem?
}

enum LibraryImportResolution {
    case keepBoth
    case replaceExisting(LibraryItem)
    case useExisting(LibraryItem)
}

enum CommodoreDiskFileType: Int, Hashable {
    case deleted = 0
    case sequential = 1
    case program = 2
    case user = 3
    case relative = 4
    case partition = 5
    case directory = 6

    init(rawType: UInt8) {
        self = CommodoreDiskFileType(rawValue: Int(rawType & 0x07)) ?? .deleted
    }

    var displayName: String {
        switch self {
        case .deleted: return "DEL"
        case .sequential: return "SEQ"
        case .program: return "PRG"
        case .user: return "USR"
        case .relative: return "REL"
        case .partition: return "CBM"
        case .directory: return "DIR"
        }
    }
}

struct CommodoreDiskDirectoryEntry: Identifiable, Hashable {
    let id: String
    let name: String
    let rawName: [UInt8]
    let fileType: CommodoreDiskFileType
    let blockCount: Int
    let isClosed: Bool
    let isLocked: Bool
}

struct CommodoreDiskImageInspection: Hashable {
    let format: LibraryMediaType
    let diskName: String
    let rawDiskName: [UInt8]
    let diskID: String
    let rawDiskID: [UInt8]
    let dosType: String
    let rawDOSType: [UInt8]
    let geometryDescription: String
    let freeBlocks: Int?
    let isFormatted: Bool
    let isWritable: Bool
    let directoryEntries: [CommodoreDiskDirectoryEntry]
    let warning: String?
}

struct G64ImageInspection: Hashable {
    let version: Int
    let halfTrackSlots: Int
    let populatedHalfTracks: Int
    let maximumTrackSize: Int
    let isWritable: Bool
}

enum LibraryMediaInspection: Hashable {
    case commodoreDisk(CommodoreDiskImageInspection)
    case g64(G64ImageInspection)
}

enum BlankDiskImageFormat: String, CaseIterable, Identifiable, Hashable {
    case d64
    case d71
    case d81

    var id: String { rawValue }

    var mediaType: LibraryMediaType {
        switch self {
        case .d64: return .d64
        case .d71: return .d71
        case .d81: return .d81
        }
    }

    var displayName: String {
        rawValue.uppercased()
    }

    var geometryDescription: String {
        switch self {
        case .d64:
            return "35 tracks · 1541 / 1541-II / 1571"
        case .d71:
            return "70 tracks · double-sided 1571"
        case .d81:
            return "80 tracks · 3.5-inch 1581"
        }
    }

    var requiredDriveDescription: String {
        switch self {
        case .d64:
            return "a Commodore 1541, 1541-II or 1571"
        case .d71:
            return "a Commodore 1571"
        case .d81:
            return "a Commodore 1581"
        }
    }

    func isCompatible(with driveModel: C64DriveModel) -> Bool {
        switch self {
        case .d64:
            return driveModel == .cbm1541
                || driveModel == .cbm1541II
                || driveModel == .cbm1571
        case .d71:
            return driveModel == .cbm1571
        case .d81:
            return driveModel == .cbm1581
        }
    }

    static func recommended(for driveModel: C64DriveModel) -> BlankDiskImageFormat {
        switch driveModel {
        case .cbm1541, .cbm1541II:
            return .d64
        case .cbm1571:
            return .d71
        case .cbm1581:
            return .d81
        }
    }

    init?(mediaType: LibraryMediaType) {
        switch mediaType {
        case .d64: self = .d64
        case .d71: self = .d71
        case .d81: self = .d81
        case .g64, .prg, .crt, .tap, .t64:
            return nil
        }
    }
}

enum BlankDiskFormatChoice: String, CaseIterable, Identifiable, Hashable {
    case automatic
    case d64
    case d71
    case d81

    var id: String { rawValue }

    func resolvedFormat(for driveModel: C64DriveModel) -> BlankDiskImageFormat {
        switch self {
        case .automatic:
            return .recommended(for: driveModel)
        case .d64:
            return .d64
        case .d71:
            return .d71
        case .d81:
            return .d81
        }
    }

    func title(for driveModel: C64DriveModel, unit: Int = 8) -> String {
        switch self {
        case .automatic:
            return "Automatic · \(resolvedFormat(for: driveModel).displayName) for Drive \(unit)"
        case .d64:
            return "D64 · 1541 / 1541-II / 1571"
        case .d71:
            return "D71 · 1571"
        case .d81:
            return "D81 · 1581"
        }
    }
}

enum BlankDiskInitialization: String, CaseIterable, Identifiable, Hashable {
    case formatted
    case unformatted

    var id: String { rawValue }

    var title: String {
        switch self {
        case .formatted:
            return "Formatted and Ready"
        case .unformatted:
            return "Completely Blank"
        }
    }

    var description: String {
        switch self {
        case .formatted:
            return "Creates an empty Commodore DOS filesystem with a directory and free-space map. It can be used immediately."
        case .unformatted:
            return "Creates a raw blank image of the selected size. Format it from the Commodore machine before saving files."
        }
    }
}

enum LibraryStoreError: LocalizedError {
    case unsupportedFormat(String)
    case sourceIsNotAFile
    case itemMissing
    case storedFileMissing(String)
    case invalidDiskImage(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let fileExtension):
            let suffix = fileExtension.isEmpty ? "without a file extension" : ".\(fileExtension)"
            return "The selected file \(suffix) is not supported. Supported formats: \(LibraryMediaType.supportedExtensionsDescription)."
        case .sourceIsNotAFile:
            return "The selected item is not a regular file."
        case .itemMissing:
            return "The selected library item no longer exists."
        case .storedFileMissing(let filename):
            return "The stored media file is missing: \(filename)."
        case .invalidDiskImage(let reason):
            return "The disk image could not be inspected: \(reason)"
        }
    }
}

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var items: [LibraryItem] = []

    private let fileManager: FileManager
    private let rootURL: URL
    private let mediaDirectoryURL: URL
    private let artworkDirectoryURL: URL
    private let indexURL: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let applicationSupport = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let fallback = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        rootURL = (applicationSupport ?? fallback)
            .appendingPathComponent("POKE64", isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
        mediaDirectoryURL = rootURL.appendingPathComponent("Media", isDirectory: true)
        artworkDirectoryURL = rootURL.appendingPathComponent("Artwork", isDirectory: true)
        indexURL = rootURL.appendingPathComponent("library.json", isDirectory: false)

        do {
            try prepareStorage()
            try loadIndex()
        } catch {
            items = []
            print("Library initialization failed: \(error)")
        }
    }

    var allItems: [LibraryItem] {
        items.sorted(by: Self.defaultSort)
    }

    var favoriteItems: [LibraryItem] {
        items.filter(\.isFavorite).sorted(by: Self.defaultSort)
    }

    var recentItems: [LibraryItem] {
        items
            .filter { $0.lastOpenedAt != nil }
            .sorted {
                ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast)
            }
    }

    func inspectImport(
        from sourceURL: URL,
        originalFilename: String? = nil
    ) throws -> LibraryImportInspection {
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let values = try sourceURL.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true else {
            throw LibraryStoreError.sourceIsNotAFile
        }

        let requestedFilename = originalFilename?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedOriginalFilename: String
        if let requestedFilename, !requestedFilename.isEmpty {
            resolvedOriginalFilename = URL(fileURLWithPath: requestedFilename).lastPathComponent
        } else {
            resolvedOriginalFilename = sourceURL.lastPathComponent
        }

        let fileExtension = sourceURL.pathExtension.lowercased()
        guard let mediaType = LibraryMediaType(fileExtension: fileExtension) else {
            throw LibraryStoreError.unsupportedFormat(fileExtension)
        }

        let data = try Data(contentsOf: sourceURL, options: [.mappedIfSafe])
        let hash = Self.sha256(data)
        let exactDuplicate = items.first {
            $0.fileSize == Int64(data.count) && $0.sha256 == hash
        }
        let filenameConflict = items.first { item in
            item.originalFilename.compare(
                resolvedOriginalFilename,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) == .orderedSame && item.sha256 != hash
        }

        return LibraryImportInspection(
            data: data,
            originalFilename: resolvedOriginalFilename,
            mediaType: mediaType,
            fileSize: Int64(data.count),
            sha256: hash,
            exactDuplicate: exactDuplicate,
            filenameConflict: filenameConflict
        )
    }

    @discardableResult
    func importMedia(
        from sourceURL: URL,
        originalFilename: String? = nil
    ) throws -> LibraryItem {
        let inspection = try inspectImport(
            from: sourceURL,
            originalFilename: originalFilename
        )
        if let duplicate = inspection.exactDuplicate {
            return try importMedia(inspection, resolution: .useExisting(duplicate))
        }
        return try importMedia(inspection, resolution: .keepBoth)
    }

    @discardableResult
    func importMedia(
        _ inspection: LibraryImportInspection,
        resolution: LibraryImportResolution
    ) throws -> LibraryItem {
        switch resolution {
        case .useExisting(let item):
            guard let existing = self.item(withID: item.id) else {
                throw LibraryStoreError.itemMissing
            }
            return existing

        case .replaceExisting(let item):
            return try replace(item, with: inspection)

        case .keepBoth:
            return try storeNewImport(inspection)
        }
    }

    func mediaSetMembers(for item: LibraryItem) -> [LibraryItem] {
        guard let descriptor = item.mediaSetDescriptor else { return [] }

        return items
            .filter { candidate in
                candidate.mediaSetDescriptor?.key == descriptor.key
            }
            .sorted { lhs, rhs in
                let lhsDescriptor = lhs.mediaSetDescriptor
                let rhsDescriptor = rhs.mediaSetDescriptor
                let lhsOrder = lhsDescriptor?.sortOrder ?? Int.max
                let rhsOrder = rhsDescriptor?.sortOrder ?? Int.max
                if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
                return Self.defaultSort(lhs, rhs)
            }
    }

    private func storeNewImport(
        _ inspection: LibraryImportInspection
    ) throws -> LibraryItem {
        let data = inspection.data
        try prepareStorage()

        let id = UUID()
        let storedFilename = id.uuidString.lowercased() + "." + inspection.mediaType.rawValue
        let destinationURL = mediaDirectoryURL.appendingPathComponent(
            storedFilename,
            isDirectory: false
        )
        try data.write(to: destinationURL, options: .atomic)

        let item = LibraryItem(
            id: id,
            title: Self.defaultTitle(forFilename: inspection.originalFilename),
            originalFilename: inspection.originalFilename,
            storedFilename: storedFilename,
            mediaType: inspection.mediaType,
            fileSize: Int64(data.count),
            sha256: Self.sha256(data),
            importedAt: Date(),
            lastOpenedAt: nil,
            isFavorite: false
        )

        items.append(item)
        items.sort(by: Self.defaultSort)

        do {
            try persist()
        } catch {
            items.removeAll { $0.id == item.id }
            try? fileManager.removeItem(at: destinationURL)
            throw error
        }

        return item
    }

    private func replace(
        _ existingItem: LibraryItem,
        with inspection: LibraryImportInspection
    ) throws -> LibraryItem {
        guard let index = items.firstIndex(where: { $0.id == existingItem.id }) else {
            throw LibraryStoreError.itemMissing
        }

        let destinationURL = mediaDirectoryURL.appendingPathComponent(
            existingItem.storedFilename,
            isDirectory: false
        )
        guard fileManager.fileExists(atPath: destinationURL.path) else {
            throw LibraryStoreError.storedFileMissing(existingItem.originalFilename)
        }

        let replacementData = inspection.data
        let previousData = try Data(contentsOf: destinationURL)
        let previousItem = items[index]
        let replacementItem = LibraryItem(
            id: previousItem.id,
            title: previousItem.title,
            originalFilename: inspection.originalFilename,
            storedFilename: previousItem.storedFilename,
            mediaType: inspection.mediaType,
            fileSize: Int64(replacementData.count),
            sha256: Self.sha256(replacementData),
            importedAt: Date(),
            lastOpenedAt: previousItem.lastOpenedAt,
            isFavorite: previousItem.isFavorite,
            notes: previousItem.notes,
            coverArtworkFilename: previousItem.coverArtworkFilename,
            screenshotArtworkFilename: previousItem.screenshotArtworkFilename
        )

        try replacementData.write(to: destinationURL, options: .atomic)
        items[index] = replacementItem
        items.sort(by: Self.defaultSort)

        do {
            try persist()
        } catch {
            try? previousData.write(to: destinationURL, options: .atomic)
            if let restoredIndex = items.firstIndex(where: { $0.id == previousItem.id }) {
                items[restoredIndex] = previousItem
                items.sort(by: Self.defaultSort)
            }
            throw error
        }

        return replacementItem
    }

    @discardableResult
    func createBlankDisk(
        title proposedTitle: String,
        format: BlankDiskImageFormat,
        initialization: BlankDiskInitialization
    ) throws -> LibraryItem {
        let trimmedTitle = proposedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmedTitle.isEmpty ? "New Disk" : trimmedTitle

        try prepareStorage()

        let id = UUID()
        let storedFilename = id.uuidString.lowercased() + "." + format.rawValue
        let originalFilename = Self.generatedDiskFilename(
            for: title,
            fileExtension: format.rawValue
        )
        let destinationURL = mediaDirectoryURL.appendingPathComponent(
            storedFilename,
            isDirectory: false
        )
        let data = CommodoreDiskImageBuilder.makeDisk(
            format: format,
            name: title,
            initialization: initialization
        )
        try data.write(to: destinationURL, options: .atomic)

        let item = LibraryItem(
            id: id,
            title: title,
            originalFilename: originalFilename,
            storedFilename: storedFilename,
            mediaType: format.mediaType,
            fileSize: Int64(data.count),
            sha256: Self.sha256(data),
            importedAt: Date(),
            lastOpenedAt: nil,
            isFavorite: false
        )

        items.append(item)
        items.sort(by: Self.defaultSort)

        do {
            try persist()
        } catch {
            items.removeAll { $0.id == item.id }
            try? fileManager.removeItem(at: destinationURL)
            throw error
        }

        return item
    }

    func item(withID id: UUID) -> LibraryItem? {
        items.first { $0.id == id }
    }

    func mediaURL(for item: LibraryItem) throws -> URL {
        guard items.contains(where: { $0.id == item.id }) else {
            throw LibraryStoreError.itemMissing
        }

        let url = mediaDirectoryURL.appendingPathComponent(item.storedFilename, isDirectory: false)
        guard fileManager.fileExists(atPath: url.path) else {
            throw LibraryStoreError.storedFileMissing(item.originalFilename)
        }
        return url
    }

    func inspectMedia(_ item: LibraryItem) throws -> LibraryMediaInspection? {
        let url = try mediaURL(for: item)
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        let isWritable = fileManager.isWritableFile(atPath: url.path)

        switch item.mediaType {
        case .d64, .d71, .d81:
            guard let format = BlankDiskImageFormat(mediaType: item.mediaType) else {
                return nil
            }
            return .commodoreDisk(
                try CommodoreDiskImageInspector.inspect(
                    data: data,
                    format: format,
                    mediaType: item.mediaType,
                    isWritable: isWritable
                )
            )

        case .g64:
            return .g64(
                try CommodoreDiskImageInspector.inspectG64(
                    data: data,
                    isWritable: isWritable
                )
            )

        case .prg, .crt, .tap, .t64:
            return nil
        }
    }

    func markOpened(_ item: LibraryItem) throws {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else {
            throw LibraryStoreError.itemMissing
        }
        items[index].lastOpenedAt = Date()
        try persist()
    }

    func toggleFavorite(_ item: LibraryItem) throws {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else {
            throw LibraryStoreError.itemMissing
        }
        items[index].isFavorite.toggle()
        try persist()
    }

    func rename(_ item: LibraryItem, to proposedTitle: String) throws {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else {
            throw LibraryStoreError.itemMissing
        }

        let trimmed = proposedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        items[index].title = trimmed.isEmpty
            ? URL(fileURLWithPath: item.originalFilename).deletingPathExtension().lastPathComponent
            : trimmed
        try persist()
    }

    func updateNotes(_ item: LibraryItem, notes: String) throws {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else {
            throw LibraryStoreError.itemMissing
        }

        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        items[index].notes = trimmed.isEmpty ? nil : trimmed
        try persist()
    }

    func artworkData(for item: LibraryItem, kind: LibraryArtworkKind) -> Data? {
        guard let filename = artworkFilename(for: item, kind: kind) else { return nil }
        let url = artworkDirectoryURL.appendingPathComponent(filename, isDirectory: false)
        return try? Data(contentsOf: url, options: [.mappedIfSafe])
    }

    func setArtwork(_ data: Data, for item: LibraryItem, kind: LibraryArtworkKind) throws {
        guard !data.isEmpty else { return }
        guard let index = items.firstIndex(where: { $0.id == item.id }) else {
            throw LibraryStoreError.itemMissing
        }

        try prepareStorage()
        let filename = "\(item.id.uuidString.lowercased())-\(kind.rawValue).image"
        let url = artworkDirectoryURL.appendingPathComponent(filename, isDirectory: false)
        try data.write(to: url, options: .atomic)

        let oldFilename = artworkFilename(for: items[index], kind: kind)
        switch kind {
        case .cover:
            items[index].coverArtworkFilename = filename
        case .screenshot:
            items[index].screenshotArtworkFilename = filename
        }

        do {
            try persist()
            if let oldFilename, oldFilename != filename {
                try? fileManager.removeItem(
                    at: artworkDirectoryURL.appendingPathComponent(oldFilename, isDirectory: false)
                )
            }
        } catch {
            try? fileManager.removeItem(at: url)
            throw error
        }
    }

    func removeArtwork(for item: LibraryItem, kind: LibraryArtworkKind) throws {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else {
            throw LibraryStoreError.itemMissing
        }

        let filename = artworkFilename(for: items[index], kind: kind)
        switch kind {
        case .cover:
            items[index].coverArtworkFilename = nil
        case .screenshot:
            items[index].screenshotArtworkFilename = nil
        }
        try persist()

        if let filename {
            try? fileManager.removeItem(
                at: artworkDirectoryURL.appendingPathComponent(filename, isDirectory: false)
            )
        }
    }

    private func artworkFilename(
        for item: LibraryItem,
        kind: LibraryArtworkKind
    ) -> String? {
        switch kind {
        case .cover: return item.coverArtworkFilename
        case .screenshot: return item.screenshotArtworkFilename
        }
    }

    func delete(_ item: LibraryItem) throws {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else {
            throw LibraryStoreError.itemMissing
        }

        let url = mediaDirectoryURL.appendingPathComponent(item.storedFilename, isDirectory: false)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }

        for filename in [item.coverArtworkFilename, item.screenshotArtworkFilename].compactMap({ $0 }) {
            try? fileManager.removeItem(
                at: artworkDirectoryURL.appendingPathComponent(filename, isDirectory: false)
            )
        }

        items.remove(at: index)
        try persist()
    }

    private func prepareStorage() throws {
        try fileManager.createDirectory(
            at: mediaDirectoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        try fileManager.createDirectory(
            at: artworkDirectoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    private func loadIndex() throws {
        guard fileManager.fileExists(atPath: indexURL.path) else {
            items = []
            return
        }

        let data = try Data(contentsOf: indexURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([LibraryItem].self, from: data)
        var existing = decoded.filter { item in
            let url = mediaDirectoryURL.appendingPathComponent(item.storedFilename, isDirectory: false)
            return fileManager.fileExists(atPath: url.path)
        }
        var upgradedMetadata = false

        for index in existing.indices where existing[index].sha256 == nil {
            let item = existing[index]
            let url = mediaDirectoryURL.appendingPathComponent(item.storedFilename, isDirectory: false)
            guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else { continue }

            existing[index] = LibraryItem(
                id: item.id,
                title: item.title,
                originalFilename: item.originalFilename,
                storedFilename: item.storedFilename,
                mediaType: item.mediaType,
                fileSize: Int64(data.count),
                sha256: Self.sha256(data),
                importedAt: item.importedAt,
                lastOpenedAt: item.lastOpenedAt,
                isFavorite: item.isFavorite,
                notes: item.notes,
                coverArtworkFilename: item.coverArtworkFilename,
                screenshotArtworkFilename: item.screenshotArtworkFilename
            )
            upgradedMetadata = true
        }

        items = existing.sorted(by: Self.defaultSort)

        if existing.count != decoded.count || upgradedMetadata {
            try persist()
        }
    }

    private func persist() throws {
        try prepareStorage()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(items)
        try data.write(to: indexURL, options: .atomic)
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func defaultTitle(forFilename filename: String) -> String {
        let url = URL(fileURLWithPath: filename)
        let title = url.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? url.lastPathComponent : title
    }

    private static func generatedDiskFilename(
        for title: String,
        fileExtension: String
    ) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let sanitizedScalars = title.unicodeScalars.map { scalar -> Character in
            forbidden.contains(scalar) ? "-" : Character(String(scalar))
        }
        let sanitized = String(sanitizedScalars)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (sanitized.isEmpty ? "New Disk" : sanitized) + "." + fileExtension
    }

    private static func defaultSort(_ lhs: LibraryItem, _ rhs: LibraryItem) -> Bool {
        if lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedSame {
            return lhs.importedAt > rhs.importedAt
        }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }
}


private enum CommodoreDiskImageInspector {
    private static let bytesPerSector = 256
    private static let petsciiPadding: UInt8 = 0xa0

    static func inspect(
        data: Data,
        format: BlankDiskImageFormat,
        mediaType: LibraryMediaType,
        isWritable: Bool
    ) throws -> CommodoreDiskImageInspection {
        let bytes = [UInt8](data)
        let requiredSize = imageSize(for: format)
        guard bytes.count >= requiredSize else {
            throw LibraryStoreError.invalidDiskImage(
                "expected at least \(requiredSize) bytes for \(mediaType.displayName), found \(bytes.count)"
            )
        }

        let headerTrack = directoryTrack(for: format)
        let headerOffset = try sectorOffset(
            track: headerTrack,
            sector: 0,
            format: format,
            byteCount: bytes.count
        )
        let nameOffset = format == .d81 ? 0x04 : 0x90
        let idOffset = format == .d81 ? 0x16 : 0xa2
        let dosTypeOffset = format == .d81 ? 0x19 : 0xa5
        let expectedDOSVersion: UInt8 = format == .d81 ? 0x44 : 0x41
        let isFormatted = bytes[headerOffset + 2] == expectedDOSVersion

        let rawDiskName = trimmedPETSCIIBytes(
            bytes[(headerOffset + nameOffset)..<(headerOffset + nameOffset + 16)]
        )
        let rawDiskID = trimmedPETSCIIBytes(
            bytes[(headerOffset + idOffset)..<(headerOffset + idOffset + 2)]
        )
        let rawDOSType = trimmedPETSCIIBytes(
            bytes[(headerOffset + dosTypeOffset)..<(headerOffset + dosTypeOffset + 2)]
        )
        let diskName = decodePETSCII(rawDiskName[...])
        let diskID = decodePETSCII(rawDiskID[...])
        let dosType = decodePETSCII(rawDOSType[...])

        let directoryResult = try readDirectory(
            bytes: bytes,
            format: format
        )
        let freeBlocks = isFormatted ? readFreeBlocks(bytes: bytes, format: format) : nil

        let warning: String?
        if !isFormatted {
            warning = "No valid Commodore DOS header was found. The image may be unformatted or use a non-standard filesystem."
        } else {
            warning = directoryResult.warning
        }

        return CommodoreDiskImageInspection(
            format: mediaType,
            diskName: diskName.isEmpty ? "Untitled" : diskName,
            rawDiskName: rawDiskName,
            diskID: diskID.isEmpty ? "—" : diskID,
            rawDiskID: rawDiskID,
            dosType: dosType.isEmpty ? "—" : dosType,
            rawDOSType: rawDOSType,
            geometryDescription: geometryDescription(for: format),
            freeBlocks: freeBlocks,
            isFormatted: isFormatted,
            isWritable: isWritable,
            directoryEntries: directoryResult.entries,
            warning: warning
        )
    }

    static func inspectG64(
        data: Data,
        isWritable: Bool
    ) throws -> G64ImageInspection {
        let bytes = [UInt8](data)
        guard bytes.count >= 12 else {
            throw LibraryStoreError.invalidDiskImage("the G64 header is incomplete")
        }

        let signature = String(bytes: bytes[0..<8], encoding: .ascii)
        guard signature == "GCR-1541" else {
            throw LibraryStoreError.invalidDiskImage("the G64 signature is not GCR-1541")
        }

        let halfTrackSlots = Int(bytes[9])
        let tableEnd = 12 + (halfTrackSlots * 4)
        guard halfTrackSlots > 0, tableEnd <= bytes.count else {
            throw LibraryStoreError.invalidDiskImage("the G64 track-offset table is invalid")
        }

        var populatedHalfTracks = 0
        for index in 0..<halfTrackSlots {
            let offset = littleEndianUInt32(bytes, at: 12 + (index * 4))
            if offset != 0 { populatedHalfTracks += 1 }
        }

        return G64ImageInspection(
            version: Int(bytes[8]),
            halfTrackSlots: halfTrackSlots,
            populatedHalfTracks: populatedHalfTracks,
            maximumTrackSize: Int(UInt16(bytes[10]) | (UInt16(bytes[11]) << 8)),
            isWritable: isWritable
        )
    }

    private static func readDirectory(
        bytes: [UInt8],
        format: BlankDiskImageFormat
    ) throws -> (entries: [CommodoreDiskDirectoryEntry], warning: String?) {
        var track = directoryTrack(for: format)
        var sector = format == .d81 ? 3 : 1
        var entries: [CommodoreDiskDirectoryEntry] = []
        var visited: Set<String> = []
        var warning: String?

        while track != 0 {
            let key = "\(track):\(sector)"
            guard visited.insert(key).inserted else {
                warning = "The directory chain contains a loop and was stopped early."
                break
            }
            guard visited.count <= 256 else {
                warning = "The directory chain is unexpectedly long and was stopped early."
                break
            }

            let offset: Int
            do {
                offset = try sectorOffset(
                    track: track,
                    sector: sector,
                    format: format,
                    byteCount: bytes.count
                )
            } catch {
                warning = "The directory points to an invalid track or sector."
                break
            }

            for slot in 0..<8 {
                let base = offset + (slot * 32)
                let rawType = bytes[base + 2]
                guard rawType != 0 else { continue }

                let rawName = trimmedPETSCIIBytes(bytes[(base + 5)..<(base + 21)])
                let name = decodePETSCII(rawName[...])
                let blockCount = Int(bytes[base + 30]) | (Int(bytes[base + 31]) << 8)
                entries.append(
                    CommodoreDiskDirectoryEntry(
                        id: "\(track):\(sector):\(slot)",
                        name: name.isEmpty ? "Untitled file" : name,
                        rawName: rawName,
                        fileType: CommodoreDiskFileType(rawType: rawType),
                        blockCount: blockCount,
                        isClosed: (rawType & 0x80) != 0,
                        isLocked: (rawType & 0x40) != 0
                    )
                )
            }

            track = Int(bytes[offset])
            sector = Int(bytes[offset + 1])
        }

        return (entries, warning)
    }

    private static func readFreeBlocks(
        bytes: [UInt8],
        format: BlankDiskImageFormat
    ) -> Int {
        var total = 0

        switch format {
        case .d64:
            guard let bam = try? sectorOffset(
                track: 18,
                sector: 0,
                format: format,
                byteCount: bytes.count
            ) else { return 0 }
            for track in 1...35 where track != 18 {
                total += Int(bytes[bam + (track * 4)])
            }

        case .d71:
            guard let firstBAM = try? sectorOffset(
                track: 18,
                sector: 0,
                format: format,
                byteCount: bytes.count
            ) else { return 0 }

            for track in 1...35 where track != 18 {
                total += Int(bytes[firstBAM + (track * 4)])
            }
            for track in 36...70 where track != 53 {
                total += Int(bytes[firstBAM + 0xdd + (track - 36)])
            }

        case .d81:
            guard let firstBAM = try? sectorOffset(
                track: 40,
                sector: 1,
                format: format,
                byteCount: bytes.count
            ), let secondBAM = try? sectorOffset(
                track: 40,
                sector: 2,
                format: format,
                byteCount: bytes.count
            ) else { return 0 }

            for track in 1...80 where track != 40 {
                let sideTrack = track <= 40 ? track : track - 40
                let bam = track <= 40 ? firstBAM : secondBAM
                total += Int(bytes[bam + (sideTrack * 6) + 10])
            }
        }

        return total
    }

    private static func trimmedPETSCIIBytes(_ bytes: ArraySlice<UInt8>) -> [UInt8] {
        var result = Array(bytes)
        while let last = result.last, last == petsciiPadding || last == 0 {
            result.removeLast()
        }
        return result
    }

    private static func decodePETSCII(_ bytes: ArraySlice<UInt8>) -> String {
        var scalars: [UnicodeScalar] = []
        scalars.reserveCapacity(bytes.count)

        for byte in bytes {
            if byte == petsciiPadding || byte == 0 { break }

            let normalized: UInt8
            switch byte {
            case 0x20...0x7e:
                normalized = byte
            case 0xc1...0xda:
                normalized = byte - 0x80
            default:
                normalized = 0x3f
            }

            if let scalar = UnicodeScalar(Int(normalized)) {
                scalars.append(scalar)
            }
        }

        return String(String.UnicodeScalarView(scalars))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func littleEndianUInt32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }

    private static func geometryDescription(for format: BlankDiskImageFormat) -> String {
        switch format {
        case .d64: return "35 tracks · 683 sectors"
        case .d71: return "70 tracks · 1,366 sectors"
        case .d81: return "80 tracks · 3,200 sectors"
        }
    }

    private static func imageSize(for format: BlankDiskImageFormat) -> Int {
        switch format {
        case .d64: return 174_848
        case .d71: return 349_696
        case .d81: return 819_200
        }
    }

    private static func directoryTrack(for format: BlankDiskImageFormat) -> Int {
        format == .d81 ? 40 : 18
    }

    private static func trackCount(for format: BlankDiskImageFormat) -> Int {
        switch format {
        case .d64: return 35
        case .d71: return 70
        case .d81: return 80
        }
    }

    private static func sectors(
        on track: Int,
        format: BlankDiskImageFormat
    ) -> Int {
        if format == .d81 { return 40 }

        let sideTrack = ((track - 1) % 35) + 1
        switch sideTrack {
        case 1...17: return 21
        case 18...24: return 19
        case 25...30: return 18
        case 31...35: return 17
        default: return 0
        }
    }

    private static func sectorOffset(
        track: Int,
        sector: Int,
        format: BlankDiskImageFormat,
        byteCount: Int
    ) throws -> Int {
        guard (1...trackCount(for: format)).contains(track),
              (0..<sectors(on: track, format: format)).contains(sector) else {
            throw LibraryStoreError.invalidDiskImage("invalid track/sector \(track)/\(sector)")
        }

        var precedingSectors = 0
        if track > 1 {
            for priorTrack in 1..<track {
                precedingSectors += sectors(on: priorTrack, format: format)
            }
        }
        let offset = (precedingSectors + sector) * bytesPerSector
        guard offset + bytesPerSector <= byteCount else {
            throw LibraryStoreError.invalidDiskImage("track/sector \(track)/\(sector) lies outside the image")
        }
        return offset
    }
}


private enum CommodoreDiskImageBuilder {
    private static let bytesPerSector = 256
    private static let petsciiPadding: UInt8 = 0xa0
    private static let defaultDiskID: [UInt8] = [0x30, 0x30, 0xa0, 0x32, 0x41]

    static func makeDisk(
        format: BlankDiskImageFormat,
        name: String,
        initialization: BlankDiskInitialization
    ) -> Data {
        var bytes = [UInt8](repeating: 0, count: imageSize(for: format))
        guard initialization == .formatted else {
            return Data(bytes)
        }

        initializeSystemSectors(format: format, bytes: &bytes)

        for track in 1...trackCount(for: format) {
            for sector in 0..<sectors(on: track, format: format) {
                markSector(
                    format: format,
                    track: track,
                    sector: sector,
                    free: true,
                    bytes: &bytes
                )
            }
        }

        let directoryTrack = directoryTrack(for: format)
        markSector(
            format: format,
            track: directoryTrack,
            sector: 0,
            free: false,
            bytes: &bytes
        )

        switch format {
        case .d64:
            break
        case .d71:
            markSector(
                format: format,
                track: directoryTrack + 35,
                sector: 0,
                free: false,
                bytes: &bytes
            )
        case .d81:
            markSector(
                format: format,
                track: directoryTrack,
                sector: 1,
                free: false,
                bytes: &bytes
            )
            markSector(
                format: format,
                track: directoryTrack,
                sector: 2,
                free: false,
                bytes: &bytes
            )
        }

        let firstDirectorySector = format == .d81 ? 3 : 1
        markSector(
            format: format,
            track: directoryTrack,
            sector: firstDirectorySector,
            free: false,
            bytes: &bytes
        )

        let directoryOffset = offset(
            track: directoryTrack,
            sector: firstDirectorySector,
            format: format
        )
        bytes[directoryOffset] = 0x00
        bytes[directoryOffset + 1] = 0xff

        writeHeader(
            format: format,
            name: name,
            bytes: &bytes
        )

        return Data(bytes)
    }

    private static func initializeSystemSectors(
        format: BlankDiskImageFormat,
        bytes: inout [UInt8]
    ) {
        let directoryTrack = directoryTrack(for: format)
        let headerOffset = offset(
            track: directoryTrack,
            sector: 0,
            format: format
        )

        switch format {
        case .d64, .d71:
            bytes[headerOffset] = UInt8(directoryTrack)
            bytes[headerOffset + 1] = 1
            bytes[headerOffset + 2] = 0x41
            bytes[headerOffset + 3] = format == .d71 ? 0x80 : 0x00
            bytes[headerOffset + 0xa0] = petsciiPadding
            bytes[headerOffset + 0xa1] = petsciiPadding
            for index in 0xa7...0xaa {
                bytes[headerOffset + index] = petsciiPadding
            }

        case .d81:
            bytes[headerOffset] = UInt8(directoryTrack)
            bytes[headerOffset + 1] = 3
            bytes[headerOffset + 2] = 0x44
            bytes[headerOffset + 0x14] = petsciiPadding
            bytes[headerOffset + 0x15] = petsciiPadding
            bytes[headerOffset + 0x1b] = petsciiPadding
            bytes[headerOffset + 0x1c] = petsciiPadding

            let firstBAMOffset = offset(
                track: directoryTrack,
                sector: 1,
                format: format
            )
            bytes[firstBAMOffset] = UInt8(directoryTrack)
            bytes[firstBAMOffset + 1] = 2
            bytes[firstBAMOffset + 2] = 0x44
            bytes[firstBAMOffset + 3] = 0xbb
            bytes[firstBAMOffset + 6] = 0xc0

            let secondBAMOffset = offset(
                track: directoryTrack,
                sector: 2,
                format: format
            )
            bytes[secondBAMOffset] = 0
            bytes[secondBAMOffset + 1] = 0xff
            bytes[secondBAMOffset + 2] = 0x44
            bytes[secondBAMOffset + 3] = 0xbb
            bytes[secondBAMOffset + 6] = 0xc0
        }
    }

    private static func writeHeader(
        format: BlankDiskImageFormat,
        name: String,
        bytes: inout [UInt8]
    ) {
        let directoryTrack = directoryTrack(for: format)
        let headerOffset = offset(
            track: directoryTrack,
            sector: 0,
            format: format
        )
        let nameOffset = format == .d81 ? 0x04 : 0x90
        let idOffset = format == .d81 ? 0x16 : 0xa2

        writePETSCII(
            name,
            into: &bytes,
            at: headerOffset + nameOffset,
            length: 16
        )
        for (index, byte) in defaultDiskID.enumerated() {
            bytes[headerOffset + idOffset + index] = byte
        }

        guard format == .d81 else { return }
        for sector in [1, 2] {
            let bamOffset = offset(
                track: directoryTrack,
                sector: sector,
                format: format
            )
            bytes[bamOffset + 4] = defaultDiskID[0]
            bytes[bamOffset + 5] = defaultDiskID[1]
        }
    }

    private static func markSector(
        format: BlankDiskImageFormat,
        track: Int,
        sector: Int,
        free: Bool,
        bytes: inout [UInt8]
    ) {
        let (countOffset, bitmapOffset) = bamEntryOffsets(
            format: format,
            track: track
        )
        let bitmapByte = bitmapOffset + (sector / 8)
        let mask = UInt8(1 << (sector % 8))
        let currentlyFree = (bytes[bitmapByte] & mask) != 0
        guard currentlyFree != free else { return }

        if free {
            bytes[countOffset] &+= 1
            bytes[bitmapByte] |= mask
        } else {
            bytes[countOffset] &-= 1
            bytes[bitmapByte] &= ~mask
        }
    }

    private static func bamEntryOffsets(
        format: BlankDiskImageFormat,
        track: Int
    ) -> (count: Int, bitmap: Int) {
        switch format {
        case .d64:
            let bamOffset = offset(track: 18, sector: 0, format: format)
            let countOffset = bamOffset + (track * 4)
            return (countOffset, countOffset + 1)

        case .d71:
            if track <= 35 {
                let bamOffset = offset(track: 18, sector: 0, format: format)
                let countOffset = bamOffset + (track * 4)
                return (countOffset, countOffset + 1)
            }

            let firstSideBAM = offset(track: 18, sector: 0, format: format)
            let secondSideBAM = offset(track: 53, sector: 0, format: format)
            let sideTrackIndex = track - 36
            return (
                firstSideBAM + 0xdd + sideTrackIndex,
                secondSideBAM + (sideTrackIndex * 3)
            )

        case .d81:
            let sideTrack = track <= 40 ? track : track - 40
            let bamSector = track <= 40 ? 1 : 2
            let bamOffset = offset(track: 40, sector: bamSector, format: format)
            let bitmapOffset = bamOffset + (sideTrack * 6) + 11
            return (bitmapOffset - 1, bitmapOffset)
        }
    }

    private static func trackCount(for format: BlankDiskImageFormat) -> Int {
        switch format {
        case .d64: return 35
        case .d71: return 70
        case .d81: return 80
        }
    }

    private static func imageSize(for format: BlankDiskImageFormat) -> Int {
        switch format {
        case .d64: return 174_848
        case .d71: return 349_696
        case .d81: return 819_200
        }
    }

    private static func directoryTrack(for format: BlankDiskImageFormat) -> Int {
        format == .d81 ? 40 : 18
    }

    private static func sectors(
        on track: Int,
        format: BlankDiskImageFormat
    ) -> Int {
        if format == .d81 {
            return 40
        }

        let sideTrack = ((track - 1) % 35) + 1
        switch sideTrack {
        case 1...17:
            return 21
        case 18...24:
            return 19
        case 25...30:
            return 18
        case 31...35:
            return 17
        default:
            preconditionFailure("Invalid Commodore track: \(track)")
        }
    }

    private static func offset(
        track: Int,
        sector: Int,
        format: BlankDiskImageFormat
    ) -> Int {
        precondition((1...trackCount(for: format)).contains(track))
        precondition((0..<sectors(on: track, format: format)).contains(sector))

        let precedingSectors = (1..<track).reduce(0) { partialResult, priorTrack in
            partialResult + sectors(on: priorTrack, format: format)
        }
        return (precedingSectors + sector) * bytesPerSector
    }

    private static func writePETSCII(
        _ text: String,
        into bytes: inout [UInt8],
        at offset: Int,
        length: Int
    ) {
        var encoded: [UInt8] = []
        encoded.reserveCapacity(length)

        for scalar in text.uppercased().unicodeScalars {
            guard encoded.count < length else { break }
            if (0x20...0x5f).contains(scalar.value) {
                encoded.append(UInt8(scalar.value))
            } else {
                encoded.append(0x20)
            }
        }

        for index in 0..<length {
            bytes[offset + index] = index < encoded.count
                ? encoded[index]
                : petsciiPadding
        }
    }
}
