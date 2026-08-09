import CoreGraphics
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers


private enum LibraryImportConflictKind {
    case exactDuplicate
    case filenameConflict
}

private struct PendingLibraryImportConflict: Identifiable {
    let id = UUID()
    let inspection: LibraryImportInspection
    let existingItem: LibraryItem
    let kind: LibraryImportConflictKind

    var title: String {
        switch kind {
        case .exactDuplicate:
            return "Duplicate Media"
        case .filenameConflict:
            return "Import Conflict"
        }
    }

    var message: String {
        switch kind {
        case .exactDuplicate:
            return "\(inspection.originalFilename) has the same SHA-256 content as “\(existingItem.title)”. Use the existing item or keep another copy?"
        case .filenameConflict:
            return "A different file named \(inspection.originalFilename) is already in the Library. Replace it, keep both versions or skip this file?"
        }
    }
}

private struct LibraryMediaSetListEntry: Identifiable {
    let descriptor: LibraryMediaSetDescriptor
    let members: [LibraryItem]

    var id: String {
        "set:\(descriptor.key)"
    }
}

private enum LibraryListEntry: Identifiable {
    case item(LibraryItem)
    case mediaSet(LibraryMediaSetListEntry)

    var id: String {
        switch self {
        case .item(let item):
            return "item:\(item.id.uuidString)"
        case .mediaSet(let set):
            return set.id
        }
    }
}

private enum LibraryFilter: String, CaseIterable, Identifiable {
    case all
    case favorites
    case recent
    case disks
    case tapes
    case cartridges

    static let primaryFilters: [LibraryFilter] = [.all, .favorites, .recent]
    static let mediaTypeFilters: [LibraryFilter] = [.disks, .tapes, .cartridges]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "All Media"
        case .favorites:
            return "Favorites"
        case .recent:
            return "Recent"
        case .disks:
            return "Disks"
        case .tapes:
            return "Tapes"
        case .cartridges:
            return "Cartridges"
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
        case .disks:
            return "externaldrive.fill"
        case .tapes:
            return "recordingtape"
        case .cartridges:
            return "shippingbox.fill"
        }
    }
}

struct LibraryView: View {
    @ObservedObject private var emulator: EmulatorModel
    @ObservedObject private var library: LibraryStore

    @Environment(\.dismiss) private var dismiss
    @State private var filter: LibraryFilter = .all
    @State private var selectedItemID: UUID?
    @State private var searchText = ""
    @State private var showImporter = false
    @State private var showNewDisk = false
    @State private var errorMessage: String?
    @State private var deletionCandidate: LibraryItem?
    @State private var mediaActionPrompt: MediaActionPromptState?
    @State private var importQueue: [URL] = []
    @State private var importFailures: [String] = []
    @State private var lastImportedItemID: UUID?
    @State private var pendingImportConflict: PendingLibraryImportConflict?
    @State private var expandedMediaSetKeys: Set<String> = []

