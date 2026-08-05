import Foundation
import SwiftUI

@MainActor
final class EmulatorModel: ObservableObject {
    @Published private(set) var status = "Core not started"
    @Published private(set) var loadedContent: String?
    @Published private(set) var isRunning = false
    @Published private(set) var firmwareReady = false
    @Published private(set) var isStarting = false
    @Published var presentedError: String?

    let session = LibretroSession()
    private var didAttemptAutomaticStart = false

    init() {
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
            isRunning = true
            status = "C64 started"
        } else {
            isRunning = false
            let message = session.lastErrorMessage ?? "Unable to start the core"
            status = Self.errorSummary(message)
            presentedError = message
        }
    }

    func importAndLoad(url: URL) {
        presentedError = nil
        refreshFirmwareState()
        guard firmwareReady else {
            status = "Configure firmware before loading content"
            return
        }

        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }

        do {
            let imported = try Self.copyIntoSandbox(url: url)
            if session.loadContent(at: imported) {
                loadedContent = imported.lastPathComponent
                isRunning = true
                status = "Running: \(imported.lastPathComponent)"
            } else {
                isRunning = false
                let message = session.lastErrorMessage ?? "Unable to load content"
                status = Self.errorSummary(message)
                presentedError = message
            }
        } catch {
            let message = error.localizedDescription
            status = Self.errorSummary(message)
            presentedError = message
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
        status = firmwareReady ? "Core stopped" : "Firmware required"
    }

    func softReset() {
        guard isRunning else { return }
        session.softReset()
        status = "Soft reset requested"
    }

    func hardReset() {
        guard isRunning else { return }
        session.hardReset()
        status = "Hard reset requested"
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
        status = "Ejecting cartridge…"
        await startEmpty()
    }

    func setJoypad(_ button: C64JoypadButton, pressed: Bool) {
        session.setJoypadButton(button, pressed: pressed)
    }

    func setKey(_ key: C64KeyCode, pressed: Bool) {
        session.setKey(key, pressed: pressed)
    }

    func setRawKey(_ keyCode: UInt, pressed: Bool) {
        session.setRawKeyCode(keyCode, pressed: pressed)
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

    private static func copyIntoSandbox(url: URL) throws -> URL {
        let fileManager = FileManager.default
        let documents = try fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let imports = documents.appendingPathComponent("Imported", isDirectory: true)
        try fileManager.createDirectory(at: imports, withIntermediateDirectories: true)

        var destination = imports.appendingPathComponent(url.lastPathComponent)
        if fileManager.fileExists(atPath: destination.path) {
            let base = url.deletingPathExtension().lastPathComponent
            let ext = url.pathExtension
            let suffix = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            destination = imports
                .appendingPathComponent("\(base)-\(suffix)")
                .appendingPathExtension(ext)
        }

        try fileManager.copyItem(at: url, to: destination)
        return destination
    }
}
