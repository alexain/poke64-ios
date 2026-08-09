import Foundation
import GameController
import SwiftUI

enum JoyportAssignment: Equatable {
    case none
    case virtualJoystick
    case commodoreMouse
    case physicalController(UUID)
}

enum DatasetteTransportCommand: Int, CaseIterable {
    case stop = 0
    case play = 1
    case fastForward = 2
    case rewind = 3
    case reset = 5
    case resetCounter = 6

    var coreCommand: C64DatasetteCommand {
        C64DatasetteCommand(rawValue: rawValue)!
    }

    var statusTitle: String {
        switch self {
        case .stop:
            return "Tape stopped"
        case .play:
            return "Tape playing"
        case .fastForward:
            return "Tape fast-forwarding"
        case .rewind:
            return "Tape rewinding"
        case .reset:
            return "Tape rewound"
        case .resetCounter:
            return "Tape counter reset"
        }
    }
}

enum DatasetteTransportState: Equatable {
    case stopped
    case playing
    case fastForwarding
    case rewinding
    case recording
    case unknown(Int)

    init(control: Int) {
        switch control {
        case 0:
            self = .stopped
        case 1:
            self = .playing
        case 2:
            self = .fastForwarding
        case 3:
            self = .rewinding
        case 4:
            self = .recording
        default:
            self = .unknown(control)
        }
    }

    var title: String {
        switch self {
        case .stopped:
            return "Stopped"
        case .playing:
            return "Playing"
        case .fastForwarding:
            return "Fast Forward"
        case .rewinding:
            return "Rewind"
        case .recording:
            return "Recording"
        case .unknown:
            return "Unknown"
        }
    }

    var systemImage: String {
        switch self {
        case .stopped:
            return "stop.fill"
        case .playing:
            return "play.fill"
        case .fastForwarding:
            return "forward.fill"
        case .rewinding:
            return "backward.fill"
        case .recording:
            return "record.circle.fill"
        case .unknown:
            return "questionmark"
        }
    }
}

struct PhysicalControllerInfo: Identifiable, Equatable {
    let id: UUID
    let name: String
}

struct MouseResetRecommendation: Identifiable, Equatable {
    let id = UUID()
    let port: Int
    let cartridgeTitle: String
}

enum MediaAction: Hashable, Identifiable {
    case runProgram
    case insertCartridgeAndReset
    case insertDisk(Int)
    case autostartDisk(Int)
    case insertTape
    case autostartTape

    var id: String {
        switch self {
        case .runProgram:
            return "run-program"
        case .insertCartridgeAndReset:
            return "insert-cartridge"
        case .insertDisk(let unit):
            return "insert-disk-\(unit)"
        case .autostartDisk(let unit):
            return "autostart-disk-\(unit)"
        case .insertTape:
            return "insert-tape"
        case .autostartTape:
            return "autostart-tape"
        }
    }

    var title: String {
        switch self {
        case .runProgram:
            return "Run Program"
        case .insertCartridgeAndReset:
            return "Insert Cartridge and Reset"
        case .insertDisk(let unit):
            return "Insert in Drive \(unit)"
        case .autostartDisk(let unit):
            return "Autostart from Drive \(unit)"
        case .insertTape:
            return "Insert Tape"
        case .autostartTape:
            return "Autostart Tape"
        }
    }

    var systemImage: String {
        switch self {
        case .runProgram:
            return "play.fill"
        case .insertCartridgeAndReset:
            return "shippingbox.fill"
        case .insertDisk:
            return "externaldrive.fill"
        case .autostartDisk:
            return "play.circle.fill"
        case .insertTape:
            return "recordingtape"
        case .autostartTape:
            return "play.circle.fill"
        }
    }
}

struct MediaReference: Identifiable, Equatable {
    let id: UUID
    let title: String
    let originalFilename: String
    let mediaType: LibraryMediaType
    let url: URL
    let isTemporary: Bool
    var libraryItemID: UUID?
    var addedLibraryItemID: UUID?
}

struct MediaActionRequest: Identifiable, Equatable {
    let id: UUID
    let media: MediaReference
    let actions: [MediaAction]

    init(media: MediaReference, actions: [MediaAction]) {
        id = UUID()
        self.media = media
        self.actions = actions
    }
}

struct MediaReplacementInfo: Equatable {
    let existingTitle: String
    let destination: String
}

struct MountedDiskSetInfo: Identifiable, Equatable {
    let unit: Int
    let displayName: String
    let members: [LibraryItem]
    let currentIndex: Int

    var id: Int { unit }

    var currentItem: LibraryItem {
        members[currentIndex]
    }

    var currentMemberLabel: String {
        currentItem.mediaSetDescriptor?.memberLabel ?? currentItem.title
    }

    var positionLabel: String {
        "Disk \(currentIndex + 1) of \(members.count)"
    }

    var hasPrevious: Bool {
        currentIndex > 0
    }

    var hasNext: Bool {
        currentIndex + 1 < members.count
    }
}

struct TemporaryMediaInfo: Identifiable, Equatable {
    let id: UUID
    let title: String
    let originalFilename: String
    let mediaType: LibraryMediaType
    let addedLibraryItemID: UUID?
}

@MainActor
final class EmulatorModel: ObservableObject {
    @Published private(set) var status = "Core not started"
    @Published private(set) var isRunning = false
    @Published private(set) var isPoweredOn = false
    @Published private(set) var isPowerTransitioning = false
    @Published private(set) var firmwareReady = false
    @Published private(set) var isStarting = false
    @Published private(set) var videoAspectRatio: CGFloat = 4.0 / 3.0
    @Published private(set) var videoFrameAspectRatio: CGFloat = 4.0 / 3.0
    @Published private(set) var powerOffVideoAspectRatio: CGFloat = 4.0 / 3.0
    @Published private(set) var powerOffVideoContentAspectRatio: CGFloat = 4.0 / 3.0
    @Published private(set) var temporaryNoBorderEnabled = false
    @Published private(set) var temporaryNoBorderLayoutAspectRatio: CGFloat?
    @Published var presentedError: String?
    @Published private(set) var joyport1Assignment: JoyportAssignment = .none
    @Published private(set) var joyport2Assignment: JoyportAssignment = .none
    @Published private(set) var mouseResetRecommendation: MouseResetRecommendation?
    @Published private(set) var physicalControllers: [PhysicalControllerInfo] = []
    @Published private(set) var hasPhysicalMouse = false
    @Published private(set) var mountedDisks: [Int: MediaReference] = [:]
    @Published private(set) var mountedTape: MediaReference?
    @Published private(set) var mountedCartridge: MediaReference?
    @Published private(set) var activeProgram: MediaReference?
    @Published private(set) var trueDriveEmulationConfigured = false
    @Published private(set) var drive9Configured = false
    @Published private(set) var drive8ActivityLEDOn = false
    @Published private(set) var datasetteTelemetryAvailable = false
    @Published private(set) var datasetteEnabled = false
    @Published private(set) var datasetteTransportState: DatasetteTransportState = .stopped
    @Published private(set) var datasetteCounter = 0
    @Published private(set) var datasetteMotorOn = false
    @Published private(set) var datasetteActivityLEDOn = false
    @Published private(set) var virtualModemTelemetryAvailable = false
    @Published private(set) var virtualModemConnected = false
    @Published private(set) var virtualModemTXBytes: UInt64 = 0
    @Published private(set) var virtualModemRXBytes: UInt64 = 0
    @Published private(set) var virtualModemReady = false
    @Published private(set) var virtualModemCommandMode = true
    @Published private(set) var virtualModemTelnetEnabled = true
    @Published private(set) var virtualModemEndpoint = ""
    @Published private(set) var virtualModemLastResult = ""
    @Published private(set) var virtualModemTraceBytes: [UInt8] = []
    @Published private(set) var virtualModemTraceDirections: [UInt8] = []

    var drive8PowerLEDOn: Bool {
        isRunning && trueDriveEmulationConfigured
    }

    var drive9PowerLEDOn: Bool {
        isRunning && trueDriveEmulationConfigured && drive9Configured
    }

    var driveActivityLEDOn: Bool {
        drive8ActivityLEDOn
    }

