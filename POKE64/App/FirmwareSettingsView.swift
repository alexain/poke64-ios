import SwiftUI
import UniformTypeIdentifiers

private enum FirmwareProfileNamePrompt: Identifiable {
    case create
    case rename(FirmwareProfile)

    var id: String {
        switch self {
        case .create:
            return "create"
        case .rename(let profile):
            return "rename-\(profile.id.uuidString)"
        }
    }

    var title: String {
        switch self {
        case .create:
            return "New Firmware Profile"
        case .rename:
            return "Rename Firmware Profile"
        }
    }
}

struct FirmwareSettingsView: View {
    @State private var statuses = FirmwareStore.statuses
    @State private var firmwareProfiles = FirmwareProfileStore.loadProfiles()
    @State private var pendingSlot: FirmwareSlot?
    @State private var showImporter = false
    @State private var errorMessage: String?
    @State private var showOpenROMsConfirmation = false
    @State private var isInstallingOpenROMs = false
    @State private var profileNamePrompt: FirmwareProfileNamePrompt?
    @State private var profileNameDraft = ""
    @State private var pendingDeleteProfile: FirmwareProfile?
    @State private var pendingApplyProfile: FirmwareProfile?

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

                    if FirmwareProfileStore.activeProfileIsModified {
                        Label("Active firmware profile has unsaved changes", systemImage: "pencil.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("Firmware")
                }

                Section {
                    if firmwareProfiles.isEmpty {
                        Text("No firmware profiles yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(firmwareProfiles) { profile in
                            firmwareProfileRow(profile)
                        }
                    }

                    Button {
                        profileNameDraft = FirmwareStore.detectedProfileName
                        profileNamePrompt = .create
                    } label: {
                        Label("New Profile from Current Firmware", systemImage: "plus")
                    }
                    .disabled(!FirmwareStore.hasAnyInstalledFirmware)

                    if let active = FirmwareProfileStore.activeProfile,
                       FirmwareProfileStore.activeProfileIsModified {
                        Button {
                            do {
                                try FirmwareProfileStore.updateProfile(active.id)
                                refresh()
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        } label: {
                            Label("Update \"\(active.name)\"", systemImage: "square.and.arrow.down")
                        }
                    }
                } header: {
                    Text("Firmware Profiles")
                } footer: {
                    Text("Each firmware profile stores one shared ROM set. Emulation profiles can reference these profiles without duplicating ROM files. Importing or removing ROMs changes the active working set; update the active profile when you want to keep those changes.")
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
                    Label(
                        "Each ROM slot is shared by every enabled drive using that model.",
                        systemImage: "square.stack.3d.up"
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)

                    firmwareRow(for: .drive1541)
                    firmwareRow(for: .drive1541II)
                    firmwareRow(for: .drive1571)
                    firmwareRow(for: .drive1581)
                } header: {
                    Text("Drive ROMs")
                } footer: {
                    Text("Drive firmware is optional for the fast virtual backend. Import the ROM matching each model selected in Disk Drives before enabling True Drive Emulation. Units 8 and 9 cannot use different ROMs when configured with the same model. Compatible replacement ROMs such as JiffyDOS are accepted.")
                }

                Section {
                    firmwareRow(for: .printerMPS803)
                } header: {
                    Text("Printer ROM")
                } footer: {
                    Text("The original MPS-803 character ROM is optional and is not distributed by POKE64. It is required only for graphical MPS-803 output such as PDF and PNG. Diagnostic RAW capture remains available without it.")
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
        .alert(
            profileNamePrompt?.title ?? "Firmware Profile",
            isPresented: Binding(
                get: { profileNamePrompt != nil },
                set: { if !$0 { profileNamePrompt = nil } }
            )
        ) {
            TextField("Profile name", text: $profileNameDraft)
            Button("Save") {
                submitProfileName()
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Unsaved firmware changes",
            isPresented: Binding(
                get: { pendingApplyProfile != nil },
                set: { if !$0 { pendingApplyProfile = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let target = pendingApplyProfile {
                if let active = FirmwareProfileStore.activeProfile {
                    Button("Update \"\(active.name)\" and Switch") {
                        do {
                            try FirmwareProfileStore.updateProfile(active.id)
                            try FirmwareProfileStore.applyProfile(target.id)
                            pendingApplyProfile = nil
                            refresh()
                        } catch {
                            pendingApplyProfile = nil
                            errorMessage = error.localizedDescription
                        }
                    }
                }
                Button("Discard Changes and Switch", role: .destructive) {
                    do {
                        try FirmwareProfileStore.applyProfile(target.id)
                        pendingApplyProfile = nil
                        refresh()
                    } catch {
                        pendingApplyProfile = nil
                        errorMessage = error.localizedDescription
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                pendingApplyProfile = nil
            }
        } message: {
            Text("The active firmware profile has changes that are not saved in its profile copy.")
        }
        .alert(
            "Delete Firmware Profile?",
            isPresented: Binding(
                get: { pendingDeleteProfile != nil },
                set: { if !$0 { pendingDeleteProfile = nil } }
            )
        ) {
            Button("Delete", role: .destructive) {
                guard let profile = pendingDeleteProfile else { return }
                do {
                    try FirmwareProfileStore.deleteProfile(profile.id)
                    pendingDeleteProfile = nil
                    refresh()
                } catch {
                    pendingDeleteProfile = nil
                    errorMessage = error.localizedDescription
                }
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteProfile = nil
            }
        } message: {
            Text("The stored ROM copies for this firmware profile will be removed. The currently active ROM files are not deleted.")
        }
        .alert("Firmware operation failed", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    @ViewBuilder
    private func firmwareProfileRow(_ profile: FirmwareProfile) -> some View {
        let isActive = FirmwareProfileStore.activeProfileID == profile.id
        let isModified = isActive && FirmwareProfileStore.activeProfileIsModified

        HStack(spacing: 12) {
            Button {
                requestApply(profile)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(profile.name)
                            .foregroundStyle(.primary)
                        Text(profile.compactSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if isModified {
                        Text("Modified")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else if isActive {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isActive)

            Menu {
                if isActive && isModified {
                    Button("Update from Current Firmware") {
                        do {
                            try FirmwareProfileStore.updateProfile(profile.id)
                            refresh()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }

                Button("Duplicate") {
                    do {
                        _ = try FirmwareProfileStore.duplicateProfile(profile.id)
                        refresh()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }

                Button("Rename") {
                    profileNameDraft = profile.name
                    profileNamePrompt = .rename(profile)
                }

                Button("Delete", role: .destructive) {
                    pendingDeleteProfile = profile
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .buttonStyle(.borderless)
        }
    }

    private func requestApply(_ profile: FirmwareProfile) {
        guard FirmwareProfileStore.activeProfileID != profile.id else { return }

        if FirmwareProfileStore.activeProfileIsModified {
            pendingApplyProfile = profile
            return
        }

        do {
            try FirmwareProfileStore.applyProfile(profile.id)
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func submitProfileName() {
        guard let prompt = profileNamePrompt else { return }
        do {
            switch prompt {
            case .create:
                _ = try FirmwareProfileStore.createProfile(named: profileNameDraft)
            case .rename(let profile):
                _ = try FirmwareProfileStore.renameProfile(profile.id, to: profileNameDraft)
            }
            profileNamePrompt = nil
            refresh()
        } catch {
            profileNamePrompt = nil
            errorMessage = error.localizedDescription
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
        firmwareProfiles = FirmwareProfileStore.loadProfiles()
    }
}