    init(emulator: EmulatorModel) {
        _emulator = ObservedObject(wrappedValue: emulator)
        _library = ObservedObject(wrappedValue: emulator.library)
    }

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
        .mediaActionPrompt(
            prompt: $mediaActionPrompt,
            emulator: emulator,
            onComplete: { dismiss() }
        )
        .sheet(isPresented: $showNewDisk) {
            NewDiskView(
                targetDriveUnit: 8,
                currentDriveModel: C64DriveModel.selected(for: 8),
                defaultInsertAfterCreation: false
            ) { title, format, initialization, insertAfterCreation in
                createBlankDisk(
                    title: title,
                    format: format,
                    initialization: initialization,
                    insertAfterCreation: insertAfterCreation
                )
            }
        }
        .sheet(isPresented: $showImporter) {
            CopyDocumentPicker(
                isPresented: $showImporter,
                allowedContentTypes: [.data],
                allowsMultipleSelection: true
            ) { urls in
                importFiles(urls)
            }
        }
        .confirmationDialog(
            pendingImportConflict?.title ?? "Import Conflict",
            isPresented: Binding(
                get: { pendingImportConflict != nil },
                set: { isPresented in
                    if !isPresented, pendingImportConflict != nil {
                        skipImportConflict()
                    }
                }
            ),
            titleVisibility: .visible,
            presenting: pendingImportConflict
        ) { conflict in
            switch conflict.kind {
            case .exactDuplicate:
                Button("Use Existing") {
                    resolveImportConflict(.useExisting(conflict.existingItem))
                }
                Button("Import Copy") {
                    resolveImportConflict(.keepBoth)
                }
                Button("Skip", role: .cancel) {
                    skipImportConflict()
                }

            case .filenameConflict:
                Button("Replace", role: .destructive) {
                    resolveImportConflict(.replaceExisting(conflict.existingItem))
                }
                Button("Keep Both") {
                    resolveImportConflict(.keepBoth)
                }
                Button("Skip", role: .cancel) {
                    skipImportConflict()
                }
            }
        } message: { conflict in
            Text(conflict.message)
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
                showNewDisk = true
            } label: {
                Label("New Disk", systemImage: "plus")
            }

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
            if !emulator.temporaryMediaItems.isEmpty {
                Section("Current Media") {
                    ForEach(emulator.temporaryMediaItems) { temporaryMedia in
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
                                addTemporaryMedia(temporaryMedia)
                            } label: {
                                Label(
                                    temporaryMedia.addedLibraryItemID == nil
                                        ? "Add to Library"
                                        : "Added to Library",
                                    systemImage: temporaryMedia.addedLibraryItemID == nil
                                        ? "plus.circle.fill"
                                        : "checkmark.circle.fill"
                                )
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(temporaryMedia.addedLibraryItemID != nil)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Section("Library") {
                ForEach(LibraryFilter.primaryFilters) { candidate in
                    sidebarFilterButton(candidate)
                }

                Divider()
                    .padding(.vertical, 4)

                ForEach(LibraryFilter.mediaTypeFilters) { candidate in
                    sidebarFilterButton(candidate)
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

    private func sidebarFilterButton(_ candidate: LibraryFilter) -> some View {
        Button {
            filter = candidate
            normalizeSelection()
        } label: {
            HStack(spacing: 12) {
                Label(candidate.title, systemImage: candidate.systemImage)
                Spacer(minLength: 12)
                Text(count(for: candidate), format: .number)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .listRowBackground(
            filter == candidate
                ? Color.accentColor.opacity(0.16)
                : Color.clear
        )
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
                    ForEach(libraryListEntries) { entry in
                        switch entry {
                        case .item(let item):
                            libraryItemRow(item)

                        case .mediaSet(let mediaSet):
                            DisclosureGroup(
                                isExpanded: mediaSetExpansionBinding(for: mediaSet.descriptor.key)
                            ) {
                                ForEach(mediaSet.members) { member in
                                    libraryItemRow(member, isMediaSetMember: true)
                                }
                            } label: {
                                LibraryMediaSetRow(
                                    mediaSet: mediaSet,
                                    selectedItemID: selectedItemID,
                                    activeItemIDs: emulator.mountedLibraryItemIDs
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedItemID = preferredItem(in: mediaSet).id
                                }
                            }
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
                isActive: emulator.mountedLibraryItemIDs.contains(item.id),
                availableDriveUnits: emulator.availableDriveUnits,
                mediaSetItems: library.mediaSetMembers(for: item),
                loadInspection: { try library.inspectMedia(item) },
                onAction: { action in beginMediaRequest(for: item, preferredAction: action) },
                onSelectMediaSetItem: { selectedItemID = $0.id },
                onMediaSetAction: { member, action in
                    beginMediaRequest(for: member, preferredAction: action)
                },
                loadArtwork: { kind in library.artworkData(for: item, kind: kind) },
                captureCurrentScreenshot: { emulator.captureCurrentVideoFrame() },
                onToggleFavorite: { toggleFavorite(item) },
                onRename: { title in rename(item, to: title) },
                onUpdateNotes: { notes in updateNotes(item, notes: notes) },
                onSetArtwork: { kind, data in setArtwork(data, for: item, kind: kind) },
                onRemoveArtwork: { kind in removeArtwork(for: item, kind: kind) },
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
        case .disks:
            return library.allItems.filter { $0.mediaType.isDiskImage }
        case .tapes:
            return library.allItems.filter { $0.mediaType == .tap || $0.mediaType == .t64 }
        case .cartridges:
            return library.allItems.filter { $0.mediaType == .crt }
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

    private var libraryListEntries: [LibraryListEntry] {
        var emittedSetKeys: Set<String> = []
        var entries: [LibraryListEntry] = []

        for item in filteredItems {
            guard let descriptor = item.mediaSetDescriptor else {
                entries.append(.item(item))
                continue
            }

            let members = filteredItems
                .filter { $0.mediaSetDescriptor?.key == descriptor.key }
                .sorted(by: Self.mediaSetMemberSort)

            guard members.count > 1 else {
                entries.append(.item(item))
                continue
            }

            guard emittedSetKeys.insert(descriptor.key).inserted else { continue }
            entries.append(
                .mediaSet(
                    LibraryMediaSetListEntry(
                        descriptor: descriptor,
                        members: members
                    )
                )
            )
        }

        return entries
    }

    @ViewBuilder
    private func libraryItemRow(
        _ item: LibraryItem,
        isMediaSetMember: Bool = false
    ) -> some View {
        LibraryRow(
            item: item,
            isSelected: selectedItemID == item.id,
            isActive: emulator.mountedLibraryItemIDs.contains(item.id)
        )
        .padding(.leading, isMediaSetMember ? 18 : 0)
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
            .disabled(emulator.mountedLibraryItemIDs.contains(item.id))
        }
        .contextMenu {
            Button {
                beginMediaRequest(for: item)
            } label: {
                Label("Media Actions", systemImage: "play.circle")
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
            .disabled(emulator.mountedLibraryItemIDs.contains(item.id))
        }
    }

    private func mediaSetExpansionBinding(for key: String) -> Binding<Bool> {
        Binding(
            get: { expandedMediaSetKeys.contains(key) },
            set: { expanded in
                if expanded {
                    expandedMediaSetKeys.insert(key)
                } else {
                    expandedMediaSetKeys.remove(key)
                }
            }
        )
    }

    private func preferredItem(in mediaSet: LibraryMediaSetListEntry) -> LibraryItem {
        if let selectedItemID,
           let selected = mediaSet.members.first(where: { $0.id == selectedItemID }) {
            return selected
        }
        if let active = mediaSet.members.first(where: {
            emulator.mountedLibraryItemIDs.contains($0.id)
        }) {
            return active
        }
        return mediaSet.members[0]
    }

    private static func mediaSetMemberSort(
        _ lhs: LibraryItem,
        _ rhs: LibraryItem
    ) -> Bool {
        let lhsOrder = lhs.mediaSetDescriptor?.sortOrder ?? Int.max
        let rhsOrder = rhs.mediaSetDescriptor?.sortOrder ?? Int.max
        if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private var selectedItem: LibraryItem? {
        guard let selectedItemID else { return nil }
        return library.item(withID: selectedItemID)
    }


    private var emptyTitle: String {
        switch filter {
        case .all:
            return "Library Empty"
        case .favorites:
            return "No Favorites"
        case .recent:
            return "No Recent Media"
        case .disks:
            return "No Disks"
        case .tapes:
            return "No Tapes"
        case .cartridges:
            return "No Cartridges"
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
        case .disks:
            return "externaldrive"
        case .tapes:
            return "recordingtape"
        case .cartridges:
            return "shippingbox"
        }
    }

    private var emptyDescription: String {
        if !searchText.isEmpty {
            return "No imported media matches “\(searchText)”."
        }

        switch filter {
        case .all:
            return "Import media, including G64 track images, or create a blank D64, D71 or D81 disk to begin."
        case .favorites:
            return "Mark library items as favorites to collect them here."
        case .recent:
            return "Media appears here after it has been launched."
        case .disks:
            return "D64, D71, D81 and G64 images are collected here automatically."
        case .tapes:
            return "TAP and T64 media are collected here automatically."
        case .cartridges:
            return "CRT cartridges are collected here automatically."
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
        case .disks:
            return library.allItems.filter { $0.mediaType.isDiskImage }.count
        case .tapes:
            return library.allItems.filter { $0.mediaType == .tap || $0.mediaType == .t64 }.count
        case .cartridges:
            return library.allItems.filter { $0.mediaType == .crt }.count
        }
    }

    private func addTemporaryMedia(_ media: TemporaryMediaInfo) {
        do {
            let item = try emulator.addTemporaryMediaToLibrary(id: media.id)
            filter = .all
            selectedItemID = item.id
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createBlankDisk(
        title: String,
        format: BlankDiskImageFormat,
        initialization: BlankDiskInitialization,
        insertAfterCreation: Bool
    ) {
        do {
            let item = try library.createBlankDisk(
                title: title,
                format: format,
                initialization: initialization
            )
            filter = .all
            searchText = ""
            selectedItemID = item.id

            guard insertAfterCreation else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                beginMediaRequest(
                    for: item,
                    preferredAction: .insertDisk(8)
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importFiles(_ urls: [URL]) {
        importQueue = urls
        importFailures = []
        lastImportedItemID = nil
        pendingImportConflict = nil
        processNextImport()
    }

    private func processNextImport() {
        while !importQueue.isEmpty {
            let url = importQueue.removeFirst()

            do {
                let inspection = try library.inspectImport(from: url)

                if let duplicate = inspection.exactDuplicate {
                    pendingImportConflict = PendingLibraryImportConflict(
                        inspection: inspection,
                        existingItem: duplicate,
                        kind: .exactDuplicate
                    )
                    return
                }

                if let conflict = inspection.filenameConflict {
                    pendingImportConflict = PendingLibraryImportConflict(
                        inspection: inspection,
                        existingItem: conflict,
                        kind: .filenameConflict
                    )
                    return
                }

                let item = try emulator.importIntoLibrary(
                    inspection: inspection,
                    resolution: .keepBoth
                )
                lastImportedItemID = item.id
            } catch {
                importFailures.append(
                    "\(url.lastPathComponent): \(error.localizedDescription)"
                )
            }
        }

        finishImportQueue()
    }

    private func resolveImportConflict(_ resolution: LibraryImportResolution) {
        guard let conflict = pendingImportConflict else { return }
        pendingImportConflict = nil

        do {
            let item = try emulator.importIntoLibrary(
                inspection: conflict.inspection,
                resolution: resolution
            )
            lastImportedItemID = item.id
        } catch {
            importFailures.append(
                "\(conflict.inspection.originalFilename): \(error.localizedDescription)"
            )
        }

        processNextImport()
    }

    private func skipImportConflict() {
        pendingImportConflict = nil
        processNextImport()
    }

    private func finishImportQueue() {
        filter = .all
        searchText = ""
        selectedItemID = lastImportedItemID

        if !importFailures.isEmpty {
            errorMessage = importFailures.joined(separator: "\n\n")
        }

        importQueue = []
        importFailures = []
        lastImportedItemID = nil
    }

    private func beginMediaRequest(
        for item: LibraryItem,
        preferredAction: MediaAction? = nil
    ) {
        do {
            let originalRequest = try emulator.actionRequest(for: item)
            let request: MediaActionRequest
            if let preferredAction {
                request = MediaActionRequest(
                    media: originalRequest.media,
                    actions: [preferredAction]
                )
            } else {
                request = originalRequest
            }

            if request.actions.count > 1 {
                mediaActionPrompt = .choose(request)
                return
            }

            guard let action = request.actions.first else { return }
            if let replacement = emulator.replacementInfo(
                for: action,
                media: request.media
            ) {
                mediaActionPrompt = .replace(
                    request,
                    action: action,
                    replacement: replacement
                )
                return
            }

            try emulator.performMediaAction(action, media: request.media)
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

    private func updateNotes(_ item: LibraryItem, notes: String) {
        do {
            try library.updateNotes(item, notes: notes)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func setArtwork(
        _ data: Data,
        for item: LibraryItem,
        kind: LibraryArtworkKind
    ) {
        do {
            try library.setArtwork(data, for: item, kind: kind)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeArtwork(
        for item: LibraryItem,
        kind: LibraryArtworkKind
    ) {
        do {
            try library.removeArtwork(for: item, kind: kind)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ item: LibraryItem) {
        guard !emulator.mountedLibraryItemIDs.contains(item.id) else {
            errorMessage = "Eject or replace the active media before deleting it."
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

struct NewDiskView: View {
    let targetDriveUnit: Int
    let currentDriveModel: C64DriveModel
    let defaultInsertAfterCreation: Bool
    let onCreate: (
        String,
        BlankDiskImageFormat,
        BlankDiskInitialization,
        Bool
    ) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = "New Disk"
    @State private var formatChoice: BlankDiskFormatChoice = .automatic
    @State private var initialization: BlankDiskInitialization = .formatted
    @State private var insertAfterCreation: Bool

    init(
        targetDriveUnit: Int = 8,
        currentDriveModel: C64DriveModel,
        defaultInsertAfterCreation: Bool,
        onCreate: @escaping (
            String,
            BlankDiskImageFormat,
            BlankDiskInitialization,
            Bool
        ) -> Void
    ) {
        self.targetDriveUnit = targetDriveUnit
        self.currentDriveModel = currentDriveModel
        self.defaultInsertAfterCreation = defaultInsertAfterCreation
        self.onCreate = onCreate
        _insertAfterCreation = State(initialValue: defaultInsertAfterCreation)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Disk") {
                    TextField("Name", text: $title)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)

                    Picker("Image format", selection: $formatChoice) {
                        ForEach(BlankDiskFormatChoice.allCases) { choice in
                            Text(choice.title(for: currentDriveModel, unit: targetDriveUnit))
                                .tag(choice)
                        }
                    }

                    LabeledContent {
                        Text(resolvedFormat.geometryDescription)
                    } label: {
                        Text(resolvedFormat.displayName)
                    }
                }

                Section("Initial state") {
                    Picker("Initial state", selection: $initialization) {
                        ForEach(BlankDiskInitialization.allCases) { option in
                            Text(option.title)
                                .tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(initialization.description)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Toggle(
                        "Insert into Drive \(targetDriveUnit)",
                        isOn: $insertAfterCreation
                    )
                    .disabled(!formatIsCompatible)

                    if !formatIsCompatible {
                        Label {
                            Text(
                                "\(resolvedFormat.displayName) requires \(resolvedFormat.requiredDriveDescription). "
                                + "Drive \(targetDriveUnit) is currently \(currentDriveModel.title). The image can still be created for later use."
                            )
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                        }
                        .font(.footnote)
                        .foregroundStyle(.orange)
                    } else {
                        Text(
                            insertAfterCreation
                                ? "The image is added to the Library and then inserted into Drive \(targetDriveUnit)."
                                : "The image is added to the Library without changing the mounted disk."
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("After creation")
                } footer: {
                    if initialization == .formatted {
                        Text("The Commodore disk label uses the first 16 supported characters of the name. The library title is kept in full.")
                    }
                }
            }
            .navigationTitle("Create New Disk")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        onCreate(
                            title,
                            resolvedFormat,
                            initialization,
                            insertAfterCreation && formatIsCompatible
                        )
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onChange(of: formatChoice) { _, _ in
            if !formatIsCompatible {
                insertAfterCreation = false
            }
        }
    }

    private var resolvedFormat: BlankDiskImageFormat {
        formatChoice.resolvedFormat(for: currentDriveModel)
    }

    private var formatIsCompatible: Bool {
        resolvedFormat.isCompatible(with: currentDriveModel)
    }
}

private struct LibraryMediaSetRow: View {
    let mediaSet: LibraryMediaSetListEntry
    let selectedItemID: UUID?
    let activeItemIDs: Set<UUID>

    var body: some View {
        HStack(spacing: 12) {
            LibraryMediaIcon(mediaType: mediaSet.members[0].mediaType, size: 38)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(mediaSet.descriptor.displayName)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)

                    Text("MULTI-DISK")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.16), in: Capsule())
                        .foregroundStyle(Color.accentColor)

                    if isActive {
                        Text("ACTIVE")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.green.opacity(0.18), in: Capsule())
                            .foregroundStyle(.green)
                    }
                }

                Text("\(mediaSet.members.count) disks · \(formatSummary)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let activeMember {
                    Text("Mounted: \(activeMember.mediaSetDescriptor?.memberLabel ?? activeMember.title)")
                        .font(.caption2)
                        .foregroundStyle(.green)
                } else {
                    Text(memberSummary)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)
        }
        .padding(.vertical, 4)
        .listRowBackground(
            isSelected
                ? Color.accentColor.opacity(0.14)
                : Color.clear
        )
    }

    private var isSelected: Bool {
        guard let selectedItemID else { return false }
        return mediaSet.members.contains(where: { $0.id == selectedItemID })
    }

    private var activeMember: LibraryItem? {
        mediaSet.members.first(where: { activeItemIDs.contains($0.id) })
    }

    private var isActive: Bool {
        activeMember != nil
    }

    private var formatSummary: String {
        let formats = Set(mediaSet.members.map { $0.mediaType.displayName })
        return formats.sorted().joined(separator: " / ")
    }

    private var memberSummary: String {
        mediaSet.members
            .compactMap { $0.mediaSetDescriptor?.memberLabel }
            .joined(separator: " · ")
    }
}

private struct LibraryRow: View {
    let item: LibraryItem
    let isSelected: Bool
    let isActive: Bool

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

                    if isActive {
                        Text("ACTIVE")
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

                Text(rowMetadata)
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


    private var rowMetadata: String {
        var components = [
            item.mediaType.displayName,
            Self.fileSizeFormatter.string(fromByteCount: item.fileSize)
        ]
        if let descriptor = item.mediaSetDescriptor {
            components.append(descriptor.memberLabel)
        }
        return components.joined(separator: " · ")
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
        case .d64, .d71, .d81, .g64:
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

private enum LibraryDetailSheet: String, Identifiable {
    case edit
    case information
    case mediaSet

    var id: String { rawValue }
}

private struct LibraryDetailView: View {
    let item: LibraryItem
    let isActive: Bool
    let availableDriveUnits: [Int]
    let mediaSetItems: [LibraryItem]
    let loadInspection: () throws -> LibraryMediaInspection?
    let onAction: (MediaAction) -> Void
    let onSelectMediaSetItem: (LibraryItem) -> Void
    let onMediaSetAction: (LibraryItem, MediaAction) -> Void
    let loadArtwork: (LibraryArtworkKind) -> Data?
    let captureCurrentScreenshot: () -> Data?
    let onToggleFavorite: () -> Void
    let onRename: (String) -> Void
    let onUpdateNotes: (String) -> Void
    let onSetArtwork: (LibraryArtworkKind, Data) -> Void
    let onRemoveArtwork: (LibraryArtworkKind) -> Void
    let onDelete: () -> Void

    @State private var editedTitle: String
    @State private var editedNotes: String
    @State private var coverArtworkData: Data?
    @State private var screenshotArtworkData: Data?
    @State private var selectedCoverPhoto: PhotosPickerItem?
    @State private var selectedScreenshotPhoto: PhotosPickerItem?
    @State private var mediaInspection: LibraryMediaInspection?
    @State private var mediaInspectionError: String?
    @State private var isInspectingMedia = false
    @State private var screenshotCaptureError: String?
    @State private var presentedSheet: LibraryDetailSheet?

    init(
        item: LibraryItem,
        isActive: Bool,
        availableDriveUnits: [Int],
        mediaSetItems: [LibraryItem],
        loadInspection: @escaping () throws -> LibraryMediaInspection?,
        onAction: @escaping (MediaAction) -> Void,
        onSelectMediaSetItem: @escaping (LibraryItem) -> Void,
        onMediaSetAction: @escaping (LibraryItem, MediaAction) -> Void,
        loadArtwork: @escaping (LibraryArtworkKind) -> Data?,
        captureCurrentScreenshot: @escaping () -> Data?,
        onToggleFavorite: @escaping () -> Void,
        onRename: @escaping (String) -> Void,
        onUpdateNotes: @escaping (String) -> Void,
        onSetArtwork: @escaping (LibraryArtworkKind, Data) -> Void,
        onRemoveArtwork: @escaping (LibraryArtworkKind) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.item = item
        self.isActive = isActive
        self.availableDriveUnits = availableDriveUnits
        self.mediaSetItems = mediaSetItems
        self.loadInspection = loadInspection
        self.onAction = onAction
        self.onSelectMediaSetItem = onSelectMediaSetItem
        self.onMediaSetAction = onMediaSetAction
        self.loadArtwork = loadArtwork
        self.captureCurrentScreenshot = captureCurrentScreenshot
        self.onToggleFavorite = onToggleFavorite
        self.onRename = onRename
        self.onUpdateNotes = onUpdateNotes
        self.onSetArtwork = onSetArtwork
        self.onRemoveArtwork = onRemoveArtwork
        self.onDelete = onDelete
        _editedTitle = State(initialValue: item.title)
        _editedNotes = State(initialValue: item.notes ?? "")
        _coverArtworkData = State(initialValue: loadArtwork(.cover))
        _screenshotArtworkData = State(initialValue: loadArtwork(.screenshot))
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    if let coverArtworkData, let coverImage = UIImage(data: coverArtworkData) {
                        Image(uiImage: coverImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 64, height: 82)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(.white.opacity(0.12), lineWidth: 1)
                            }
                    } else {
                        LibraryMediaIcon(mediaType: item.mediaType, size: 64)
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.title)
                            .font(.title2.weight(.semibold))

                        Text(item.mediaType.displayName)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.secondary)

                        if isActive {
                            Label(activeStatusTitle, systemImage: activeStatusSystemImage)
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                }
                .padding(.vertical, 6)

                mediaActionButtons

                screenshotPreview

                if let notes = item.notes, !notes.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Label("Notes", systemImage: "note.text")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(notes)
                            .font(.callout)
                            .lineLimit(3)
                    }
                    .padding(.top, 4)
                }
            }

            diskDirectoryPresentationSection

            if mediaSetItems.count > 1 {
                Section("Multi-Disk Set") {
                    Button {
                        presentedSheet = .mediaSet
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "square.stack.3d.up.fill")
                                .foregroundStyle(.tint)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.mediaSetDescriptor?.displayName ?? "Multi-disk set")
                                    .foregroundStyle(.primary)
                                Text("\(mediaSetItems.count) disks · \(item.mediaSetDescriptor?.memberLabel ?? item.title)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("Details") {
                Button {
                    presentedSheet = .information
                } label: {
                    Label("Media Information", systemImage: "info.circle")
                }

                Button {
                    presentedSheet = .edit
                } label: {
                    Label("Edit Library Entry", systemImage: "pencil")
                }
            }
        }
        .navigationTitle("Media Details")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    onToggleFavorite()
                } label: {
                    Image(systemName: item.isFavorite ? "star.fill" : "star")
                }
                .accessibilityLabel(item.isFavorite ? "Remove from Favorites" : "Add to Favorites")

                Menu {
                    Button {
                        presentedSheet = .edit
                    } label: {
                        Label("Edit Library Entry", systemImage: "pencil")
                    }

                    Button {
                        presentedSheet = .information
                    } label: {
                        Label("Media Information", systemImage: "info.circle")
                    }

                    if mediaSetItems.count > 1 {
                        Button {
                            presentedSheet = .mediaSet
                        } label: {
                            Label("Multi-Disk Set", systemImage: "square.stack.3d.up")
                        }
                    }

                    Divider()

                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("Delete from Library", systemImage: "trash")
                    }
                    .disabled(isActive)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("More library actions")
            }
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .edit:
                editLibraryEntrySheet
            case .information:
                mediaInformationSheet
            case .mediaSet:
                multiDiskSetSheet
            }
        }
        .task(id: item.id) {
            await loadMediaInspectionIfNeeded()
        }
        .onChange(of: item.title) { _, newValue in
            editedTitle = newValue
        }
        .onChange(of: item.notes) { _, newValue in
            editedNotes = newValue ?? ""
        }
        .onChange(of: item.coverArtworkFilename) { _, _ in
            coverArtworkData = loadArtwork(.cover)
        }
        .onChange(of: item.screenshotArtworkFilename) { _, _ in
            screenshotArtworkData = loadArtwork(.screenshot)
        }
        .onChange(of: selectedCoverPhoto) { _, newValue in
            importArtwork(from: newValue, kind: .cover)
        }
        .onChange(of: selectedScreenshotPhoto) { _, newValue in
            importArtwork(from: newValue, kind: .screenshot)
        }
        .alert(
            "Screenshot unavailable",
            isPresented: Binding(
                get: { screenshotCaptureError != nil },
                set: { if !$0 { screenshotCaptureError = nil } }
            )
        ) {
            Button("OK") {
                screenshotCaptureError = nil
            }
        } message: {
            Text(screenshotCaptureError ?? "Unable to capture the current C64 frame.")
        }
    }

    private var editLibraryEntrySheet: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Title", text: $editedTitle)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .onSubmit {
                            saveEditedMetadata()
                        }
                }

                Section("Notes") {
                    TextEditor(text: $editedNotes)
                        .frame(minHeight: 110)
                    Text("Notes are stored locally with this Library entry.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                artworkEditorSection(
                    title: "Cover",
                    kind: .cover,
                    data: coverArtworkData,
                    selection: $selectedCoverPhoto,
                    aspectRatio: 3.0 / 4.0
                )

                artworkEditorSection(
                    title: "Screenshot",
                    kind: .screenshot,
                    data: screenshotArtworkData,
                    selection: $selectedScreenshotPhoto,
                    aspectRatio: 4.0 / 3.0
                )

                Section("Library") {
                    Button {
                        onToggleFavorite()
                    } label: {
                        Label(
                            item.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                            systemImage: item.isFavorite ? "star.slash" : "star"
                        )
                    }
                }
            }
            .navigationTitle("Edit Library Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        editedTitle = item.title
                        editedNotes = item.notes ?? ""
                        presentedSheet = nil
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        saveEditedMetadata()
                        presentedSheet = nil
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var mediaInformationSheet: some View {
        NavigationStack {
            Form {
                Section("Media") {
                    LabeledContent("Original file", value: item.originalFilename)
                    LabeledContent("Format", value: item.mediaType.displayName)
                    LabeledContent(
                        "Size",
                        value: Self.fileSizeFormatter.string(fromByteCount: item.fileSize)
                    )

                    if let driveRequirement = item.mediaType.driveRequirementDescription {
                        LabeledContent("Compatible drive", value: driveRequirement)
                    }

                    if let descriptor = item.mediaSetDescriptor {
                        LabeledContent("Detected set", value: descriptor.displayName)
                        LabeledContent("Set member", value: descriptor.memberLabel)
                    }

                    LabeledContent(
                        "Imported",
                        value: item.importedAt.formatted(date: .abbreviated, time: .shortened)
                    )
                    LabeledContent(
                        "Last opened",
                        value: item.lastOpenedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Never"
                    )
                }

                if let hash = item.sha256 {
                    Section {
                        Text(hash)
                            .font(.caption2)
                            .monospaced()
                            .textSelection(.enabled)
                    } header: {
                        Text("SHA-256")
                    }
                }

                mediaTechnicalInspectionSections
            }
            .navigationTitle("Media Information")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        presentedSheet = nil
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var multiDiskSetSheet: some View {
        NavigationStack {
            List {
                ForEach(mediaSetItems) { member in
                    HStack(spacing: 10) {
                        Button {
                            onSelectMediaSetItem(member)
                            presentedSheet = nil
                        } label: {
                            HStack(spacing: 10) {
                                Image(
                                    systemName: member.id == item.id
                                        ? "checkmark.circle.fill"
                                        : "circle"
                                )
                                .foregroundStyle(
                                    member.id == item.id
                                        ? Color.accentColor
                                        : Color.secondary
                                )

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(member.mediaSetDescriptor?.memberLabel ?? member.title)
                                        .foregroundStyle(.primary)
                                    Text(member.originalFilename)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Menu {
                            ForEach(availableDriveUnits, id: \.self) { unit in
                                Button {
                                    onMediaSetAction(member, .insertDisk(unit))
                                    presentedSheet = nil
                                } label: {
                                    Label(
                                        "Insert in Drive \(unit)",
                                        systemImage: "externaldrive.fill"
                                    )
                                }
                            }
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .frame(width: 32, height: 32)
                        }
                        .accessibilityLabel("Insert \(member.title)")
                    }
                }
            }
            .navigationTitle(item.mediaSetDescriptor?.displayName ?? "Multi-Disk Set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        presentedSheet = nil
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func saveEditedMetadata() {
        let trimmedTitle = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTitle.isEmpty {
            editedTitle = item.title
        } else if trimmedTitle != item.title {
            onRename(trimmedTitle)
        }

        let normalizedNotes = editedNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedNotes != (item.notes ?? "") {
            onUpdateNotes(editedNotes)
        }
    }

    @ViewBuilder
    private func artworkEditorSection(
        title: String,
        kind: LibraryArtworkKind,
        data: Data?,
        selection: Binding<PhotosPickerItem?>,
        aspectRatio: CGFloat
    ) -> some View {
        Section(title) {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .aspectRatio(aspectRatio, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            if kind == .screenshot {
                Button {
                    captureCurrentScreenshotArtwork()
                } label: {
                    Label(
                        data == nil ? "Capture Current Screen" : "Replace with Current Screen",
                        systemImage: "camera.viewfinder"
                    )
                }
                .disabled(!isActive)

                if !isActive {
                    Text("Mount or run this Library entry before capturing the current C64 screen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            PhotosPicker(selection: selection, matching: .images) {
                Label(
                    data == nil ? "Choose Image…" : "Replace Image…",
                    systemImage: "photo.on.rectangle"
                )
            }

            if data != nil {
                Button(role: .destructive) {
                    onRemoveArtwork(kind)
                    switch kind {
                    case .cover:
                        coverArtworkData = nil
                        selectedCoverPhoto = nil
                    case .screenshot:
                        screenshotArtworkData = nil
                        selectedScreenshotPhoto = nil
                    }
                } label: {
                    Label("Remove \(title)", systemImage: "trash")
                }
            }
        }
    }

    private func captureCurrentScreenshotArtwork() {
        guard isActive else { return }
        guard let frameData = captureCurrentScreenshot(),
              let normalized = Self.normalizedArtworkData(frameData, kind: .screenshot) else {
            screenshotCaptureError = "POKE64 could not read the current emulator framebuffer. Return to the emulator, let it render a frame, then try again."
            return
        }

        onSetArtwork(.screenshot, normalized)
        screenshotArtworkData = normalized
        selectedScreenshotPhoto = nil
    }

    private func importArtwork(
        from pickerItem: PhotosPickerItem?,
        kind: LibraryArtworkKind
    ) {
        guard let pickerItem else { return }

        Task {
            guard let data = try? await pickerItem.loadTransferable(type: Data.self),
                  let normalized = Self.normalizedArtworkData(data, kind: kind) else {
                return
            }

            await MainActor.run {
                onSetArtwork(kind, normalized)
                switch kind {
                case .cover:
                    coverArtworkData = normalized
                case .screenshot:
                    screenshotArtworkData = normalized
                }
            }
        }
    }

    private static func normalizedArtworkData(
        _ data: Data,
        kind: LibraryArtworkKind
    ) -> Data? {
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else {
            return nil
        }

        let maximumDimension: CGFloat = kind == .cover ? 1_200 : 1_600
        let largestDimension = max(image.size.width, image.size.height)
        let scale = min(1, maximumDimension / largestDimension)
        let targetSize = CGSize(
            width: max(1, image.size.width * scale),
            height: max(1, image.size.height * scale)
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let rendered = renderer.image { context in
            UIColor.black.setFill()
            context.cgContext.fill(CGRect(origin: .zero, size: targetSize))
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return rendered.jpegData(compressionQuality: 0.86)
    }

    @ViewBuilder
    private var screenshotPreview: some View {
        if let screenshotArtworkData,
           let screenshotImage = UIImage(data: screenshotArtworkData) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Screenshot", systemImage: "photo")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Image(uiImage: screenshotImage)
                    .resizable()
                    .scaledToFit()
                    .aspectRatio(4.0 / 3.0, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(.white.opacity(0.08), lineWidth: 1)
                    }
                    .accessibilityLabel("Screenshot for \(item.title)")
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private var diskDirectoryPresentationSection: some View {
        if item.mediaType == .d64 || item.mediaType == .d71 || item.mediaType == .d81 {
            if isInspectingMedia {
                Section("Disk Directory") {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Reading disk image…")
                            .foregroundStyle(.secondary)
                    }
                }
            } else if let mediaInspectionError {
                Section("Disk Directory") {
                    Label(mediaInspectionError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)

                    Button("Retry Inspection") {
                        Task { await loadMediaInspectionIfNeeded(force: true) }
                    }
                }
            } else if case .commodoreDisk(let inspection) = mediaInspection {
                commodoreDirectorySection(inspection)
            }
        }
    }

    @ViewBuilder
    private var mediaTechnicalInspectionSections: some View {
        if item.mediaType == .g64 {
            if isInspectingMedia {
                Section("G64 Image") {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Reading G64 image…")
                            .foregroundStyle(.secondary)
                    }
                }
            } else if let mediaInspectionError {
                Section("G64 Image") {
                    Label(mediaInspectionError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)

                    Button("Retry Inspection") {
                        Task { await loadMediaInspectionIfNeeded(force: true) }
                    }
                }
            } else if case .g64(let inspection) = mediaInspection {
                g64Sections(inspection)
            }
        } else if case .commodoreDisk(let inspection) = mediaInspection {
            commodoreDiskInformationSection(inspection)
        }
    }

    private func commodoreDirectorySection(
        _ inspection: CommodoreDiskImageInspection
    ) -> some View {
        Section {
            if inspection.directoryEntries.isEmpty && !inspection.isFormatted {
                Label(
                    "The image does not contain a readable Commodore DOS directory.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.orange)
            } else {
                C64DirectoryListingView(inspection: inspection)
            }

            Button {
                Task { await loadMediaInspectionIfNeeded(force: true) }
            } label: {
                Label("Refresh Directory", systemImage: "arrow.clockwise")
            }
        } header: {
            HStack {
                Text("Disk Directory")
                Spacer()
                Text("LOAD \"$\",8")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text("The listing is rendered with the active C64 character ROM, including PETSCII graphics stored in disk and file names.")
        }
    }

    private func commodoreDiskInformationSection(
        _ inspection: CommodoreDiskImageInspection
    ) -> some View {
        Section("Disk Information") {
            LabeledContent("Disk name", value: inspection.diskName)
            LabeledContent("Disk ID", value: inspection.diskID)
            LabeledContent("DOS type", value: inspection.dosType)
            LabeledContent("Geometry", value: inspection.geometryDescription)
            LabeledContent(
                "Free blocks",
                value: inspection.freeBlocks.map { String($0) } ?? "Unavailable"
            )
            LabeledContent(
                "Library copy",
                value: inspection.isWritable ? "Writable" : "Read-only"
            )

            if let warning = inspection.warning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private func g64Sections(_ inspection: G64ImageInspection) -> some View {
        Section("G64 Image") {
            LabeledContent("Container version", value: String(inspection.version))
            LabeledContent("Half-track slots", value: String(inspection.halfTrackSlots))
            LabeledContent("Populated half-tracks", value: String(inspection.populatedHalfTracks))
            LabeledContent(
                "Maximum track size",
                value: Self.fileSizeFormatter.string(
                    fromByteCount: Int64(inspection.maximumTrackSize)
                )
            )
            LabeledContent(
                "Library copy",
                value: inspection.isWritable ? "Writable" : "Read-only"
            )

            Button {
                Task { await loadMediaInspectionIfNeeded(force: true) }
            } label: {
                Label("Refresh G64 Information", systemImage: "arrow.clockwise")
            }
        }

        Section("Directory") {
            Label(
                "G64 stores raw GCR track data. Directory inspection requires GCR decoding and is not exposed by this Library inspector.",
                systemImage: "info.circle"
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    @MainActor
    private func loadMediaInspectionIfNeeded(force: Bool = false) async {
        guard item.mediaType.isDiskImage else { return }
        guard force || (mediaInspection == nil && mediaInspectionError == nil) else { return }

        isInspectingMedia = true
        mediaInspectionError = nil
        await Task.yield()

        do {
            mediaInspection = try loadInspection()
        } catch {
            mediaInspection = nil
            mediaInspectionError = error.localizedDescription
        }
        isInspectingMedia = false
    }

    @ViewBuilder
    private var mediaActionButtons: some View {
        switch item.mediaType {
        case .prg:
            actionButton(.runProgram, prominent: true)

        case .crt:
            actionButton(.insertCartridgeAndReset, prominent: true)

        case .d64, .d71, .d81, .g64:
            ForEach(availableDriveUnits, id: \.self) { unit in
                actionButton(.insertDisk(unit), prominent: false)
                actionButton(.autostartDisk(unit), prominent: true)
            }

        case .tap, .t64:
            actionButton(.insertTape, prominent: false)
            actionButton(.autostartTape, prominent: true)
        }
    }

    @ViewBuilder
    private func actionButton(_ action: MediaAction, prominent: Bool) -> some View {
        if prominent {
            Button {
                onAction(action)
            } label: {
                Label(action.title, systemImage: action.systemImage)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        } else {
            Button {
                onAction(action)
            } label: {
                Label(action.title, systemImage: action.systemImage)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private var activeStatusTitle: String {
        item.mediaType == .prg ? "Currently running" : "Currently mounted"
    }

    private var activeStatusSystemImage: String {
        item.mediaType == .prg ? "play.circle.fill" : "checkmark.circle.fill"
    }

    private static let fileSizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.includesUnit = true
        return formatter
    }()
}

private struct C64DirectoryListingView: View {
    let inspection: CommodoreDiskImageInspection

    private var screenLines: [[UInt8]] {
        C64DirectoryListingBuilder.lines(for: inspection)
    }

    var body: some View {
        if let characterROM = FirmwareStore.characterROMData,
           let bitmap = C64DirectoryBitmapRenderer.makeImage(
               lines: screenLines,
               characterROM: characterROM,
               reverseColumnsByLine: [
                   0: C64DirectoryListingBuilder.headerReverseColumns
               ]
           ) {
            GeometryReader { proxy in
                let imageHeight = proxy.size.width
                    * CGFloat(bitmap.height)
                    / CGFloat(bitmap.width)

                ScrollView(.vertical) {
                    Image(decorative: bitmap, scale: 1, orientation: .up)
                        .resizable()
                        .interpolation(.none)
                        .frame(width: proxy.size.width, height: imageHeight)
                        .accessibilityLabel(accessibilityListing)
                }
                .scrollIndicators(.visible)
            }
            .frame(height: previewHeight)
            .background(C64DirectoryBitmapRenderer.backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Label(
                    "The active C64 character ROM is unavailable, so PETSCII graphics cannot be rendered.",
                    systemImage: "textformat.alt"
                )
                .font(.footnote)
                .foregroundStyle(.orange)

                Text(accessibilityListing)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
        }
    }

    private var previewHeight: CGFloat {
        min(380, max(112, CGFloat(screenLines.count) * 15.5))
    }

    private var accessibilityListing: String {
        var lines = [
            "0 \"\(inspection.diskName)\" \(inspection.diskID) \(inspection.dosType)"
        ]
        lines.append(contentsOf: inspection.directoryEntries.map { entry in
            let openMarker = entry.isClosed ? "" : "*"
            let lockMarker = entry.isLocked ? "<" : ""
            return "\(entry.blockCount) \"\(entry.name)\" \(openMarker)\(entry.fileType.displayName)\(lockMarker)"
        })
        if let freeBlocks = inspection.freeBlocks {
            lines.append("\(freeBlocks) BLOCKS FREE.")
        }
        return lines.joined(separator: "\n")
    }
}

private enum C64DirectoryListingBuilder {
    static let columns = 40
    static let headerReverseColumns = 5..<29

    static func lines(for inspection: CommodoreDiskImageInspection) -> [[UInt8]] {
        var result: [[UInt8]] = []

        var header = screenCodes(forASCII: "   0 ")
        header.append(screenCode(forPETSCII: 0x22))
        header.append(contentsOf: paddedPETSCII(inspection.rawDiskName, width: 16))
        header.append(screenCode(forPETSCII: 0x22))
        header.append(screenCode(forPETSCII: 0x20))
        header.append(contentsOf: paddedPETSCII(inspection.rawDiskID, width: 2))
        header.append(screenCode(forPETSCII: 0x20))
        header.append(contentsOf: paddedPETSCII(inspection.rawDOSType, width: 2))
        result.append(fitted(header))

        for entry in inspection.directoryEntries {
            var line = screenCodes(
                forASCII: String(format: "%4d ", entry.blockCount)
            )
            line.append(screenCode(forPETSCII: 0x22))
            line.append(contentsOf: paddedPETSCII(entry.rawName, width: 16))
            line.append(screenCode(forPETSCII: 0x22))
            line.append(screenCode(forPETSCII: 0x20))

            if !entry.isClosed {
                line.append(contentsOf: screenCodes(forASCII: "*"))
            }
            line.append(contentsOf: screenCodes(forASCII: entry.fileType.displayName))
            if entry.isLocked {
                line.append(contentsOf: screenCodes(forASCII: "<"))
            }
            result.append(fitted(line))
        }

        if let freeBlocks = inspection.freeBlocks {
            result.append(
                fitted(screenCodes(forASCII: String(format: "%4d BLOCKS FREE.", freeBlocks)))
            )
        }

        return result.isEmpty ? [Array(repeating: 0x20, count: columns)] : result
    }

    private static func paddedPETSCII(_ bytes: [UInt8], width: Int) -> [UInt8] {
        var result = bytes.prefix(width).map(screenCode(forPETSCII:))
        if result.count < width {
            result.append(contentsOf: repeatElement(UInt8(0x20), count: width - result.count))
        }
        return result
    }

    private static func screenCodes(forASCII text: String) -> [UInt8] {
        text.uppercased().utf8.map(screenCode(forPETSCII:))
    }

    private static func fitted(_ values: [UInt8]) -> [UInt8] {
        var result = Array(values.prefix(columns))
        if result.count < columns {
            result.append(contentsOf: repeatElement(UInt8(0x20), count: columns - result.count))
        }
        return result
    }

    private static func screenCode(forPETSCII byte: UInt8) -> UInt8 {
        switch byte {
        case 0x00...0x1f:
            return byte &+ 0x80
        case 0x20...0x3f:
            return byte
        case 0x40...0x5f:
            return byte &- 0x40
        case 0x60...0x7f:
            return byte &- 0x20
        case 0x80...0x9f:
            return byte &+ 0x40
        case 0xa0...0xbf:
            return byte &- 0x40
        case 0xc0...0xfe:
            return byte &- 0x80
        case 0xff:
            return 0x5e
        default:
            return 0x3f
        }
    }
}

private enum C64DirectoryBitmapRenderer {
    static let backgroundColor = Color(
        red: 0x40 / 255,
        green: 0x34 / 255,
        blue: 0xa2 / 255
    )

    private static let pixelWidth = C64DirectoryListingBuilder.columns * 8
    private static let backgroundRGBA: (UInt8, UInt8, UInt8, UInt8) = (0x40, 0x34, 0xa2, 0xff)
    private static let foregroundRGBA: (UInt8, UInt8, UInt8, UInt8) = (0xa7, 0x9b, 0xff, 0xff)

    static func makeImage(
        lines: [[UInt8]],
        characterROM: Data,
        reverseColumnsByLine: [Int: Range<Int>] = [:]
    ) -> CGImage? {
        guard characterROM.count >= 2_048 else { return nil }

        let pixelHeight = max(8, lines.count * 8)
        var pixels = [UInt8](repeating: 0, count: pixelWidth * pixelHeight * 4)

        for offset in stride(from: 0, to: pixels.count, by: 4) {
            pixels[offset] = backgroundRGBA.0
            pixels[offset + 1] = backgroundRGBA.1
            pixels[offset + 2] = backgroundRGBA.2
            pixels[offset + 3] = backgroundRGBA.3
        }

        for (lineIndex, line) in lines.enumerated() {
            let reverseColumns = reverseColumnsByLine[lineIndex]

            for (column, screenCode) in line.prefix(C64DirectoryListingBuilder.columns).enumerated() {
                let glyphOffset = Int(screenCode) * 8
                guard glyphOffset + 7 < characterROM.count else { continue }
                let isReversed = reverseColumns?.contains(column) == true

                for glyphRow in 0..<8 {
                    let bits = characterROM[glyphOffset + glyphRow]

                    for glyphColumn in 0..<8 {
                        let glyphPixelIsSet = (bits & (0x80 >> glyphColumn)) != 0
                        let useForeground = glyphPixelIsSet != isReversed
                        let color = useForeground ? foregroundRGBA : backgroundRGBA
                        let x = (column * 8) + glyphColumn
                        let y = (lineIndex * 8) + glyphRow
                        let pixelOffset = ((y * pixelWidth) + x) * 4
                        pixels[pixelOffset] = color.0
                        pixels[pixelOffset + 1] = color.1
                        pixels[pixelOffset + 2] = color.2
                        pixels[pixelOffset + 3] = color.3
                    }
                }
            }
        }

        let data = Data(pixels) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }

        return CGImage(
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: pixelWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}