    var mountedTapeSupportsPhysicalTransport: Bool {
        mountedTape?.mediaType == .tap
    }

    var datasetteCounterDisplay: String {
        guard let tape = mountedTape else { return "---" }
        guard tape.mediaType == .tap else { return "T64" }
        guard datasetteTelemetryAvailable else { return "---" }
        return String(format: "%03d", min(999, max(0, datasetteCounter)))
    }

    var datasetteFormatSummary: String {
        guard let tape = mountedTape else { return "No tape" }
        switch tape.mediaType {
        case .tap:
            return "TAP · physical tape image"
        case .t64:
            return "T64 · read-only container"
        default:
            return tape.mediaType.displayName
        }
    }

    let session = LibretroSession()
    let library = LibraryStore()

    var availableDriveUnits: [Int] {
        drive9Configured ? [8, 9] : [8]
    }

    private var didAttemptAutomaticStart = false
    private var virtualJoypadMask: UInt32 = 0
    private var controllerMasks: [UUID: UInt32] = [:]
    private var controllerObjects: [UUID: GCController] = [:]
    private var controllerIDs: [ObjectIdentifier: UUID] = [:]
    private var configuredMouseIDs: Set<ObjectIdentifier> = []
    private var notificationTokens: [NSObjectProtocol] = []
    private var configuredMousePort = 0
    private var driveLEDOffTask: Task<Void, Never>?
    private var persistentCheckpointTask: Task<Void, Never>?
    private var persistentSessionRestoreAttempted = false

    private static let machinePowerStateKey = "poke64.machine.poweredOn"
    private static let machinePowerAspectRatioKey = "poke64.machine.powerOffAspectRatio"
    private static let machinePowerContentAspectRatioKey = "poke64.machine.powerOffContentAspectRatio"

