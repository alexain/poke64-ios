import SwiftUI
import UniformTypeIdentifiers

struct FirmwareSettingsView: View {
    @State private var statuses = FirmwareStore.statuses
    @State private var pendingSlot: FirmwareSlot?
    @State private var showImporter = false
    @State private var errorMessage: String?
    @State private var showOpenROMsConfirmation = false
    @State private var isInstallingOpenROMs = false

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

                    LabeledContent("Active profile", value: FirmwareStore.activeProfileName)
                } header: {
                    Text("Firmware")
                }

                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("MEGA65 OpenROMs")
                                .font(.body.weight(.medium))
                            Text("Open-source BASIC, KERNAL and character ROM replacements")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if FirmwareStore.isOpenROMsInstalled {
                            Label("Active", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }

                    Text("OpenROMs is experimental and does not yet provide complete C64 compatibility. Installation requires an internet connection and replaces the active system ROM files.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Button {
                        if FirmwareStore.hasInstalledSystemFirmware {
                            showOpenROMsConfirmation = true
                        } else {
                            installOpenROMs()
                        }
                    } label: {
                        HStack {
                            if isInstallingOpenROMs {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Label(
                                FirmwareStore.isOpenROMsInstalled ? "Reinstall OpenROMs" : "Install OpenROMs",
                                systemImage: "arrow.down.circle"
                            )
                        }
                    }
                    .disabled(isInstallingOpenROMs)

                    if FirmwareStore.canRestorePreviousFirmware {
                        Button("Restore Previous Firmware") {
                            do {
                                try FirmwareStore.restorePreviousFirmware()
                                refresh()
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        }
                        .disabled(isInstallingOpenROMs)
                    }

                    Link(
                        "OpenROMs project and license information",
                        destination: URL(string: "https://github.com/MEGA65/open-roms")!
                    )
                    .font(.footnote)
                } header: {
                    Text("Open-source firmware")
                } footer: {
                    Text("POKE64 downloads the generic OpenROMs set pinned to upstream revision \(FirmwareStore.openROMsDisplayRevision). The three matching ROMs are installed together.")
                }

                Section("C64 system ROMs") {
                    firmwareRow(for: .basic)
                    firmwareRow(for: .kernal)
                    firmwareRow(for: .chargen)
                }

                Section {
                    firmwareRow(for: .drive1541)
                    firmwareRow(for: .drive1541II)
                    firmwareRow(for: .drive1571)
                    firmwareRow(for: .drive1581)
                } header: {
                    Text("Drive ROMs")
                } footer: {
                    Text("Drive firmware is optional for the fast virtual backend. Import the ROM matching the model selected in Disk Drives before enabling True Drive Emulation. Compatible replacement ROMs such as JiffyDOS are accepted.")
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
        .alert("Install OpenROMs?", isPresented: $showOpenROMsConfirmation) {
            Button("Install", role: .destructive) {
                installOpenROMs()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("OpenROMs will replace the active BASIC, KERNAL and character ROMs. If the current system ROM set is complete, POKE64 will preserve it so it can be restored later.")
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

    private func installOpenROMs() {
        guard !isInstallingOpenROMs else { return }
        isInstallingOpenROMs = true

        Task {
            do {
                try await FirmwareStore.installOpenROMs()
                await MainActor.run {
                    refresh()
                    isInstallingOpenROMs = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isInstallingOpenROMs = false
                }
            }
        }
    }

    private func refresh() {
        statuses = FirmwareStore.statuses
    }
}
