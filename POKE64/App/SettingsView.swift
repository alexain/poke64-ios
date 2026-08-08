import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum C64MachineModel: String, CaseIterable, Identifiable {
    case c64PAL = "C64 PAL"
    case c64NTSC = "C64 NTSC"
    case c64cPAL = "C64C PAL"
    case c64cNTSC = "C64C NTSC"

    static let defaultsKey = "poke64.machineModel"
    static let defaultModel: C64MachineModel = .c64PAL

    var id: String { rawValue }

    var title: String { rawValue }

    var region: String {
        switch self {
        case .c64PAL, .c64cPAL:
            return "PAL"
        case .c64NTSC, .c64cNTSC:
            return "NTSC"
        }
    }

    var timingSummary: String {
        switch self {
        case .c64PAL, .c64cPAL:
            return "approximately 50 Hz"
        case .c64NTSC, .c64cNTSC:
            return "approximately 59.94 Hz"
        }
    }

    var hardwareSummary: String {
        switch self {
        case .c64PAL, .c64NTSC:
            return "Original C64 hardware profile"
        case .c64cPAL, .c64cNTSC:
            return "Later C64C hardware profile"
        }
    }

    static var selected: C64MachineModel {
        get {
            guard let value = UserDefaults.standard.string(forKey: defaultsKey),
                  let model = C64MachineModel(rawValue: value) else {
                return defaultModel
            }
            return model
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
        }
    }
}


enum C64REUSize: String, CaseIterable, Identifiable {
    case disabled = "none"
    case kb128 = "128kB"
    case kb256 = "256kB"
    case kb512 = "512kB"
    case mb1 = "1024kB"
    case mb2 = "2048kB"
    case mb4 = "4096kB"
    case mb8 = "8192kB"
    case mb16 = "16384kB"

    static let defaultsKey = "poke64.system.reuSize"
    static let defaultValue: C64REUSize = .disabled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .disabled:
            return "Disabled"
        case .kb128:
            return "128 KB — Commodore 1700"
        case .kb256:
            return "256 KB — Commodore 1764"
        case .kb512:
            return "512 KB — Commodore 1750"
        case .mb1:
            return "1 MB"
        case .mb2:
            return "2 MB"
        case .mb4:
            return "4 MB"
        case .mb8:
            return "8 MB"
        case .mb16:
            return "16 MB"
        }
    }

    var capacityTitle: String {
        switch self {
        case .disabled:
            return "Disabled"
        case .kb128:
            return "128 KB"
        case .kb256:
            return "256 KB"
        case .kb512:
            return "512 KB"
        case .mb1:
            return "1 MB"
        case .mb2:
            return "2 MB"
        case .mb4:
            return "4 MB"
        case .mb8:
            return "8 MB"
        case .mb16:
            return "16 MB"
        }
    }

    var sizeInKilobytes: Int? {
        switch self {
        case .disabled:
            return nil
        case .kb128:
            return 128
        case .kb256:
            return 256
        case .kb512:
            return 512
        case .mb1:
            return 1024
        case .mb2:
            return 2048
        case .mb4:
            return 4096
        case .mb8:
            return 8192
        case .mb16:
            return 16384
        }
    }

    static var selected: C64REUSize {
        get {
            guard let value = UserDefaults.standard.string(forKey: defaultsKey),
                  let size = C64REUSize(rawValue: value) else {
                return defaultValue
            }
            return size
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
        }
    }

    static func matching(byteCount: Int) -> C64REUSize? {
        allCases.first { size in
            guard let kilobytes = size.sizeInKilobytes else { return false }
            return kilobytes * 1024 == byteCount
        }
    }
}

enum C64REUSettings {
    static let persistentMemoryKey = "poke64.system.reuPersistentMemory"
    static let importedImageNameKey = "poke64.system.reuImportedImageName"
    static let imageRevisionKey = "poke64.system.reuImageRevision"
    static let defaultPersistentMemory = false

    static var persistentMemoryEnabled: Bool {
        let defaults = UserDefaults.standard
        return defaults.object(forKey: persistentMemoryKey) == nil
            ? defaultPersistentMemory
            : defaults.bool(forKey: persistentMemoryKey)
    }

    static var importedImageName: String? {
        UserDefaults.standard.string(forKey: importedImageNameKey)
    }

    static var imageRevision: String {
        UserDefaults.standard.string(forKey: imageRevisionKey) ?? "none"
    }

    static func recordImportedImage(named filename: String) {
        let defaults = UserDefaults.standard
        defaults.set(filename, forKey: importedImageNameKey)
        defaults.set(UUID().uuidString, forKey: imageRevisionKey)
    }

    static func clearImportedImage() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: importedImageNameKey)
        defaults.set(UUID().uuidString, forKey: imageRevisionKey)
    }

    static var configurationFingerprint: String {
        [
            C64REUSize.selected.rawValue,
            String(persistentMemoryEnabled),
            importedImageName ?? "no-image",
            imageRevision
        ].joined(separator: ":")
    }
}

enum C64TapeSettings {
    static let autoShowControlsKey = "poke64.tape.autoShowControls"
    static let resetCounterOnInsertKey = "poke64.tape.resetCounterOnInsert"
    static let resetWithCPUKey = "poke64.tape.resetWithCPU"
    static let autostartBasicLoadKey = "poke64.tape.autostartBasicLoad"

    static let defaultAutoShowControls = true
    static let defaultResetCounterOnInsert = true
    static let defaultResetWithCPU = false
    static let defaultAutostartBasicLoad = true

    private static func boolValue(forKey key: String, defaultValue: Bool) -> Bool {
        let defaults = UserDefaults.standard
        return defaults.object(forKey: key) == nil
            ? defaultValue
            : defaults.bool(forKey: key)
    }

    static var autoShowControls: Bool {
        boolValue(forKey: autoShowControlsKey, defaultValue: defaultAutoShowControls)
    }

    static var resetCounterOnInsert: Bool {
        boolValue(
            forKey: resetCounterOnInsertKey,
            defaultValue: defaultResetCounterOnInsert
        )
    }

    static var resetWithCPU: Bool {
        boolValue(forKey: resetWithCPUKey, defaultValue: defaultResetWithCPU)
    }

    static var autostartBasicLoad: Bool {
        boolValue(
            forKey: autostartBasicLoadKey,
            defaultValue: defaultAutostartBasicLoad
        )
    }

    static var configurationFingerprint: String {
        [
            String(resetWithCPU),
            String(autostartBasicLoad)
        ].joined(separator: ":")
    }
}

enum C64PrinterExportFormat: String, CaseIterable, Identifiable {
    case pdf
    case png
    case raw
    case pdfAndRaw = "pdf+raw"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pdf: return "PDF"
        case .png: return "PNG pages"
        case .raw: return "RAW diagnostic stream"
        case .pdfAndRaw: return "PDF + RAW"
        }
    }

    var usesRasterRenderer: Bool { self != .raw }
    var includesRawCapture: Bool { self == .raw || self == .pdfAndRaw }
}

enum C64PrinterDotIntensity: String, CaseIterable, Identifiable {
    case light
    case normal
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: return "Light"
        case .normal: return "Normal"
        case .dark: return "Dark"
        }
    }

    var inkLevel: UInt8 {
        switch self {
        case .light: return 145
        case .normal: return 72
        case .dark: return 22
        }
    }
}

enum C64PrinterSettings {
    static let enabledKey = "poke64.printer.enabled"
    static let deviceKey = "poke64.printer.device"
    static let exportFormatKey = "poke64.printer.exportFormat"
    static let dotIntensityKey = "poke64.printer.dotIntensity"
    static let defaultEnabled = false
    static let defaultDevice = 4
    static let defaultExportFormat: C64PrinterExportFormat = .pdf
    static let defaultDotIntensity: C64PrinterDotIntensity = .normal
    static let supportedDevices = [4, 5]

    static var enabled: Bool {
        let defaults = UserDefaults.standard
        return defaults.object(forKey: enabledKey) == nil
            ? defaultEnabled
            : defaults.bool(forKey: enabledKey)
    }

    static var device: Int {
        let stored = UserDefaults.standard.object(forKey: deviceKey) == nil
            ? defaultDevice
            : UserDefaults.standard.integer(forKey: deviceKey)
        return supportedDevices.contains(stored) ? stored : defaultDevice
    }

    static var exportFormat: C64PrinterExportFormat {
        let raw = UserDefaults.standard.string(forKey: exportFormatKey)
        return C64PrinterExportFormat(rawValue: raw ?? "") ?? defaultExportFormat
    }

    static var dotIntensity: C64PrinterDotIntensity {
        let raw = UserDefaults.standard.string(forKey: dotIntensityKey)
        return C64PrinterDotIntensity(rawValue: raw ?? "") ?? defaultDotIntensity
    }

    static var isReadyForSelectedFormat: Bool {
        !exportFormat.usesRasterRenderer
            || FirmwareStore.status(for: .printerMPS803).isValid
    }

    static var configurationFingerprint: String {
        [
            String(enabled),
            String(device),
            exportFormat.rawValue
        ].joined(separator: ":")
    }
}

enum C64PrinterOutputStoreError: LocalizedError {
    case noCapturedData
    case invalidRasterPage(String)
    case outputCreationFailed(String)

    var errorDescription: String? {
        switch self {
        case .noCapturedData:
            return "The printer does not contain any printable data."
        case .invalidRasterPage(let filename):
            return "The printer page \(filename) is not a valid POKE64 raster page."
        case .outputCreationFailed(let message):
            return "The printer output could not be created: \(message)"
        }
    }
}

enum C64PrinterOutputStore {
    static let relativeOutputPath = "POKE64/Printer/printer.raw"
    static let outputFilename = "printer.raw"

    @discardableResult
    static func prepareDirectory() throws -> URL {
        let directory = try outputDirectory()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: try spoolDirectory(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: try ejectedOutputDirectory(),
            withIntermediateDirectories: true
        )
        return directory
    }

    static func outputURL() throws -> URL {
        try prepareDirectory()
            .appendingPathComponent(outputFilename, isDirectory: false)
    }

    static func spoolDirectoryURL() throws -> URL {
        try prepareDirectory()
        return try spoolDirectory()
    }

    static func capturedByteCount() -> Int? {
        activeByteCount(
            device: C64PrinterSettings.device,
            format: C64PrinterSettings.exportFormat
        )
    }

    static func activeByteCount(
        device: Int,
        format: C64PrinterExportFormat
    ) -> Int? {
        var total = 0
        var found = false

        if format.includesRawCapture,
           let attributes = try? FileManager.default.attributesOfItem(
            atPath: try outputURL().path
           ),
           let size = attributes[.size] as? NSNumber {
            total += size.intValue
            found = true
        }

        if format.usesRasterRenderer {
            for url in activeRasterURLs(device: device, includePreview: true) {
                if let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
                   let fileSize = values.fileSize {
                    total += fileSize
                    found = true
                }
            }
        }
        return found ? total : nil
    }

    static func activeRasterPageCount(device: Int) -> Int {
        activeRasterURLs(device: device).count
    }

    static func previewImage(
        device: Int,
        intensity: C64PrinterDotIntensity
    ) throws -> UIImage? {
        let preview = try spoolDirectory()
            .appendingPathComponent("printer-\(device)-preview.pgm")
        let source: URL?
        if FileManager.default.fileExists(atPath: preview.path) {
            source = preview
        } else {
            source = activeRasterURLs(device: device).last
        }
        guard let source else { return nil }
        return try rasterImage(from: source, intensity: intensity)
    }

    static func removeOutput() throws {
        try discardActiveOutput(device: C64PrinterSettings.device)
    }

