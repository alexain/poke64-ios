import SwiftUI
import UniformTypeIdentifiers

struct FirmwareSettingsView: View {
    @State private var statuses = FirmwareStore.statuses
    @State private var pendingSlot: FirmwareSlot?
    @State private var showImporter = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
                Section {
                    Text("POKE64 does not provide Commodore firmware. Import legally obtained ROM images before starting the emulator.")
                        .font(.callout)

                    Label(
                        FirmwareStore.isBootReady ? "Required firmware is ready" : "Required firmware is incomplete",
                        systemImage: FirmwareStore.isBootReady ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(FirmwareStore.isBootReady ? .green : .orange)
                } header: {
                    Text("Firmware")
                }

                Section("C64 system ROMs") {
                    firmwareRow(for: .basic)
                    firmwareRow(for: .kernal)
                    firmwareRow(for: .chargen)
                }

                Section {
                    firmwareRow(for: .drive1541II)
                } header: {
                    Text("Drive ROM")
                } footer: {
                    Text("The drive ROM is optional. When installed, POKE64 enables VICE True Drive Emulation. A matching replacement ROM can be used together with a custom KERNAL such as JiffyDOS.")
                }

                Section("Storage") {
                    Text("Imported files are copied into the app sandbox. POKE64 records file size and SHA-256 only for validation and diagnostics.")
                        .font(.footnote)
                }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            guard let slot = pendingSlot else { return }
            pendingSlot = nil

            do {
                let urls = try result.get()
                guard let url = urls.first else { return }
                let accessing = url.startAccessingSecurityScopedResource()
                defer {
                    if accessing { url.stopAccessingSecurityScopedResource() }
                }
                try FirmwareStore.importFirmware(from: url, into: slot)
                refresh()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        .alert("Firmware import failed", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    @ViewBuilder
    private func firmwareRow(for slot: FirmwareSlot) -> some View {
        let status = statuses.first(where: { $0.slot == slot }) ?? FirmwareStore.status(for: slot)

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(slot.title)
                        .font(.body.weight(.medium))
                    Text(slot.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                if status.isValid {
                    Label("Installed", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else if status.isInstalled {
                    Label("Invalid", systemImage: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                } else {
                    Text(slot.isRequiredForBoot ? "Required" : "Optional")
                        .font(.caption)
                        .foregroundStyle(slot.isRequiredForBoot ? .orange : .secondary)
                }
            }

            if let fileSize = status.fileSize {
                Text("Size: \(fileSize) bytes")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if let hash = status.sha256 {
                Text("SHA-256: \(hash)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
            }

            if let validationError = status.validationError {
                Text(validationError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button(status.isInstalled ? "Replace" : "Import") {
                    pendingSlot = slot
                    showImporter = true
                }
                .buttonStyle(.bordered)

                if status.isInstalled {
                    Button("Remove", role: .destructive) {
                        do {
                            try FirmwareStore.remove(slot)
                            refresh()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func refresh() {
        statuses = FirmwareStore.statuses
    }
}
