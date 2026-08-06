import Combine
import Foundation

/// Media formats currently exposed by the first persistent-library implementation.
enum LibraryMediaType: String, Codable, CaseIterable, Hashable {
    case d64
    case d71
    case d81
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
        case .d64, .d71, .d81:
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
}

struct LibraryItem: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    let originalFilename: String
    let storedFilename: String
    let mediaType: LibraryMediaType
    let fileSize: Int64
    let importedAt: Date
    var lastOpenedAt: Date?
    var isFavorite: Bool
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
        case .prg, .crt, .tap, .t64:
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
        }
    }
}

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var items: [LibraryItem] = []

    private let fileManager: FileManager
    private let rootURL: URL
    private let mediaDirectoryURL: URL
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

    @discardableResult
    func importMedia(
        from sourceURL: URL,
        originalFilename: String? = nil
    ) throws -> LibraryItem {
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let values = try sourceURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
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

        try prepareStorage()

        let id = UUID()
        let storedFilename = id.uuidString.lowercased() + "." + mediaType.rawValue
        let destinationURL = mediaDirectoryURL.appendingPathComponent(storedFilename, isDirectory: false)
        try fileManager.copyItem(at: sourceURL, to: destinationURL)

        let title = Self.defaultTitle(forFilename: resolvedOriginalFilename)
        let item = LibraryItem(
            id: id,
            title: title,
            originalFilename: resolvedOriginalFilename,
            storedFilename: storedFilename,
            mediaType: mediaType,
            fileSize: Int64(values.fileSize ?? 0),
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

    func delete(_ item: LibraryItem) throws {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else {
            throw LibraryStoreError.itemMissing
        }

        let url = mediaDirectoryURL.appendingPathComponent(item.storedFilename, isDirectory: false)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
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
        let existing = decoded.filter { item in
            let url = mediaDirectoryURL.appendingPathComponent(item.storedFilename, isDirectory: false)
            return fileManager.fileExists(atPath: url.path)
        }
        items = existing.sorted(by: Self.defaultSort)

        if existing.count != decoded.count {
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

            let secondSideBAM = offset(track: 53, sector: 0, format: format)
            let sideTrackIndex = track - 36
            return (
                secondSideBAM + 0xdd + sideTrackIndex,
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
