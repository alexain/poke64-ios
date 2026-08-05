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

struct TemporaryMediaInfo: Equatable {
    let title: String
    let originalFilename: String
    let mediaType: LibraryMediaType
}

@MainActor
final class EmulatorModel: ObservableObject {
    @Published private(set) var status = "Core not started"
    @Published private(set) var loadedContent: String?
    @Published private(set) var isRunning = false
    @Published private(set) var firmwareReady = false
    @Published private(set) var isStarting = false
    @Published var presentedError: String?
    @Published private(set) var joyport1Assignment: JoyportAssignment = .none
    @Published private(set) var joyport2Assignment: JoyportAssignment = .none
    @Published private(set) var physicalControllers: [PhysicalControllerInfo] = []
    @Published private(set) var loadedLibraryItemID: UUID?
    @Published private(set) var loadedTemporaryMedia: TemporaryMediaInfo?
    @Published private(set) var loadedTemporaryMediaLibraryItemID: UUID?

    let session = LibretroSession()
    let library = LibraryStore()

    private var didAttemptAutomaticStart = false
    private var virtualJoypadMask: UInt32 = 0
    private var controllerMasks: [UUID: UInt32] = [:]
    private var controllerObjects: [UUID: GCController] = [:]
    private var controllerIDs: [ObjectIdentifier: UUID] = [:]
    private var configuredMouseIDs: Set<ObjectIdentifier> = []
    private var notificationTokens: [NSObjectProtocol] = []
    private var configuredMousePort = 0
    private var loadedTemporaryMediaURL: URL?

    init() {
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

        // Give SwiftUI time to draw the loading screen before VICE performs
        // synchronous startup work on the main actor.
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(120))