    init() {
        let hasStoredPowerState = UserDefaults.standard.object(forKey: Self.machinePowerStateKey) != nil
        if hasStoredPowerState {
            isPoweredOn = UserDefaults.standard.bool(forKey: Self.machinePowerStateKey)
        }
        let storedPowerOffAspectRatio = UserDefaults.standard.double(forKey: Self.machinePowerAspectRatioKey)
        if storedPowerOffAspectRatio.isFinite, storedPowerOffAspectRatio > 0 {
            powerOffVideoAspectRatio = CGFloat(storedPowerOffAspectRatio)
        }
        let storedPowerOffContentAspectRatio = UserDefaults.standard.double(
            forKey: Self.machinePowerContentAspectRatioKey
        )
        if storedPowerOffContentAspectRatio.isFinite, storedPowerOffContentAspectRatio > 0 {
            videoFrameAspectRatio = CGFloat(storedPowerOffContentAspectRatio)
            powerOffVideoContentAspectRatio = CGFloat(storedPowerOffContentAspectRatio)
        }

        session.videoGeometryDidChange = { [weak self] aspectRatio in
            guard aspectRatio.isFinite, aspectRatio > 0 else { return }
            Task { @MainActor in
                guard let self else { return }
                self.videoAspectRatio = CGFloat(aspectRatio)
                if !self.isPowerTransitioning {
                    self.powerOffVideoAspectRatio = CGFloat(aspectRatio)
                    UserDefaults.standard.set(
                        aspectRatio,
                        forKey: Self.machinePowerAspectRatioKey
                    )
                }
            }
        }
        session.videoFrameAspectRatioDidChange = { [weak self] aspectRatio in
            guard aspectRatio.isFinite, aspectRatio > 0 else { return }
            Task { @MainActor in
                guard let self else { return }
                self.videoFrameAspectRatio = CGFloat(aspectRatio)
                if !self.isPowerTransitioning {
                    self.powerOffVideoContentAspectRatio = CGFloat(aspectRatio)
                    UserDefaults.standard.set(
                        aspectRatio,
                        forKey: Self.machinePowerContentAspectRatioKey
                    )
                }
            }
        }
        session.driveLEDStateDidChange = { [weak self] active in
            Task { @MainActor in
                guard let self else { return }
                self.driveLEDOffTask?.cancel()
                self.driveLEDOffTask = nil

                guard self.trueDriveEmulationConfigured else {
                    self.drive8ActivityLEDOn = false
                    return
                }

                if active {
                    self.drive8ActivityLEDOn = true
                    return
                }

                self.driveLEDOffTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(160))
                    guard !Task.isCancelled, let self else { return }
                    self.drive8ActivityLEDOn = false
                    self.driveLEDOffTask = nil
                }
            }
        }
        session.datasetteLEDStateDidChange = { [weak self] active in
            Task { @MainActor in
                self?.datasetteActivityLEDOn = active
            }
        }
        session.datasetteStateDidChange = { [weak self] available, enabled, control, counter, motorOn in
            Task { @MainActor in
                guard let self else { return }
                self.datasetteTelemetryAvailable = available
                self.datasetteEnabled = enabled
                self.datasetteTransportState = DatasetteTransportState(control: control)
                self.datasetteCounter = min(999, max(0, counter))
                self.datasetteMotorOn = motorOn
            }
        }
        session.virtualModemStateDidChange = { [weak self] available, connected, txBytes, rxBytes in
            Task { @MainActor in
                guard let self else { return }
                self.virtualModemTelemetryAvailable = available
                self.virtualModemConnected = connected
                self.virtualModemTXBytes = txBytes
                self.virtualModemRXBytes = rxBytes
            }
        }
        session.virtualModemDiagnosticsDidChange = { [weak self] ready, commandMode, telnetEnabled, endpoint, lastResult, traceBytes, traceDirections in
            Task { @MainActor in
                guard let self else { return }
                self.virtualModemReady = ready
                self.virtualModemCommandMode = commandMode
                self.virtualModemTelnetEnabled = telnetEnabled
                self.virtualModemEndpoint = endpoint
                self.virtualModemLastResult = lastResult
                self.virtualModemTraceBytes = Array(traceBytes)
                self.virtualModemTraceDirections = Array(traceDirections)
            }
        }

        Self.cleanTemporaryMediaDirectory()
        observeInputDevices()
        refreshPhysicalControllers()
        refreshPhysicalMice()
        syncInputConfiguration()

        FirmwareStore.prepareDirectoriesAndConfiguration()
        refreshFirmwareState()
        refreshDriveConfigurationState()
        if !hasStoredPowerState {
            // A genuinely new installation waits at the powered-off CRT until
            // firmware is configured. Upgrades that already have valid ROMs keep
            // the historical start-on-launch behavior.
            isPoweredOn = firmwareReady
            UserDefaults.standard.set(isPoweredOn, forKey: Self.machinePowerStateKey)
        }
        if !firmwareReady {
            status = "Firmware required"
        }
    }

    var temporaryMediaItems: [TemporaryMediaInfo] {
        uniqueMediaReferences
            .filter(\.isTemporary)
            .map {
                TemporaryMediaInfo(
                    id: $0.id,
                    title: $0.title,
                    originalFilename: $0.originalFilename,
                    mediaType: $0.mediaType,
                    addedLibraryItemID: $0.addedLibraryItemID
                )
            }
    }

    var mountedLibraryItemIDs: Set<UUID> {
        Set(uniqueMediaReferences.compactMap(\.libraryItemID))
    }

    var mountedDiskSetUnits: [Int] {
        availableDriveUnits.filter { mountedDiskSetInfo(for: $0) != nil }
    }

    func mountedDiskSetInfo(for unit: Int) -> MountedDiskSetInfo? {
        guard let mounted = mountedDisks[unit],
              let libraryItemID = mounted.libraryItemID,
              let currentItem = library.item(withID: libraryItemID),
              let descriptor = currentItem.mediaSetDescriptor else {
            return nil
        }

        let members = library.mediaSetMembers(for: currentItem)
        guard members.count > 1,
              let currentIndex = members.firstIndex(where: { $0.id == currentItem.id }) else {
            return nil
        }

        return MountedDiskSetInfo(
            unit: unit,
            displayName: descriptor.displayName,
            members: members,
            currentIndex: currentIndex
        )
    }

    func selectDiskSetMember(_ item: LibraryItem, in unit: Int) {
        do {
            let request = try actionRequest(for: item)
            try performMediaAction(
                .insertDisk(unit),
                media: request.media,
                replacingExisting: true
            )
        } catch {
            present(error)
        }
    }

    func selectAdjacentDisk(in unit: Int, offset: Int) {
        guard let info = mountedDiskSetInfo(for: unit) else { return }
        let targetIndex = info.currentIndex + offset
        guard info.members.indices.contains(targetIndex) else { return }
        selectDiskSetMember(info.members[targetIndex], in: unit)
    }

    func attach(videoView: C64MetalView) {
        session.videoView = videoView
    }

    func attach(crtPreviewVideoView: C64MetalView?) {
        session.videoView?.crtPreviewMirror = crtPreviewVideoView
    }

    func captureCurrentVideoFrame() -> Data? {
        session.videoView?.captureCurrentFramePNGData()
    }

    func startAutomatically() async {
        guard !didAttemptAutomaticStart else { return }
        didAttemptAutomaticStart = true

        if !isPoweredOn,
           firmwareReady,
           FirmwareProfileStore.initialAutoPowerOnPending {
            FirmwareProfileStore.consumeInitialAutoPowerOnPending()
            await powerOn()
            return
        }

        guard isPoweredOn else {
            PersistentSessionStore.clear()
            status = firmwareReady ? "C64 powered off" : "Firmware required"
            return
        }

        if await restorePersistentSessionIfAvailable() {
            return
        }

        refreshFirmwareState()
        guard firmwareReady else {
            status = "Import BASIC, KERNAL and character ROMs"
            return
        }

        await startEmpty()
    }

    func startEmpty() async {
        presentedError = nil
        refreshFirmwareState()
        refreshDriveConfigurationState()
        guard firmwareReady else {
            isRunning = false
            isStarting = false
            status = "Firmware required"
            return
        }

        isStarting = true
        status = "Starting C64…"
        defer { isStarting = false }

        await Task.yield()
        try? await Task.sleep(for: .milliseconds(120))

        if session.startWithoutContent() {
            clearMediaState(removeTemporaryFiles: true)
            isRunning = true
            syncInputConfiguration()
            startPersistentCheckpointLoop()
            status = "C64 started"
        } else {
            isRunning = false
            let message = session.lastErrorMessage ?? "Unable to start the core"
            status = Self.errorSummary(message)
            presentedError = message
        }
    }

    func prepareTemporaryMedia(url: URL) -> MediaActionRequest? {
        do {
            presentedError = nil
            refreshFirmwareState()
            guard firmwareReady else {
                throw EmulatorModelError.firmwareRequired
            }

            let copiedMedia = try copyToTemporaryMediaDirectory(sourceURL: url)
            let media = MediaReference(
                id: UUID(),
                title: Self.displayTitle(for: url),
                originalFilename: url.lastPathComponent,
                mediaType: copiedMedia.mediaType,
                url: copiedMedia.url,
                isTemporary: true,
                libraryItemID: nil,
                addedLibraryItemID: nil
            )
            return makeActionRequest(for: media)
        } catch {
            present(error)
            return nil
        }
    }

    func actionRequest(for item: LibraryItem) throws -> MediaActionRequest {
        let url = try library.mediaURL(for: item)
        let media = MediaReference(
            id: item.id,
            title: item.title,
            originalFilename: item.originalFilename,
            mediaType: item.mediaType,
            url: url,
            isTemporary: false,
            libraryItemID: item.id,
            addedLibraryItemID: nil
        )
        return makeActionRequest(for: media)
    }

    func replacementInfo(
        for action: MediaAction,
        media: MediaReference
    ) -> MediaReplacementInfo? {
        let existing: MediaReference?
        let destination: String

        switch action {
        case .insertDisk(let unit), .autostartDisk(let unit):
            existing = mountedDisks[unit]
            destination = "Drive \(unit)"
        case .insertTape, .autostartTape:
            existing = mountedTape
            destination = "the datasette"
        case .insertCartridgeAndReset:
            existing = mountedCartridge
            destination = "the cartridge port"
        case .runProgram:
            return nil
        }

        guard let existing, existing.id != media.id else { return nil }
        if let existingLibraryItemID = existing.libraryItemID,
           existingLibraryItemID == media.libraryItemID {
            return nil
        }
        return MediaReplacementInfo(
            existingTitle: existing.originalFilename,
            destination: destination
        )
    }

    func performMediaAction(
        _ action: MediaAction,
        media: MediaReference,
        replacingExisting: Bool = false
    ) throws {
        presentedError = nil
        refreshFirmwareState()
        guard firmwareReady else {
            throw EmulatorModelError.firmwareRequired
        }
        guard isRunning else {
            throw EmulatorModelError.coreNotRunning
        }

        let effectiveAction: MediaAction
        if action == .insertTape, media.mediaType == .t64 {
            effectiveAction = .autostartTape
        } else {
            effectiveAction = action
        }

        try validateDiskCompatibility(for: effectiveAction, media: media)

        if !replacingExisting,
           let replacement = replacementInfo(for: effectiveAction, media: media) {
            throw EmulatorModelError.replacementRequired(
                replacement.existingTitle,
                replacement.destination
            )
        }

        let replacedMedia: MediaReference?
        let programReleasedByReset: MediaReference?
        let success: Bool

        switch effectiveAction {
        case .runProgram:
            replacedMedia = activeProgram
            programReleasedByReset = nil
            success = session.runProgram(at: media.url)

        case .insertCartridgeAndReset:
            replacedMedia = mountedCartridge
            programReleasedByReset = activeProgram
            success = session.attachCartridge(at: media.url)

        case .insertDisk(let unit):
            replacedMedia = mountedDisks[unit]
            programReleasedByReset = nil
            success = session.attachDisk(at: media.url, driveUnit: unit)

        case .autostartDisk(let unit):
            replacedMedia = mountedDisks[unit]
            programReleasedByReset = activeProgram
            success = session.autostartDisk(at: media.url, driveUnit: unit)

        case .insertTape:
            replacedMedia = mountedTape
            programReleasedByReset = nil
            success = session.attachTape(at: media.url)

        case .autostartTape:
            replacedMedia = mountedTape
            programReleasedByReset = activeProgram
            success = session.autostartTape(at: media.url)
        }

        guard success else {
            throw EmulatorModelError.coreFailure(
                session.lastErrorMessage ?? "Unable to complete the media operation"
            )
        }

        switch effectiveAction {
        case .runProgram:
            activeProgram = media
            status = "Running program: \(media.title)"

        case .insertCartridgeAndReset:
            activeProgram = nil
            mountedCartridge = media
            status = "Cartridge inserted: \(media.title)"

        case .insertDisk(let unit):
            mountedDisks[unit] = media
            status = "Inserted in Drive \(unit): \(media.title)"

        case .autostartDisk(let unit):
            activeProgram = nil
            mountedDisks[unit] = media
            status = "Autostarting from Drive \(unit): \(media.title)"

        case .insertTape:
            mountedTape = media
            resetDatasettePresentation(for: media)
            resetTapeCounterAfterInsertionIfNeeded(media)
            status = "Tape inserted: \(media.title)"

        case .autostartTape:
            activeProgram = nil
            mountedTape = media
            resetDatasettePresentation(for: media)
            resetTapeCounterAfterInsertionIfNeeded(media)
            status = media.mediaType == .t64
                ? "Autostarting T64: \(media.title)"
                : "Autostarting tape: \(media.title)"
        }

        if let itemID = media.libraryItemID,
           let item = library.item(withID: itemID) {
            do {
                try library.markOpened(item)
            } catch {
                print("Unable to update library recents: \(error)")
            }
        }

        if let replacedMedia, replacedMedia.id != media.id {
            removeTemporaryFileIfUnused(replacedMedia)
        }
        if let programReleasedByReset, programReleasedByReset.id != media.id {
            removeTemporaryFileIfUnused(programReleasedByReset)
        }
    }

    func discardPreparedMedia(_ media: MediaReference) {
        removeTemporaryFileIfUnused(media)
    }

    func presentMediaError(_ error: Error) {
        present(error)
    }

    func reportCreatedDisk(_ item: LibraryItem) {
        status = "Created \(item.mediaType.displayName): \(item.title)"
    }

    @discardableResult
    func addTemporaryMediaToLibrary(id: UUID) throws -> LibraryItem {
        guard let media = uniqueMediaReferences.first(where: { $0.id == id && $0.isTemporary }) else {
            throw EmulatorModelError.noTemporaryMedia
        }

        if let itemID = media.addedLibraryItemID,
           let existingItem = library.item(withID: itemID) {
            return existingItem
        }

        let item = try library.importMedia(
            from: media.url,
            originalFilename: media.originalFilename
        )
        updateMediaReference(id: media.id) {
            $0.libraryItemID = item.id
            $0.addedLibraryItemID = item.id
        }
        do {
            try library.markOpened(item)
        } catch {
            print("Unable to update library recents: \(error)")
        }
        status = "Added to Library: \(item.title)"
        return item
    }

    @discardableResult
    func importIntoLibrary(url: URL) throws -> LibraryItem {
        let item = try library.importMedia(from: url)
        status = "Imported: \(item.title)"
        return item
    }

    @discardableResult
    func importIntoLibrary(
        inspection: LibraryImportInspection,
        resolution: LibraryImportResolution
    ) throws -> LibraryItem {
        let item = try library.importMedia(inspection, resolution: resolution)
        switch resolution {
        case .replaceExisting:
            status = "Replaced library media: \(item.title)"
        case .useExisting:
            status = "Using existing library media: \(item.title)"
        case .keepBoth:
            status = "Imported: \(item.title)"
        }
        return item
    }

    func settingsDidClose(previousFirmwareFingerprint: String) async {
        FirmwareStore.prepareDirectoriesAndConfiguration()
        refreshFirmwareState()
        refreshDriveConfigurationState()

        if !isPoweredOn,
           firmwareReady,
           FirmwareProfileStore.initialAutoPowerOnPending {
            FirmwareProfileStore.consumeInitialAutoPowerOnPending()
            await powerOn()
            return
        }

        guard FirmwareStore.configurationFingerprint != previousFirmwareFingerprint else {
            return
        }

        if isRunning {
            session.stop()
            isRunning = false
            temporaryNoBorderEnabled = false
            temporaryNoBorderLayoutAspectRatio = nil
            clearMediaState(removeTemporaryFiles: true)
        }

        guard isPoweredOn else {
            isStarting = false
            status = firmwareReady ? "C64 powered off" : "Firmware required"
            return
        }

        if firmwareReady {
            await startEmpty()
        } else {
            isStarting = false
            status = "Import BASIC, KERNAL and character ROMs"
        }
    }

    func flushPrinterOutput() throws {
        guard isRunning else { return }
        guard session.flushPrinter(atDevice: C64PrinterSettings.device) else {
            throw EmulatorModelError.coreFailure(
                session.lastErrorMessage ?? "Unable to flush the printer output"
            )
        }
    }

    func snapshotPrinterOutput() throws {
        guard isRunning else { return }
        if C64PrinterSettings.exportFormat.usesRasterRenderer {
            guard session.snapshotPrinter(atDevice: C64PrinterSettings.device) else {
                throw EmulatorModelError.coreFailure(
                    session.lastErrorMessage ?? "Unable to refresh the printer preview"
                )
            }
        } else {
            try flushPrinterOutput()
        }
    }

    func clearPrinterCapture() async throws {
        // A real form feed resets the MPS-803 interpreter to the top of the
        // next sheet. The finalized page is then deleted instead of exported.
        try flushPrinterOutput()
        try C64PrinterOutputStore.discardActiveOutput(
            device: C64PrinterSettings.device
        )
        status = "Printer paper discarded"
    }

    func ejectPrinterPaper() async throws -> [URL] {
        try flushPrinterOutput()
        let outputURLs = try C64PrinterOutputStore.ejectOutput(
            device: C64PrinterSettings.device,
            format: C64PrinterSettings.exportFormat,
            intensity: C64PrinterSettings.dotIntensity
        )
        status = "Printer paper ejected"
        return outputURLs
    }

    func dialVirtualModem(host: String, port: Int, telnet: Bool) throws {
        guard isRunning else {
            throw EmulatorModelError.coreFailure("The C64 core is not running")
        }
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty, (1...65535).contains(port) else {
            throw EmulatorModelError.coreFailure("Enter a valid BBS host and TCP port")
        }
        let target = "\(trimmedHost):\(port)"
        guard session.dialVirtualModem(target: target, telnet: telnet) else {
            throw EmulatorModelError.coreFailure(
                session.lastErrorMessage ?? "Unable to dial the selected BBS"
            )
        }
        status = "Dialing \(target)"
    }

    func hangUpVirtualModem() throws {
        guard isRunning else { return }
        guard session.hangUpVirtualModem() else {
            throw EmulatorModelError.coreFailure(
                session.lastErrorMessage ?? "Unable to hang up the virtual modem"
            )
        }
        status = "Virtual modem hung up"
    }

    func clearVirtualModemTraffic() throws {
        guard isRunning else { return }
        guard session.clearVirtualModemTraffic() else {
            throw EmulatorModelError.coreFailure(
                session.lastErrorMessage ?? "Unable to clear modem traffic"
            )
        }
        virtualModemTraceBytes = []
        virtualModemTraceDirections = []
    }

    func handleScenePhase(_ phase: ScenePhase) async {
        switch phase {
        case .active:
            guard isRunning else { return }
            session.setSuspended(false)

        case .inactive:
            guard isRunning else { return }
            session.setSuspended(true)

        case .background:
            guard isRunning else { return }
            session.setSuspended(true)
            checkpointPersistentSession(reportFailure: false)

        @unknown default:
            break
        }
    }

    func checkpointPersistentSession(reportFailure: Bool = false) {
        guard isRunning else { return }

        do {
            let disks = try mountedDisks.keys.sorted().compactMap { unit -> PersistentSessionDiskDescriptor? in
                guard let media = mountedDisks[unit] else { return nil }
                return PersistentSessionDiskDescriptor(
                    unit: unit,
                    media: try PersistentSessionStore.descriptor(for: media)
                )
            }
            let tape = try mountedTape.map(PersistentSessionStore.descriptor(for:))
            let cartridge = try mountedCartridge.map(PersistentSessionStore.descriptor(for:))
            let program = try activeProgram.map(PersistentSessionStore.descriptor(for:))

            guard let state = session.serializeState() else {
                throw EmulatorModelError.coreFailure(
                    session.lastErrorMessage ?? "Unable to save the current POKE64 session"
                )
            }

            let metadata = PersistentSessionMetadata(
                version: PersistentSessionMetadata.schemaVersion,
                savedAt: Date(),
                appVersion: PersistentSessionStore.currentAppVersion,
                configurationFingerprint: FirmwareStore.configurationFingerprint,
                emulationProfileID: EmulationProfileStore.selectedProfileID,
                firmwareProfileID: FirmwareProfileStore.activeProfileID,
                disks: disks,
                tape: tape,
                cartridge: cartridge,
                activeProgram: program,
                stateByteCount: state.count
            )
            try PersistentSessionStore.save(state: state, metadata: metadata)
        } catch {
            if reportFailure {
                present(error)
            } else {
                print("Unable to checkpoint persistent POKE64 session: \(error)")
            }
        }
    }

    private func startPersistentCheckpointLoop() {
        persistentCheckpointTask?.cancel()
        persistentCheckpointTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled, let self, self.isRunning else { continue }
                self.checkpointPersistentSession(reportFailure: false)
            }
        }
    }

    private func restorePersistentSessionIfAvailable() async -> Bool {
        guard !persistentSessionRestoreAttempted else { return false }
        persistentSessionRestoreAttempted = true

        let archive: PersistentSessionArchive
        do {
            guard let loaded = try PersistentSessionStore.load() else { return false }
            archive = loaded
        } catch {
            print("Ignoring invalid previous POKE64 session: \(error)")
            PersistentSessionStore.clear()
            return false
        }

        guard archive.metadata.appVersion == PersistentSessionStore.currentAppVersion else {
            PersistentSessionStore.clear()
            return false
        }

        FirmwareStore.prepareDirectoriesAndConfiguration()
        refreshFirmwareState()
        refreshDriveConfigurationState()

        guard firmwareReady,
              archive.metadata.configurationFingerprint == FirmwareStore.configurationFingerprint else {
            PersistentSessionStore.clear()
            return false
        }

        do {
            let restoredDisks = try Dictionary(uniqueKeysWithValues: archive.metadata.disks.map { descriptor in
                (descriptor.unit, try persistentMediaReference(from: descriptor.media))
            })
            let restoredTape = try archive.metadata.tape.map(persistentMediaReference(from:))
            let restoredCartridge = try archive.metadata.cartridge.map(persistentMediaReference(from:))
            let restoredProgram = try archive.metadata.activeProgram.map(persistentMediaReference(from:))

            isStarting = true
            status = "Restoring previous session…"
            defer { isStarting = false }

            await Task.yield()
            guard session.startWithoutContent() else {
                throw EmulatorModelError.coreFailure(
                    session.lastErrorMessage ?? "Unable to start VICE for session restore"
                )
            }

            for unit in restoredDisks.keys.sorted() {
                guard let media = restoredDisks[unit],
                      session.attachDisk(at: media.url, driveUnit: unit) else {
                    throw EmulatorModelError.coreFailure(
                        session.lastErrorMessage ?? "Unable to restore Drive \(unit) media"
                    )
                }
            }
            if let restoredTape, !session.attachTape(at: restoredTape.url) {
                throw EmulatorModelError.coreFailure(
                    session.lastErrorMessage ?? "Unable to restore the mounted tape"
                )
            }
            if let restoredCartridge, !session.attachCartridge(at: restoredCartridge.url) {
                throw EmulatorModelError.coreFailure(
                    session.lastErrorMessage ?? "Unable to restore the mounted cartridge"
                )
            }

            guard session.unserializeState(archive.state) else {
                throw EmulatorModelError.coreFailure(
                    session.lastErrorMessage ?? "Unable to restore the previous POKE64 session"
                )
            }

            mountedDisks = restoredDisks
            mountedTape = restoredTape
            mountedCartridge = restoredCartridge
            activeProgram = restoredProgram
            resetDatasettePresentation(for: restoredTape)
            isRunning = true
            syncInputConfiguration()

            // Network sockets cannot be serialized across process launches.
            // Ensure a restored terminal sees a disconnected virtual modem.
            _ = session.hangUpVirtualModem()

            session.setSuspended(false)
            startPersistentCheckpointLoop()
            status = "Previous session restored"
            return true
        } catch {
            print("Unable to restore previous POKE64 session: \(error)")
            session.stop()
            isRunning = false
            clearMediaState(removeTemporaryFiles: false)
            PersistentSessionStore.clear()
            return false
        }
    }

    private func persistentMediaReference(
        from descriptor: PersistentSessionMediaDescriptor
    ) throws -> MediaReference {
        let url: URL
        let isTemporary: Bool

        if let libraryItemID = descriptor.libraryItemID {
            guard let item = library.item(withID: libraryItemID) else {
                throw PersistentSessionStoreError.mediaUnavailable(descriptor.originalFilename)
            }
            url = try library.mediaURL(for: item)
            isTemporary = false
        } else {
            url = try PersistentSessionStore.mediaURL(for: descriptor)
            isTemporary = false
        }

        return MediaReference(
            id: descriptor.id,
            title: descriptor.title,
            originalFilename: descriptor.originalFilename,
            mediaType: descriptor.mediaType,
            url: url,
            isTemporary: isTemporary,
            libraryItemID: descriptor.libraryItemID,
            addedLibraryItemID: nil
        )
    }

    func powerOff() async {
        guard isPoweredOn || isRunning else { return }
        guard !isPowerTransitioning else { return }

        persistentCheckpointTask?.cancel()
        persistentCheckpointTask = nil
        PersistentSessionStore.clear()

        // Keep the final video frame and its exact geometry stable while the UI
        // performs the CRT power-down collapse.  VICE may report a fallback
        // geometry while shutting down, which must not resize the powered-off CRT.
        powerOffVideoAspectRatio = videoAspectRatio
        powerOffVideoContentAspectRatio = videoFrameAspectRatio
        UserDefaults.standard.set(
            Double(powerOffVideoAspectRatio),
            forKey: Self.machinePowerAspectRatioKey
        )
        UserDefaults.standard.set(
            Double(powerOffVideoContentAspectRatio),
            forKey: Self.machinePowerContentAspectRatioKey
        )
        isPowerTransitioning = true
        status = "Powering off C64…"
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(2200))

        let previousProgram = activeProgram
        activeProgram = nil

        if isRunning {
            session.stop()
        }
        isRunning = false
        temporaryNoBorderEnabled = false
        temporaryNoBorderLayoutAspectRatio = nil
        isPoweredOn = false
        isPowerTransitioning = false
        UserDefaults.standard.set(false, forKey: Self.machinePowerStateKey)

        driveLEDOffTask?.cancel()
        driveLEDOffTask = nil
        drive8ActivityLEDOn = false
        datasetteTelemetryAvailable = false
        datasetteMotorOn = false
        datasetteActivityLEDOn = false
        virtualModemTelemetryAvailable = false
        virtualModemConnected = false
        virtualModemReady = false
        virtualModemCommandMode = true
        virtualModemEndpoint = ""
        virtualModemLastResult = ""
        virtualModemTraceBytes = []
        virtualModemTraceDirections = []

        if let previousProgram {
            removeTemporaryFileIfUnused(previousProgram)
        }
        status = "C64 powered off"
    }

    func powerOn() async {
        guard !isRunning else {
            if !isPoweredOn {
                isPoweredOn = true
                UserDefaults.standard.set(true, forKey: Self.machinePowerStateKey)
            }
            return
        }

        presentedError = nil
        isPoweredOn = true
        UserDefaults.standard.set(true, forKey: Self.machinePowerStateKey)
        PersistentSessionStore.clear()

        do {
            _ = try EmulationProfileStore.applyPowerOnProfileIfConfigured()
        } catch {
            present(error)
            return
        }

        refreshFirmwareState()
        refreshDriveConfigurationState()
        guard firmwareReady else {
            status = "Import BASIC, KERNAL and character ROMs"
            return
        }

        isStarting = true
        isPowerTransitioning = true
        status = "Powering on C64…"
        defer {
            isStarting = false
            isPowerTransitioning = false
        }

        await Task.yield()

        guard session.startWithoutContent() else {
            let message = session.lastErrorMessage ?? "Unable to start the core"
            status = Self.errorSummary(message)
            presentedError = message
            return
        }

        do {
            try reattachMountedMediaAfterPowerOn()
            isRunning = true
            syncInputConfiguration()
            startPersistentCheckpointLoop()
            status = "C64 powered on"
        } catch {
            session.stop()
            isRunning = false
            present(error)
        }
    }

    func togglePower() async {
        if isPoweredOn {
            await powerOff()
        } else {
            await powerOn()
        }
    }

    private func reattachMountedMediaAfterPowerOn() throws {
        for unit in mountedDisks.keys.sorted() {
            guard let media = mountedDisks[unit] else { continue }
            guard session.attachDisk(at: media.url, driveUnit: unit) else {
                throw EmulatorModelError.coreFailure(
                    session.lastErrorMessage ?? "Unable to restore Drive \(unit) after power on"
                )
            }
        }

        if let mountedTape, !session.attachTape(at: mountedTape.url) {
            throw EmulatorModelError.coreFailure(
                session.lastErrorMessage ?? "Unable to restore the mounted tape after power on"
            )
        }

        if let mountedCartridge, !session.attachCartridge(at: mountedCartridge.url) {
            throw EmulatorModelError.coreFailure(
                session.lastErrorMessage ?? "Unable to restore the mounted cartridge after power on"
            )
        }

        resetDatasettePresentation(for: mountedTape)
    }

    func stop() {
        persistentCheckpointTask?.cancel()
        persistentCheckpointTask = nil
        PersistentSessionStore.clear()
        session.stop()
        isRunning = false
        temporaryNoBorderEnabled = false
        temporaryNoBorderLayoutAspectRatio = nil
        driveLEDOffTask?.cancel()
        driveLEDOffTask = nil
        drive8ActivityLEDOn = false
        clearMediaState(removeTemporaryFiles: true)
        status = firmwareReady ? "Core stopped" : "Firmware required"
    }

    func toggleTemporaryNoBorder() {
        guard isRunning, isPoweredOn, !isPowerTransitioning else { return }
        let enabled = !temporaryNoBorderEnabled
        if enabled {
            // Preserve the on-screen canvas footprint while VICE changes the
            // cropped video geometry. No-border should crop the source, not
            // unexpectedly expand the SwiftUI layout around it.
            temporaryNoBorderLayoutAspectRatio = videoAspectRatio
        }
        session.setTemporaryMaximumVideoCropEnabled(enabled)
        temporaryNoBorderEnabled = enabled
        if !enabled {
            temporaryNoBorderLayoutAspectRatio = nil
        }
        status = enabled ? "Temporary no-border view" : "Configured borders restored"
    }

    private func restoreConfiguredVideoCrop() {
        guard temporaryNoBorderEnabled else { return }
        session.setTemporaryMaximumVideoCropEnabled(false)
        temporaryNoBorderEnabled = false
        temporaryNoBorderLayoutAspectRatio = nil
    }

    func softReset() {
        guard isRunning else { return }
        restoreConfiguredVideoCrop()
        let previousProgram = activeProgram
        activeProgram = nil
        session.softReset()
        if let previousProgram {
            removeTemporaryFileIfUnused(previousProgram)
        }
        status = "Soft reset requested"
    }

    func hardReset() {
        guard isRunning else { return }
        restoreConfiguredVideoCrop()
        let previousProgram = activeProgram
        activeProgram = nil
        session.hardReset()
        if let previousProgram {
            removeTemporaryFileIfUnused(previousProgram)
        }
        status = "Hard reset requested"
    }

    func ejectDisk(from unit: Int) throws {
        guard let media = mountedDisks[unit] else { return }
        guard session.ejectDisk(fromDriveUnit: unit) else {
            throw EmulatorModelError.coreFailure(
                session.lastErrorMessage ?? "Unable to eject the disk"
            )
        }
        mountedDisks[unit] = nil
        removeTemporaryFileIfUnused(media)
        status = "Drive \(unit) ejected"
    }

    func controlDatasette(_ command: DatasetteTransportCommand) throws {
        guard let tape = mountedTape else {
            throw EmulatorModelError.coreFailure("No tape is inserted")
        }
        guard tape.mediaType == .tap else {
            throw EmulatorModelError.coreFailure(
                "T64 containers are launched through autostart and do not expose datasette transport controls"
            )
        }
        guard session.controlDatasette(command.coreCommand) else {
            throw EmulatorModelError.coreFailure(
                session.lastErrorMessage ?? "Unable to control the datasette"
            )
        }
        status = command.statusTitle
    }

    func ejectTape() throws {
        guard let media = mountedTape else { return }
        guard session.ejectTape() else {
            throw EmulatorModelError.coreFailure(
                session.lastErrorMessage ?? "Unable to eject the tape"
            )
        }
        mountedTape = nil
        resetDatasettePresentation(for: nil)
        removeTemporaryFileIfUnused(media)
        status = "Tape ejected"
    }

    func ejectCartridge() throws {
        guard let media = mountedCartridge else { return }
        guard session.ejectCartridge() else {
            throw EmulatorModelError.coreFailure(
                session.lastErrorMessage ?? "Unable to eject the cartridge"
            )
        }
        mountedCartridge = nil
        mouseResetRecommendation = nil
        removeTemporaryFileIfUnused(media)
        status = "Cartridge ejected"
    }

    func ejectAllMediaAndReset() {
        guard isRunning else { return }
        do {
            guard session.ejectAllMediaAndReset() else {
                throw EmulatorModelError.coreFailure(
                    session.lastErrorMessage ?? "Unable to eject all media"
                )
            }
            clearMediaState(removeTemporaryFiles: true)
            status = "All media ejected and C64 reset"
        } catch {
            present(error)
        }
    }

    var virtualJoystickPort: Int? {
        if joyport1Assignment == .virtualJoystick { return 1 }
        if joyport2Assignment == .virtualJoystick { return 2 }
        return nil
    }

    var mousePort: Int? {
        if joyport1Assignment == .commodoreMouse { return 1 }
        if joyport2Assignment == .commodoreMouse { return 2 }
        return nil
    }

    var externalMouseCaptureActive: Bool {
        isRunning && hasPhysicalMouse && mousePort != nil
    }

    func joyportAssignment(for port: Int) -> JoyportAssignment {
        port == 1 ? joyport1Assignment : joyport2Assignment
    }

    func joyportAssignmentTitle(for port: Int) -> String {
        assignmentTitle(joyportAssignment(for: port))
    }

    func joyportCompactAssignmentTitle(for port: Int) -> String {
        compactAssignmentTitle(joyportAssignment(for: port))
    }

    func swapJoyportAssignments() {
        let previousPort1 = joyport1Assignment
        joyport1Assignment = joyport2Assignment
        joyport2Assignment = previousPort1
        syncInputConfiguration()
        recommendMouseResetIfNeeded()
        status = "Joystick ports swapped"
    }

    func controllerAssignedPort(_ controllerID: UUID) -> Int? {
        if joyport1Assignment == .physicalController(controllerID) { return 1 }
        if joyport2Assignment == .physicalController(controllerID) { return 2 }
        return nil
    }

    func setJoyportAssignment(_ assignment: JoyportAssignment, for port: Int) {
        guard port == 1 || port == 2 else { return }

        switch assignment {
        case .none:
            setAssignment(.none, for: port)

        case .virtualJoystick:
            clearAssignment(.virtualJoystick, except: port)
            setAssignment(.virtualJoystick, for: port)

        case .commodoreMouse:
            clearAssignment(.commodoreMouse, except: port)
            setAssignment(.commodoreMouse, for: port)

        case .physicalController(let controllerID):
            guard controllerObjects[controllerID] != nil else { return }
            clearPhysicalController(controllerID, except: port)
            setAssignment(.physicalController(controllerID), for: port)
        }

        syncInputConfiguration()
        if assignment == .commodoreMouse {
            recommendMouseResetIfNeeded()
        } else if mousePort == nil {
            mouseResetRecommendation = nil
        }
        status = "Port \(port): \(assignmentTitle(assignment))"
    }

    func dismissMouseResetRecommendation() {
        mouseResetRecommendation = nil
    }

    func hardResetForMouseDetection() {
        guard mouseResetRecommendation != nil else { return }
        mouseResetRecommendation = nil
        hardReset()
        status = "Hard reset requested for Commodore 1351 mouse"
    }

    func setJoypad(_ button: C64JoypadButton, pressed: Bool) {
        guard virtualJoystickPort != nil else { return }
        let bit = UInt32(1) << UInt32(button.rawValue)
        if pressed {
            virtualJoypadMask |= bit
        } else {
            virtualJoypadMask &= ~bit
        }
        syncJoypadMasks()
    }

    func moveMouse(deltaX: CGFloat, deltaY: CGFloat) {
        guard mousePort != nil else { return }
        let x = Int(deltaX.rounded())
        let y = Int(deltaY.rounded())
        guard x != 0 || y != 0 else { return }
        session.addMouseDeltaX(x, deltaY: y)
    }

    func setMouseButton(_ button: Int, pressed: Bool) {
        guard mousePort != nil else { return }
        session.setMouseButton(button, pressed: pressed)
    }

    func setKey(_ key: C64KeyCode, pressed: Bool) {
        session.setKey(key, pressed: pressed)
    }

    func setRawKey(_ keyCode: UInt, pressed: Bool) {
        session.setRawKeyCode(keyCode, pressed: pressed)
    }

    private func setAssignment(_ assignment: JoyportAssignment, for port: Int) {
        if port == 1 {
            joyport1Assignment = assignment
        } else {
            joyport2Assignment = assignment
        }
    }

    private func clearAssignment(_ assignment: JoyportAssignment, except port: Int) {
        if port != 1, joyport1Assignment == assignment {
            joyport1Assignment = .none
        }
        if port != 2, joyport2Assignment == assignment {
            joyport2Assignment = .none
        }
    }

    private func clearPhysicalController(_ controllerID: UUID, except port: Int) {
        if port != 1, joyport1Assignment == .physicalController(controllerID) {
            joyport1Assignment = .none
        }
        if port != 2, joyport2Assignment == .physicalController(controllerID) {
            joyport2Assignment = .none
        }
    }

    private func assignmentTitle(_ assignment: JoyportAssignment) -> String {
        switch assignment {
        case .none:
            return "None"
        case .virtualJoystick:
            return "Virtual Joystick"
        case .commodoreMouse:
            return "Commodore 1351 Mouse"
        case .physicalController(let controllerID):
            return physicalControllers.first(where: { $0.id == controllerID })?.name
                ?? "Disconnected Controller"
        }
    }

    private func compactAssignmentTitle(_ assignment: JoyportAssignment) -> String {
        switch assignment {
        case .none:
            return "None"
        case .virtualJoystick:
            return "Virtual"
        case .commodoreMouse:
            return "Mouse"
        case .physicalController(let controllerID):
            return physicalControllers.first(where: { $0.id == controllerID })?.name
                ?? "Disconnected"
        }
    }

    private func syncInputConfiguration() {
        let selectedMousePort = mousePort ?? 0
        if configuredMousePort != selectedMousePort {
            configuredMousePort = selectedMousePort
            session.setMousePort(selectedMousePort)
        }
        syncJoypadMasks()
    }

    private func recommendMouseResetIfNeeded() {
        guard isRunning,
              let port = mousePort,
              let cartridge = mountedCartridge else {
            mouseResetRecommendation = nil
            return
        }

        mouseResetRecommendation = MouseResetRecommendation(
            port: port,
            cartridgeTitle: cartridge.title
        )
    }

    private func syncJoypadMasks() {
        session.setJoypadMask(joypadMask(for: 1), forC64Port: 1)
        session.setJoypadMask(joypadMask(for: 2), forC64Port: 2)
    }

    private func joypadMask(for port: Int) -> UInt32 {
        switch joyportAssignment(for: port) {
        case .virtualJoystick:
            return virtualJoypadMask
        case .physicalController(let controllerID):
            return controllerMasks[controllerID] ?? 0
        case .none, .commodoreMouse:
            return 0
        }
    }

    private func observeInputDevices() {
        let center = NotificationCenter.default

        notificationTokens.append(
            center.addObserver(
                forName: .GCControllerDidConnect,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.refreshPhysicalControllers()
                }
            }
        )

        notificationTokens.append(
            center.addObserver(
                forName: .GCControllerDidDisconnect,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.refreshPhysicalControllers()
                }
            }
        )

        notificationTokens.append(
            center.addObserver(
                forName: .GCMouseDidConnect,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.refreshPhysicalMice()
                }
            }
        )

        notificationTokens.append(
            center.addObserver(
                forName: .GCMouseDidDisconnect,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.refreshPhysicalMice()
                }
            }
        )
    }

    private func refreshPhysicalControllers() {
        let connected = GCController.controllers().filter { $0.extendedGamepad != nil }
        let connectedObjectIDs = Set(connected.map(ObjectIdentifier.init))
        let disconnectedIDs = controllerIDs
            .filter { !connectedObjectIDs.contains($0.key) }
            .map(\.value)

        for controllerID in disconnectedIDs {
            controllerMasks[controllerID] = nil
            controllerObjects[controllerID] = nil
            if joyport1Assignment == .physicalController(controllerID) {
                joyport1Assignment = .none
            }
            if joyport2Assignment == .physicalController(controllerID) {
                joyport2Assignment = .none
            }
        }

        controllerIDs = controllerIDs.filter { connectedObjectIDs.contains($0.key) }

        let baseNames = connected.map { $0.vendorName ?? "Game Controller" }
        let totals = Dictionary(grouping: baseNames, by: { $0 }).mapValues(\.count)
        var occurrences: [String: Int] = [:]
        var infos: [PhysicalControllerInfo] = []
        var objects: [UUID: GCController] = [:]

        for (index, controller) in connected.enumerated() {
            let objectID = ObjectIdentifier(controller)
            let controllerID = controllerIDs[objectID] ?? UUID()
            controllerIDs[objectID] = controllerID
            objects[controllerID] = controller

            let baseName = baseNames[index]
            occurrences[baseName, default: 0] += 1
            let displayName = totals[baseName, default: 0] > 1
                ? "\(baseName) #\(occurrences[baseName, default: 1])"
                : baseName

            infos.append(PhysicalControllerInfo(id: controllerID, name: displayName))
            configure(controller: controller, id: controllerID)
        }

        controllerObjects = objects
        physicalControllers = infos
        syncInputConfiguration()

        if !disconnectedIDs.isEmpty {
            status = "Controller disconnected"
        }
    }

    private func configure(controller: GCController, id: UUID) {
        guard let gamepad = controller.extendedGamepad else { return }

        gamepad.valueChangedHandler = { [weak self] profile, _ in
            let mask = Self.joypadMask(from: profile)
            Task { @MainActor in
                guard let self else { return }
                self.controllerMasks[id] = mask
                self.syncJoypadMasks()
            }
        }

        controllerMasks[id] = Self.joypadMask(from: gamepad)
    }

    private static func joypadMask(from gamepad: GCExtendedGamepad) -> UInt32 {
        let deadZone: Float = 0.45
        var mask: UInt32 = 0

        let up = gamepad.dpad.up.isPressed || gamepad.leftThumbstick.yAxis.value > deadZone
        let down = gamepad.dpad.down.isPressed || gamepad.leftThumbstick.yAxis.value < -deadZone
        let left = gamepad.dpad.left.isPressed || gamepad.leftThumbstick.xAxis.value < -deadZone
        let right = gamepad.dpad.right.isPressed || gamepad.leftThumbstick.xAxis.value > deadZone
        let fire = gamepad.buttonA.isPressed || gamepad.buttonB.isPressed

        if up { mask |= UInt32(1) << UInt32(C64JoypadButton.up.rawValue) }
        if down { mask |= UInt32(1) << UInt32(C64JoypadButton.down.rawValue) }
        if left { mask |= UInt32(1) << UInt32(C64JoypadButton.left.rawValue) }
        if right { mask |= UInt32(1) << UInt32(C64JoypadButton.right.rawValue) }
        if fire { mask |= UInt32(1) << UInt32(C64JoypadButton.fire.rawValue) }

        return mask
    }

    private func refreshPhysicalMice() {
        let mice = GCMouse.mice()
        hasPhysicalMouse = !mice.isEmpty
        let connectedIDs = Set(mice.map(ObjectIdentifier.init))
        configuredMouseIDs.formIntersection(connectedIDs)

        for mouse in mice {
            let identifier = ObjectIdentifier(mouse)
            guard !configuredMouseIDs.contains(identifier), let input = mouse.mouseInput else {
                continue
            }

            configuredMouseIDs.insert(identifier)

            input.mouseMovedHandler = { [weak self] _, deltaX, deltaY in
                Task { @MainActor in
                    self?.moveMouse(
                        deltaX: CGFloat(deltaX),
                        deltaY: CGFloat(-deltaY)
                    )
                }
            }

            input.leftButton.pressedChangedHandler = { [weak self] _, _, pressed in
                Task { @MainActor in
                    self?.setMouseButton(0, pressed: pressed)
                }
            }

            input.rightButton?.pressedChangedHandler = { [weak self] _, _, pressed in
                Task { @MainActor in
                    self?.setMouseButton(1, pressed: pressed)
                }
            }

            input.middleButton?.pressedChangedHandler = { [weak self] _, _, pressed in
                Task { @MainActor in
                    self?.setMouseButton(2, pressed: pressed)
                }
            }
        }
    }



    private func validateDiskCompatibility(
        for action: MediaAction,
        media: MediaReference
    ) throws {
        let unit: Int
        switch action {
        case .insertDisk(let selectedUnit), .autostartDisk(let selectedUnit):
            unit = selectedUnit
        case .runProgram, .insertCartridgeAndReset, .insertTape, .autostartTape:
            return
        }

        guard availableDriveUnits.contains(unit) else {
            throw EmulatorModelError.driveDisabled(unit)
        }
        let driveModel = C64DriveModel.selected(for: unit)

        if media.mediaType == .g64 {
            let compatible = driveModel == .cbm1541
                || driveModel == .cbm1541II
                || driveModel == .cbm1571
            guard compatible else {
                throw EmulatorModelError.incompatibleDiskImage(
                    unit: unit,
                    format: media.mediaType.displayName,
                    currentDrive: driveModel.title,
                    requiredDrive: "a Commodore 1541, 1541-II or 1571"
                )
            }
            return
        }

        guard let format = BlankDiskImageFormat(mediaType: media.mediaType) else {
            return
        }

        guard format.isCompatible(with: driveModel) else {
            throw EmulatorModelError.incompatibleDiskImage(
                unit: unit,
                format: format.displayName,
                currentDrive: driveModel.title,
                requiredDrive: format.requiredDriveDescription
            )
        }
    }

    private func makeActionRequest(for media: MediaReference) -> MediaActionRequest {
        let actions: [MediaAction]
        switch media.mediaType {
        case .prg:
            actions = [.runProgram]
        case .crt:
            actions = [.insertCartridgeAndReset]
        case .d64, .d71, .d81, .g64:
            actions = availableDriveUnits.flatMap { unit in
                [.insertDisk(unit), .autostartDisk(unit)]
            }
        case .tap:
            actions = [.insertTape, .autostartTape]
        case .t64:
            actions = [.autostartTape]
        }
        return MediaActionRequest(media: media, actions: actions)
    }

    private var uniqueMediaReferences: [MediaReference] {
        var seen: Set<UUID> = []
        var result: [MediaReference] = []
        let candidates = [activeProgram, mountedCartridge, mountedTape]
            .compactMap { $0 }
            + mountedDisks.keys.sorted().compactMap { mountedDisks[$0] }

        for media in candidates where seen.insert(media.id).inserted {
            result.append(media)
        }
        return result
    }

    private func updateMediaReference(
        id: UUID,
        mutation: (inout MediaReference) -> Void
    ) {
        if var media = activeProgram, media.id == id {
            mutation(&media)
            activeProgram = media
        }
        if var media = mountedCartridge, media.id == id {
            mutation(&media)
            mountedCartridge = media
        }
        if var media = mountedTape, media.id == id {
            mutation(&media)
            mountedTape = media
        }
        for unit in mountedDisks.keys {
            guard var media = mountedDisks[unit], media.id == id else { continue }
            mutation(&media)
            mountedDisks[unit] = media
        }
    }

    private func resetTapeCounterAfterInsertionIfNeeded(_ media: MediaReference) {
        guard media.mediaType == .tap,
              C64TapeSettings.resetCounterOnInsert else {
            return
        }
        if !session.controlDatasette(DatasetteTransportCommand.resetCounter.coreCommand) {
            print(session.lastErrorMessage ?? "Unable to reset the tape counter")
        }
    }

    private func resetDatasettePresentation(for media: MediaReference?) {
        datasetteTelemetryAvailable = false
        datasetteEnabled = media != nil
        datasetteTransportState = .stopped
        datasetteCounter = 0
        datasetteMotorOn = false
        datasetteActivityLEDOn = false
    }

    private func clearMediaState(removeTemporaryFiles: Bool) {
        activeProgram = nil
        mountedCartridge = nil
        mouseResetRecommendation = nil
        mountedTape = nil
        resetDatasettePresentation(for: nil)
        mountedDisks = [:]
        if removeTemporaryFiles {
            Self.cleanTemporaryMediaDirectory()
        }
    }

    private func removeTemporaryFileIfUnused(_ media: MediaReference) {
        guard media.isTemporary,
              !uniqueMediaReferences.contains(where: { $0.id == media.id }) else {
            return
        }
        try? FileManager.default.removeItem(at: media.url)
    }

    private func copyToTemporaryMediaDirectory(
        sourceURL: URL
    ) throws -> (url: URL, mediaType: LibraryMediaType) {
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

        let fileExtension = sourceURL.pathExtension.lowercased()
        guard let mediaType = LibraryMediaType(fileExtension: fileExtension) else {
            throw LibraryStoreError.unsupportedFormat(fileExtension)
        }

        let directoryURL = Self.temporaryMediaDirectoryURL
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let destinationURL = directoryURL.appendingPathComponent(
            UUID().uuidString.lowercased() + "." + mediaType.rawValue,
            isDirectory: false
        )
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        return (destinationURL, mediaType)
    }

    private static var temporaryMediaDirectoryURL: URL {
        let cachesURL = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

        return cachesURL
            .appendingPathComponent("POKE64", isDirectory: true)
            .appendingPathComponent("TemporaryMedia", isDirectory: true)
    }

    private static func cleanTemporaryMediaDirectory() {
        let fileManager = FileManager.default
        let directoryURL = temporaryMediaDirectoryURL

        do {
            guard fileManager.fileExists(atPath: directoryURL.path) else { return }
            let entries = try fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            for entry in entries {
                try fileManager.removeItem(at: entry)
            }
        } catch {
            print("Unable to clean temporary media: \(error)")
        }
    }

    private static func displayTitle(for url: URL) -> String {
        let title = url.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? url.lastPathComponent : title
    }

    private func refreshDriveConfigurationState() {
        let defaults = UserDefaults.standard
        drive9Configured = defaults.object(forKey: C64DriveSettings.drive9EnabledKey) == nil
            ? C64DriveSettings.defaultDrive9Enabled
            : defaults.bool(forKey: C64DriveSettings.drive9EnabledKey)
        let requested = defaults.object(forKey: C64DriveSettings.trueDriveEmulationKey) == nil
            ? C64DriveSettings.defaultTrueDriveEmulation
            : defaults.bool(forKey: C64DriveSettings.trueDriveEmulationKey)
        let drive8Ready = FirmwareStore.status(
            for: C64DriveModel.selected(for: 8).firmwareSlot
        ).isValid
        let drive9Ready = !drive9Configured || FirmwareStore.status(
            for: C64DriveModel.selected(for: 9).firmwareSlot
        ).isValid
        trueDriveEmulationConfigured = requested && drive8Ready && drive9Ready
        if !trueDriveEmulationConfigured {
            driveLEDOffTask?.cancel()
            driveLEDOffTask = nil
            drive8ActivityLEDOn = false
        }
    }

    private func refreshFirmwareState() {
        firmwareReady = FirmwareStore.isBootReady
    }

    private static func errorSummary(_ message: String) -> String {
        let normalized = message
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")

        guard normalized.count > 96 else { return normalized }
        return String(normalized.prefix(93)) + "…"
    }

    private func present(_ error: Error) {
        let message = error.localizedDescription
        status = Self.errorSummary(message)
        presentedError = message
    }
}


private enum EmulatorModelError: LocalizedError {
    case firmwareRequired
    case coreNotRunning
    case noTemporaryMedia
    case replacementRequired(String, String)
    case driveDisabled(Int)
    case incompatibleDiskImage(unit: Int, format: String, currentDrive: String, requiredDrive: String)
    case coreFailure(String)

    var errorDescription: String? {
        switch self {
        case .firmwareRequired:
            return "Configure BASIC, KERNAL and character ROMs before opening or running media."
        case .coreNotRunning:
            return "Start the C64 before changing media."
        case .noTemporaryMedia:
            return "The selected temporary media is no longer available."
        case .replacementRequired(let current, let destination):
            return "\(destination) already contains \(current). Confirm replacement before continuing."
        case .driveDisabled(let unit):
            return "Drive \(unit) is disabled. Enable it in Settings → Disk Drives and restart the core before inserting media."
        case .incompatibleDiskImage(let unit, let format, let currentDrive, let requiredDrive):
            return "\(format) requires \(requiredDrive). Drive \(unit) is configured as \(currentDrive). Change Settings → Disk Drives and restart the core before inserting this image."
        case .coreFailure(let message):
            return message
        }
    }
}
