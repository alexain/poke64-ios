import Foundation
import SwiftUI

@MainActor
final class EmulatorModel: ObservableObject {
    @Published private(set) var status = "Core not started"
    @Published private(set) var loadedContent: String?
    @Published private(set) var isRunning = false
    @Published private(set) var firmwareReady = false

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

    func startAutomatically() {
        guard !didAttemptAutomaticStart else { return }
        didAttemptAutomaticStart = true
        refreshFirmwareState()

        guard firmwareReady else {
            status = "Import BASIC, KERNAL and character ROMs"
            return
        }

        startEmpty()
    }

    func startEmpty() {
        refreshFirmwareState()
        guard firmwareReady else {
            isRunning = false
            status = "Firmware required"
            return
        }

        if session.startWithoutContent() {
            loadedContent = nil
            isRunning = true
            status = "C64 started"
        } else {
            isRunning = false
            status = session.lastErrorMessage ?? "Unable to start the core"
        }
    }

    func importAndLoad(url: URL) {
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
                status = session.lastErrorMessage ?? "Unable to load content"
            }
        } catch {
            status = error.localizedDescription
        }
    }

    func firmwareConfigurationChanged() {
        FirmwareStore.prepareDirectoriesAndConfiguration()

        if isRunning {
            session.stop()
            isRunning = false
            loadedContent = nil
        }

        refreshFirmwareState()
        if firmwareReady {
            startEmpty()
        } else {
            status = "Import BASIC, KERNAL and character ROMs"
        }
    }

    func stop() {
        session.stop()
        isRunning = false
        status = firmwareReady ? "Core stopped" : "Firmware required"
    }

    func reset() {
        guard isRunning else { return }
        session.resetCore()
        status = "Reset requested"
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
