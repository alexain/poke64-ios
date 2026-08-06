import Foundation
import GameController
import SwiftUI

enum JoyportAssignment: Equatable {
    case none
    case virtualJoystick
    case commodoreMouse
    case physicalController(UUID)
}

struct PhysicalControllerInfo: Identifiable, Equatable {
    let id: UUID
    let name: String
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
    @Published private(set) var firmwareReady = false
    @Published private(set) var isStarting = false
    @Published private(set) var videoAspectRatio: CGFloat = 4.0 / 3.0
    @Published var presentedError: String?
    @Published private(set) var joyport1Assignment: JoyportAssignment = .none
    @Published private(set) var joyport2Assignment: JoyportAssignment = .none
    @Published private(set) var physicalControllers: [PhysicalControllerInfo] = []
    @Published private(set) var mountedDisks: [Int: MediaReference] = [:]
    @Published private(set) var mountedTape: MediaReference?
    @Published private(set) var mountedCartridge: MediaReference?
    @Published private(set) var activeProgram: MediaReference?

    let session = LibretroSession()
    let library = LibraryStore()

    let availableDriveUnits = [8]

    private var didAttemptAutomaticStart = false
    private var virtualJoypadMask: UInt32 = 0
    private var controllerMasks: [UUID: UInt32] = [:]
    private var controllerObjects: [UUID: GCController] = [:]
    private var controllerIDs: [ObjectIdentifier: UUID] = [:]
    private var configuredMouseIDs: Set<ObjectIdentifier> = []
    private var notificationTokens: [NSObjectProtocol] = []
    private var configuredMousePort = 0

    init() {
        session.videoGeometryDidChange = { [weak self] aspectRatio in
            guard aspectRatio.isFinite, aspectRatio > 0 else { return }
            Task { @MainActor in
                self?.videoAspectRatio = CGFloat(aspectRatio)
            }
        }

        Self.cleanTemporaryMediaDirectory()
        observeInputDevices()
        refreshPhysicalControllers()
        refreshPhysicalMice()
        syncInputConfiguration()

        FirmwareStore.prepareDirectoriesAndConfiguration()
        refreshFirmwareState()
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

    func attach(videoView: C64MetalView) {
        session.videoView = videoView
    }

    func startAutomatically() async {
        guard !didAttemptAutomaticStart else { return }
        didAttemptAutomaticStart = true
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
        if !replacingExisting,
           let replacement = replacementInfo(for: action, media: media) {
            throw EmulatorModelError.replacementRequired(
                replacement.existingTitle,
                replacement.destination
            )
        }

        let replacedMedia: MediaReference?
        let programReleasedByReset: MediaReference?
        let success: Bool

        switch action {
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

        switch action {
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
            status = "Tape inserted: \(media.title)"

        case .autostartTape:
            activeProgram = nil
            mountedTape = media
            status = "Autostarting tape: \(media.title)"
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

    func settingsDidClose(previousFirmwareFingerprint: String) async {
        FirmwareStore.prepareDirectoriesAndConfiguration()
        refreshFirmwareState()

        guard FirmwareStore.configurationFingerprint != previousFirmwareFingerprint else {
            return
        }

        if isRunning {
            session.stop()
            isRunning = false
            clearMediaState(removeTemporaryFiles: true)
        }

        if firmwareReady {
            await startEmpty()
        } else {
            isStarting = false
            status = "Import BASIC, KERNAL and character ROMs"
        }
    }

    func stop() {
        session.stop()
        isRunning = false
        clearMediaState(removeTemporaryFiles: true)
        status = firmwareReady ? "Core stopped" : "Firmware required"
    }

    func softReset() {
        guard isRunning else { return }
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

    func ejectTape() throws {
        guard let media = mountedTape else { return }
        guard session.ejectTape() else {
            throw EmulatorModelError.coreFailure(
                session.lastErrorMessage ?? "Unable to eject the tape"
            )
        }
        mountedTape = nil
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
        status = "Port \(port): \(assignmentTitle(assignment))"
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
            return "Commodore Mouse"
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



    private func makeActionRequest(for media: MediaReference) -> MediaActionRequest {
        let actions: [MediaAction]
        switch media.mediaType {
        case .prg:
            actions = [.runProgram]
        case .crt:
            actions = [.insertCartridgeAndReset]
        case .d64:
            actions = availableDriveUnits.flatMap { unit in
                [.insertDisk(unit), .autostartDisk(unit)]
            }
        case .tap, .t64:
            actions = [.insertTape, .autostartTape]
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

    private func clearMediaState(removeTemporaryFiles: Bool) {
        activeProgram = nil
        mountedCartridge = nil
        mountedTape = nil
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
        case .coreFailure(let message):
            return message
        }
    }
}