        if session.startWithoutContent() {
            loadedContent = nil
            loadedLibraryItemID = nil
            loadedTemporaryMediaURL = nil
            loadedTemporaryMedia = nil
            loadedTemporaryMediaLibraryItemID = nil
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

    func openTemporaryMedia(url: URL) {
        do {
            presentedError = nil
            refreshFirmwareState()
            guard firmwareReady else {
                throw EmulatorModelError.firmwareRequired
            }

            let copiedMedia = try copyToTemporaryMediaDirectory(sourceURL: url)
            guard session.loadContent(at: copiedMedia.url) else {
                try? FileManager.default.removeItem(at: copiedMedia.url)
                isRunning = false
                loadedContent = nil
                loadedLibraryItemID = nil
                loadedTemporaryMediaURL = nil
                loadedTemporaryMedia = nil
                loadedTemporaryMediaLibraryItemID = nil
                Self.cleanTemporaryMediaDirectory()
                let message = session.lastErrorMessage ?? "Unable to load content"
                throw EmulatorModelError.coreFailure(message)
            }

            let title = Self.displayTitle(for: url)
            loadedContent = url.lastPathComponent
            loadedLibraryItemID = nil
            loadedTemporaryMediaURL = copiedMedia.url
            loadedTemporaryMedia = TemporaryMediaInfo(
                title: title,
                originalFilename: url.lastPathComponent,
                mediaType: copiedMedia.mediaType
            )
            loadedTemporaryMediaLibraryItemID = nil
            isRunning = true
            syncInputConfiguration()
            Self.cleanTemporaryMediaDirectory(preserving: copiedMedia.url)
            status = "Running temporarily: \(title)"
        } catch {
            present(error)
        }
    }

    @discardableResult
    func addCurrentTemporaryMediaToLibrary() throws -> LibraryItem {
        guard let sourceURL = loadedTemporaryMediaURL,
              let temporaryMedia = loadedTemporaryMedia else {
            throw EmulatorModelError.noTemporaryMedia
        }

        if let itemID = loadedTemporaryMediaLibraryItemID,
           let existingItem = library.item(withID: itemID) {
            return existingItem
        }

        let item = try library.importMedia(
            from: sourceURL,
            originalFilename: temporaryMedia.originalFilename
        )
        loadedTemporaryMediaLibraryItemID = item.id
        status = "Added to Library: \(item.title)"
        return item
    }

    @discardableResult
    func importIntoLibrary(url: URL) throws -> LibraryItem {
        let item = try library.importMedia(from: url)
        status = "Imported: \(item.title)"
        return item
    }

    func loadLibraryItem(_ item: LibraryItem) throws {
        presentedError = nil
        refreshFirmwareState()
        guard firmwareReady else {
            throw EmulatorModelError.firmwareRequired
        }

        do {
            let mediaURL = try library.mediaURL(for: item)
            guard session.loadContent(at: mediaURL) else {
                isRunning = false
                loadedContent = nil
                loadedLibraryItemID = nil
                loadedTemporaryMediaURL = nil
                loadedTemporaryMedia = nil
                loadedTemporaryMediaLibraryItemID = nil
                Self.cleanTemporaryMediaDirectory()
                let message = session.lastErrorMessage ?? "Unable to load content"
                status = Self.errorSummary(message)
                throw EmulatorModelError.coreFailure(message)
            }

            loadedContent = item.originalFilename
            loadedLibraryItemID = item.id
            loadedTemporaryMediaURL = nil
            loadedTemporaryMedia = nil
            loadedTemporaryMediaLibraryItemID = nil
            isRunning = true
            syncInputConfiguration()
            Self.cleanTemporaryMediaDirectory()
            do {
                try library.markOpened(item)
            } catch {
                print("Unable to update library recents: \(error)")
            }
            status = "Running: \(item.title)"
        } catch {
            if !isRunning {
                loadedContent = nil
                loadedLibraryItemID = nil
            }
            status = Self.errorSummary(error.localizedDescription)
            throw error
        }
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
            loadedContent = nil
            loadedLibraryItemID = nil
            loadedTemporaryMediaURL = nil
            loadedTemporaryMedia = nil
            loadedTemporaryMediaLibraryItemID = nil
            Self.cleanTemporaryMediaDirectory()
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
        loadedContent = nil
        loadedLibraryItemID = nil
        loadedTemporaryMediaURL = nil
        loadedTemporaryMedia = nil
        loadedTemporaryMediaLibraryItemID = nil
        Self.cleanTemporaryMediaDirectory()
        status = firmwareReady ? "Core stopped" : "Firmware required"
    }

    func softReset() {
        guard isRunning else { return }
        session.softReset()
        status = "Soft reset requested"
    }

    func hardReset() async {
        guard isRunning else { return }

        guard loadedTemporaryMediaURL != nil else {
            session.hardReset()
            status = "Hard reset requested"
            return
        }

        session.stop()
        isRunning = false
        loadedContent = nil
        loadedLibraryItemID = nil
        loadedTemporaryMediaURL = nil
        loadedTemporaryMedia = nil
        loadedTemporaryMediaLibraryItemID = nil
        status = "Hard resetting…"
        Self.cleanTemporaryMediaDirectory()
        await startEmpty()
    }

    var hasLoadedCartridge: Bool {
        guard let loadedContent else { return false }
        return URL(fileURLWithPath: loadedContent)
            .pathExtension
            .caseInsensitiveCompare("crt") == .orderedSame
    }

    func ejectCartridgeAndReset() async {
        guard hasLoadedCartridge else { return }
        session.stop()
        isRunning = false
        loadedContent = nil
        loadedLibraryItemID = nil
        loadedTemporaryMediaURL = nil
        loadedTemporaryMedia = nil
        loadedTemporaryMediaLibraryItemID = nil
        Self.cleanTemporaryMediaDirectory()
        status = "Ejecting cartridge…"
        await startEmpty()
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


    private func copyToTemporaryMediaDirectory(sourceURL: URL) throws -> (url: URL, mediaType: LibraryMediaType) {
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

    private static func cleanTemporaryMediaDirectory(preserving preservedURL: URL? = nil) {
        let fileManager = FileManager.default
        let directoryURL = temporaryMediaDirectoryURL

        do {
            guard fileManager.fileExists(atPath: directoryURL.path) else { return }
            let entries = try fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            let preservedPath = preservedURL?.standardizedFileURL.path

            for entry in entries where entry.standardizedFileURL.path != preservedPath {
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
    case noTemporaryMedia
    case coreFailure(String)

    var errorDescription: String? {
        switch self {
        case .firmwareRequired:
            return "Configure BASIC, KERNAL and character ROMs before opening or running media."
        case .noTemporaryMedia:
            return "There is no temporary media to add to the Library."
        case .coreFailure(let message):
            return message
        }
    }
}