    static func truncateOutput() throws {
        let url = try outputURL()
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: url.path) {
            fileManager.createFile(atPath: url.path, contents: nil)
            return
        }

        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.truncate(atOffset: 0)
        try handle.synchronize()
    }

    static func discardActiveOutput(device: Int) throws {
        let manager = FileManager.default
        for url in activeRasterURLs(device: device, includePreview: true) {
            try? manager.removeItem(at: url)
        }
        try truncateOutput()
    }

    static func ejectOutput(
        device: Int,
        format: C64PrinterExportFormat,
        intensity: C64PrinterDotIntensity
    ) throws -> [URL] {
        if format == .raw {
            let raw = try finalizeRawOutput(device: device)
            return [raw]
        }

        let pages = activeRasterURLs(device: device)
        guard !pages.isEmpty else {
            throw C64PrinterOutputStoreError.noCapturedData
        }

        let jobDirectory = try createJobDirectory(device: device)
        var outputs: [URL] = []

        switch format {
        case .pdf, .pdfAndRaw:
            let pdfURL = jobDirectory.appendingPathComponent(
                "printer-\(device).pdf",
                isDirectory: false
            )
            try createPDF(from: pages, intensity: intensity, at: pdfURL)
            outputs.append(pdfURL)

        case .png:
            for (index, page) in pages.enumerated() {
                let image = try rasterImage(from: page, intensity: intensity)
                guard let data = image.pngData() else {
                    throw C64PrinterOutputStoreError.outputCreationFailed(
                        "PNG encoding failed"
                    )
                }
                let url = jobDirectory.appendingPathComponent(
                    String(format: "printer-%d-page-%03d.png", device, index + 1),
                    isDirectory: false
                )
                try data.write(to: url, options: [.atomic])
                outputs.append(url)
            }

        case .raw:
            break
        }

        if format.includesRawCapture,
           (capturedRawByteCount() ?? 0) > 0 {
            let rawURL = jobDirectory.appendingPathComponent(
                "printer-\(device).raw",
                isDirectory: false
            )
            try FileManager.default.copyItem(at: try outputURL(), to: rawURL)
            outputs.append(rawURL)
        }

        try discardActiveOutput(device: device)
        return outputs
    }

    static func mostRecentEjectedOutputURLs() -> [URL] {
        guard let directory = try? ejectedOutputDirectory(),
              let jobs = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        let latest = jobs
            .filter {
                (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }
            .sorted { lhs, rhs in
                let lhsDate = try? lhs.resourceValues(
                    forKeys: [.contentModificationDateKey]
                ).contentModificationDate
                let rhsDate = try? rhs.resourceValues(
                    forKeys: [.contentModificationDateKey]
                ).contentModificationDate
                return (lhsDate ?? .distantPast) > (rhsDate ?? .distantPast)
            }
            .first

        guard let latest,
              let files = try? FileManager.default.contentsOfDirectory(
                at: latest,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }
        return files.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func makeShareSnapshot() throws -> URL {
        let sourceURL = try outputURL()
        guard FileManager.default.fileExists(atPath: sourceURL.path),
              (capturedRawByteCount() ?? 0) > 0 else {
            throw C64PrinterOutputStoreError.noCapturedData
        }

        let snapshotURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "POKE64-printer-\(UUID().uuidString).raw",
                isDirectory: false
            )
        try FileManager.default.copyItem(at: sourceURL, to: snapshotURL)
        return snapshotURL
    }

    static func removeShareSnapshot(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private static func capturedRawByteCount() -> Int? {
        guard let attributes = try? FileManager.default.attributesOfItem(
            atPath: try outputURL().path
        ), let size = attributes[.size] as? NSNumber else {
            return nil
        }
        return size.intValue
    }

    private static func activeRasterURLs(
        device: Int,
        includePreview: Bool = false
    ) -> [URL] {
        guard let directory = try? spoolDirectory(),
              let files = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }
        let pagePrefix = "printer-\(device)-page-"
        let previewName = "printer-\(device)-preview.pgm"
        return files
            .filter {
                $0.pathExtension.lowercased() == "pgm"
                    && ($0.lastPathComponent.hasPrefix(pagePrefix)
                        || (includePreview && $0.lastPathComponent == previewName))
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func finalizeRawOutput(device: Int) throws -> URL {
        guard (capturedRawByteCount() ?? 0) > 0 else {
            throw C64PrinterOutputStoreError.noCapturedData
        }
        let jobDirectory = try createJobDirectory(device: device)
        let destination = jobDirectory.appendingPathComponent(
            "printer-\(device).raw",
            isDirectory: false
        )
        try FileManager.default.copyItem(at: try outputURL(), to: destination)
        try truncateOutput()
        return destination
    }

    private static func createJobDirectory(device: Int) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let root = try ejectedOutputDirectory()
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        var directory = root.appendingPathComponent(
            "printer-\(device)-\(formatter.string(from: Date()))",
            isDirectory: true
        )
        if FileManager.default.fileExists(atPath: directory.path) {
            directory = root.appendingPathComponent(
                "printer-\(device)-\(UUID().uuidString)",
                isDirectory: true
            )
        }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private static func createPDF(
        from pages: [URL],
        intensity: C64PrinterDotIntensity,
        at destination: URL
    ) throws {
        let images = try pages.map { try rasterImage(from: $0, intensity: intensity) }
        let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)
        do {
            try renderer.writePDF(to: destination) { context in
                for image in images {
                    context.beginPage()
                    context.cgContext.setFillColor(UIColor.white.cgColor)
                    context.cgContext.fill(pageBounds)
                    let printable = pageBounds.insetBy(dx: 24, dy: 24)
                    let physicalSize = CGSize(
                        width: image.size.width / 60.0,
                        height: image.size.height / 72.0
                    )
                    let scale = min(
                        printable.width / physicalSize.width,
                        printable.height / physicalSize.height
                    )
                    let size = CGSize(
                        width: physicalSize.width * scale,
                        height: physicalSize.height * scale
                    )
                    let rect = CGRect(
                        x: printable.midX - size.width / 2,
                        y: printable.midY - size.height / 2,
                        width: size.width,
                        height: size.height
                    )
                    image.draw(in: rect)
                }
            }
        } catch {
            throw C64PrinterOutputStoreError.outputCreationFailed(
                error.localizedDescription
            )
        }
    }

    private static func rasterImage(
        from url: URL,
        intensity: C64PrinterDotIntensity
    ) throws -> UIImage {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        var index = 0
        func token() -> String? {
            while index < data.count {
                let byte = data[index]
                if byte == 35 {
                    while index < data.count && data[index] != 10 { index += 1 }
                } else if byte == 9 || byte == 10 || byte == 13 || byte == 32 {
                    index += 1
                } else {
                    break
                }
            }
            let start = index
            while index < data.count {
                let byte = data[index]
                if byte == 9 || byte == 10 || byte == 13 || byte == 32 || byte == 35 {
                    break
                }
                index += 1
            }
            guard index > start else { return nil }
            return String(data: data[start..<index], encoding: .ascii)
        }

        guard token() == "P5",
              let widthToken = token(), let width = Int(widthToken),
              let heightToken = token(), let height = Int(heightToken),
              token() == "255" else {
            throw C64PrinterOutputStoreError.invalidRasterPage(
                url.lastPathComponent
            )
        }
        while index < data.count,
              [9, 10, 13, 32].contains(data[index]) {
            index += 1
        }
        let (required, overflow) = width.multipliedReportingOverflow(by: height)
        guard width > 0, width <= 4_096,
              height > 0, height <= 8_192,
              !overflow, required > 0,
              data.count - index >= required else {
            throw C64PrinterOutputStoreError.invalidRasterPage(
                url.lastPathComponent
            )
        }

        var pixels = [UInt8](data[index..<(index + required)])
        let ink = intensity.inkLevel
        for offset in pixels.indices {
            if pixels[offset] < 128 {
                pixels[offset] = ink
            } else {
                pixels[offset] = 255
            }
        }
        let pixelData = Data(pixels) as CFData
        guard let provider = CGDataProvider(data: pixelData),
              let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGBitmapInfo(rawValue: 0),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            throw C64PrinterOutputStoreError.outputCreationFailed(
                "The raster image could not be decoded"
            )
        }
        return UIImage(cgImage: image, scale: 1, orientation: .up)
    }

    private static func outputDirectory() throws -> URL {
        let documents = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return documents
            .appendingPathComponent("Saves", isDirectory: true)
            .appendingPathComponent("POKE64", isDirectory: true)
            .appendingPathComponent("Printer", isDirectory: true)
    }

    private static func spoolDirectory() throws -> URL {
        try outputDirectory()
            .appendingPathComponent("Spool", isDirectory: true)
    }

    private static func ejectedOutputDirectory() throws -> URL {
        try outputDirectory()
            .appendingPathComponent("Jobs", isDirectory: true)
    }
}

enum C64VideoAspectRatio: String, CaseIterable, Identifiable {
    case automatic = "auto"
    case pal
    case ntsc
    case raw

    static let defaultsKey = "poke64.video.aspectRatio"
    static let defaultValue: C64VideoAspectRatio = .automatic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic:
            return "Automatic"
        case .pal:
            return "PAL pixels"
        case .ntsc:
            return "NTSC pixels"
        case .raw:
            return "Raw pixels"
        }
    }
}

enum C64VideoCrop: String, CaseIterable, Identifiable {
    case disabled
    case small
    case medium
    case maximum
    case automatic = "auto"

    static let defaultsKey = "poke64.video.crop"
    static let defaultValue: C64VideoCrop = .disabled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .disabled:
            return "Full borders"
        case .small:
            return "Small crop"
        case .medium:
            return "Medium crop"
        case .maximum:
            return "Maximum crop"
        case .automatic:
            return "Automatic"
        }
    }
}

enum C64VideoPalette: String, CaseIterable, Identifiable {
    case internalPalette = "default"
    case vice
    case colodore
    case communityColors = "community-colors"
    case peptoPAL = "pepto-pal"
    case peptoNTSC = "pepto-ntsc"
    case theC64 = "the64"
    case rgb

    static let defaultsKey = "poke64.video.palette"
    static let defaultValue: C64VideoPalette = .internalPalette

    var id: String { rawValue }

    var title: String {
        switch self {
        case .internalPalette:
            return "Internal (adjustable)"
        case .vice:
            return "VICE Default"
        case .colodore:
            return "Colodore"
        case .communityColors:
            return "Community Colors"
        case .peptoPAL:
            return "Pepto PAL"
        case .peptoNTSC:
            return "Pepto NTSC"
        case .theC64:
            return "TheC64"
        case .rgb:
            return "RGB"
        }
    }

    var supportsColorAdjustments: Bool {
        self == .internalPalette
    }
}

enum C64VideoFilter: String, CaseIterable, Identifiable {
    case disabled
    case sharpPAL = "enabled_noblur"
    case lowBlur = "enabled_lowblur"
    case mediumBlur = "enabled_medblur"
    case authenticPAL = "enabled"

    static let defaultsKey = "poke64.video.filter"
    static let defaultValue: C64VideoFilter = .disabled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .disabled:
            return "Off"
        case .sharpPAL:
            return "Sharp PAL"
        case .lowBlur:
            return "Low Blur"
        case .mediumBlur:
            return "Medium Blur"
        case .authenticPAL:
            return "Authentic PAL"
        }
    }
}

enum C64VideoSettings {
    static let cropDelayKey = "poke64.video.cropDelay"
    static let brightnessKey = "poke64.video.brightness"
    static let contrastKey = "poke64.video.contrast"
    static let saturationKey = "poke64.video.saturation"
    static let gammaKey = "poke64.video.gamma"
    static let tintKey = "poke64.video.tint"

    static let defaultCropDelay = true
    static let defaultBrightness = 1000
    static let defaultContrast = 1000
    static let defaultSaturation = 1000
    static let defaultGamma = 2800
    static let defaultTint = 1000

    static var configurationFingerprint: String {
        let defaults = UserDefaults.standard
        return [
            defaults.string(forKey: C64VideoAspectRatio.defaultsKey)
                ?? C64VideoAspectRatio.defaultValue.rawValue,
            defaults.string(forKey: C64VideoCrop.defaultsKey)
                ?? C64VideoCrop.defaultValue.rawValue,
            String(defaults.object(forKey: cropDelayKey) == nil
                ? defaultCropDelay
                : defaults.bool(forKey: cropDelayKey)),
            defaults.string(forKey: C64VideoPalette.defaultsKey)
                ?? C64VideoPalette.defaultValue.rawValue,
            defaults.string(forKey: C64VideoFilter.defaultsKey)
                ?? C64VideoFilter.defaultValue.rawValue,
            String(defaults.object(forKey: brightnessKey) == nil
                ? defaultBrightness
                : defaults.integer(forKey: brightnessKey)),
            String(defaults.object(forKey: contrastKey) == nil
                ? defaultContrast
                : defaults.integer(forKey: contrastKey)),
            String(defaults.object(forKey: saturationKey) == nil
                ? defaultSaturation
                : defaults.integer(forKey: saturationKey)),
            String(defaults.object(forKey: gammaKey) == nil
                ? defaultGamma
                : defaults.integer(forKey: gammaKey)),
            String(defaults.object(forKey: tintKey) == nil
                ? defaultTint
                : defaults.integer(forKey: tintKey))
        ].joined(separator: ":")
    }
}

enum C64CRTMaskType: Int, CaseIterable, Identifiable, Codable {
    case off = 0
    case dotMask = 1
    case apertureGrille = 2
    case vga = 3

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .off:
            "Off"
        case .dotMask:
            "Dot Mask"
        case .apertureGrille:
            "Aperture Grille"
        case .vga:
            "VGA Mask"
        }
    }
}

struct C64CRTParameters: Codable, Equatable {
    var scanlineIntensity: Double
    var beamSoftness: Double
    var sharpness: Double
    var maskIntensity: Double
    var maskType: Int
    var curvature: Double
    var brightness: Double
    var bloomAmount: Double
    var bloomSoftness: Double

    private enum CodingKeys: String, CodingKey {
        case scanlineIntensity
        case beamSoftness
        case sharpness
        case maskIntensity
        case maskType
        case curvature
        case brightness
        case bloomAmount
        case bloomSoftness
    }
}

extension C64CRTParameters {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        scanlineIntensity = try container.decode(Double.self, forKey: .scanlineIntensity)
        beamSoftness = try container.decode(Double.self, forKey: .beamSoftness)
        sharpness = try container.decode(Double.self, forKey: .sharpness)
        maskIntensity = try container.decode(Double.self, forKey: .maskIntensity)
        maskType = try container.decodeIfPresent(Int.self, forKey: .maskType)
            ?? C64CRTMaskType.dotMask.rawValue
        curvature = try container.decode(Double.self, forKey: .curvature)
        brightness = try container.decode(Double.self, forKey: .brightness)
        bloomAmount = try container.decodeIfPresent(Double.self, forKey: .bloomAmount) ?? 0.16
        bloomSoftness = try container.decodeIfPresent(Double.self, forKey: .bloomSoftness) ?? 0.55
    }
}

struct C64CRTPreset: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var parameters: C64CRTParameters
    let isBuiltIn: Bool
}

enum C64CRTSettings {
    static let enabledKey = "poke64.crt.enabled"
    static let scanlineIntensityKey = "poke64.crt.scanlineIntensity"
    static let beamSoftnessKey = "poke64.crt.beamSoftness"
    static let sharpnessKey = "poke64.crt.sharpness"
    static let maskIntensityKey = "poke64.crt.maskIntensity"
    static let maskTypeKey = "poke64.crt.maskType"
    static let curvatureKey = "poke64.crt.curvature"
    static let brightnessKey = "poke64.crt.brightness"
    static let bloomAmountKey = "poke64.crt.bloomAmount"
    static let bloomSoftnessKey = "poke64.crt.bloomSoftness"

    static let defaultEnabled = false
    static let defaultParameters = C64CRTParameters(
        scanlineIntensity: 0.52,
        beamSoftness: 0.58,
        sharpness: 0.82,
        maskIntensity: 0.22,
        maskType: C64CRTMaskType.dotMask.rawValue,
        curvature: 0.12,
        brightness: 1.06,
        bloomAmount: 0.16,
        bloomSoftness: 0.55
    )

    static var currentParameters: C64CRTParameters {
        let defaults = UserDefaults.standard
        return C64CRTParameters(
            scanlineIntensity: doubleValue(
                defaults,
                key: scanlineIntensityKey,
                defaultValue: defaultParameters.scanlineIntensity
            ),
            beamSoftness: doubleValue(
                defaults,
                key: beamSoftnessKey,
                defaultValue: defaultParameters.beamSoftness
            ),
            sharpness: doubleValue(
                defaults,
                key: sharpnessKey,
                defaultValue: defaultParameters.sharpness
            ),
            maskIntensity: doubleValue(
                defaults,
                key: maskIntensityKey,
                defaultValue: defaultParameters.maskIntensity
            ),
            maskType: integerValue(
                defaults,
                key: maskTypeKey,
                defaultValue: defaultParameters.maskType
            ),
            curvature: doubleValue(
                defaults,
                key: curvatureKey,
                defaultValue: defaultParameters.curvature
            ),
            brightness: doubleValue(
                defaults,
                key: brightnessKey,
                defaultValue: defaultParameters.brightness
            ),
            bloomAmount: doubleValue(
                defaults,
                key: bloomAmountKey,
                defaultValue: defaultParameters.bloomAmount
            ),
            bloomSoftness: doubleValue(
                defaults,
                key: bloomSoftnessKey,
                defaultValue: defaultParameters.bloomSoftness
            )
        )
    }

