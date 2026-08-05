import Combine
import Foundation

/// Media formats currently exposed by the first persistent-library implementation.
enum LibraryMediaType: String, Codable, CaseIterable, Hashable {
    case d64
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
        case .d64:
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

    private static func defaultSort(_ lhs: LibraryItem, _ rhs: LibraryItem) -> Bool {
        if lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedSame {
            return lhs.importedAt > rhs.importedAt
        }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }
}
