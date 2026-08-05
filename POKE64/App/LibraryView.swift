import SwiftUI
import UniformTypeIdentifiers

private enum LibraryFilter: String, CaseIterable, Identifiable {
    case all
    case favorites
    case recent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "All Media"
        case .favorites:
            return "Favorites"
        case .recent:
            return "Recent"
        }
    }

    var systemImage: String {
        switch self {
        case .all:
            return "books.vertical.fill"
        case .favorites:
            return "star.fill"
        case .recent:
            return "clock.fill"
        }
    }
}

struct LibraryView: View {
    @ObservedObject var library: LibraryStore
    let loadedItemID: UUID?
    let temporaryMedia: TemporaryMediaInfo?
    let temporaryMediaAddedItemID: UUID?
    let onImport: (URL) throws -> LibraryItem
    let onAddTemporaryMedia: () throws -> LibraryItem
    let onRun: (LibraryItem) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var filter: LibraryFilter = .all
    @State private var selectedItemID: UUID?
    @State private var searchText = ""
    @State private var showImporter = false
    @State private var errorMessage: String?
    @State private var deletionCandidate: LibraryItem?
    @State private var newlyAddedTemporaryMediaItemID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            libraryHeader

            Divider()

            NavigationSplitView {
                sidebar
            } content: {
                itemList
            } detail: {
                detail
            }
            .navigationSplitViewStyle(.balanced)
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.data],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                importFiles(urls)
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .alert(
            "Delete media?",
            isPresented: Binding(
                get: { deletionCandidate != nil },
                set: { if !$0 { deletionCandidate = nil } }
            ),
            presenting: deletionCandidate
        ) { item in
            Button("Delete", role: .destructive) {
                delete(item)
            }
            Button("Cancel", role: .cancel) {
                deletionCandidate = nil
            }
        } message: { item in
            Text("“\(item.title)” and its imported file will be removed from POKE64.")
        }
        .alert(
            "Library error",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK") {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    private var libraryHeader: some View {
        HStack(spacing: 14) {
            Text("Library")
                .font(.headline)

            Spacer()

            Button {
                showImporter = true
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
            }

            Button("Done") {
                dismiss()
            }
            .fontWeight(.semibold)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var sidebar: some View {
        List {
            if let temporaryMedia {
                Section("Current Media") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            LibraryMediaIcon(mediaType: temporaryMedia.mediaType, size: 42)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(temporaryMedia.title)
                                    .font(.body.weight(.semibold))
                                    .lineLimit(1)

                                Text(temporaryMedia.originalFilename)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)

                                Text("Temporary \(temporaryMedia.mediaType.displayName) media")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        Button {
                            addTemporaryMedia()
                        } label: {
                            Label(
                                temporaryMediaIsAdded ? "Added to Library" : "Add to Library",
                                systemImage: temporaryMediaIsAdded
                                    ? "checkmark.circle.fill"
                                    : "plus.circle.fill"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(temporaryMediaIsAdded)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Library") {
                ForEach(LibraryFilter.allCases) { candidate in
                    Button {
                        filter = candidate
                        normalizeSelection()
                    } label: {
                        HStack {
                            Label(candidate.title, systemImage: candidate.systemImage)
                            Spacer()
                            Text(count(for: candidate), format: .number)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(
                        filter == candidate
                            ? Color.accentColor.opacity(0.16)
                            : Color.clear
                    )
                }
            }

            Section("Supported formats") {
                Text(LibraryMediaType.supportedExtensionsDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("POKE64")
    }

    private var itemList: some View {
        Group {
            if filteredItems.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? emptyTitle : "No Results",
                    systemImage: searchText.isEmpty ? emptySystemImage : "magnifyingglass",
                    description: Text(emptyDescription)
                )
            } else {
                List {
                    ForEach(filteredItems) { item in
                        LibraryRow(
                            item: item,
                            isSelected: selectedItemID == item.id,
                            isRunning: loadedItemID == item.id
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedItemID = item.id
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                toggleFavorite(item)
                            } label: {
                                Label(
                                    item.isFavorite ? "Unfavorite" : "Favorite",
                                    systemImage: item.isFavorite ? "star.slash" : "star"
                                )
                            }
                            .tint(.yellow)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                deletionCandidate = item
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .disabled(loadedItemID == item.id)
                        }
                        .contextMenu {
                            Button {
                                run(item)
                            } label: {
                                Label("Run", systemImage: "play.fill")
                            }

                            Button {
                                toggleFavorite(item)
                            } label: {
                                Label(
                                    item.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                                    systemImage: item.isFavorite ? "star.slash" : "star"
                                )
                            }

                            Divider()

                            Button(role: .destructive) {
                                deletionCandidate = item
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .disabled(loadedItemID == item.id)
                        }
                    }
                }
            }
        }
        .navigationTitle(filter.title)
        .searchable(text: $searchText, prompt: "Search title or filename")
        .onAppear {
            normalizeSelection()
        }
        .onChange(of: filter) { _, _ in
            normalizeSelection()
        }
        .onChange(of: searchText) { _, _ in
            normalizeSelection()
        }
        .onChange(of: library.items) { _, _ in
            normalizeSelection()
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let item = selectedItem {
            LibraryDetailView(
                item: item,
                isRunning: loadedItemID == item.id,
                onRun: { run(item) },
                onToggleFavorite: { toggleFavorite(item) },
                onRename: { title in rename(item, to: title) },
                onDelete: { deletionCandidate = item }
            )
            .id(item.id)
        } else {
            ContentUnavailableView(
                "Select Media",
                systemImage: "books.vertical",
                description: Text("Choose an imported disk, program, tape or cartridge.")
            )
        }
    }

    private var sourceItems: [LibraryItem] {
        switch filter {
        case .all:
            return library.allItems
        case .favorites:
            return library.favoriteItems
        case .recent:
            return library.recentItems
        }
    }

    private var filteredItems: [LibraryItem] {
        guard !searchText.isEmpty else { return sourceItems }
        return sourceItems.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
                || $0.originalFilename.localizedCaseInsensitiveContains(searchText)
                || $0.mediaType.displayName.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var selectedItem: LibraryItem? {
        guard let selectedItemID else { return nil }
        return library.item(withID: selectedItemID)
    }

    private var temporaryMediaIsAdded: Bool {
        let itemID = newlyAddedTemporaryMediaItemID ?? temporaryMediaAddedItemID
        guard let itemID else { return false }
        return library.item(withID: itemID) != nil
    }

    private var emptyTitle: String {
        switch filter {
        case .all:
            return "Library Empty"
        case .favorites:
            return "No Favorites"
        case .recent:
            return "No Recent Media"
        }
    }

    private var emptySystemImage: String {
        switch filter {
        case .all:
            return "books.vertical"
        case .favorites:
            return "star"
        case .recent:
            return "clock"
        }
    }

    private var emptyDescription: String {
        if !searchText.isEmpty {
            return "No imported media matches “\(searchText)”."
        }

        switch filter {
        case .all:
            return "Import a D64, PRG, CRT, TAP or T64 file to begin."
        case .favorites:
            return "Mark library items as favorites to collect them here."
        case .recent:
            return "Media appears here after it has been launched."
        }
    }

    private func count(for filter: LibraryFilter) -> Int {
        switch filter {
        case .all:
            return library.allItems.count
        case .favorites:
            return library.favoriteItems.count
        case .recent:
            return library.recentItems.count
        }
    }

    private func addTemporaryMedia() {
        do {
            let item = try onAddTemporaryMedia()
            newlyAddedTemporaryMediaItemID = item.id
            filter = .all
            selectedItemID = item.id
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importFiles(_ urls: [URL]) {
        var lastImported: LibraryItem?
        var failures: [String] = []

        for url in urls {
            do {
                lastImported = try onImport(url)
            } catch {
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        filter = .all
        selectedItemID = lastImported?.id

        if !failures.isEmpty {
            errorMessage = failures.joined(separator: "\n\n")
        }
    }

    private func run(_ item: LibraryItem) {
        do {
            try onRun(item)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleFavorite(_ item: LibraryItem) {
        do {
            try library.toggleFavorite(item)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func rename(_ item: LibraryItem, to title: String) {
        do {
            try library.rename(item, to: title)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ item: LibraryItem) {
        guard loadedItemID != item.id else {
            errorMessage = "Eject or replace the currently running media before deleting it."
            deletionCandidate = nil
            return
        }

        do {
            try library.delete(item)
            if selectedItemID == item.id {
                selectedItemID = nil
            }
            deletionCandidate = nil
            normalizeSelection()
        } catch {
            deletionCandidate = nil
            errorMessage = error.localizedDescription
        }
    }

    private func normalizeSelection() {
        if let selectedItemID,
           filteredItems.contains(where: { $0.id == selectedItemID }) {
            return
        }
        selectedItemID = filteredItems.first?.id
    }
}

private struct LibraryRow: View {
    let item: LibraryItem
    let isSelected: Bool
    let isRunning: Bool

    var body: some View {
        HStack(spacing: 12) {
            LibraryMediaIcon(mediaType: item.mediaType, size: 34)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(.body.weight(.medium))
                        .lineLimit(1)

                    if item.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }

                    if isRunning {
                        Text("RUNNING")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.green.opacity(0.18), in: Capsule())
                            .foregroundStyle(.green)
                    }
                }

                Text(item.originalFilename)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text("\(item.mediaType.displayName) · \(Self.fileSizeFormatter.string(fromByteCount: item.fileSize))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            if isSelected {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(
            isSelected
                ? Color.accentColor.opacity(0.14)
                : Color.clear
        )
    }

    private static let fileSizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.includesUnit = true
        return formatter
    }()
}

private struct LibraryMediaIcon: View {
    let mediaType: LibraryMediaType
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
                .fill(.quaternary)

            mediaArtwork
                .frame(width: size * 0.72, height: size * 0.72)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("\(mediaType.displayName) media")
    }

    @ViewBuilder
    private var mediaArtwork: some View {
        switch mediaType {
        case .d64:
            floppyArtwork
        case .crt:
            cartridgeArtwork
        case .tap, .t64:
            tapeArtwork
        case .prg:
            programArtwork
        }
    }

    private var floppyArtwork: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)

            ZStack {
                RoundedRectangle(cornerRadius: side * 0.08, style: .continuous)
                    .fill(Color.accentColor.opacity(0.82))

                RoundedRectangle(cornerRadius: side * 0.025)
                    .fill(Color.primary.opacity(0.9))
                    .frame(width: side * 0.48, height: side * 0.22)
                    .offset(y: -side * 0.23)

                Circle()
                    .fill(Color.primary.opacity(0.92))
                    .frame(width: side * 0.34, height: side * 0.34)
                    .offset(y: side * 0.14)

                Circle()
                    .fill(Color.accentColor.opacity(0.75))
                    .frame(width: side * 0.12, height: side * 0.12)
                    .offset(y: side * 0.14)

                Rectangle()
                    .fill(Color.primary.opacity(0.92))
                    .frame(width: side * 0.14, height: side * 0.08)
                    .offset(x: side * 0.27, y: -side * 0.33)
            }
        }
    }

    private var cartridgeArtwork: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)

            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: side * 0.1, style: .continuous)
                    .fill(Color.accentColor.opacity(0.82))
                    .frame(width: side * 0.82, height: side * 0.66)
                    .offset(y: -side * 0.05)

                RoundedRectangle(cornerRadius: side * 0.04)
                    .fill(.secondary)
                    .frame(width: side * 0.58, height: side * 0.16)

                HStack(spacing: side * 0.055) {
                    ForEach(0..<5, id: \.self) { _ in
                        Rectangle()
                            .fill(Color.primary.opacity(0.9))
                            .frame(width: side * 0.055, height: side * 0.1)
                    }
                }
                .offset(y: -side * 0.03)

                RoundedRectangle(cornerRadius: side * 0.03)
                    .stroke(Color.primary.opacity(0.85), lineWidth: max(1, side * 0.04))
                    .frame(width: side * 0.42, height: side * 0.2)
                    .offset(y: -side * 0.29)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var tapeArtwork: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)

            ZStack {
                RoundedRectangle(cornerRadius: side * 0.1, style: .continuous)
                    .fill(Color.accentColor.opacity(0.82))
                    .frame(width: side * 0.9, height: side * 0.62)

                RoundedRectangle(cornerRadius: side * 0.04)
                    .fill(Color.primary.opacity(0.88))
                    .frame(width: side * 0.66, height: side * 0.28)

                HStack(spacing: side * 0.18) {
                    tapeReel(side: side)
                    tapeReel(side: side)
                }

                Capsule()
                    .fill(.secondary.opacity(0.8))
                    .frame(width: side * 0.46, height: side * 0.08)
                    .offset(y: side * 0.22)
            }
        }
    }

    private func tapeReel(side: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(.secondary)
                .frame(width: side * 0.2, height: side * 0.2)
            Circle()
                .fill(Color.primary)
                .frame(width: side * 0.07, height: side * 0.07)
        }
    }

    private var programArtwork: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)

            ZStack {
                RoundedRectangle(cornerRadius: side * 0.08, style: .continuous)
                    .fill(Color.accentColor.opacity(0.82))

                RoundedRectangle(cornerRadius: side * 0.035)
                    .fill(Color.primary.opacity(0.9))
                    .frame(width: side * 0.72, height: side * 0.56)

                Text(">_")
                    .font(.system(size: side * 0.27, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.accentColor)
                    .offset(x: -side * 0.06)
            }
        }
    }
}

private struct LibraryDetailView: View {
    let item: LibraryItem
    let isRunning: Bool
    let onRun: () -> Void
    let onToggleFavorite: () -> Void
    let onRename: (String) -> Void
    let onDelete: () -> Void

    @State private var editedTitle: String

    init(
        item: LibraryItem,
        isRunning: Bool,
        onRun: @escaping () -> Void,
        onToggleFavorite: @escaping () -> Void,
        onRename: @escaping (String) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.item = item
        self.isRunning = isRunning
        self.onRun = onRun
        self.onToggleFavorite = onToggleFavorite
        self.onRename = onRename
        self.onDelete = onDelete
        _editedTitle = State(initialValue: item.title)
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    LibraryMediaIcon(mediaType: item.mediaType, size: 64)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.title)
                            .font(.title2.weight(.semibold))

                        Text(item.mediaType.displayName)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.secondary)

                        if isRunning {
                            Label("Currently running", systemImage: "play.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                }
                .padding(.vertical, 6)

                Button {
                    onRun()
                } label: {
                    Label(isRunning ? "Restart Media" : "Run", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }

            Section("Title") {
                TextField("Title", text: $editedTitle)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .onSubmit {
                        onRename(editedTitle)
                    }

                Button("Save Title") {
                    onRename(editedTitle)
                }
                .disabled(
                    editedTitle.trimmingCharacters(in: .whitespacesAndNewlines) == item.title
                )
            }

            Section("Media") {
                LabeledContent("Original file", value: item.originalFilename)
                LabeledContent("Format", value: item.mediaType.displayName)
                LabeledContent(
                    "Size",
                    value: Self.fileSizeFormatter.string(fromByteCount: item.fileSize)
                )
                LabeledContent("Imported", value: item.importedAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent(
                    "Last opened",
                    value: item.lastOpenedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Never"
                )
            }

            Section {
                Button {
                    onToggleFavorite()
                } label: {
                    Label(
                        item.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                        systemImage: item.isFavorite ? "star.slash" : "star"
                    )
                }

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete from Library", systemImage: "trash")
                }
                .disabled(isRunning)
            } footer: {
                if isRunning {
                    Text("Currently running media cannot be deleted. Eject it or launch another item first.")
                }
            }
        }
        .navigationTitle("Media Details")
        .onChange(of: item.title) { _, newValue in
            editedTitle = newValue
        }
    }

    private static let fileSizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.includesUnit = true
        return formatter
    }()
}