    static func apply(_ parameters: C64CRTParameters) {
        let defaults = UserDefaults.standard
        defaults.set(parameters.scanlineIntensity, forKey: scanlineIntensityKey)
        defaults.set(parameters.beamSoftness, forKey: beamSoftnessKey)
        defaults.set(parameters.sharpness, forKey: sharpnessKey)
        defaults.set(parameters.maskIntensity, forKey: maskIntensityKey)
        defaults.set(parameters.maskType, forKey: maskTypeKey)
        defaults.set(parameters.curvature, forKey: curvatureKey)
        defaults.set(parameters.brightness, forKey: brightnessKey)
        defaults.set(parameters.bloomAmount, forKey: bloomAmountKey)
        defaults.set(parameters.bloomSoftness, forKey: bloomSoftnessKey)
    }

    private static func doubleValue(
        _ defaults: UserDefaults,
        key: String,
        defaultValue: Double
    ) -> Double {
        defaults.object(forKey: key) == nil ? defaultValue : defaults.double(forKey: key)
    }

    private static func integerValue(
        _ defaults: UserDefaults,
        key: String,
        defaultValue: Int
    ) -> Int {
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        let value = defaults.integer(forKey: key)
        return C64CRTMaskType(rawValue: value) == nil ? defaultValue : value
    }
}

enum C64CRTPresetStoreError: LocalizedError {
    case invalidName
    case builtInPresetProtected
    case presetNotFound
    case presetInUse([String])

    var errorDescription: String? {
        switch self {
        case .invalidName:
            return "Enter a CRT preset name."
        case .builtInPresetProtected:
            return "The built-in Commodore Monitor preset cannot be changed or deleted."
        case .presetNotFound:
            return "The selected CRT preset no longer exists."
        case .presetInUse(let profileNames):
            return "This CRT preset is used by: \(profileNames.joined(separator: ", "))."
        }
    }
}

enum C64CRTPresetStore {
    static let builtInPresetID = UUID(uuidString: "00000000-0000-4000-8000-000000001702")!
    private static let activePresetIDKey = "poke64.crt.activePresetID"
    private static let userPresetsKey = "poke64.crt.userPresets.data"

    static var builtInPreset: C64CRTPreset {
        C64CRTPreset(
            id: builtInPresetID,
            name: "Commodore Monitor",
            parameters: C64CRTSettings.defaultParameters,
            isBuiltIn: true
        )
    }

    static var activePresetID: UUID {
        get {
            guard let raw = UserDefaults.standard.string(forKey: activePresetIDKey),
                  let id = UUID(uuidString: raw),
                  loadPresets().contains(where: { $0.id == id }) else {
                return builtInPresetID
            }
            return id
        }
        set {
            UserDefaults.standard.set(newValue.uuidString, forKey: activePresetIDKey)
        }
    }

    static var activePreset: C64CRTPreset {
        loadPresets().first(where: { $0.id == activePresetID }) ?? builtInPreset
    }

    static var activePresetIsModified: Bool {
        C64CRTSettings.currentParameters != activePreset.parameters
    }

    static func loadPresets() -> [C64CRTPreset] {
        let userPresets: [C64CRTPreset]
        if let data = UserDefaults.standard.data(forKey: userPresetsKey),
           let decoded = try? JSONDecoder().decode([C64CRTPreset].self, from: data) {
            userPresets = decoded.filter { $0.id != builtInPresetID }
        } else {
            userPresets = []
        }
        return [builtInPreset] + userPresets.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    @discardableResult
    static func applyPreset(_ presetID: UUID) -> C64CRTPreset {
        let preset = loadPresets().first(where: { $0.id == presetID }) ?? builtInPreset
        C64CRTSettings.apply(preset.parameters)
        activePresetID = preset.id
        return preset
    }

    @discardableResult
    static func saveCurrentPreset(named rawName: String) throws -> C64CRTPreset {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw C64CRTPresetStoreError.invalidName }

        var userPresets = loadPresets().filter { !$0.isBuiltIn }
        let existingNames = Set(userPresets.map { $0.name.lowercased() })
        var name = trimmed
        var suffix = 2
        while existingNames.contains(name.lowercased()) || name.caseInsensitiveCompare(builtInPreset.name) == .orderedSame {
            name = "\(trimmed) \(suffix)"
            suffix += 1
        }

        let preset = C64CRTPreset(
            id: UUID(),
            name: name,
            parameters: C64CRTSettings.currentParameters,
            isBuiltIn: false
        )
        userPresets.append(preset)
        try saveUserPresets(userPresets)
        activePresetID = preset.id
        return preset
    }

    @discardableResult
    static func updateActivePreset() throws -> C64CRTPreset {
        let id = activePresetID
        guard id != builtInPresetID else {
            throw C64CRTPresetStoreError.builtInPresetProtected
        }
        var userPresets = loadPresets().filter { !$0.isBuiltIn }
        guard let index = userPresets.firstIndex(where: { $0.id == id }) else {
            throw C64CRTPresetStoreError.presetNotFound
        }
        userPresets[index].parameters = C64CRTSettings.currentParameters
        try saveUserPresets(userPresets)
        return userPresets[index]
    }

    static func deletePreset(_ presetID: UUID) throws {
        guard presetID != builtInPresetID else {
            throw C64CRTPresetStoreError.builtInPresetProtected
        }
        let wasActive = activePresetID == presetID
        let referencingProfiles = EmulationProfileStore.profileNamesReferencingCRTPreset(presetID)
        guard referencingProfiles.isEmpty else {
            throw C64CRTPresetStoreError.presetInUse(referencingProfiles)
        }

        var userPresets = loadPresets().filter { !$0.isBuiltIn }
        guard userPresets.contains(where: { $0.id == presetID }) else {
            throw C64CRTPresetStoreError.presetNotFound
        }
        userPresets.removeAll { $0.id == presetID }
        try saveUserPresets(userPresets)
        if wasActive {
            _ = applyPreset(builtInPresetID)
        }
    }

    private static func saveUserPresets(_ presets: [C64CRTPreset]) throws {
        let data = try JSONEncoder().encode(presets)
        UserDefaults.standard.set(data, forKey: userPresetsKey)
    }
}

enum C64SIDEngine: String, CaseIterable, Identifiable {
    case fastSID = "FastSID"
    case reSID = "ReSID"
    case reSIDFP = "ReSID-FP"

    static let defaultsKey = "poke64.audio.sidEngine"
    static let defaultValue: C64SIDEngine = .reSID

    var id: String { rawValue }

    var title: String { rawValue }

    var detail: String {
        switch self {
        case .fastSID:
            return "Lowest CPU usage"
        case .reSID:
            return "Accurate"
        case .reSIDFP:
            return "Highest accuracy"
        }
    }
}

enum C64SIDModel: String, CaseIterable, Identifiable {
    case automatic = "default"
    case mos6581 = "6581"
    case mos8580 = "8580"
    case mos8580RD = "8580RD"

    static let defaultsKey = "poke64.audio.sidModel"
    static let defaultValue: C64SIDModel = .automatic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic:
            return "Automatic"
        case .mos6581:
            return "MOS 6581"
        case .mos8580:
            return "MOS 8580"
        case .mos8580RD:
            return "MOS 8580 RD"
        }
    }
}

enum C64ReSIDSampling: String, CaseIterable, Identifiable {
    case fast
    case interpolation
    case fastResampling = "fast resampling"
    case resampling

    static let defaultsKey = "poke64.audio.residSampling"
    static let defaultValue: C64ReSIDSampling = .resampling

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fast:
            return "Fast"
        case .interpolation:
            return "Interpolation"
        case .fastResampling:
            return "Fast Resampling"
        case .resampling:
            return "Resampling"
        }
    }
}

enum C64AudioSampleRate: String, CaseIterable, Identifiable {
    case hz44100 = "44100"
    case hz48000 = "48000"
    case hz96000 = "96000"

    static let defaultsKey = "poke64.audio.sampleRate"
    static let defaultValue: C64AudioSampleRate = .hz48000

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hz44100:
            return "44,100 Hz"
        case .hz48000:
            return "48,000 Hz"
        case .hz96000:
            return "96,000 Hz"
        }
    }
}

enum C64AudioSettings {
    static let audioLeakLevelKey = "poke64.audio.leakLevel"
    static let datasetteSoundLevelKey = "poke64.audio.datasetteSoundLevel"

    static let defaultAudioLeakLevel = 0
    static let defaultDatasetteSoundLevel = 20

    static var configurationFingerprint: String {
        let defaults = UserDefaults.standard
        return [
            defaults.string(forKey: C64SIDEngine.defaultsKey)
                ?? C64SIDEngine.defaultValue.rawValue,
            defaults.string(forKey: C64SIDModel.defaultsKey)
                ?? C64SIDModel.defaultValue.rawValue,
            defaults.string(forKey: C64ReSIDSampling.defaultsKey)
                ?? C64ReSIDSampling.defaultValue.rawValue,
            defaults.string(forKey: C64AudioSampleRate.defaultsKey)
                ?? C64AudioSampleRate.defaultValue.rawValue,
            String(defaults.object(forKey: audioLeakLevelKey) == nil
                ? defaultAudioLeakLevel
                : defaults.integer(forKey: audioLeakLevelKey)),
            String(defaults.object(forKey: datasetteSoundLevelKey) == nil
                ? defaultDatasetteSoundLevel
                : defaults.integer(forKey: datasetteSoundLevelKey))
        ].joined(separator: ":")
    }
}

enum C64DriveModel: String, CaseIterable, Identifiable {
    case cbm1541 = "1541"
    case cbm1541II = "1541-II"
    case cbm1571 = "1571"
    case cbm1581 = "1581"

    static let drive8DefaultsKey = "poke64.drive.model"
    static let drive9DefaultsKey = "poke64.drive9.model"
    static let defaultsKey = drive8DefaultsKey
    static let defaultValue: C64DriveModel = .cbm1541II

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cbm1541:
            return "Commodore 1541"
        case .cbm1541II:
            return "Commodore 1541-II"
        case .cbm1571:
            return "Commodore 1571"
        case .cbm1581:
            return "Commodore 1581"
        }
    }

    var resourceValue: Int {
        switch self {
        case .cbm1541: return 1541
        case .cbm1541II: return 1542
        case .cbm1571: return 1571
        case .cbm1581: return 1581
        }
    }

    var firmwareSlot: FirmwareSlot {
        switch self {
        case .cbm1541: return .drive1541
        case .cbm1541II: return .drive1541II
        case .cbm1571: return .drive1571
        case .cbm1581: return .drive1581
        }
    }

    var mediaSummary: String {
        switch self {
        case .cbm1541, .cbm1541II:
            return "1541-family media such as D64 and G64"
        case .cbm1571:
            return "D64 and double-sided D71 media"
        case .cbm1581:
            return "3.5-inch D81 media"
        }
    }

    var supportsMechanicalSound: Bool {
        self != .cbm1581
    }

    static func defaultsKey(for unit: Int) -> String {
        unit == 9 ? drive9DefaultsKey : drive8DefaultsKey
    }

    static func selected(for unit: Int) -> C64DriveModel {
        guard let value = UserDefaults.standard.string(forKey: defaultsKey(for: unit)),
              let model = C64DriveModel(rawValue: value) else {
            return defaultValue
        }
        return model
    }

    static var selected: C64DriveModel {
        get { selected(for: 8) }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: drive8DefaultsKey) }
    }
}

enum C64DriveSettings {
    static let trueDriveEmulationKey = "poke64.drive.trueEmulation"
    static let drive9EnabledKey = "poke64.drive9.enabled"
    static let writeProtectionKey = "poke64.drive.writeProtection"
    static let soundLevelKey = "poke64.drive.soundLevel"

    static let defaultTrueDriveEmulation = false
    static let defaultDrive9Enabled = false
    static let defaultWriteProtection = false
    static let defaultSoundLevel = 20

    static var configurationFingerprint: String {
        let defaults = UserDefaults.standard
        return [
            defaults.string(forKey: C64DriveModel.drive8DefaultsKey)
                ?? C64DriveModel.defaultValue.rawValue,
            String(defaults.object(forKey: drive9EnabledKey) == nil
                ? defaultDrive9Enabled
                : defaults.bool(forKey: drive9EnabledKey)),
            defaults.string(forKey: C64DriveModel.drive9DefaultsKey)
                ?? C64DriveModel.defaultValue.rawValue,
            String(defaults.object(forKey: trueDriveEmulationKey) == nil
                ? defaultTrueDriveEmulation
                : defaults.bool(forKey: trueDriveEmulationKey)),
            String(defaults.object(forKey: writeProtectionKey) == nil
                ? defaultWriteProtection
                : defaults.bool(forKey: writeProtectionKey)),
            String(defaults.object(forKey: soundLevelKey) == nil
                ? defaultSoundLevel
                : defaults.integer(forKey: soundLevelKey))
        ].joined(separator: ":")
    }
}

enum C64VirtualModemSettings {
    static let enabledKey = "poke64.network.virtualModem.enabled"
    static let baudKey = "poke64.network.virtualModem.baud"

    static let defaultEnabled = false
    static let defaultBaud = 9600
    static let supportedBaudRates = [300, 600, 1200, 2400, 9600]

    static var enabled: Bool {
        let defaults = UserDefaults.standard
        return defaults.object(forKey: enabledKey) == nil
            ? defaultEnabled
            : defaults.bool(forKey: enabledKey)
    }

    static var baud: Int {
        let defaults = UserDefaults.standard
        let value = defaults.object(forKey: baudKey) == nil
            ? defaultBaud
            : defaults.integer(forKey: baudKey)
        return supportedBaudRates.contains(value) ? value : defaultBaud
    }

    static var configurationFingerprint: String {
        [String(enabled), String(baud)].joined(separator: ":")
    }
}

enum SettingsPanel: String, CaseIterable, Identifiable {
    case profiles
    case system
    case graphics
    case audio
    case tape
    case diskDrives
    case printer
    case firmware
    case networking
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .profiles: "Emulation Profiles"
        case .system: "System"
        case .graphics: "Graphics"
        case .audio: "Audio"
        case .tape: "Tape"
        case .diskDrives: "Disk Drives"
        case .printer: "Printer"
        case .firmware: "Firmware / ROMs"
        case .networking: "Networking"
        case .about: "About"
        }
    }

    var icon: String {
        switch self {
        case .profiles: "square.stack.3d.up"
        case .system: "cpu"
        case .graphics: "display"
        case .audio: "waveform"
        case .tape: "rectangle.stack"
        case .diskDrives: "externaldrive"
        case .printer: "printer"
        case .firmware: "memorychip"
        case .networking: "network"
        case .about: "info.circle"
        }
    }

    var summary: String {
        switch self {
        case .profiles:
            "Save and recall complete emulator configurations."
        case .system:
            "C64 model, timing and memory expansion."
        case .graphics:
            "Display geometry, palette, VIC-II and CRT filtering."
        case .audio:
            "SID model, emulation engine and audio output."
        case .tape:
            "Datasette behavior and tape transport options."
        case .diskDrives:
            "Drive units, models and True Drive Emulation."
        case .printer:
            "IEC printer emulation and output capture."
        case .firmware:
            "BASIC, KERNAL, character and drive ROMs."
        case .networking:
            "Virtual modem, Telnet and BBS connectivity."
        case .about:
            "Version, credits, licenses and project links."
        }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: SettingsPanel

    var body: some View {
        VStack(spacing: 0) {
            settingsHeader

            Divider()

            NavigationSplitView {
                List(SettingsPanel.allCases) { panel in
                    Button {
                        selection = panel
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(panel.title)
                                Text(panel.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        } icon: {
                            Image(systemName: panel.icon)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(
                        selection == panel
                            ? Color.accentColor.opacity(0.16)
                            : Color.clear
                    )
                    .padding(.vertical, 3)
                }
                .navigationTitle("Settings")
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 340)
            } detail: {
                SettingsPanelDetail(panel: selection)
            }
            .navigationSplitViewStyle(.balanced)
        }
    }

    private var settingsHeader: some View {
        HStack(spacing: 14) {
            Text("Settings")
                .font(.headline)

            Spacer()

            Button("Done") {
                dismiss()
            }
            .fontWeight(.semibold)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }
}

private struct SettingsPanelDetail: View {
    let panel: SettingsPanel

    var body: some View {
        Group {
            switch panel {
            case .profiles:
                EmulationProfilesSettingsView()
            case .system:
                SystemSettingsView()
            case .graphics:
                VideoSettingsView()
            case .audio:
                AudioSettingsView()
            case .tape:
                TapeSettingsView()
            case .diskDrives:
                DiskDriveSettingsView()
            case .printer:
                PrinterSettingsView()
            case .firmware:
                FirmwareSettingsView()
            case .networking:
                VirtualModemSettingsView()
            case .about:
                AboutSettingsView()
            }
        }
        .navigationTitle(panel.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct EmulationProfilesSettingsView: View {
    @State private var profiles = EmulationProfileStore.loadProfiles()
    @State private var selectedProfileID = EmulationProfileStore.selectedProfileID
    @State private var powerOnProfileID = EmulationProfileStore.powerOnProfileID
    @State private var nameEditor: ProfileNameEditor?
    @State private var pendingDeleteProfile: EmulationProfile?
    @State private var pendingResetDefault = false
    @State private var pendingSwitchProfileID: UUID?
    @State private var errorMessage: String?
    @State private var statusMessage: String?

    private var selectedProfile: EmulationProfile? {
        guard let selectedProfileID else { return nil }
        return profiles.first { $0.id == selectedProfileID }
    }

    private var selectedProfileMatchesCurrent: Bool {
        guard let selectedProfile else { return false }
        return EmulationProfileStore.matchesCurrentConfiguration(selectedProfile)
    }

    private var currentProfileTitle: String {
        guard let selectedProfile else { return "Custom configuration" }
        return selectedProfileMatchesCurrent
            ? selectedProfile.name
            : "\(selectedProfile.name) — Modified"
    }

    private func firmwareProfileName(for profile: EmulationProfile) -> String {
        guard let firmwareProfileID = profile.firmwareProfileID else {
            return "Current firmware"
        }
        return FirmwareProfileStore.loadProfiles()
            .first(where: { $0.id == firmwareProfileID })?.name
            ?? "Missing firmware profile"
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Current profile", value: currentProfileTitle)
                LabeledContent(
                    "Firmware profile",
                    value: FirmwareProfileStore.activeProfile?.name ?? FirmwareStore.activeProfileName
                )

                if let selectedProfile, !selectedProfileMatchesCurrent {
                    Label(
                        "Settings have changed since this profile was applied.",
                        systemImage: "pencil.and.outline"
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)

                    Button("Update \"\(selectedProfile.name)\" from Current Settings") {
                        updateProfile(selectedProfile.id)
                    }
                }

                if let statusMessage {
                    Label(statusMessage, systemImage: "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.green)
                }
            } header: {
                Text("Current Configuration")
            } footer: {
                Text("Applying a profile updates POKE64 settings immediately. Hardware-affecting changes restart the C64 when Settings is closed.")
            }

            Section {
                Picker("Power-on profile", selection: Binding(
                    get: { powerOnProfileID },
                    set: { profileID in
                        powerOnProfileID = profileID
                        EmulationProfileStore.powerOnProfileID = profileID
                    }
                )) {
                    Text("Keep current profile")
                        .tag(nil as UUID?)
                    ForEach(profiles) { profile in
                        Text(profile.name)
                            .tag(profile.id as UUID?)
                    }
                }
            } header: {
                Text("Power")
            } footer: {
                Text("Choose a profile to apply the next time the emulated C64 is powered on. Keep Current Profile preserves the active profile across power cycles. Closing and reopening POKE64 still resumes the previous session when available.")
            }

            Section {
                ForEach(profiles) { profile in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(profile.name)
                                        .font(.headline)

                                    if EmulationProfileStore.isBuiltInProfile(profile.id) {
                                        Label("Built-in", systemImage: "lock.fill")
                                            .labelStyle(.titleAndIcon)
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                            .accessibilityLabel("Built-in Default profile")
                                    }

                                    if selectedProfileID == profile.id
                                        && EmulationProfileStore.matchesCurrentConfiguration(profile) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                            .accessibilityLabel("Active profile")
                                    }
                                }

                                Text(profile.settings.compactSummary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 12)

                            Button("Apply") {
                                requestProfileSwitch(profile.id)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(
                                selectedProfileID == profile.id
                                    && EmulationProfileStore.matchesCurrentConfiguration(profile)
                            )

                            Menu {
                                Button("Duplicate") {
                                    duplicateProfile(profile.id)
                                }
                                if EmulationProfileStore.isBuiltInProfile(profile.id) {
                                    Divider()
                                    Button("Reset to Initial Settings…") {
                                        pendingResetDefault = true
                                    }
                                } else {
                                    Button("Rename") {
                                        nameEditor = ProfileNameEditor(
                                            mode: .rename(profile.id),
                                            name: profile.name
                                        )
                                    }
                                    Divider()
                                    Button("Delete", role: .destructive) {
                                        pendingDeleteProfile = profile
                                    }
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .font(.title3)
                            }
                            .buttonStyle(.borderless)
                        }

                        Label(
                            "Firmware: \(firmwareProfileName(for: profile))",
                            systemImage: "memorychip"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        if let reuImageName = profile.settings.reuImageName {
                            Label("REU image: \(reuImageName)", systemImage: "memorychip")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Button {
                    nameEditor = ProfileNameEditor(mode: .createBlank, name: "")
                } label: {
                    Label("New Profile", systemImage: "plus.circle.fill")
                }

                Button {
                    nameEditor = ProfileNameEditor(mode: .createFromCurrent, name: "")
                } label: {
                    Label("New Profile from Current Settings", systemImage: "plus.square.on.square")
                }
            } header: {
                Text("Profiles")
            } footer: {
                Text("Default is always available and can be updated or duplicated, but it cannot be renamed or deleted. New Profile starts from clean POKE64 hardware settings and keeps the current Firmware Profile; New Profile from Current Settings captures the current configuration. Mounted PRG/D64/G64/TAP/CRT media are not stored in a profile.")
            }

            Section("Profile Scope") {
                Label(
                    "Imported .reu images are snapshotted into the profile. Apply restores a working copy; Update Profile captures later changes.",
                    systemImage: "memorychip"
                )
                Label(
                    "Each emulation profile references a Firmware Profile by ID. ROM files remain stored once in Firmware Profiles and are restored when the emulation profile is applied.",
                    systemImage: "memorychip.fill"
                )
                Label(
                    "The BBS directory and runtime physical-controller assignments remain global; profiles store the modem state and baud rate only.",
                    systemImage: "network"
                )
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .sheet(item: $nameEditor) { editor in
            ProfileNameEditorSheet(editor: editor) { mode, name in
                switch mode {
                case .createBlank:
                    createBlankProfile(named: name)
                case .createFromCurrent:
                    createProfileFromCurrentSettings(named: name)
                case .rename(let profileID):
                    renameProfile(profileID, to: name)
                }
            }
        }
        .confirmationDialog(
            pendingDeleteProfile.map { "Delete \"\($0.name)\"?" } ?? "Delete Profile?",
            isPresented: Binding(
                get: { pendingDeleteProfile != nil },
                set: { if !$0 { pendingDeleteProfile = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let profile = pendingDeleteProfile {
                Button("Delete Profile", role: .destructive) {
                    deleteProfile(profile.id)
                    pendingDeleteProfile = nil
                }
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteProfile = nil
            }
        } message: {
            Text("This removes the saved configuration and any REU image snapshot stored with the profile. Mounted Library media is not affected.")
        }
        .confirmationDialog(
            "Reset Default to Initial Settings?",
            isPresented: $pendingResetDefault,
            titleVisibility: .visible
        ) {
            Button("Reset Default", role: .destructive) {
                resetBuiltInDefault()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This restores Default to POKE64's initial emulator settings and removes its saved REU image. Its Firmware Profile association is preserved.")
        }
        .confirmationDialog(
            "Unsaved Profile Changes",
            isPresented: Binding(
                get: { pendingSwitchProfileID != nil },
                set: { if !$0 { pendingSwitchProfileID = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let targetID = pendingSwitchProfileID {
                Button("Save Current Changes and Switch") {
                    updateCurrentProfileAndSwitch(to: targetID)
                    pendingSwitchProfileID = nil
                }
                Button("Discard Changes and Switch", role: .destructive) {
                    performProfileSwitch(targetID)
                    pendingSwitchProfileID = nil
                }
            }
            Button("Cancel", role: .cancel) {
                pendingSwitchProfileID = nil
            }
        } message: {
            Text("The current emulation profile or its firmware profile has unsaved changes. Saving firmware changes updates the shared Firmware Profile.")
        }
        .alert(
            "Emulation Profile Error",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Unknown profile error")
        }
        .onAppear {
            reloadProfiles()
        }
    }

    private func reloadProfiles() {
        profiles = EmulationProfileStore.loadProfiles()
        selectedProfileID = EmulationProfileStore.selectedProfileID
        powerOnProfileID = EmulationProfileStore.powerOnProfileID
    }

    private func createBlankProfile(named name: String) {
        do {
            let profile = try EmulationProfileStore.createBlankProfile(named: name)
            reloadProfiles()
            statusMessage = "Created clean profile \"\(profile.name)\"."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createProfileFromCurrentSettings(named name: String) {
        do {
            let profile = try EmulationProfileStore.createProfile(named: name)
            reloadProfiles()
            statusMessage = "Saved \"\(profile.name)\" from current settings."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func renameProfile(_ profileID: UUID, to name: String) {
        do {
            let profile = try EmulationProfileStore.renameProfile(profileID, to: name)
            reloadProfiles()
            statusMessage = "Renamed profile to \"\(profile.name)\"."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func duplicateProfile(_ profileID: UUID) {
        do {
            let profile = try EmulationProfileStore.duplicateProfile(profileID)
            reloadProfiles()
            statusMessage = "Created \"\(profile.name)\"."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteProfile(_ profileID: UUID) {
        do {
            try EmulationProfileStore.deleteProfile(profileID)
            reloadProfiles()
            statusMessage = "Profile deleted."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func requestProfileSwitch(_ profileID: UUID) {
        if let selectedProfile, !selectedProfileMatchesCurrent {
            pendingSwitchProfileID = profileID
            return
        }
        performProfileSwitch(profileID)
    }

    private func updateCurrentProfileAndSwitch(to profileID: UUID) {
        guard let selectedProfileID else {
            performProfileSwitch(profileID)
            return
        }

        do {
            if FirmwareProfileStore.activeProfileIsModified,
               let activeFirmwareProfileID = FirmwareProfileStore.activeProfileID {
                _ = try FirmwareProfileStore.updateProfile(activeFirmwareProfileID)
            }
            _ = try EmulationProfileStore.updateProfile(selectedProfileID)
            try EmulationProfileStore.applyProfile(profileID)
            reloadProfiles()
            if let profile = profiles.first(where: { $0.id == profileID }) {
                statusMessage = "Applied \(profile.name)."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func performProfileSwitch(_ profileID: UUID) {
        do {
            try EmulationProfileStore.applyProfile(profileID)
            reloadProfiles()
            if let profile = profiles.first(where: { $0.id == profileID }) {
                statusMessage = "Applied \(profile.name)."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resetBuiltInDefault() {
        do {
            let profile = try EmulationProfileStore.resetBuiltInDefaultToInitialSettings()
            reloadProfiles()
            statusMessage = "Reset \"\(profile.name)\" to initial settings."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func updateProfile(_ profileID: UUID) {
        do {
            let profile = try EmulationProfileStore.updateProfile(profileID)
            reloadProfiles()
            statusMessage = "Updated \"\(profile.name)\" from the current configuration."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ProfileNameEditor: Identifiable {
    enum Mode {
        case createBlank
        case createFromCurrent
        case rename(UUID)
    }

    let id = UUID()
    let mode: Mode
    let name: String
}

private struct ProfileNameEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let editor: ProfileNameEditor
    let onSave: (ProfileNameEditor.Mode, String) -> Void

    @State private var name: String

    init(
        editor: ProfileNameEditor,
        onSave: @escaping (ProfileNameEditor.Mode, String) -> Void
    ) {
        self.editor = editor
        self.onSave = onSave
        _name = State(initialValue: editor.name)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var title: String {
        switch editor.mode {
        case .createBlank:
            return "New Emulation Profile"
        case .createFromCurrent:
            return "New Profile from Current Settings"
        case .rename:
            return "Rename Profile"
        }
    }

    private var profileDescription: String {
        switch editor.mode {
        case .createBlank:
            return "Starts from POKE64's clean hardware settings and uses the current Firmware Profile. Mounted media is not included."
        case .createFromCurrent:
            return "Captures the current emulator configuration. Mounted media remains part of the current session or Library item."
        case .rename:
            return "Renaming changes only the profile name."
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile Name") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                }

                Section {
                    Text(profileDescription)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(editor.mode, trimmedName)
                        dismiss()
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}


private struct SystemSettingsView: View {
    @AppStorage(C64MachineModel.defaultsKey)
    private var selectedModelRawValue = C64MachineModel.defaultModel.rawValue

    @AppStorage(C64REUSize.defaultsKey)
    private var selectedREUSizeRawValue = C64REUSize.defaultValue.rawValue

    @AppStorage(C64REUSettings.persistentMemoryKey)
    private var persistentREUMemory = C64REUSettings.defaultPersistentMemory

    @State private var showREUImporter = false
    @State private var reuImageInfo = FirmwareStore.importedREUImageInfo()
    @State private var reuImageError: String?

    private var selectedModel: C64MachineModel {
        C64MachineModel(rawValue: selectedModelRawValue) ?? .defaultModel
    }

    private var selectedREUSize: C64REUSize {
        C64REUSize(rawValue: selectedREUSizeRawValue) ?? .defaultValue
    }

    private var systemDefaultsAreSelected: Bool {
        selectedModel == .defaultModel
            && selectedREUSize == .defaultValue
            && persistentREUMemory == C64REUSettings.defaultPersistentMemory
            && reuImageInfo == nil
    }

    var body: some View {
        Form {
            Section {
                Picker("Machine model", selection: $selectedModelRawValue) {
                    ForEach(C64MachineModel.allCases) { model in
                        Text(model.title).tag(model.rawValue)
                    }
                }
                .pickerStyle(.menu)

                LabeledContent("Video standard", value: selectedModel.region)
                LabeledContent("Timing", value: selectedModel.timingSummary)
                LabeledContent("Profile", value: selectedModel.hardwareSummary)
            } header: {
                Text("Machine")
            } footer: {
                Text("Changing the machine model restarts the C64 when Settings is closed. PAL and NTSC also change the core timing and video geometry.")
            }

            Section {
                Picker("RAM Expansion Unit", selection: $selectedREUSizeRawValue) {
                    ForEach(C64REUSize.allCases) { size in
                        Text(size.title).tag(size.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .disabled(reuImageInfo != nil)

                Toggle(
                    reuImageInfo == nil
                        ? "Persistent REU memory"
                        : "Save changes to imported image",
                    isOn: $persistentREUMemory
                )
                .disabled(selectedREUSize == .disabled)

                if let reuImageInfo {
                    LabeledContent("REU image", value: reuImageInfo.filename)
                    LabeledContent("Detected size", value: reuImageInfo.size.capacityTitle)

                    HStack {
                        Button("Replace REU Image…") {
                            showREUImporter = true
                        }
                        .buttonStyle(.bordered)

                        Button("Eject Image", role: .destructive) {
                            removeImportedREUImage()
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    Button("Load REU Image…") {
                        showREUImporter = true
                    }
                    .buttonStyle(.bordered)
                }
            } header: {
                Text("Memory Expansion")
            } footer: {
                if reuImageInfo == nil {
                    Text("REU changes restart the C64 when Settings is closed. Persistent memory restores the REU image at startup and writes it when the core closes.")
                } else {
                    Text("Imported .reu files are copied into the POKE64 sandbox and their size selects the matching REU automatically. Save changes writes back to the sandbox copy, never to the original file in Files.")
                }
            }

            Section("Compatibility") {
                Label(
                    "Start with C64 PAL unless software specifically requires NTSC or the later C64C profile.",
                    systemImage: "info.circle"
                )

                Label(
                    "The REU shares the expansion port address space. Some CRT cartridges may conflict with it or require it to be disabled.",
                    systemImage: "exclamationmark.triangle"
                )
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            Section {
                Button("Restore System Defaults") {
                    do {
                        if reuImageInfo != nil {
                            try FirmwareStore.removeImportedREUImage()
                            reuImageInfo = nil
                        }
                        selectedModelRawValue = C64MachineModel.defaultModel.rawValue
                        selectedREUSizeRawValue = C64REUSize.defaultValue.rawValue
                        persistentREUMemory = C64REUSettings.defaultPersistentMemory
                    } catch {
                        reuImageError = error.localizedDescription
                    }
                }
                .disabled(systemDefaultsAreSelected)
            }
        }
        .fileImporter(
            isPresented: $showREUImporter,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            do {
                let urls = try result.get()
                guard let url = urls.first else { return }
                let accessing = url.startAccessingSecurityScopedResource()
                defer {
                    if accessing {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                let info = try FirmwareStore.importREUImage(from: url)
                selectedREUSizeRawValue = info.size.rawValue
                reuImageInfo = info
            } catch {
                reuImageError = error.localizedDescription
            }
        }
        .alert(
            "REU image error",
            isPresented: Binding(
                get: { reuImageError != nil },
                set: { if !$0 { reuImageError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(reuImageError ?? "Unknown error")
        }
    }

    private func removeImportedREUImage() {
        do {
            try FirmwareStore.removeImportedREUImage()
            reuImageInfo = nil
        } catch {
            reuImageError = error.localizedDescription
        }
    }
}


private struct VideoSettingsView: View {
    @State private var showCRTAdvanced = false

    @AppStorage(C64CRTSettings.enabledKey)
    private var crtFilterEnabled = C64CRTSettings.defaultEnabled

    @AppStorage(C64VideoAspectRatio.defaultsKey)
    private var aspectRatioRawValue = C64VideoAspectRatio.defaultValue.rawValue

    @AppStorage(C64VideoCrop.defaultsKey)
    private var cropRawValue = C64VideoCrop.defaultValue.rawValue

    @AppStorage(C64VideoSettings.cropDelayKey)
    private var cropDelay = C64VideoSettings.defaultCropDelay

    @AppStorage(C64VideoPalette.defaultsKey)
    private var paletteRawValue = C64VideoPalette.defaultValue.rawValue

    @AppStorage(C64VideoFilter.defaultsKey)
    private var filterRawValue = C64VideoFilter.defaultValue.rawValue

    @AppStorage(C64VideoSettings.brightnessKey)
    private var brightness = C64VideoSettings.defaultBrightness

    @AppStorage(C64VideoSettings.contrastKey)
    private var contrast = C64VideoSettings.defaultContrast

    @AppStorage(C64VideoSettings.saturationKey)
    private var saturation = C64VideoSettings.defaultSaturation

    @AppStorage(C64VideoSettings.gammaKey)
    private var gamma = C64VideoSettings.defaultGamma

    @AppStorage(C64VideoSettings.tintKey)
    private var tint = C64VideoSettings.defaultTint

    private var selectedCrop: C64VideoCrop {
        C64VideoCrop(rawValue: cropRawValue) ?? .defaultValue
    }

    private var selectedPalette: C64VideoPalette {
        C64VideoPalette(rawValue: paletteRawValue) ?? .defaultValue
    }

    var body: some View {
        Form {
            Section {
                Picker("Pixel aspect ratio", selection: $aspectRatioRawValue) {
                    ForEach(C64VideoAspectRatio.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                .pickerStyle(.menu)

                Picker("Borders", selection: $cropRawValue) {
                    ForEach(C64VideoCrop.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                .pickerStyle(.menu)

                Toggle("Automatic crop delay", isOn: $cropDelay)
                    .disabled(selectedCrop != .automatic)
            } header: {
                Text("Display Geometry")
            } footer: {
                Text("Automatic uses the selected PAL or NTSC machine model. Crop changes the video geometry while preserving the core-provided display ratio.")
            }

            Section {
                Picker("Palette", selection: $paletteRawValue) {
                    ForEach(C64VideoPalette.allCases) { palette in
                        Text(palette.title).tag(palette.rawValue)
                    }
                }
                .pickerStyle(.menu)

                Picker("VIC-II filter", selection: $filterRawValue) {
                    ForEach(C64VideoFilter.allCases) { filter in
                        Text(filter.title).tag(filter.rawValue)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("VIC-II Appearance")
            } footer: {
                Text("The VIC-II filter runs inside VICE. The CRT filter below is a separate Metal post-process and can be adjusted live.")
            }

            Section {
                Toggle("CRT Filter", isOn: $crtFilterEnabled)

                Button {
                    showCRTAdvanced = true
                } label: {
                    HStack {
                        Text("Advanced…")
                        Spacer()
                        Text(C64CRTPresetStore.activePresetIsModified
                            ? "\(C64CRTPresetStore.activePreset.name) · Modified"
                            : C64CRTPresetStore.activePreset.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("CRT Filter")
            } footer: {
                Text("CRT-Lottes-inspired Metal filtering. Advanced controls are applied immediately and do not restart the C64.")
            }

            Section {
                VideoAdjustmentSlider(
                    title: "Brightness",
                    value: $brightness,
                    range: 20...2000,
                    step: 20,
                    valueText: Self.percentageText
                )
                VideoAdjustmentSlider(
                    title: "Contrast",
                    value: $contrast,
                    range: 20...2000,
                    step: 20,
                    valueText: Self.percentageText
                )
                VideoAdjustmentSlider(
                    title: "Saturation",
                    value: $saturation,
                    range: 20...2000,
                    step: 20,
                    valueText: Self.percentageText
                )
                VideoAdjustmentSlider(
                    title: "Gamma",
                    value: $gamma,
                    range: 1000...4000,
                    step: 50,
                    valueText: Self.gammaText
                )
                VideoAdjustmentSlider(
                    title: "Tint",
                    value: $tint,
                    range: 20...2000,
                    step: 20,
                    valueText: Self.percentageText
                )
            } header: {
                Text("Advanced Color")
            } footer: {
                Text(selectedPalette.supportsColorAdjustments
                    ? "Color adjustments apply to VICE's internal palette."
                    : "Select Internal (adjustable) to enable these controls.")
            }
            .disabled(!selectedPalette.supportsColorAdjustments)

            Section {
                Button("Restore Video Defaults") {
                    restoreDefaults()
                }
                .disabled(isUsingDefaults)
            } footer: {
                Text("Video changes are applied when Settings is closed and the C64 restarts.")
            }
        }
        .fullScreenCover(isPresented: $showCRTAdvanced) {
            CRTAdvancedSettingsView()
        }
    }

    private var isUsingDefaults: Bool {
        aspectRatioRawValue == C64VideoAspectRatio.defaultValue.rawValue
            && cropRawValue == C64VideoCrop.defaultValue.rawValue
            && cropDelay == C64VideoSettings.defaultCropDelay
            && paletteRawValue == C64VideoPalette.defaultValue.rawValue
            && filterRawValue == C64VideoFilter.defaultValue.rawValue
            && brightness == C64VideoSettings.defaultBrightness
            && contrast == C64VideoSettings.defaultContrast
            && saturation == C64VideoSettings.defaultSaturation
            && gamma == C64VideoSettings.defaultGamma
            && tint == C64VideoSettings.defaultTint
            && crtFilterEnabled == C64CRTSettings.defaultEnabled
            && C64CRTPresetStore.activePresetID == C64CRTPresetStore.builtInPresetID
            && !C64CRTPresetStore.activePresetIsModified
    }

    private func restoreDefaults() {
        aspectRatioRawValue = C64VideoAspectRatio.defaultValue.rawValue
        cropRawValue = C64VideoCrop.defaultValue.rawValue
        cropDelay = C64VideoSettings.defaultCropDelay
        paletteRawValue = C64VideoPalette.defaultValue.rawValue
        filterRawValue = C64VideoFilter.defaultValue.rawValue
        brightness = C64VideoSettings.defaultBrightness
        contrast = C64VideoSettings.defaultContrast
        saturation = C64VideoSettings.defaultSaturation
        gamma = C64VideoSettings.defaultGamma
        tint = C64VideoSettings.defaultTint
        crtFilterEnabled = C64CRTSettings.defaultEnabled
        _ = C64CRTPresetStore.applyPreset(C64CRTPresetStore.builtInPresetID)
    }

    private static func percentageText(_ value: Int) -> String {
        "\(value / 10)%"
    }

    private static func gammaText(_ value: Int) -> String {
        String(format: "%.2f", Double(value) / 1000.0)
    }
}

private struct VideoAdjustmentSlider: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let valueText: (Int) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text(valueText(value))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { value = Int($0.rounded()) }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: Double(step)
            )
        }
        .padding(.vertical, 2)
    }
}

private struct CRTAdvancedSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var emulator: EmulatorModel

    @AppStorage(C64CRTSettings.scanlineIntensityKey)
    private var scanlineIntensity = C64CRTSettings.defaultParameters.scanlineIntensity
    @AppStorage(C64CRTSettings.beamSoftnessKey)
    private var beamSoftness = C64CRTSettings.defaultParameters.beamSoftness
    @AppStorage(C64CRTSettings.sharpnessKey)
    private var sharpness = C64CRTSettings.defaultParameters.sharpness
    @AppStorage(C64CRTSettings.maskIntensityKey)
    private var maskIntensity = C64CRTSettings.defaultParameters.maskIntensity
    @AppStorage(C64CRTSettings.maskTypeKey)
    private var maskType = C64CRTSettings.defaultParameters.maskType
    @AppStorage(C64CRTSettings.curvatureKey)
    private var curvature = C64CRTSettings.defaultParameters.curvature
    @AppStorage(C64CRTSettings.brightnessKey)
    private var brightness = C64CRTSettings.defaultParameters.brightness
    @AppStorage(C64CRTSettings.bloomAmountKey)
    private var bloomAmount = C64CRTSettings.defaultParameters.bloomAmount
    @AppStorage(C64CRTSettings.bloomSoftnessKey)
    private var bloomSoftness = C64CRTSettings.defaultParameters.bloomSoftness

    @State private var presets = C64CRTPresetStore.loadPresets()
    @State private var selectedPresetID = C64CRTPresetStore.activePresetID
    @State private var showSaveAs = false
    @State private var newPresetName = ""
    @State private var pendingDelete = false
    @State private var errorMessage: String?

    private var selectedPreset: C64CRTPreset {
        presets.first(where: { $0.id == selectedPresetID }) ?? C64CRTPresetStore.builtInPreset
    }

    private var isModified: Bool {
        C64CRTSettings.currentParameters != selectedPreset.parameters
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                if usesSideBySideLayout(geometry.size) {
                    HStack(spacing: 0) {
                        Form {
                            presetSection
                            pictureSection
                            maskSection
                            tubeSection
                            actionsSection
                        }
                        .frame(
                            width: min(
                                500,
                                max(360, geometry.size.width * 0.44)
                            )
                        )

                        Divider()

                        landscapePreviewPane
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    Form {
                        portraitPreviewSection
                        presetSection
                        pictureSection
                        maskSection
                        tubeSection
                        actionsSection
                    }
                }
            }
            .navigationTitle("CRT Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Save CRT Preset", isPresented: $showSaveAs) {
                TextField("Preset name", text: $newPresetName)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    do {
                        let preset = try C64CRTPresetStore.saveCurrentPreset(named: newPresetName)
                        selectedPresetID = preset.id
                        reloadPresets()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            } message: {
                Text("Save the current CRT adjustments as a reusable preset.")
            }
            .confirmationDialog(
                "Delete \"\(selectedPreset.name)\"?",
                isPresented: $pendingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete Preset", role: .destructive) {
                    do {
                        try C64CRTPresetStore.deletePreset(selectedPresetID)
                        selectedPresetID = C64CRTPresetStore.activePresetID
                        reloadPresets()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert(
                "CRT Preset Error",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
        }
    }

    private func usesSideBySideLayout(_ size: CGSize) -> Bool {
        size.width > size.height && size.width >= 760
    }

    @ViewBuilder
    private var previewContent: some View {
        if emulator.isRunning, emulator.isPoweredOn {
            CRTLivePreviewRepresentable()
                .environmentObject(emulator)
                .background(.black)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                }
        } else {
            ContentUnavailableView(
                "Live Preview Unavailable",
                systemImage: "display.slash",
                description: Text("Power on the C64 to preview CRT adjustments live.")
            )
        }
    }

    private var portraitPreviewSection: some View {
        Section {
            previewContent
                .frame(maxWidth: .infinity)
                .frame(height: 220)
        } header: {
            Text("Live Preview")
        }
    }

    private var landscapePreviewPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Live Preview")
                .font(.headline)

            previewContent
                .aspectRatio(4.0 / 3.0, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Text("CRT adjustments update here immediately.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }

    private var presetSection: some View {
        Section {
            Picker("Preset", selection: $selectedPresetID) {
                ForEach(presets) { preset in
                    Text(preset.name).tag(preset.id)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: selectedPresetID) { _, newValue in
                _ = C64CRTPresetStore.applyPreset(newValue)
                reloadPresets()
            }

            LabeledContent("Status") {
                Text(isModified ? "Modified" : "Preset values")
                    .foregroundStyle(isModified ? .orange : .secondary)
            }
        } header: {
            Text("Preset")
        }
    }

    private var pictureSection: some View {
        Section {
            CRTAdjustmentSlider(
                title: "Scanlines",
                value: $scanlineIntensity,
                range: 0...1
            )
            CRTAdjustmentSlider(
                title: "Beam Softness",
                value: $beamSoftness,
                range: 0...1
            )
            CRTAdjustmentSlider(
                title: "Sharpness",
                value: $sharpness,
                range: 0...1
            )
            CRTAdjustmentSlider(
                title: "Brightness",
                value: $brightness,
                range: 0.80...1.30,
                valueText: { "\(Int(($0 * 100).rounded()))%" }
            )
        } header: {
            Text("Picture")
        }
    }

    private var maskSection: some View {
        Section {
            Picker("Mask Type", selection: $maskType) {
                ForEach(C64CRTMaskType.allCases) { type in
                    Text(type.title).tag(type.rawValue)
                }
            }
            .pickerStyle(.menu)

            CRTAdjustmentSlider(
                title: "Mask Strength",
                value: $maskIntensity,
                range: 0...1
            )
            .disabled(maskType == C64CRTMaskType.off.rawValue)
        } header: {
            Text("Phosphor Mask")
        } footer: {
            Text("Dot Mask gives a classic shadow-mask look; Aperture Grille uses vertical RGB stripes; VGA uses wider staggered phosphor groups.")
        }
    }

    private var tubeSection: some View {
        Section {
            CRTAdjustmentSlider(
                title: "Curvature",
                value: $curvature,
                range: 0...1
            )
            CRTAdjustmentSlider(
                title: "Bloom",
                value: $bloomAmount,
                range: 0...1
            )
            CRTAdjustmentSlider(
                title: "Bloom Softness",
                value: $bloomSoftness,
                range: 0...1
            )
        } header: {
            Text("Tube")
        } footer: {
            Text("Bloom adds a restrained phosphor glow around bright pixels. Softness controls how broadly that glow spreads.")
        }
    }

    private var actionsSection: some View {
        Section {
            Button("Reset to Preset") {
                _ = C64CRTPresetStore.applyPreset(selectedPresetID)
            }
            .disabled(!isModified)

            if !selectedPreset.isBuiltIn {
                Button("Update \"\(selectedPreset.name)\"") {
                    do {
                        _ = try C64CRTPresetStore.updateActivePreset()
                        reloadPresets()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
                .disabled(!isModified)
            }

            Button("Save As…") {
                newPresetName = selectedPreset.isBuiltIn
                    ? "My Commodore Monitor"
                    : "\(selectedPreset.name) Copy"
                showSaveAs = true
            }

            if !selectedPreset.isBuiltIn {
                Button("Delete Preset", role: .destructive) {
                    pendingDelete = true
                }
            }
        }
    }

    private func reloadPresets() {
        presets = C64CRTPresetStore.loadPresets()
        let activeID = C64CRTPresetStore.activePresetID
        if presets.contains(where: { $0.id == activeID }) {
            selectedPresetID = activeID
        } else {
            selectedPresetID = C64CRTPresetStore.builtInPresetID
        }
    }
}

private struct CRTLivePreviewRepresentable: UIViewRepresentable {
    @EnvironmentObject private var emulator: EmulatorModel

    final class Coordinator {
        let emulator: EmulatorModel

        init(emulator: EmulatorModel) {
            self.emulator = emulator
        }
    }

    @AppStorage(C64CRTSettings.scanlineIntensityKey)
    private var scanlineIntensity = C64CRTSettings.defaultParameters.scanlineIntensity
    @AppStorage(C64CRTSettings.beamSoftnessKey)
    private var beamSoftness = C64CRTSettings.defaultParameters.beamSoftness
    @AppStorage(C64CRTSettings.sharpnessKey)
    private var sharpness = C64CRTSettings.defaultParameters.sharpness
    @AppStorage(C64CRTSettings.maskIntensityKey)
    private var maskIntensity = C64CRTSettings.defaultParameters.maskIntensity
    @AppStorage(C64CRTSettings.maskTypeKey)
    private var maskType = C64CRTSettings.defaultParameters.maskType
    @AppStorage(C64CRTSettings.curvatureKey)
    private var curvature = C64CRTSettings.defaultParameters.curvature
    @AppStorage(C64CRTSettings.brightnessKey)
    private var brightness = C64CRTSettings.defaultParameters.brightness
    @AppStorage(C64CRTSettings.bloomAmountKey)
    private var bloomAmount = C64CRTSettings.defaultParameters.bloomAmount
    @AppStorage(C64CRTSettings.bloomSoftnessKey)
    private var bloomSoftness = C64CRTSettings.defaultParameters.bloomSoftness

    func makeCoordinator() -> Coordinator {
        Coordinator(emulator: emulator)
    }

    func makeUIView(context: Context) -> C64MetalView {
        let view = C64MetalView(frame: .zero)
        view.isUserInteractionEnabled = false
        applyCRTSettings(to: view)
        emulator.attach(crtPreviewVideoView: view)
        return view
    }

    func updateUIView(_ uiView: C64MetalView, context: Context) {
        applyCRTSettings(to: uiView)
        emulator.attach(crtPreviewVideoView: uiView)
    }

    static func dismantleUIView(_ uiView: C64MetalView, coordinator: Coordinator) {
        coordinator.emulator.attach(crtPreviewVideoView: nil)
    }

    private func applyCRTSettings(to view: C64MetalView) {
        view.crtFilterEnabled = true
        view.crtScanlineIntensity = Float(scanlineIntensity)
        view.crtBeamSoftness = Float(beamSoftness)
        view.crtSharpness = Float(sharpness)
        view.crtMaskIntensity = Float(maskIntensity)
        view.crtMaskType = maskType
        view.crtCurvature = Float(curvature)
        view.crtBrightness = Float(brightness)
        view.crtBloomAmount = Float(bloomAmount)
        view.crtBloomSoftness = Float(bloomSoftness)
        view.setNeedsDisplay()
    }
}

private struct CRTAdjustmentSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var valueText: (Double) -> String = { "\(Int(($0 * 100).rounded()))%" }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(valueText(value))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range)
        }
        .padding(.vertical, 2)
    }
}

private struct AudioSettingsView: View {
    @AppStorage(C64SIDEngine.defaultsKey)
    private var sidEngineRawValue = C64SIDEngine.defaultValue.rawValue

    @AppStorage(C64SIDModel.defaultsKey)
    private var sidModelRawValue = C64SIDModel.defaultValue.rawValue

    @AppStorage(C64ReSIDSampling.defaultsKey)
    private var residSamplingRawValue = C64ReSIDSampling.defaultValue.rawValue

    @AppStorage(C64AudioSampleRate.defaultsKey)
    private var sampleRateRawValue = C64AudioSampleRate.defaultValue.rawValue

    @AppStorage(C64AudioSettings.audioLeakLevelKey)
    private var audioLeakLevel = C64AudioSettings.defaultAudioLeakLevel

    @AppStorage(C64AudioSettings.datasetteSoundLevelKey)
    private var datasetteSoundLevel = C64AudioSettings.defaultDatasetteSoundLevel

    private var selectedEngine: C64SIDEngine {
        C64SIDEngine(rawValue: sidEngineRawValue) ?? .defaultValue
    }

    var body: some View {
        Form {
            Section {
                Picker("Emulation engine", selection: $sidEngineRawValue) {
                    ForEach(C64SIDEngine.allCases) { engine in
                        Text(engine.title).tag(engine.rawValue)
                    }
                }
                .pickerStyle(.menu)

                Picker("SID model", selection: $sidModelRawValue) {
                    ForEach(C64SIDModel.allCases) { model in
                        Text(model.title).tag(model.rawValue)
                    }
                }
                .pickerStyle(.menu)

                LabeledContent("Engine profile", value: selectedEngine.detail)
            } header: {
                Text("SID")
            } footer: {
                Text("Automatic selects the traditional 6581 for C64 models and the later 8580 for C64C models. ReSID-FP is the most accurate option; FastSID is intended for lower-powered hardware.")
            }

            Section {
                Picker("ReSID sampling", selection: $residSamplingRawValue) {
                    ForEach(C64ReSIDSampling.allCases) { sampling in
                        Text(sampling.title).tag(sampling.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .disabled(selectedEngine == .fastSID)

                Picker("Sample rate", selection: $sampleRateRawValue) {
                    ForEach(C64AudioSampleRate.allCases) { rate in
                        Text(rate.title).tag(rate.rawValue)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("Audio Quality")
            } footer: {
                Text(selectedEngine == .fastSID
                    ? "ReSID sampling is unavailable while FastSID is selected. 48,000 Hz is recommended for normal iPad playback."
                    : "Resampling provides the highest ReSID quality. 48,000 Hz is recommended for normal iPad playback.")
            }

            Section {
                AudioLevelSlider(
                    title: "VIC-II audio leak",
                    value: $audioLeakLevel,
                    range: 0...10,
                    step: 1,
                    valueText: { $0 == 0 ? "Off" : "Level \($0)" }
                )

                AudioLevelSlider(
                    title: "Datasette sound",
                    value: $datasetteSoundLevel,
                    range: 0...100,
                    step: 5,
                    valueText: { $0 == 0 ? "Off" : "\($0)%" }
                )
            } header: {
                Text("Emulated Sounds")
            } footer: {
                Text("VIC-II audio leak simulates video-chip interference. Datasette sound is audible only when a compatible TAP image is active.")
            }

            Section {
                Button("Restore Audio Defaults") {
                    restoreDefaults()
                }
                .disabled(isUsingDefaults)
            } footer: {
                Text("Audio changes are applied when Settings is closed and the C64 restarts.")
            }
        }
    }

    private var isUsingDefaults: Bool {
        sidEngineRawValue == C64SIDEngine.defaultValue.rawValue
            && sidModelRawValue == C64SIDModel.defaultValue.rawValue
            && residSamplingRawValue == C64ReSIDSampling.defaultValue.rawValue
            && sampleRateRawValue == C64AudioSampleRate.defaultValue.rawValue
            && audioLeakLevel == C64AudioSettings.defaultAudioLeakLevel
            && datasetteSoundLevel == C64AudioSettings.defaultDatasetteSoundLevel
    }

    private func restoreDefaults() {
        sidEngineRawValue = C64SIDEngine.defaultValue.rawValue
        sidModelRawValue = C64SIDModel.defaultValue.rawValue
        residSamplingRawValue = C64ReSIDSampling.defaultValue.rawValue
        sampleRateRawValue = C64AudioSampleRate.defaultValue.rawValue
        audioLeakLevel = C64AudioSettings.defaultAudioLeakLevel
        datasetteSoundLevel = C64AudioSettings.defaultDatasetteSoundLevel
    }
}

private struct AudioLevelSlider: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let valueText: (Int) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text(valueText(value))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { value = Int($0.rounded()) }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: Double(step)
            )
        }
        .padding(.vertical, 2)
    }
}

private struct TapeSettingsView: View {
    @AppStorage(C64TapeSettings.autoShowControlsKey)
    private var autoShowControls = C64TapeSettings.defaultAutoShowControls

    @AppStorage(C64TapeSettings.resetCounterOnInsertKey)
    private var resetCounterOnInsert = C64TapeSettings.defaultResetCounterOnInsert

    @AppStorage(C64TapeSettings.resetWithCPUKey)
    private var resetWithCPU = C64TapeSettings.defaultResetWithCPU

    @AppStorage(C64TapeSettings.autostartBasicLoadKey)
    private var autostartBasicLoad = C64TapeSettings.defaultAutostartBasicLoad

    private var isUsingDefaults: Bool {
        autoShowControls == C64TapeSettings.defaultAutoShowControls
            && resetCounterOnInsert == C64TapeSettings.defaultResetCounterOnInsert
            && resetWithCPU == C64TapeSettings.defaultResetWithCPU
            && autostartBasicLoad == C64TapeSettings.defaultAutostartBasicLoad
    }

    var body: some View {
        Form {
            Section {
                Toggle(
                    "Show controls when a TAP image is inserted",
                    isOn: $autoShowControls
                )
                Toggle(
                    "Reset TAP counter on insertion",
                    isOn: $resetCounterOnInsert
                )
            } header: {
                Text("Interface")
            } footer: {
                Text("TAP controls can always be shown or hidden by tapping the counter/status panel beside the emulator. T64 containers do not display datasette controls.")
            }

            Section {
                Toggle("Rewind datasette with C64 reset", isOn: $resetWithCPU)
                Toggle("Autostart tape at BASIC start", isOn: $autostartBasicLoad)
            } header: {
                Text("VICE Behavior")
            } footer: {
                Text("These options are applied when Settings is closed and restart the C64 core. BASIC start changes the load address used by tape autostart.")
            }

            Section("Format Compatibility") {
                Label(
                    "TAP images expose the physical transport, motor and three-digit counter.",
                    systemImage: "recordingtape"
                )
                Label(
                    "T64 is a read-only logical container. It is always launched through autostart and does not display physical datasette controls.",
                    systemImage: "info.circle"
                )
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            Section {
                Button("Restore Tape Defaults") {
                    autoShowControls = C64TapeSettings.defaultAutoShowControls
                    resetCounterOnInsert = C64TapeSettings.defaultResetCounterOnInsert
                    resetWithCPU = C64TapeSettings.defaultResetWithCPU
                    autostartBasicLoad = C64TapeSettings.defaultAutostartBasicLoad
                }
                .disabled(isUsingDefaults)
            }
        }
    }
}

struct PrinterShareItem: Identifiable {
    let id = UUID()
    let urls: [URL]
}

struct PrinterActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}

private enum PrinterBufferAction: String, Identifiable, Equatable {
    case eject
    case discard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .eject: return "Eject current paper?"
        case .discard: return "Discard current paper?"
        }
    }

    var message: String {
        switch self {
        case .eject:
            return "The active paper will be finalized in the selected export format. The C64 and mounted media will remain running."
        case .discard:
            return "The active page and optional RAW stream will be deleted without restarting the C64."
        }
    }
}

struct PrinterCaptureSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var emulator: EmulatorModel

    @Binding var capturedBytes: Int?
    let isPrinting: Bool

    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var shareItem: PrinterShareItem?
    @State private var temporaryShareURLs: [URL] = []
    @State private var latestEjectedOutputURLs: [URL] = []
    @State private var previewImage: UIImage?
    @State private var isRefreshing = false
    @State private var isPerformingFileOperation = false
    @State private var pendingBufferAction: PrinterBufferAction?
    @State private var lastRefreshDate: Date?
    @State private var showExpandedPreview = false

    private var printerDevice: Int { C64PrinterSettings.device }
    private var exportFormat: C64PrinterExportFormat {
        C64PrinterSettings.exportFormat
    }
    private var dotIntensity: C64PrinterDotIntensity {
        C64PrinterSettings.dotIntensity
    }

    private var capturedSizeDescription: String {
        guard let capturedBytes, capturedBytes > 0 else { return "Empty" }
        return ByteCountFormatter.string(
            fromByteCount: Int64(capturedBytes),
            countStyle: .file
        )
    }

    private var activePaperDescription: String {
        guard exportFormat.usesRasterRenderer else {
            return capturedSizeDescription
        }
        let pages = C64PrinterOutputStore.activeRasterPageCount(device: printerDevice)
        if pages > 0 {
            return "\(pages) completed page\(pages == 1 ? "" : "s")"
        }
        return previewImage == nil ? "Empty" : "Page in progress"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    printerStatusCard

                    if exportFormat.usesRasterRenderer {
                        printerPreview
                    }

                    captureActions

                    if let statusMessage {
                        Label(statusMessage, systemImage: "checkmark.circle.fill")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(
                                .secondary.opacity(0.08),
                                in: RoundedRectangle(
                                    cornerRadius: 12,
                                    style: .continuous
                                )
                            )
                    }

                    Text(exportFormat.usesRasterRenderer
                        ? "The MPS-803 driver interprets text, Commodore graphics characters, control codes and bit-image data before POKE64 creates the PDF or PNG output."
                        : "RAW keeps the original IEC byte stream for diagnostics and compatibility analysis.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(20)
            }
            .navigationTitle("Virtual Printer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            refreshOutputStatus()
            latestEjectedOutputURLs = C64PrinterOutputStore
                .mostRecentEjectedOutputURLs()
        }
        .sheet(item: $shareItem, onDismiss: cleanupShareSnapshots) { item in
            PrinterActivityView(activityItems: item.urls)
        }
        .fullScreenCover(isPresented: $showExpandedPreview) {
            if let previewImage {
                PrinterExpandedPreview(image: previewImage)
            }
        }
        .task(id: isPrinting) {
            guard isPrinting, exportFormat.usesRasterRenderer else { return }
            await refreshPreviewWhilePrinting()
        }
        .confirmationDialog(
            pendingBufferAction?.title ?? "Printer paper",
            isPresented: Binding(
                get: { pendingBufferAction != nil },
                set: { if !$0 { pendingBufferAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            if pendingBufferAction == .eject {
                Button("Eject Paper") {
                    pendingBufferAction = nil
                    Task { await ejectPaper() }
                }
            } else if pendingBufferAction == .discard {
                Button("Discard Paper", role: .destructive) {
                    pendingBufferAction = nil
                    Task { await discardBuffer() }
                }
            }
            Button("Cancel", role: .cancel) { pendingBufferAction = nil }
        } message: {
            Text(pendingBufferAction?.message ?? "")
        }
        .alert(
            "Printer output error",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    private var printerStatusCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                statusActivityLED

                VStack(alignment: .leading, spacing: 2) {
                    Text("IEC PRINTER \(printerDevice)")
                        .font(.headline)
                    Text(emulator.isRunning
                        ? (isPrinting ? "Printing…" : "Connected")
                        : "Core stopped")
                        .font(.caption)
                        .foregroundStyle(isPrinting ? .orange : .secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(exportFormat.usesRasterRenderer ? "MPS-803" : "RAW")
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                    Text(exportFormat.title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("ACTIVE PAPER")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(activePaperDescription)
                        .font(.system(.title3, design: .monospaced).weight(.bold))
                }

                Spacer()

                if let lastRefreshDate {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("LAST CHECK")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(lastRefreshDate.formatted(date: .omitted, time: .standard))
                            .font(.caption.monospacedDigit())
                    }
                }
            }
        }
        .padding(16)
        .background(
            .secondary.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }

    @ViewBuilder
    private var printerPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("PAPER PREVIEW")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                if previewImage != nil {
                    Button {
                        showExpandedPreview = true
                    } label: {
                        Label("Expand", systemImage: "arrow.up.left.and.arrow.down.right")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderless)
                }
            }

            if let previewImage {
                Image(uiImage: previewImage)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        showExpandedPreview = true
                    }

                Text("Tap the page to open a full-screen preview with pinch-to-zoom. The preview refreshes periodically while data is being printed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ContentUnavailableView(
                    "No Printed Dots Yet",
                    systemImage: "printer",
                    description: Text("Print from the C64, then refresh the preview.")
                )
                .frame(maxWidth: .infinity, minHeight: 160)
            }
        }
        .padding(14)
        .background(
            .secondary.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }

    @ViewBuilder
    private var statusActivityLED: some View {
        if isPrinting {
            TimelineView(.periodic(from: .now, by: 0.32)) { context in
                let phase = Int(context.date.timeIntervalSinceReferenceDate / 0.32)
                let illuminated = phase.isMultiple(of: 2)

                Circle()
                    .fill(.orange)
                    .frame(width: 14, height: 14)
                    .opacity(illuminated ? 1 : 0.42)
                    .shadow(
                        color: .orange.opacity(illuminated ? 0.9 : 0.28),
                        radius: illuminated ? 7 : 3
                    )
                    .scaleEffect(illuminated ? 1.12 : 0.96)
            }
        } else {
            Circle()
                .fill(.green)
                .frame(width: 14, height: 14)
                .shadow(color: .green.opacity(0.8), radius: 5)
        }
    }

    private var captureActions: some View {
        VStack(spacing: 10) {
            actionButton(
                exportFormat.usesRasterRenderer ? "Refresh Preview" : "Refresh Status",
                systemImage: "arrow.clockwise",
                isBusy: isRefreshing
            ) {
                Task { await refreshOutputStatusWithFeedback() }
            }
            .disabled(isRefreshing || isPerformingFileOperation)

            if exportFormat == .raw {
                actionButton(
                    "Share Active RAW…",
                    systemImage: "square.and.arrow.up"
                ) {
                    Task { await shareActiveCapture() }
                }
                .disabled(isPerformingFileOperation)
            }

            actionButton("Eject Paper", systemImage: "eject.fill") {
                pendingBufferAction = .eject
            }
            .disabled(isPerformingFileOperation)

            if !latestEjectedOutputURLs.isEmpty {
                actionButton(
                    "Share Last Ejected Output…",
                    systemImage: "doc.badge.arrow.up"
                ) {
                    shareItem = PrinterShareItem(urls: latestEjectedOutputURLs)
                }
                .disabled(isPerformingFileOperation)
            }

            Button(role: .destructive) {
                pendingBufferAction = .discard
            } label: {
                HStack {
                    Label("Discard Paper", systemImage: "trash")
                    Spacer()
                    if isPerformingFileOperation {
                        ProgressView().controlSize(.small)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 34)
                .contentShape(Rectangle())
            }
            .buttonStyle(.bordered)
            .disabled(isPerformingFileOperation)
        }
    }

    private func actionButton(
        _ title: String,
        systemImage: String,
        isBusy: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                if isBusy { ProgressView().controlSize(.small) }
            }
            .frame(maxWidth: .infinity, minHeight: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
    }

    private func refreshOutputStatus() {
        capturedBytes = C64PrinterOutputStore.capturedByteCount()
        if exportFormat.usesRasterRenderer {
            do {
                previewImage = try C64PrinterOutputStore.previewImage(
                    device: printerDevice,
                    intensity: dotIntensity
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        } else {
            previewImage = nil
        }
        lastRefreshDate = Date()
    }

    @MainActor
    private func refreshPreviewWhilePrinting() async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .milliseconds(1_200))
            } catch {
                return
            }

            guard !isRefreshing, !isPerformingFileOperation else { continue }

            do {
                try emulator.snapshotPrinterOutput()
                refreshOutputStatus()
            } catch {
                // A manual refresh still reports errors. Background preview
                // updates remain silent so they do not interrupt printing.
            }
        }
    }

    @MainActor
    private func refreshOutputStatusWithFeedback() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        statusMessage = nil
        defer { isRefreshing = false }

        do {
            try emulator.snapshotPrinterOutput()
            try? await Task.sleep(for: .milliseconds(120))
            refreshOutputStatus()
        } catch {
            errorMessage = error.localizedDescription
            refreshOutputStatus()
        }
    }

    @MainActor
    private func shareActiveCapture() async {
        do {
            try emulator.snapshotPrinterOutput()
            refreshOutputStatus()
            let snapshotURL = try C64PrinterOutputStore.makeShareSnapshot()
            temporaryShareURLs = [snapshotURL]
            shareItem = PrinterShareItem(urls: [snapshotURL])
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func cleanupShareSnapshots() {
        for url in temporaryShareURLs {
            C64PrinterOutputStore.removeShareSnapshot(at: url)
        }
        temporaryShareURLs = []
        shareItem = nil
    }

    @MainActor
    private func ejectPaper() async {
        guard !isPerformingFileOperation else { return }
        isPerformingFileOperation = true
        statusMessage = nil
        defer { isPerformingFileOperation = false }

        do {
            let outputURLs = try await emulator.ejectPrinterPaper()
            latestEjectedOutputURLs = outputURLs
            let names = outputURLs.map(\.lastPathComponent).joined(separator: ", ")
            statusMessage = "Paper ejected as \(names)."
            refreshOutputStatus()
        } catch {
            errorMessage = error.localizedDescription
            refreshOutputStatus()
        }
    }

    @MainActor
    private func discardBuffer() async {
        guard !isPerformingFileOperation else { return }
        isPerformingFileOperation = true
        statusMessage = nil
        defer { isPerformingFileOperation = false }

        do {
            try await emulator.clearPrinterCapture()
            statusMessage = "The active printer paper was discarded."
            refreshOutputStatus()
        } catch {
            errorMessage = error.localizedDescription
            refreshOutputStatus()
        }
    }
}


private struct PrinterExpandedPreview: View {
    @Environment(\.dismiss) private var dismiss
    let image: UIImage

    @State private var zoom: CGFloat = 1
    @State private var settledZoom: CGFloat = 1

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(width: max(proxy.size.width, 1) * zoom)
                        .background(.white)
                        .gesture(
                            MagnifyGesture()
                                .onChanged { value in
                                    zoom = min(8, max(1, settledZoom * value.magnification))
                                }
                                .onEnded { _ in
                                    settledZoom = zoom
                                }
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                zoom = zoom > 1.05 ? 1 : 2.5
                                settledZoom = zoom
                            }
                        }
                }
                .background(Color(uiColor: .systemGroupedBackground))
            }
            .navigationTitle("Printer Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button {
                        zoom = max(1, zoom - 0.5)
                        settledZoom = zoom
                    } label: {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    .disabled(zoom <= 1)

                    Button {
                        zoom = min(8, zoom + 0.5)
                        settledZoom = zoom
                    } label: {
                        Image(systemName: "plus.magnifyingglass")
                    }

                    Button("Fit") {
                        zoom = 1
                        settledZoom = 1
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct PrinterSettingsView: View {
    @AppStorage(C64PrinterSettings.enabledKey)
    private var printerEnabled = C64PrinterSettings.defaultEnabled
    @AppStorage(C64PrinterSettings.deviceKey)
    private var printerDevice = C64PrinterSettings.defaultDevice
    @AppStorage(C64PrinterSettings.exportFormatKey)
    private var exportFormatRawValue = C64PrinterSettings.defaultExportFormat.rawValue
    @AppStorage(C64PrinterSettings.dotIntensityKey)
    private var dotIntensityRawValue = C64PrinterSettings.defaultDotIntensity.rawValue

    @State private var capturedBytes: Int?

    private var exportFormat: C64PrinterExportFormat {
        C64PrinterExportFormat(rawValue: exportFormatRawValue)
            ?? C64PrinterSettings.defaultExportFormat
    }

    private var printerFirmwareStatus: FirmwareStatus {
        FirmwareStore.status(for: .printerMPS803)
    }

    private var canEnablePrinter: Bool {
        !exportFormat.usesRasterRenderer || printerFirmwareStatus.isValid
    }

    private var capturedSizeDescription: String {
        guard let capturedBytes, capturedBytes > 0 else { return "Empty" }
        return ByteCountFormatter.string(
            fromByteCount: Int64(capturedBytes),
            countStyle: .file
        )
    }

    var body: some View {
        Form {
            Section {
                Toggle("Enable IEC printer", isOn: $printerEnabled)
                    .disabled(!canEnablePrinter)

                Picker("IEC device", selection: $printerDevice) {
                    ForEach(C64PrinterSettings.supportedDevices, id: \.self) { device in
                        Text("Device \(device)").tag(device)
                    }
                }
                .disabled(!printerEnabled)
            } header: {
                Text("Printer")
            } footer: {
                Text("Closing Settings restarts the core when the printer device or backend changes. When enabled, PRN \(printerDevice) appears beside the emulator.")
            }

            Section {
                Picker("Export format", selection: $exportFormatRawValue) {
                    ForEach(C64PrinterExportFormat.allCases) { format in
                        Text(format.title).tag(format.rawValue)
                    }
                }

                LabeledContent(
                    "Printer model",
                    value: exportFormat.usesRasterRenderer
                        ? "Commodore MPS-803"
                        : "RAW diagnostic capture"
                )

                if exportFormat.usesRasterRenderer {
                    Picker("Dot intensity", selection: $dotIntensityRawValue) {
                        ForEach(C64PrinterDotIntensity.allCases) { intensity in
                            Text(intensity.title).tag(intensity.rawValue)
                        }
                    }

                    HStack {
                        Label(
                            printerFirmwareStatus.isValid
                                ? "MPS-803 ROM installed"
                                : "MPS-803 ROM required",
                            systemImage: printerFirmwareStatus.isValid
                                ? "checkmark.circle.fill"
                                : "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(
                            printerFirmwareStatus.isValid ? .green : .orange
                        )
                        Spacer()
                        Text("4 KB")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    if !printerFirmwareStatus.isValid {
                        Text("Import mps803-D7811G-111-U32053A.bin in Settings → Firmware / ROMs before enabling graphical printing.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Output")
            } footer: {
                Text(exportFormat.usesRasterRenderer
                    ? "PDF is the default. Text and bit-image graphics are rendered as MPS-803 dot-matrix pages before export. PDF + RAW also retains the original IEC stream."
                    : "RAW stores the unprocessed IEC byte stream and does not require printer firmware.")
            }

            Section("Active Paper") {
                LabeledContent("Buffered data", value: capturedSizeDescription)
                if exportFormat.usesRasterRenderer {
                    LabeledContent(
                        "Completed pages",
                        value: "\(C64PrinterOutputStore.activeRasterPageCount(device: printerDevice))"
                    )
                }
                Text("Use the PRN \(printerDevice) panel beside the emulator to preview, eject, export or discard the current paper.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("BASIC Test") {
                Text(
                    """
                    10 OPEN1,\(printerDevice)
                    20 PRINT#1,"POKE64 PRINTER TEST"
                    30 CLOSE1
                    """
                )
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)

                Text("For graphical output, eject the paper from the PRN panel after printing to create the selected PDF or PNG files.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            capturedBytes = C64PrinterOutputStore.capturedByteCount()
        }
        .onChange(of: exportFormatRawValue) { _, _ in
            if !canEnablePrinter {
                printerEnabled = false
            }
        }
    }
}


private struct VirtualModemSettingsView: View {
    @AppStorage(C64VirtualModemSettings.enabledKey)
    private var modemEnabled = C64VirtualModemSettings.defaultEnabled
    @AppStorage(C64VirtualModemSettings.baudKey)
    private var baud = C64VirtualModemSettings.defaultBaud

    var body: some View {
        Form {
            Section {
                Toggle("Enable Virtual Modem", isOn: $modemEnabled)

                LabeledContent(
                    "Backend",
                    value: "Hayes modem → VICE rs232net"
                )
            } header: {
                Text("Virtual Modem")
            } footer: {
                Text("Closing Settings restarts the C64 core when this configuration changes. The modem stays in AT command mode until C64 software dials a destination.")
            }

            Section("Serial Interface") {
                Picker("Baud rate", selection: $baud) {
                    ForEach(C64VirtualModemSettings.supportedBaudRates, id: \.self) { rate in
                        Text(rate == 9600 ? "9600 (UP9600 / EZ232, recommended)" : "\(rate) (legacy)")
                            .tag(rate)
                    }
                }
                .disabled(!modemEnabled)

                if baud != 9600 {
                    Label(
                        "300–2400 baud uses VICE's bit-banged User Port path and remains experimental in POKE64. UP9600 at 9600 baud is the verified mode.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.callout)
                    .foregroundStyle(.orange)
                }
            }

            Section("Hayes Commands") {
                Text("Use your C64 terminal program to control the modem with AT commands, or open the Virtual Modem sheet for the BBS directory, native Dial/Hang Up controls, and read-only traffic diagnostics.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Text("AT\nATDT bbs.example.com:6400\n+++\nATH")
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)

                Text("Supported: AT, ATZ, AT&F, ATE0/1, ATV0/1, ATQ0/1, ATI, ATDT/ATDP host:port, ATNET0/1, +++, ATO and ATH. Common X, &C, &D, &K and S0=0 initialization commands are accepted for compatibility.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: baud) { _, value in
            if !C64VirtualModemSettings.supportedBaudRates.contains(value) {
                baud = C64VirtualModemSettings.defaultBaud
            }
        }
    }
}


private struct DiskDriveSettingsView: View {
    @AppStorage(C64DriveModel.drive8DefaultsKey)
    private var drive8ModelRawValue = C64DriveModel.defaultValue.rawValue

    @AppStorage(C64DriveSettings.drive9EnabledKey)
    private var drive9Enabled = C64DriveSettings.defaultDrive9Enabled

    @AppStorage(C64DriveModel.drive9DefaultsKey)
    private var drive9ModelRawValue = C64DriveModel.defaultValue.rawValue

    @AppStorage(C64DriveSettings.trueDriveEmulationKey)
    private var trueDriveEmulation = C64DriveSettings.defaultTrueDriveEmulation

    @AppStorage(C64DriveSettings.writeProtectionKey)
    private var writeProtection = C64DriveSettings.defaultWriteProtection

    @AppStorage(C64DriveSettings.soundLevelKey)
    private var driveSoundLevel = C64DriveSettings.defaultSoundLevel

    private var drive8Model: C64DriveModel {
        C64DriveModel(rawValue: drive8ModelRawValue) ?? .defaultValue
    }

    private var drive9Model: C64DriveModel {
        C64DriveModel(rawValue: drive9ModelRawValue) ?? .defaultValue
    }

    private var drive8FirmwareStatus: FirmwareStatus {
        FirmwareStore.status(for: drive8Model.firmwareSlot)
    }

    private var drive9FirmwareStatus: FirmwareStatus {
        FirmwareStore.status(for: drive9Model.firmwareSlot)
    }

    private var canEnableTrueDrive: Bool {
        drive8FirmwareStatus.isValid
            && (!drive9Enabled || drive9FirmwareStatus.isValid)
    }

    private var anyEnabledDriveSupportsSound: Bool {
        drive8Model.supportsMechanicalSound
            || (drive9Enabled && drive9Model.supportsMechanicalSound)
    }

    var body: some View {
        Form {
            Section {
                Toggle(
                    "True Drive Emulation",
                    isOn: $trueDriveEmulation
                )
                .disabled(!canEnableTrueDrive)

                LabeledContent(
                    "Active backend",
                    value: trueDriveEmulation ? "Hardware-level drives" : "Fast virtual drives"
                )
            } header: {
                Text("Drive Emulation")
            } footer: {
                Text(trueDriveEmulation
                    ? "True Drive Emulation applies to every enabled drive. It executes each selected model's ROM and is required for complete JiffyDOS compatibility, accurate timing and mechanical drive sound."
                    : "Fast virtual drive mode applies to every enabled drive and uses VICE traps for convenient loading. It does not execute drive firmware, so drive-side JiffyDOS commands are unavailable.")
            }

            Section {
                driveModelPicker(
                    title: "Drive model",
                    selection: $drive8ModelRawValue
                )

                LabeledContent("Typical media", value: drive8Model.mediaSummary)
            } header: {
                Text("Drive 8")
            } footer: {
                Text("Drive 8 is always enabled. Its model is independent, while the emulation backend is shared by all enabled drives.")
            }

            Section {
                Toggle("Enable Drive 9", isOn: $drive9Enabled)

                driveModelPicker(
                    title: "Drive model",
                    selection: $drive9ModelRawValue
                )
                .disabled(!drive9Enabled)

                LabeledContent(
                    "Active backend",
                    value: drive9Enabled
                        ? (trueDriveEmulation ? "Hardware-level drive" : "Fast virtual drive")
                        : "Disabled"
                )

                if drive9Enabled {
                    LabeledContent("Typical media", value: drive9Model.mediaSummary)
                }
            } header: {
                Text("Drive 9")
            } footer: {
                Text("Drive 9 is optional. Its model can be configured independently, while the emulation backend is shared by all enabled drives.")
            }

            Section {
                firmwareRow(
                    units: drive9Enabled && drive9Model == drive8Model ? [8, 9] : [8],
                    model: drive8Model,
                    status: drive8FirmwareStatus
                )

                if drive9Enabled && drive9Model != drive8Model {
                    firmwareRow(
                        units: [9],
                        model: drive9Model,
                        status: drive9FirmwareStatus
                    )
                }

                if !canEnableTrueDrive {
                    Label(
                        "Import every required drive ROM in Firmware / ROMs before enabling True Drive Emulation.",
                        systemImage: "info.circle"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            } header: {
                Text("Drive Firmware")
            } footer: {
                Text("Drive ROMs are shared by model, not assigned separately to unit 8 or 9. Two enabled drives using the same model must therefore use the same ROM. POKE64 accepts standard or compatible replacement firmware; for JiffyDOS, use matching C64 KERNAL and drive ROMs.")
            }

            Section {
                Toggle("Default write protection", isOn: $writeProtection)
            } header: {
                Text("Media Safety")
            } footer: {
                Text("When enabled, newly attached images in Drive 8 and Drive 9 are opened read-only. Existing files are not modified by this setting.")
            }

            Section {
                AudioLevelSlider(
                    title: "Mechanical drive sound",
                    value: $driveSoundLevel,
                    range: 0...100,
                    step: 5,
                    valueText: { $0 == 0 ? "Off" : "\($0)%" }
                )
                .disabled(!trueDriveEmulation || !anyEnabledDriveSupportsSound)
            } header: {
                Text("Drive Sound")
            } footer: {
                if !anyEnabledDriveSupportsSound {
                    Text("The VICE libretro drive-sound option supports 1541-family and 1571 drives, not the 1581.")
                } else if !trueDriveEmulation {
                    Text("Mechanical drive sound requires True Drive Emulation and a compatible disk image.")
                } else {
                    Text("Mechanical drive sound is shared by the enabled 1541-family and 1571 drives.")
                }
            }

            Section("Compatibility") {
                Label(
                    "Drive configuration changes apply when Settings is closed and the C64 restarts.",
                    systemImage: "arrow.clockwise"
                )
                .font(.callout)
                .foregroundStyle(.secondary)

                if trueDriveEmulation {
                    Label(
                        "JiffyDOS requires matching custom C64 KERNAL and drive ROMs.",
                        systemImage: "bolt.horizontal.circle"
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            }

            Section {
                Button("Restore Drive Defaults") {
                    restoreDefaults()
                }
                .disabled(isUsingDefaults)
            }
        }
        .onChange(of: drive8ModelRawValue) { _, _ in
            sanitizeTrueDriveSelection()
        }
        .onChange(of: drive9ModelRawValue) { _, _ in
            sanitizeTrueDriveSelection()
        }
        .onChange(of: drive9Enabled) { _, _ in
            sanitizeTrueDriveSelection()
        }
        .onChange(of: trueDriveEmulation) { _, enabled in
            if enabled && !canEnableTrueDrive {
                trueDriveEmulation = false
            }
        }
    }

    private func driveModelPicker(
        title: String,
        selection: Binding<String>
    ) -> some View {
        Picker(title, selection: selection) {
            ForEach(C64DriveModel.allCases) { model in
                Text(model.title).tag(model.rawValue)
            }
        }
        .pickerStyle(.menu)
    }

    @ViewBuilder
    private func firmwareRow(
        units: [Int],
        model: C64DriveModel,
        status: FirmwareStatus
    ) -> some View {
        let unitLabel = units.count == 1
            ? "Drive \(units[0])"
            : "Drives \(units.map { String($0) }.joined(separator: " and "))"

        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(unitLabel) · \(model.firmwareSlot.title)")
                    .font(.body.weight(.medium))
                Text(model.firmwareSlot.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Shared by every enabled drive using \(model.title).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if status.isValid {
                Label("Installed", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else if status.isInstalled {
                Label("Invalid", systemImage: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                Label("Missing", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var isUsingDefaults: Bool {
        drive8ModelRawValue == C64DriveModel.defaultValue.rawValue
            && drive9Enabled == C64DriveSettings.defaultDrive9Enabled
            && drive9ModelRawValue == C64DriveModel.defaultValue.rawValue
            && trueDriveEmulation == C64DriveSettings.defaultTrueDriveEmulation
            && writeProtection == C64DriveSettings.defaultWriteProtection
            && driveSoundLevel == C64DriveSettings.defaultSoundLevel
    }

    private func sanitizeTrueDriveSelection() {
        if trueDriveEmulation && !canEnableTrueDrive {
            trueDriveEmulation = false
        }
    }

    private func restoreDefaults() {
        drive8ModelRawValue = C64DriveModel.defaultValue.rawValue
        drive9Enabled = C64DriveSettings.defaultDrive9Enabled
        drive9ModelRawValue = C64DriveModel.defaultValue.rawValue
        trueDriveEmulation = C64DriveSettings.defaultTrueDriveEmulation
        writeProtection = C64DriveSettings.defaultWriteProtection
        driveSoundLevel = C64DriveSettings.defaultSoundLevel
    }
}

private struct SettingsPlaceholderView: View {
    let panel: SettingsPanel
    let plannedFeatures: [String]

    var body: some View {
        Form {
            Section {
                Label(panel.summary, systemImage: panel.icon)
                    .font(.headline)
            }

            Section("Planned") {
                ForEach(plannedFeatures, id: \.self) { feature in
                    Label(feature, systemImage: "circle.dashed")
                }
            }

            Section {
                Text("This panel establishes the settings structure and will be implemented incrementally in upcoming releases.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct AboutSettingsView: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "Development"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? "Development"
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image("AppIconPreview")
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .accessibilityLabel("POKE64 app icon")

                    VStack(alignment: .leading, spacing: 4) {
                        Text("POKE64")
                            .font(.title2.weight(.semibold))
                        Text("Native Commodore 64 emulator for iPad")
                            .foregroundStyle(.secondary)
                        Text("Version \(version) (\(build))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }

            Section("Technology") {
                LabeledContent("Emulation", value: "VICE x64sc / libretro")
                LabeledContent("Interface", value: "SwiftUI + UIKit")
                LabeledContent("Video", value: "Metal")
                LabeledContent("Audio", value: "AVAudioEngine")
            }

            Section("Created by") {
                Text("Created by Alessandro Capano in 2026.")
                Link("www.alexain.it/poke64", destination: URL(string: "https://www.alexain.it/poke64")!)
            }

            Section("Credits and licenses") {
                Text("POKE64 is an independent open-source project. It is not affiliated with Commodore, VICE, RetroArch or libretro.")
                Text("See LICENSE and THIRD_PARTY_NOTICES.md in the repository for complete licensing information.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
