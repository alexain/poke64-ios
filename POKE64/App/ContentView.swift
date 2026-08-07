import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var emulator: EmulatorModel
    @AppStorage(C64TapeSettings.autoShowControlsKey)
    private var autoShowDatasetteControls = C64TapeSettings.defaultAutoShowControls
    @AppStorage(C64PrinterSettings.enabledKey)
    private var printerEnabled = C64PrinterSettings.defaultEnabled
    @AppStorage(C64PrinterSettings.deviceKey)
    private var printerDevice = C64PrinterSettings.defaultDevice
    @AppStorage(C64VirtualModemSettings.enabledKey)
    private var virtualModemEnabled = C64VirtualModemSettings.defaultEnabled
    @AppStorage("poke64.toolbar.collapsed")
    private var toolbarCollapsed = false
    @State private var toolbarHeight: CGFloat = 62
    @State private var showImporter = false
    @State private var showKeyboard = false
    @State private var showDatasetteControls = false
    @State private var showPrinterControls = false
    @State private var showVirtualModemControls = false
    @State private var virtualModemActivityPulse = false
    @State private var virtualModemActivitySequence = 0
    @State private var printerCapturedBytes: Int?
    @State private var printerActivityPulse = false
    @State private var printerActivitySequence = 0
    @State private var keyboardMode: C64KeyboardMode = .compact
    @State private var keyboardShiftLockIsActive = false
    @State private var showLibrary = false
    @State private var showPorts = false
    @State private var showDevices = false
    @State private var showNewDisk = false
    @State private var newDiskTargetUnit = 8
    @State private var deviceImportTarget: DeviceImportTarget?
    @State private var mediaActionPrompt: MediaActionPromptState?
    @State private var showSettings = false
    @State private var settingsInitialPanel: SettingsPanel = .profiles
    @State private var settingsFirmwareFingerprint = FirmwareStore.configurationFingerprint
    @State private var emulationProfiles = EmulationProfileStore.loadProfiles()
    @State private var selectedEmulationProfileID = EmulationProfileStore.selectedProfileID
    @State private var pendingToolbarProfileSwitchID: UUID?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            HardwareKeyboardCapture(isEnabled: emulator.isRunning) { keyCode, pressed in
                emulator.setRawKey(keyCode, pressed: pressed)
            }
            .frame(width: 1, height: 1)
            .accessibilityHidden(true)

            VStack(spacing: 0) {
                header
                    .frame(height: toolbarHeight, alignment: .top)
                    .clipped()
                    .allowsHitTesting(toolbarHeight > 1)

                emulatorArea

                if showKeyboard {
                    Divider()
                        .overlay(.white.opacity(0.12))

                    C64KeyboardView(
                        mode: $keyboardMode,
                        shiftLockIsActive: $keyboardShiftLockIsActive,
                        onHide: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showKeyboard = false
                            }
                        }
                    )
                    .environmentObject(emulator)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if showDatasetteControls,
                          emulator.mountedTapeSupportsPhysicalTransport {
                    Divider()
                        .overlay(.white.opacity(0.12))

                    DatasetteControlDock(
                        emulator: emulator,
                        onHide: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showDatasetteControls = false
                            }
                        }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }

            toolbarRestoreButton
                .padding(.top, 8)
                .padding(.trailing, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .opacity(toolbarCollapsed ? 1 : 0)
                .offset(y: toolbarCollapsed ? 0 : -8)
                .allowsHitTesting(toolbarCollapsed)
                .accessibilityHidden(!toolbarCollapsed)
                .zIndex(80)

            if emulator.externalMouseCaptureActive {
                ExternalMouseCaptureShield()
                    .ignoresSafeArea()
                    .zIndex(90)
            }

            if emulator.isStarting {
                bootOverlay
                    .transition(.opacity)
                    .zIndex(100)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: emulator.isStarting)
        .animation(.easeInOut(duration: 0.2), value: showKeyboard)
        .animation(.easeInOut(duration: 0.2), value: showDatasetteControls)
        .onAppear {
            toolbarHeight = toolbarCollapsed ? 0 : 62
            reloadToolbarProfiles()
        }
        .onChange(of: emulator.mountedTape?.id) { previousID, currentID in
            guard previousID != currentID else { return }
            if currentID == nil || !emulator.mountedTapeSupportsPhysicalTransport {
                showDatasetteControls = false
            } else if autoShowDatasetteControls {
                showKeyboard = false
                showDatasetteControls = true
            }
        }
        .onChange(of: printerEnabled) { _, enabled in
            if !enabled {
                showPrinterControls = false
                printerCapturedBytes = nil
                printerActivityPulse = false
            }
        }
        .onChange(of: virtualModemEnabled) { _, enabled in
            if !enabled {
                showVirtualModemControls = false
                virtualModemActivityPulse = false
            }
        }
        .onChange(of: emulator.virtualModemTXBytes) { previous, current in
            if current > previous {
                signalVirtualModemActivity()
            }
        }
        .onChange(of: emulator.virtualModemRXBytes) { previous, current in
            if current > previous {
                signalVirtualModemActivity()
            }
        }
        .task {
            do {
                _ = try EmulationProfileStore.applyDefaultProfileAtLaunchIfEnabled()
                reloadToolbarProfiles()
            } catch {
                emulator.presentMediaError(error)
            }
            await emulator.startAutomatically()
        }
        .task(id: printerEnabled) {
            await monitorPrinterCapture()
        }
        .confirmationDialog(
            "Unsaved Profile Changes",
            isPresented: Binding(
                get: { pendingToolbarProfileSwitchID != nil },
                set: { if !$0 { pendingToolbarProfileSwitchID = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let targetID = pendingToolbarProfileSwitchID {
                Button("Save Current Changes and Switch") {
                    updateCurrentToolbarProfileAndSwitch(to: targetID)
                    pendingToolbarProfileSwitchID = nil
                }
                Button("Discard Changes and Switch", role: .destructive) {
                    performToolbarProfileSwitch(targetID)
                    pendingToolbarProfileSwitchID = nil
                }
            }
            Button("Cancel", role: .cancel) {
                pendingToolbarProfileSwitchID = nil
            }
        } message: {
            Text("The current emulation profile or its firmware profile has unsaved changes. Saving firmware changes updates the shared Firmware Profile.")
        }
        .fullScreenCover(isPresented: $showSettings, onDismiss: {
            reloadToolbarProfiles()
            Task {
                await emulator.settingsDidClose(
                    previousFirmwareFingerprint: settingsFirmwareFingerprint
                )
            }
        }) {
            SettingsView(initialPanel: settingsInitialPanel)
        }
        .fullScreenCover(isPresented: $showLibrary) {
            LibraryView(emulator: emulator)
        }
        .sheet(isPresented: $showPrinterControls) {
            PrinterCaptureSheet(
                capturedBytes: $printerCapturedBytes,
                isPrinting: printerActivityPulse
            )
            .environmentObject(emulator)
        }
        .sheet(isPresented: $showVirtualModemControls) {
            VirtualModemStatusSheet(
                emulator: emulator,
                activityPulse: virtualModemActivityPulse,
                onOpenSettings: {
                    showVirtualModemControls = false
                    DispatchQueue.main.async {
                        openSettings(.networking)
                    }
                }
            )
        }
        .sheet(isPresented: $showNewDisk) {
            NewDiskView(
                targetDriveUnit: newDiskTargetUnit,
                currentDriveModel: C64DriveModel.selected(for: newDiskTargetUnit),
                defaultInsertAfterCreation: emulator.mountedDisks[newDiskTargetUnit] == nil
            ) { title, format, initialization, insertAfterCreation in
                createDiskFromDevices(
                    title: title,
                    format: format,
                    initialization: initialization,
                    insertAfterCreation: insertAfterCreation
                )
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.data, .archive],
            allowsMultipleSelection: false
        ) { result in
            let target = deviceImportTarget
            deviceImportTarget = nil

            switch result {
            case .success(let urls):
                guard let url = urls.first,
                      let request = emulator.prepareTemporaryMedia(url: url) else {
                    return
                }

                do {
                    let resolvedRequest = try target?.request(for: request.media) ?? request
                    beginMediaRequest(resolvedRequest)
                } catch {
                    emulator.discardPreparedMedia(request.media)
                    emulator.presentMediaError(error)
                }

            case .failure(let error):
                print("File importer: \(error)")
            }
        }
        .mediaActionPrompt(
            prompt: $mediaActionPrompt,
            emulator: emulator
        )
        .sheet(
            isPresented: Binding(
                get: { emulator.presentedError != nil },
                set: { if !$0 { emulator.presentedError = nil } }
            )
        ) {
            StartupErrorView(message: emulator.presentedError ?? "Unknown error") {
                emulator.presentedError = nil
            }
        }
    }

    private var emulatorArea: some View {
        GeometryReader { proxy in
            let displaySize = Self.fittedC64Size(
                in: proxy.size,
                aspectRatio: emulator.videoAspectRatio
            )
            let sideMargin = max(0, (proxy.size.width - displaySize.width) / 2)
            let sideStatusPanelWidth = min(sideMargin, 104)

            ZStack(alignment: .top) {
                Color.black

                ZStack(alignment: .bottom) {
                    C64ScreenRepresentable()
                        .environmentObject(emulator)
                        .frame(width: displaySize.width, height: displaySize.height)
                        .background(Color.black)

                    if emulator.mousePort != nil {
                        C64MouseCaptureView(
                            onMove: { deltaX, deltaY in
                                emulator.moveMouse(deltaX: deltaX, deltaY: deltaY)
                            },
                            onButton: { button, pressed in
                                emulator.setMouseButton(button, pressed: pressed)
                            }
                        )
                    }

                    if !emulator.firmwareReady {
                        firmwareRequiredOverlay
                    }

                    if emulator.virtualJoystickPort != nil {
                        gameControlsOverlay
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .frame(width: displaySize.width, height: displaySize.height)
                .clipped()

                if sideMargin >= 72,
                   emulator.trueDriveEmulationConfigured
                    || emulator.mountedTapeSupportsPhysicalTransport
                    || (printerEnabled && emulator.isRunning)
                    || (virtualModemEnabled && emulator.isRunning) {
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        VStack(spacing: 12) {
                            if virtualModemEnabled, emulator.isRunning {
                                NetworkStatusPanel(
                                    connected: emulator.virtualModemConnected,
                                    telemetryAvailable: emulator.virtualModemTelemetryAvailable,
                                    txBytes: emulator.virtualModemTXBytes,
                                    rxBytes: emulator.virtualModemRXBytes,
                                    activityPulse: virtualModemActivityPulse,
                                    onOpen: {
                                        showVirtualModemControls = true
                                    }
                                )
                            }

                            if emulator.trueDriveEmulationConfigured {
                                DriveStatusPanel(
                                    drive8PowerOn: emulator.drive8PowerLEDOn,
                                    drive9Enabled: emulator.drive9Configured,
                                    drive9PowerOn: emulator.drive9PowerLEDOn,
                                    activityOn: emulator.driveActivityLEDOn
                                )
                                .allowsHitTesting(false)
                            }

                            if printerEnabled, emulator.isRunning {
                                PrinterStatusPanel(
                                    device: printerDevice,
                                    format: C64PrinterSettings.exportFormat,
                                    capturedBytes: printerCapturedBytes,
                                    activityPulse: printerActivityPulse,
                                    onOpen: {
                                        showPrinterControls = true
                                    }
                                )
                            }

                            if emulator.mountedTapeSupportsPhysicalTransport {
                                DatasetteStatusPanel(
                                    emulator: emulator,
                                    controlsVisible: showDatasetteControls,
                                    onToggleControls: {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            showKeyboard = false
                                            showDatasetteControls.toggle()
                                        }
                                    }
                                )
                            }
                        }
                        .frame(width: sideStatusPanelWidth)
                        .frame(width: sideMargin)
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    private static func fittedC64Size(
        in availableSize: CGSize,
        aspectRatio: CGFloat
    ) -> CGSize {
        guard availableSize.width > 0,
              availableSize.height > 0,
              aspectRatio.isFinite,
              aspectRatio > 0 else {
            return .zero
        }

        let widthFromHeight = availableSize.height * aspectRatio

        if widthFromHeight <= availableSize.width {
            return CGSize(width: widthFromHeight, height: availableSize.height)
        }

        return CGSize(
            width: availableSize.width,
            height: availableSize.width / aspectRatio
        )
    }

    private var header: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                toolbarButtons
                    .frame(
                        minWidth: max(0, proxy.size.width - 32),
                        alignment: .center
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
            }
        }
        .frame(height: 62)
        .background(.black)
        .popover(isPresented: $showPorts, arrowEdge: .top) {
            PortsConfigurationView(emulator: emulator)
                .frame(
                    minWidth: 430,
                    idealWidth: 460,
                    minHeight: 520,
                    idealHeight: 560
                )
                .presentationCompactAdaptation(.sheet)
        }
        .popover(isPresented: $showDevices, arrowEdge: .top) {
            DevicesConfigurationView(
                emulator: emulator,
                onChooseMedia: { target in
                    chooseMedia(for: target)
                },
                onCreateDisk: { unit in
                    createDiskFromDevices(unit: unit)
                }
            )
            .frame(
                minWidth: 440,
                idealWidth: 480,
                minHeight: 560,
                idealHeight: 620
            )
            .presentationCompactAdaptation(.sheet)
        }
    }

    @ViewBuilder
    private var toolbarButtons: some View {
        HStack(spacing: 10) {
            Button {
                deviceImportTarget = nil
                showImporter = true
            } label: {
                toolbarLabel("Open", systemImage: "folder")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!emulator.firmwareReady)

            Button {
                showLibrary = true
            } label: {
                toolbarLabel("Library", systemImage: "books.vertical")
            }
            .buttonStyle(.bordered)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showDatasetteControls = false
                    showKeyboard.toggle()
                }
            } label: {
                toolbarLabel(
                    "Keyboard",
                    systemImage: showKeyboard ? "keyboard.chevron.compact.down" : "keyboard"
                )
            }
            .buttonStyle(.bordered)
            .disabled(!emulator.isRunning)

            Button {
                showDevices = false
                showPorts = true
            } label: {
                PortsToolbarLabel(
                    port1Title: emulator.joyportCompactAssignmentTitle(for: 1),
                    port2Title: emulator.joyportCompactAssignmentTitle(for: 2)
                )
            }
            .buttonStyle(.bordered)
            .disabled(!emulator.isRunning)

            Button {
                showPorts = false
                showDevices = true
            } label: {
                DevicesToolbarLabel(
                    drive8Mounted: emulator.mountedDisks[8] != nil,
                    drive9Enabled: emulator.drive9Configured,
                    drive9Mounted: emulator.mountedDisks[9] != nil,
                    tapeMounted: emulator.mountedTape != nil,
                    cartridgeMounted: emulator.mountedCartridge != nil
                )
            }
            .buttonStyle(.bordered)
            .disabled(!emulator.isRunning)

            Menu {
                ForEach(emulationProfiles) { profile in
                    Button {
                        requestToolbarProfileSwitch(profile.id)
                    } label: {
                        Label(
                            profile.name,
                            systemImage: toolbarProfileIcon(for: profile)
                        )
                    }
                }

                Divider()

                Button {
                    openSettings(.profiles)
                } label: {
                    Label("Manage Profiles…", systemImage: "slider.horizontal.3")
                }
            } label: {
                ToolbarStatusLabel(
                    title: "Profile",
                    systemImage: "square.stack.3d.up",
                    detail: toolbarProfileDetail
                )
            }
            .buttonStyle(.bordered)

            Button {
                openSettings(.profiles)
            } label: {
                toolbarLabel("Settings", systemImage: "gearshape")
            }
            .buttonStyle(.bordered)

            Menu {
                Button("Soft Reset", systemImage: "arrow.counterclockwise") {
                    emulator.softReset()
                }
                Button("Hard Reset", systemImage: "power") {
                    emulator.hardReset()
                }

                Divider()

                Button(
                    "Eject All Media and Reset",
                    systemImage: "eject"
                ) {
                    emulator.ejectAllMediaAndReset()
                }
            } label: {
                toolbarLabel("Reset", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(!emulator.isRunning)

            Button {
                collapseToolbar()
            } label: {
                Image(systemName: "chevron.up")
                    .font(.caption.weight(.bold))
                    .frame(minWidth: 12, minHeight: 18)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Hide Toolbar")
            .help("Hide Toolbar")
        }
        .buttonBorderShape(.roundedRectangle(radius: 14))
    }

    private func chooseMedia(for target: DeviceImportTarget) {
        deviceImportTarget = target
        showDevices = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            showImporter = true
        }
    }

    private func createDiskFromDevices(unit: Int) {
        newDiskTargetUnit = unit
        showDevices = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            showNewDisk = true
        }
    }

    private func createDiskFromDevices(
        title: String,
        format: BlankDiskImageFormat,
        initialization: BlankDiskInitialization,
        insertAfterCreation: Bool
    ) {
        do {
            let item = try emulator.library.createBlankDisk(
                title: title,
                format: format,
                initialization: initialization
            )
            emulator.reportCreatedDisk(item)
            guard insertAfterCreation else { return }
            let originalRequest = try emulator.actionRequest(for: item)
            let request = MediaActionRequest(
                media: originalRequest.media,
                actions: [.insertDisk(newDiskTargetUnit)]
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                beginMediaRequest(request)
            }
        } catch {
            emulator.presentMediaError(error)
        }
    }

    private func beginMediaRequest(_ request: MediaActionRequest) {
        if request.actions.count > 1 {
            mediaActionPrompt = .choose(request)
            return
        }

        guard let action = request.actions.first else {
            emulator.discardPreparedMedia(request.media)
            return
        }

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

        do {
            try emulator.performMediaAction(action, media: request.media)
        } catch {
            emulator.discardPreparedMedia(request.media)
            emulator.presentMediaError(error)
        }
    }

    private func toolbarLabel(_ title: String, systemImage: String) -> some View {
        ToolbarStatusLabel(
            title: title,
            systemImage: systemImage,
            detail: nil
        )
    }

    private var toolbarRestoreButton: some View {
        Button {
            expandToolbar()
        } label: {
            Image(systemName: "chevron.down")
                .font(.caption.weight(.bold))
                .frame(width: 28, height: 24)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 10))
        .accessibilityLabel("Show Toolbar")
        .help("Show Toolbar")
    }

    private func collapseToolbar() {
        withAnimation(.easeInOut(duration: 0.32)) {
            toolbarHeight = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            guard toolbarHeight <= 0.5 else { return }
            toolbarCollapsed = true
        }
    }

    private func expandToolbar() {
        toolbarCollapsed = false
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.32)) {
                toolbarHeight = 62
            }
        }
    }

    private var toolbarSelectedProfile: EmulationProfile? {
        guard let selectedEmulationProfileID else { return nil }
        return emulationProfiles.first { $0.id == selectedEmulationProfileID }
    }

    private var toolbarProfileDetail: String {
        guard let profile = toolbarSelectedProfile else {
            return "Custom"
        }
        return EmulationProfileStore.matchesCurrentConfiguration(profile)
            ? profile.name
            : "\(profile.name) · Modified"
    }

    private func toolbarProfileIcon(for profile: EmulationProfile) -> String {
        guard selectedEmulationProfileID == profile.id else {
            return "circle"
        }
        return EmulationProfileStore.matchesCurrentConfiguration(profile)
            ? "checkmark.circle.fill"
            : "pencil.circle"
    }

    private func reloadToolbarProfiles() {
        emulationProfiles = EmulationProfileStore.loadProfiles()
        selectedEmulationProfileID = EmulationProfileStore.selectedProfileID
    }

    private func requestToolbarProfileSwitch(_ profileID: UUID) {
        if let selected = toolbarSelectedProfile,
           !EmulationProfileStore.matchesCurrentConfiguration(selected) {
            pendingToolbarProfileSwitchID = profileID
            return
        }
        performToolbarProfileSwitch(profileID)
    }

    private func updateCurrentToolbarProfileAndSwitch(to profileID: UUID) {
        guard let selectedEmulationProfileID else {
            performToolbarProfileSwitch(profileID)
            return
        }

        do {
            if FirmwareProfileStore.activeProfileIsModified,
               let activeFirmwareProfileID = FirmwareProfileStore.activeProfileID {
                _ = try FirmwareProfileStore.updateProfile(activeFirmwareProfileID)
            }
            _ = try EmulationProfileStore.updateProfile(selectedEmulationProfileID)
            performToolbarProfileSwitch(profileID)
        } catch {
            emulator.presentMediaError(error)
        }
    }

    private func performToolbarProfileSwitch(_ profileID: UUID) {
        let previousFingerprint = FirmwareStore.configurationFingerprint

        do {
            try EmulationProfileStore.applyProfile(profileID)
            reloadToolbarProfiles()

            Task {
                await emulator.settingsDidClose(
                    previousFirmwareFingerprint: previousFingerprint
                )
                reloadToolbarProfiles()
            }
        } catch {
            emulator.presentMediaError(error)
        }
    }

    private func openSettings(_ panel: SettingsPanel) {
        settingsInitialPanel = panel
        settingsFirmwareFingerprint = FirmwareStore.configurationFingerprint
        showSettings = true
    }

    private var bootOverlay: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Image("AppIconPreview")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 112, height: 112)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                Text("POKE64 is loading…")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)

                ProgressView()
                    .controlSize(.large)
                    .tint(.white)

                Text("Starting VICE x64sc")
                    .font(.callout.monospaced())
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("POKE64 is loading")
    }

    private var firmwareRequiredOverlay: some View {
        VStack(spacing: 14) {
            Image(systemName: "memorychip")
                .font(.system(size: 38))

            Text("C64 firmware required")
                .font(.title3.weight(.semibold))

            Text("POKE64 does not include Commodore firmware. Import legally obtained BASIC, KERNAL and character ROM images to start the emulator.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 460)

            Button("Configure Firmware") {
                openSettings(.firmware)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(24)
    }

    @MainActor
    private func monitorPrinterCapture() async {
        guard printerEnabled else {
            printerCapturedBytes = nil
            printerActivityPulse = false
            return
        }

        var previousByteCount = C64PrinterOutputStore.capturedByteCount()
        printerCapturedBytes = previousByteCount

        while printerEnabled, !Task.isCancelled {
            do {
                try await Task.sleep(for: .milliseconds(300))
            } catch {
                return
            }

            let currentByteCount = C64PrinterOutputStore.capturedByteCount()
            if let currentByteCount,
               currentByteCount > (previousByteCount ?? 0) {
                signalPrinterActivity()
            }
            printerCapturedBytes = currentByteCount
            previousByteCount = currentByteCount
        }
    }

    @MainActor
    private func signalPrinterActivity() {
        printerActivitySequence += 1
        let sequence = printerActivitySequence
        printerActivityPulse = true

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1_250))
            guard sequence == printerActivitySequence else { return }
            printerActivityPulse = false
        }
    }

    @MainActor
    private func signalVirtualModemActivity() {
        virtualModemActivitySequence += 1
        let sequence = virtualModemActivitySequence
        virtualModemActivityPulse = true

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            guard sequence == virtualModemActivitySequence else { return }
            virtualModemActivityPulse = false
        }
    }

    private var gameControlsOverlay: some View {
        HStack(alignment: .bottom) {
            DPad { button, pressed in
                emulator.setJoypad(button, pressed: pressed)
            }

            Spacer()

            HoldButton("FIRE", diameter: 92) { pressed in
                emulator.setJoypad(.fire, pressed: pressed)
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 18)
        .contentShape(Rectangle())
        .disabled(!emulator.isRunning)
        .opacity(emulator.isRunning ? 1 : 0.45)
    }
}

private enum DeviceImportTarget {
    case drive(Int)
    case tape
    case cartridge

    func request(for media: MediaReference) throws -> MediaActionRequest {
        let actions: [MediaAction]

        switch self {
        case .drive(let unit):
            guard BlankDiskImageFormat(mediaType: media.mediaType) != nil else {
                throw DeviceMediaSelectionError.unsupported(
                    expected: "a D64, D71 or D81 disk image",
                    destination: "Drive \(unit)"
                )
            }
            actions = [.insertDisk(unit), .autostartDisk(unit)]

        case .tape:
            guard media.mediaType == .tap || media.mediaType == .t64 else {
                throw DeviceMediaSelectionError.unsupported(
                    expected: "a TAP or T64 tape image",
                    destination: "the datasette"
                )
            }
            actions = media.mediaType == .t64
                ? [.autostartTape]
                : [.insertTape, .autostartTape]

        case .cartridge:
            guard media.mediaType == .crt else {
                throw DeviceMediaSelectionError.unsupported(
                    expected: "a CRT cartridge image",
                    destination: "the cartridge port"
                )
            }
            actions = [.insertCartridgeAndReset]
        }

        return MediaActionRequest(media: media, actions: actions)
    }
}

private enum DeviceMediaSelectionError: LocalizedError {
    case unsupported(expected: String, destination: String)

    var errorDescription: String? {
        switch self {
        case .unsupported(let expected, let destination):
            return "Select \(expected) for \(destination)."
        }
    }
}

private struct ToolbarStatusLabel: View {
    let title: String
    let systemImage: String
    let detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
            }
            .lineLimit(1)

            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                Text(" ")
                    .font(.caption2)
                    .hidden()
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 1)
        .fixedSize(horizontal: true, vertical: false)
        .contentShape(Rectangle())
        .accessibilityLabel(title)
    }
}

private struct PortsToolbarLabel: View {
    let port1Title: String
    let port2Title: String

    var body: some View {
        ToolbarStatusLabel(
            title: "Ports",
            systemImage: "gamecontroller",
            detail: "1 \(port1Title) · 2 \(port2Title)"
        )
        .accessibilityLabel(
            "Ports, Port 1 \(port1Title), Port 2 \(port2Title)"
        )
    }
}

private struct PortsConfigurationView: View {
    @ObservedObject var emulator: EmulatorModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                portSection(1)
                portSection(2)

                Section {
                    Button {
                        emulator.swapJoyportAssignments()
                    } label: {
                        Label("Swap Port 1 and Port 2", systemImage: "arrow.left.arrow.right")
                    }
                } footer: {
                    Text("Assignments are applied immediately.")
                }
            }
            .navigationTitle("Joystick Ports")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert(
                "Restart cartridge for mouse?",
                isPresented: Binding(
                    get: { emulator.mouseResetRecommendation != nil },
                    set: { presented in
                        if !presented {
                            emulator.dismissMouseResetRecommendation()
                        }
                    }
                )
            ) {
                Button("Hard Reset") {
                    emulator.hardResetForMouseDetection()
                }
                Button("Not Now", role: .cancel) {
                    emulator.dismissMouseResetRecommendation()
                }
            } message: {
                if let recommendation = emulator.mouseResetRecommendation {
                    Text(
                        "\(recommendation.cartridgeTitle) may detect the Commodore 1351 mouse only during startup. "
                        + "Hard reset now with the mouse connected to Port \(recommendation.port)."
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func portSection(_ port: Int) -> some View {
        let assignment = emulator.joyportAssignment(for: port)

        Section("Port \(port)") {
            assignmentButton(
                title: "None",
                systemImage: "circle.slash",
                assignment: .none,
                selectedAssignment: assignment,
                port: port
            )

            assignmentButton(
                title: "Virtual Joystick",
                systemImage: "gamecontroller",
                assignment: .virtualJoystick,
                selectedAssignment: assignment,
                port: port
            )

            assignmentButton(
                title: "Commodore 1351 Mouse",
                systemImage: "computermouse",
                assignment: .commodoreMouse,
                selectedAssignment: assignment,
                port: port
            )

            if emulator.physicalControllers.isEmpty {
                Label("No physical controllers connected", systemImage: "gamecontroller")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(emulator.physicalControllers) { controller in
                    let controllerAssignment = JoyportAssignment.physicalController(controller.id)
                    let assignedPort = emulator.controllerAssignedPort(controller.id)

                    Button {
                        emulator.setJoyportAssignment(controllerAssignment, for: port)
                    } label: {
                        HStack {
                            Label(controller.name, systemImage: "gamecontroller.fill")
                                .lineLimit(1)

                            Spacer()

                            if assignment == controllerAssignment {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                            } else if let assignedPort, assignedPort != port {
                                Text("Port \(assignedPort)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    .disabled(assignedPort != nil && assignedPort != port)
                }
            }
        }
    }

    private func assignmentButton(
        title: String,
        systemImage: String,
        assignment: JoyportAssignment,
        selectedAssignment: JoyportAssignment,
        port: Int
    ) -> some View {
        Button {
            emulator.setJoyportAssignment(assignment, for: port)
        } label: {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                if selectedAssignment == assignment {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }
}

private struct DevicesToolbarLabel: View {
    let drive8Mounted: Bool
    let drive9Enabled: Bool
    let drive9Mounted: Bool
    let tapeMounted: Bool
    let cartridgeMounted: Bool

    var body: some View {
        ToolbarStatusLabel(
            title: "Devices",
            systemImage: "externaldrive.fill",
            detail: summary
        )
        .accessibilityLabel(accessibilitySummary)
    }

    private var summary: String {
        let drive9 = drive9Enabled
            ? " · 9 \(drive9Mounted ? "Disk" : "Empty")"
            : ""
        return "8 \(drive8Mounted ? "Disk" : "Empty")\(drive9) · T \(tapeMounted ? "Tape" : "Empty") · C \(cartridgeMounted ? "CRT" : "Empty")"
    }

    private var accessibilitySummary: String {
        let drive8 = drive8Mounted ? "Drive 8 loaded" : "Drive 8 empty"
        let drive9 = drive9Enabled
            ? (drive9Mounted ? ", Drive 9 loaded" : ", Drive 9 empty")
            : ""
        let tape = tapeMounted ? "tape loaded" : "tape empty"
        let cartridge = cartridgeMounted ? "cartridge loaded" : "cartridge empty"
        return "Devices, \(drive8)\(drive9), \(tape), \(cartridge)"
    }
}

private struct DevicesConfigurationView: View {
    @ObservedObject var emulator: EmulatorModel
    let onChooseMedia: (DeviceImportTarget) -> Void
    let onCreateDisk: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?
    @State private var driveMediaSetSelection: DriveMediaSetSelection?

    var body: some View {
        NavigationStack {
            Form {
                ForEach(emulator.availableDriveUnits, id: \.self) { unit in
                    driveSection(unit: unit)
                }
                tapeSection
                cartridgeSection
                reuSection

                Section {
                    Button(role: .destructive) {
                        emulator.ejectAllMediaAndReset()
                    } label: {
                        Label("Eject All Media and Reset", systemImage: "eject")
                    }
                    .disabled(!hasMountedMedia)
                } footer: {
                    Text("Device changes are applied immediately. Hard Reset keeps mounted media inserted.")
                }
            }
            .navigationTitle("Devices")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert(
                "Device error",
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
        .sheet(item: $driveMediaSetSelection) { selection in
            DriveMediaSetSheet(unit: selection.unit, emulator: emulator)
        }
    }

    @ViewBuilder
    private func driveSection(unit: Int) -> some View {
        let media = emulator.mountedDisks[unit]

        Section("Drive \(unit)") {
            deviceStatusRow(
                media: media,
                emptyTitle: "No disk inserted",
                systemImage: "externaldrive.fill"
            )

            Button {
                dismiss()
                onCreateDisk(unit)
            } label: {
                Label("Create New Disk…", systemImage: "plus.square.on.square")
            }

            if let media {
                Button {
                    perform(.autostartDisk(unit), media: media)
                } label: {
                    Label("Autostart Disk", systemImage: "play.circle.fill")
                }

                if let setInfo = emulator.mountedDiskSetInfo(for: unit) {
                    LabeledContent("Multi-disk set") {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(setInfo.displayName)
                                .lineLimit(1)
                            Text("\(setInfo.currentMemberLabel) · \(setInfo.positionLabel)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button {
                        driveMediaSetSelection = DriveMediaSetSelection(unit: unit)
                    } label: {
                        Label("Swap Multi-Disk Set…", systemImage: "arrow.left.arrow.right.circle")
                    }
                }

                Button {
                    choose(.drive(unit))
                } label: {
                    Label("Replace Disk…", systemImage: "arrow.triangle.2.circlepath")
                }

                Button(role: .destructive) {
                    do {
                        try emulator.ejectDisk(from: unit)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                } label: {
                    Label("Eject Disk", systemImage: "eject")
                }
            } else {
                Button {
                    choose(.drive(unit))
                } label: {
                    Label("Insert Disk…", systemImage: "plus.circle")
                }
            }
        }
    }

    private var tapeSection: some View {
        Section("Datasette") {
            deviceStatusRow(
                media: emulator.mountedTape,
                emptyTitle: "No tape inserted",
                systemImage: "recordingtape"
            )

            if let media = emulator.mountedTape {
                if media.mediaType == .tap {
                    LabeledContent(
                        "Transport",
                        value: emulator.datasetteTransportState.title
                    )
                    LabeledContent("Counter", value: emulator.datasetteCounterDisplay)
                } else if media.mediaType == .t64 {
                    LabeledContent("Launch mode", value: "Autostart")
                }
                LabeledContent("Format", value: emulator.datasetteFormatSummary)
            }

            if let media = emulator.mountedTape {
                Button {
                    perform(.autostartTape, media: media)
                } label: {
                    Label(
                        media.mediaType == .t64 ? "Run T64" : "Autostart Tape",
                        systemImage: "play.circle.fill"
                    )
                }

                Button {
                    choose(.tape)
                } label: {
                    Label("Replace Tape…", systemImage: "arrow.triangle.2.circlepath")
                }

                Button(role: .destructive) {
                    do {
                        try emulator.ejectTape()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                } label: {
                    Label("Eject Tape", systemImage: "eject")
                }
            } else {
                Button {
                    choose(.tape)
                } label: {
                    Label("Insert Tape…", systemImage: "plus.circle")
                }
            }
        }
    }

    private var cartridgeSection: some View {
        Section("Cartridge") {
            deviceStatusRow(
                media: emulator.mountedCartridge,
                emptyTitle: "No cartridge inserted",
                systemImage: "shippingbox.fill"
            )

            if emulator.mountedCartridge != nil {
                Button {
                    choose(.cartridge)
                } label: {
                    Label("Replace Cartridge…", systemImage: "arrow.triangle.2.circlepath")
                }

                Button(role: .destructive) {
                    do {
                        try emulator.ejectCartridge()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                } label: {
                    Label("Eject Cartridge", systemImage: "eject")
                }
            } else {
                Button {
                    choose(.cartridge)
                } label: {
                    Label("Insert Cartridge…", systemImage: "plus.circle")
                }
            }
        }
    }

    private var reuSection: some View {
        let size = C64REUSize.selected
        let persistentMemory = C64REUSettings.persistentMemoryEnabled

        return Section {
            HStack(spacing: 12) {
                Image(systemName: "memorychip")
                    .font(.title3)
                    .foregroundStyle(size == .disabled ? Color.secondary : Color.accentColor)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 3) {
                    Text("REU")
                        .font(.body.weight(.medium))

                    if size == .disabled {
                        Text("Disabled")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(size.capacityTitle) · Active")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(persistentMemory ? "Persistent memory enabled" : "Volatile memory")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: size == .disabled ? "circle" : "checkmark.circle.fill")
                    .foregroundStyle(size == .disabled ? Color.secondary : Color.green)
            }
        } header: {
            Text("RAM Expansion Unit")
        } footer: {
            if size != .disabled {
                Text("Some cartridges use the same expansion-port address space and may require the REU to be disabled in Settings → System.")
            }
        }
    }

    private var hasMountedMedia: Bool {
        !emulator.mountedDisks.isEmpty
            || emulator.mountedTape != nil
            || emulator.mountedCartridge != nil
    }

    private func deviceStatusRow(
        media: MediaReference?,
        emptyTitle: String,
        systemImage: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(media == nil ? Color.secondary : Color.accentColor)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(media?.title ?? emptyTitle)
                    .font(.body.weight(.medium))
                    .lineLimit(1)

                if let media {
                    Text(media.originalFilename)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text(media.isTemporary ? "Temporary media" : "Library media")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: media == nil ? "circle" : "checkmark.circle.fill")
                .foregroundStyle(media == nil ? Color.secondary : Color.green)
        }
    }

    private func choose(_ target: DeviceImportTarget) {
        dismiss()
        onChooseMedia(target)
    }

    private func perform(_ action: MediaAction, media: MediaReference) {
        do {
            try emulator.performMediaAction(action, media: media)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct DatasetteControlDock: View {
    @ObservedObject var emulator: EmulatorModel
    let onHide: () -> Void

    @State private var errorMessage: String?

    private var physicalTransportAvailable: Bool {
        emulator.mountedTapeSupportsPhysicalTransport
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "recordingtape")
                    .font(.title2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(emulator.mountedTape?.title ?? "Datasette")
                        .font(.headline)
                        .lineLimit(1)
                    Text(emulator.datasetteFormatSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(emulator.datasetteCounterDisplay)
                        .font(.system(.title2, design: .monospaced, weight: .bold))
                    Text(emulator.datasetteTransportState.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("Hide", action: onHide)
                    .buttonStyle(.bordered)
            }

            HStack(spacing: 10) {
                transportButton(
                    "REW",
                    systemImage: "backward.fill",
                    command: .rewind,
                    enabled: physicalTransportAvailable
                )
                transportButton(
                    "STOP",
                    systemImage: "stop.fill",
                    command: .stop,
                    enabled: true
                )
                transportButton(
                    "PLAY",
                    systemImage: "play.fill",
                    command: .play,
                    enabled: true
                )
                transportButton(
                    "F.FWD",
                    systemImage: "forward.fill",
                    command: .fastForward,
                    enabled: physicalTransportAvailable
                )
                transportButton(
                    "COUNTER",
                    systemImage: "gobackward",
                    command: .resetCounter,
                    enabled: physicalTransportAvailable
                )
            }

            if !physicalTransportAvailable {
                Text("T64 containers do not provide a physical reel position; fast transport and counter reset are unavailable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.regularMaterial)
        .alert(
            "Datasette error",
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

    private func transportButton(
        _ title: String,
        systemImage: String,
        command: DatasetteTransportCommand,
        enabled: Bool
    ) -> some View {
        Button {
            do {
                try emulator.controlDatasette(command)
            } catch {
                errorMessage = error.localizedDescription
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.bold))
                Text(title)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.bordered)
        .tint(isActive(command) ? Color.accentColor : Color.gray)
        .disabled(!enabled)
    }

    private func isActive(_ command: DatasetteTransportCommand) -> Bool {
        switch (command, emulator.datasetteTransportState) {
        case (.stop, .stopped),
             (.play, .playing),
             (.fastForward, .fastForwarding),
             (.rewind, .rewinding):
            return true
        default:
            return false
        }
    }
}

private struct NetworkStatusPanel: View {
    let connected: Bool
    let telemetryAvailable: Bool
    let txBytes: UInt64
    let rxBytes: UInt64
    let activityPulse: Bool
    let onOpen: () -> Void

    private var statusTitle: String {
        guard telemetryAvailable else { return "N/A" }
        return connected ? "ONLINE" : "READY"
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(spacing: 8) {
                Image(systemName: "wifi")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.62))

                networkActivityLED

                Text(activityPulse ? "TX / RX" : statusTitle)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(activityPulse ? .orange : .white.opacity(0.55))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)

                VStack(spacing: 2) {
                    Text("↑ \(txBytes)  ↓ \(rxBytes)")
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                        .minimumScaleFactor(0.45)
                    Text("BYTES")
                        .font(.system(size: 6, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 7)
            .frame(width: 64)
            .background(
                .white.opacity(activityPulse ? 0.075 : 0.045),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        activityPulse ? .orange.opacity(0.32) : .white.opacity(0.08),
                        lineWidth: 1
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Virtual modem, \(connected ? "connected" : "waiting"), transmitted \(txBytes) bytes, received \(rxBytes) bytes"
        )
        .accessibilityHint("Opens Virtual Modem status")
        .animation(.easeOut(duration: 0.15), value: activityPulse)
    }

    @ViewBuilder
    private var networkActivityLED: some View {
        if activityPulse {
            TimelineView(.periodic(from: .now, by: 0.24)) { context in
                let phase = Int(context.date.timeIntervalSinceReferenceDate / 0.24)
                let illuminated = phase.isMultiple(of: 2)

                Circle()
                    .fill(.orange)
                    .frame(width: 13, height: 13)
                    .opacity(illuminated ? 1 : 0.42)
                    .shadow(
                        color: .orange.opacity(illuminated ? 0.95 : 0.3),
                        radius: illuminated ? 8 : 3
                    )
                    .scaleEffect(illuminated ? 1.14 : 0.96)
            }
        } else {
            Circle()
                .fill(telemetryAvailable ? .green : .gray)
                .frame(width: 13, height: 13)
                .opacity(connected ? 1 : 0.62)
                .shadow(
                    color: telemetryAvailable ? .green.opacity(connected ? 0.8 : 0.35) : .clear,
                    radius: connected ? 5 : 2
                )
        }
    }
}

private enum VirtualModemSheetSection: String, CaseIterable, Identifiable {
    case status = "Status"
    case directory = "BBS"
    case traffic = "Traffic"

    var id: String { rawValue }
}

private enum BBSConnectionProtocol: String, Codable, CaseIterable, Identifiable {
    case raw = "RAW TCP"
    case telnet = "TELNET"

    var id: String { rawValue }
    var usesTelnet: Bool { self == .telnet }
}

private struct BBSDirectoryEntry: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var host: String
    var port: Int
    var connectionProtocol: BBSConnectionProtocol
    var notes: String = ""

    var target: String { "\(host):\(port)" }
}

private enum BBSDirectoryStore {
    static let key = "poke64.network.bbsDirectory.v1"

    static let defaults: [BBSDirectoryEntry] = [
        BBSDirectoryEntry(
            name: "Cottonwood BBS",
            host: "cottonwoodbbs.dyndns.org",
            port: 6502,
            connectionProtocol: .telnet,
            notes: "Commodore / PETSCII"
        ),
        BBSDirectoryEntry(
            name: "Borderline BBS",
            host: "borderlinebbs.dyndns.org",
            port: 6400,
            connectionProtocol: .telnet,
            notes: "Commodore / PETSCII"
        ),
        BBSDirectoryEntry(
            name: "RetroCampus",
            host: "bbs.retrocampus.com",
            port: 6510,
            connectionProtocol: .raw,
            notes: "Italian C64 / PETSCII endpoint"
        )
    ]

    static func load() -> [BBSDirectoryEntry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let entries = try? JSONDecoder().decode([BBSDirectoryEntry].self, from: data) else {
            return defaults
        }
        return entries
    }

    static func save(_ entries: [BBSDirectoryEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

private struct BBSEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: BBSDirectoryEntry
    let isNew: Bool
    let onSave: (BBSDirectoryEntry) -> Void

    init(entry: BBSDirectoryEntry, isNew: Bool, onSave: @escaping (BBSDirectoryEntry) -> Void) {
        _draft = State(initialValue: entry)
        self.isNew = isNew
        self.onSave = onSave
    }

    private var canSave: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draft.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (1...65535).contains(draft.port)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("BBS") {
                    TextField("Name", text: $draft.name)
                    TextField("Host", text: $draft.host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Port", value: $draft.port, format: .number)
                        .keyboardType(.numberPad)
                    Picker("Protocol", selection: $draft.connectionProtocol) {
                        ForEach(BBSConnectionProtocol.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                }

                Section("Notes") {
                    TextField("Optional notes", text: $draft.notes, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle(isNew ? "Add BBS" : "Edit BBS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        draft.host = draft.host.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}

private struct VirtualModemStatusSheet: View {
    @ObservedObject var emulator: EmulatorModel
    let activityPulse: Bool
    let onOpenSettings: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSection: VirtualModemSheetSection = .status
    @State private var entries = BBSDirectoryStore.load()
    @State private var editorEntry: BBSDirectoryEntry?
    @State private var editorIsNew = false
    @State private var trafficHexMode = false
    @State private var actionError: String?

    private var statusTitle: String {
        if emulator.virtualModemConnected { return "Online" }
        if emulator.virtualModemReady { return "AT command mode" }
        return "Waiting for C64 terminal"
    }

    private var protocolTitle: String {
        emulator.virtualModemTelnetEnabled ? "TELNET" : "RAW TCP"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Virtual Modem", selection: $selectedSection) {
                    ForEach(VirtualModemSheetSection.allCases) { section in
                        Text(section.rawValue).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 10)

                switch selectedSection {
                case .status:
                    statusList
                case .directory:
                    directoryList
                case .traffic:
                    trafficView
                }
            }
            .navigationTitle("Virtual Modem")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .sheet(item: $editorEntry) { entry in
            BBSEditorSheet(entry: entry, isNew: editorIsNew) { saved in
                if let index = entries.firstIndex(where: { $0.id == saved.id }) {
                    entries[index] = saved
                } else {
                    entries.append(saved)
                }
                BBSDirectoryStore.save(entries)
            }
        }
        .alert(
            "Virtual Modem",
            isPresented: Binding(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "Unknown modem error")
        }
    }

    private var statusList: some View {
        List {
            Section("Connection") {
                LabeledContent("Status", value: statusTitle)
                if !emulator.virtualModemEndpoint.isEmpty {
                    LabeledContent("Endpoint", value: emulator.virtualModemEndpoint)
                        .textSelection(.enabled)
                }
                LabeledContent("Protocol", value: protocolTitle)
                LabeledContent(
                    "Interface",
                    value: C64VirtualModemSettings.baud == 9600
                        ? "UP9600 / EZ232"
                        : "User Port RS-232"
                )
                LabeledContent("Baud", value: "\(C64VirtualModemSettings.baud)")
                if !emulator.virtualModemLastResult.isEmpty {
                    LabeledContent("Last result", value: emulator.virtualModemLastResult)
                }
            }

            Section("Traffic") {
                LabeledContent("Transmitted", value: byteCount(emulator.virtualModemTXBytes))
                LabeledContent("Received", value: byteCount(emulator.virtualModemRXBytes))

                if activityPulse {
                    Label("Modem activity", systemImage: "arrow.up.arrow.down.circle.fill")
                        .foregroundStyle(.orange)
                }
            }

            Section {
                Button(role: .destructive) {
                    do {
                        try emulator.hangUpVirtualModem()
                    } catch {
                        actionError = error.localizedDescription
                    }
                } label: {
                    Label("Hang Up", systemImage: "phone.down.fill")
                }
                .disabled(!emulator.virtualModemConnected)

                Button("Networking Settings", action: onOpenSettings)
            } footer: {
                Text("Dial from C64 software with ATDT host:port, or use the BBS directory. Native Dial still reports CONNECT/NO CARRIER back to the C64 terminal.")
            }
        }
    }

    private var directoryList: some View {
        List {
            Section {
                if entries.isEmpty {
                    ContentUnavailableView(
                        "No BBS entries",
                        systemImage: "list.bullet.rectangle",
                        description: Text("Add a BBS host and port to dial it directly from POKE64.")
                    )
                } else {
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(entry.name)
                                        .font(.headline)
                                    Text(entry.target)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                    if !entry.notes.isEmpty {
                                        Text(entry.notes)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 12)
                                Text(entry.connectionProtocol.rawValue)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }

                            HStack {
                                Button {
                                    dial(entry)
                                } label: {
                                    Label("Dial", systemImage: "phone.arrow.up.right")
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(!emulator.isRunning || !C64VirtualModemSettings.enabled)

                                Button("Edit") {
                                    editorIsNew = false
                                    editorEntry = entry
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(.vertical, 4)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                entries.removeAll { $0.id == entry.id }
                                BBSDirectoryStore.save(entries)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            } header: {
                HStack {
                    Text("BBS Directory")
                    Spacer()
                    Button {
                        editorIsNew = true
                        editorEntry = BBSDirectoryEntry(
                            name: "",
                            host: "",
                            port: 23,
                            connectionProtocol: .telnet
                        )
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .textCase(nil)
                }
            } footer: {
                if !emulator.virtualModemReady {
                    Text("Open the modem in a C64 terminal such as CCGMS first. Once the User Port device is ready, Dial can open the selected BBS without typing ATDT manually.")
                } else {
                    Text("Dial uses the same Hayes/rs232net backend as ATDT. The selected RAW/TELNET mode applies only to that call.")
                }
            }
        }
    }

    private var trafficView: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Traffic format", selection: $trafficHexMode) {
                    Text("Text").tag(false)
                    Text("Hex").tag(true)
                }
                .pickerStyle(.segmented)

                Button("Clear") {
                    do {
                        try emulator.clearVirtualModemTraffic()
                    } catch {
                        actionError = error.localizedDescription
                    }
                }
                .disabled(emulator.virtualModemTraceBytes.isEmpty)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            Divider()

            if emulator.virtualModemTraceBytes.isEmpty {
                ContentUnavailableView(
                    "No traffic captured",
                    systemImage: "waveform.path.ecg",
                    description: Text("AT commands and online C64 RX/TX bytes will appear here without being consumed by the monitor.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView([.vertical, .horizontal]) {
                    Text(trafficHexMode ? trafficHexText : trafficText)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding()
                }
                .background(.black.opacity(0.18))
            }
        }
    }

    private func dial(_ entry: BBSDirectoryEntry) {
        do {
            try emulator.dialVirtualModem(
                host: entry.host,
                port: entry.port,
                telnet: entry.connectionProtocol.usesTelnet
            )
            selectedSection = .status
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func byteCount(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file)
    }

    private var tracePairs: [(direction: UInt8, byte: UInt8)] {
        Array(zip(emulator.virtualModemTraceDirections, emulator.virtualModemTraceBytes))
            .map { (direction: $0.0, byte: $0.1) }
    }

    private var trafficText: String {
        guard !tracePairs.isEmpty else { return "" }
        var output = ""
        var lastDirection: UInt8?

        for item in tracePairs {
            if item.direction != lastDirection {
                if !output.isEmpty && !output.hasSuffix("\n") { output.append("\n") }
                output.append(item.direction == 0 ? "TX  " : "RX  ")
                lastDirection = item.direction
            }

            switch item.byte {
            case 13:
                output.append("␍\n")
                lastDirection = nil
            case 10:
                output.append("␊\n")
                lastDirection = nil
            case 32...126:
                output.append(Character(UnicodeScalar(item.byte)))
            default:
                output.append("·")
            }
        }
        return output
    }

    private var trafficHexText: String {
        guard !tracePairs.isEmpty else { return "" }
        var lines: [String] = []
        var currentDirection: UInt8?
        var currentBytes: [UInt8] = []

        func flush() {
            guard let direction = currentDirection, !currentBytes.isEmpty else { return }
            var offset = 0
            while offset < currentBytes.count {
                let chunk = currentBytes[offset..<min(offset + 16, currentBytes.count)]
                let values = chunk.map { String(format: "%02X", $0) }.joined(separator: " ")
                lines.append("\(direction == 0 ? "TX" : "RX")  \(values)")
                offset += 16
            }
            currentBytes.removeAll(keepingCapacity: true)
        }

        for item in tracePairs {
            if currentDirection != item.direction {
                flush()
                currentDirection = item.direction
            }
            currentBytes.append(item.byte)
        }
        flush()
        return lines.joined(separator: "\n")
    }
}

private struct PrinterStatusPanel: View {
    let device: Int
    let format: C64PrinterExportFormat
    let capturedBytes: Int?
    let activityPulse: Bool
    let onOpen: () -> Void

    private var capturedSizeDescription: String {
        guard let capturedBytes, capturedBytes > 0 else { return "0 B" }
        return ByteCountFormatter.string(
            fromByteCount: Int64(capturedBytes),
            countStyle: .file
        )
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(spacing: 8) {
                HStack(spacing: 4) {
                    Text("PRN \(device)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.62))

                    Spacer(minLength: 2)

                    Image(systemName: "chevron.up.circle")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.58))
                }

                printerActivityLED

                Text(activityPulse ? "PRINTING" : format.rawValue.uppercased())
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(activityPulse ? .orange : .white.opacity(0.55))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)

                Text(capturedSizeDescription)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.86))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 7)
            .frame(maxWidth: .infinity)
            .background(
                .white.opacity(activityPulse ? 0.075 : 0.045),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        activityPulse ? .orange.opacity(0.32) : .white.opacity(0.08),
                        lineWidth: 1
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "IEC printer \(device), \(activityPulse ? "printing" : "ready"), captured data \(capturedSizeDescription)"
        )
        .accessibilityHint("Opens the virtual printer controls")
        .animation(.easeOut(duration: 0.15), value: activityPulse)
    }

    @ViewBuilder
    private var printerActivityLED: some View {
        if activityPulse {
            TimelineView(.periodic(from: .now, by: 0.32)) { context in
                let phase = Int(context.date.timeIntervalSinceReferenceDate / 0.32)
                let illuminated = phase.isMultiple(of: 2)

                Circle()
                    .fill(.orange)
                    .frame(width: 13, height: 13)
                    .opacity(illuminated ? 1 : 0.42)
                    .shadow(
                        color: .orange.opacity(illuminated ? 0.95 : 0.3),
                        radius: illuminated ? 8 : 3
                    )
                    .scaleEffect(illuminated ? 1.14 : 0.96)
            }
        } else {
            Circle()
                .fill(.green)
                .frame(width: 13, height: 13)
                .shadow(color: .green.opacity(0.72), radius: 4)
        }
    }
}

private struct DatasetteStatusPanel: View {
    @ObservedObject var emulator: EmulatorModel
    let controlsVisible: Bool
    let onToggleControls: () -> Void

    var body: some View {
        Button(action: onToggleControls) {
            VStack(spacing: 8) {
                HStack(spacing: 4) {
                    Text("TAPE")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.55))

                    Spacer(minLength: 2)

                    Image(systemName: controlsVisible
                        ? "chevron.down.circle.fill"
                        : "chevron.up.circle")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.58))
                }

                Text(emulator.datasetteCounterDisplay)
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                    .minimumScaleFactor(0.6)

                Image(systemName: emulator.datasetteTransportState.systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.72))

                Text(emulator.datasetteTransportState.title.uppercased())
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                HStack(spacing: 8) {
                    smallIndicator(
                        title: "MOTOR",
                        isOn: emulator.datasetteMotorOn,
                        activeColor: .green
                    )
                    smallIndicator(
                        title: "READ",
                        isOn: emulator.datasetteActivityLEDOn,
                        activeColor: .red
                    )
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 7)
            .frame(maxWidth: .infinity)
            .background(
                .white.opacity(controlsVisible ? 0.075 : 0.045),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        .white.opacity(controlsVisible ? 0.18 : 0.08),
                        lineWidth: 1
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!emulator.isRunning)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Datasette, counter \(emulator.datasetteCounterDisplay), \(emulator.datasetteTransportState.title)"
        )
        .accessibilityHint(
            controlsVisible
                ? "Hides the datasette controls"
                : "Shows the datasette controls"
        )
    }

    private func smallIndicator(
        title: String,
        isOn: Bool,
        activeColor: Color
    ) -> some View {
        VStack(spacing: 3) {
            Circle()
                .fill(isOn ? activeColor : activeColor.opacity(0.16))
                .frame(width: 10, height: 10)
                .shadow(
                    color: isOn ? activeColor.opacity(0.85) : .clear,
                    radius: isOn ? 4 : 0
                )
            Text(title)
                .font(.system(size: 7, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.45))
        }
    }
}

private struct DriveMediaSetSelection: Identifiable {
    let unit: Int
    var id: Int { unit }
}

private struct DriveMediaSetSheet: View {
    let unit: Int
    @ObservedObject var emulator: EmulatorModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let info = emulator.mountedDiskSetInfo(for: unit) {
                    List {
                        Section {
                            LabeledContent("Drive", value: "\(unit)")
                            LabeledContent("Set", value: info.displayName)
                            LabeledContent("Current", value: info.currentMemberLabel)
                            LabeledContent("Position", value: info.positionLabel)
                        }

                        Section("Available Disks") {
                            ForEach(info.members) { member in
                                let memberIndex = info.members.firstIndex(where: {
                                    $0.id == member.id
                                }) ?? 0
                                let isCurrent = member.id == info.currentItem.id

                                Button {
                                    emulator.selectDiskSetMember(member, in: unit)
                                    dismiss()
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(
                                            systemName: isCurrent
                                                ? "checkmark.circle.fill"
                                                : "circle"
                                        )
                                        .foregroundStyle(
                                            isCurrent
                                                ? Color.accentColor
                                                : Color.secondary
                                        )

                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(
                                                member.mediaSetDescriptor?.memberLabel
                                                    ?? "Disk \(memberIndex + 1)"
                                            )
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
                                .disabled(isCurrent)
                            }
                        }

                        Section {
                            Text("Selecting another member replaces the image in Drive \(unit) immediately, without resetting the C64.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "Multi-disk Set Unavailable",
                        systemImage: "externaldrive.badge.questionmark",
                        description: Text("The mounted disk is no longer part of a detected Library set.")
                    )
                }
            }
            .navigationTitle("Swap Multi-Disk Set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct DriveStatusPanel: View {
    let drive8PowerOn: Bool
    let drive9Enabled: Bool
    let drive9PowerOn: Bool
    let activityOn: Bool

    var body: some View {
        VStack(spacing: 9) {
            Text(drive9Enabled ? "DRIVES" : "DRIVE 8")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.55))

            if drive9Enabled {
                powerIndicator(unit: 8, isOn: drive8PowerOn)
                powerIndicator(unit: 9, isOn: drive9PowerOn)
                indicator(title: "ACT", isOn: activityOn, activeColor: .red)
            } else {
                indicator(title: "PWR", isOn: drive8PowerOn, activeColor: .green)
                indicator(title: "ACT", isOn: activityOn, activeColor: .red)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(
            .white.opacity(0.045),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        if drive9Enabled {
            return "Drive 8 power \(drive8PowerOn ? "on" : "off"), Drive 9 power \(drive9PowerOn ? "on" : "off"), disk activity \(activityOn ? "active" : "idle")"
        }
        return "Drive 8, power \(drive8PowerOn ? "on" : "off"), activity \(activityOn ? "active" : "idle")"
    }

    private func powerIndicator(unit: Int, isOn: Bool) -> some View {
        indicator(title: "\(unit) PWR", isOn: isOn, activeColor: .green)
    }

    private func indicator(
        title: String,
        isOn: Bool,
        activeColor: Color
    ) -> some View {
        VStack(spacing: 4) {
            Circle()
                .fill(isOn ? activeColor : activeColor.opacity(0.16))
                .frame(width: 13, height: 13)
                .shadow(
                    color: isOn ? activeColor.opacity(0.85) : .clear,
                    radius: isOn ? 5 : 0
                )

            Text(title)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
        }
        .animation(.easeOut(duration: 0.08), value: isOn)
    }
}

private struct C64ScreenRepresentable: UIViewRepresentable {
    @EnvironmentObject private var emulator: EmulatorModel

    func makeUIView(context: Context) -> C64MetalView {
        let view = C64MetalView(frame: .zero)
        emulator.attach(videoView: view)
        return view
    }

    func updateUIView(_ uiView: C64MetalView, context: Context) {
        emulator.attach(videoView: uiView)
    }
}

private struct DPad: View {
    let action: (C64JoypadButton, Bool) -> Void

    var body: some View {
        Grid(horizontalSpacing: 4, verticalSpacing: 4) {
            GridRow {
                Color.clear.frame(width: 48, height: 48)
                HoldButton("▲", diameter: 48) { action(.up, $0) }
                Color.clear.frame(width: 48, height: 48)
            }
            GridRow {
                HoldButton("◀", diameter: 48) { action(.left, $0) }
                Circle().fill(.black.opacity(0.55)).frame(width: 48, height: 48)
                HoldButton("▶", diameter: 48) { action(.right, $0) }
            }
            GridRow {
                Color.clear.frame(width: 48, height: 48)
                HoldButton("▼", diameter: 48) { action(.down, $0) }
                Color.clear.frame(width: 48, height: 48)
            }
        }
    }
}

private struct HoldButton: View {
    let title: String
    let diameter: CGFloat?
    let action: (Bool) -> Void
    @State private var pressed = false

    init(_ title: String, diameter: CGFloat? = nil, action: @escaping (Bool) -> Void) {
        self.title = title
        self.diameter = diameter
        self.action = action
    }

    var body: some View {
        Text(title)
            .font(.system(size: diameter == nil ? 12 : 18, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: diameter, height: diameter)
            .padding(diameter == nil ? 11 : 0)
            .background(pressed ? .black.opacity(0.82) : .black.opacity(0.62))
            .overlay {
                HoldButtonShape(circular: diameter != nil)
                    .stroke(.white.opacity(0.28), lineWidth: 1)
            }
            .clipShape(HoldButtonShape(circular: diameter != nil))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !pressed else { return }
                        pressed = true
                        action(true)
                    }
                    .onEnded { _ in
                        pressed = false
                        action(false)
                    }
            )
            .onDisappear {
                guard pressed else { return }
                pressed = false
                action(false)
            }
    }
}

private struct HoldButtonShape: Shape {
    let circular: Bool

    func path(in rect: CGRect) -> Path {
        if circular {
            return Circle().path(in: rect)
        }
        return RoundedRectangle(cornerRadius: 8).path(in: rect)
    }
}


struct MediaActionPromptState: Identifiable, Equatable {
    enum Mode: Equatable {
        case choose
        case replace(MediaAction, MediaReplacementInfo)
    }

    let id: UUID
    let request: MediaActionRequest
    let mode: Mode

    static func choose(_ request: MediaActionRequest) -> MediaActionPromptState {
        MediaActionPromptState(id: UUID(), request: request, mode: .choose)
    }

    static func replace(
        _ request: MediaActionRequest,
        action: MediaAction,
        replacement: MediaReplacementInfo
    ) -> MediaActionPromptState {
        MediaActionPromptState(
            id: UUID(),
            request: request,
            mode: .replace(action, replacement)
        )
    }
}

extension View {
    func mediaActionPrompt(
        prompt: Binding<MediaActionPromptState?>,
        emulator: EmulatorModel,
        onComplete: @escaping () -> Void = {}
    ) -> some View {
        modifier(
            MediaActionPromptModifier(
                prompt: prompt,
                emulator: emulator,
                onComplete: onComplete
            )
        )
    }
}

private struct MediaActionPromptModifier: ViewModifier {
    @Binding var prompt: MediaActionPromptState?
    @ObservedObject var emulator: EmulatorModel
    let onComplete: () -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                chooseDialogTitle,
                isPresented: chooseDialogBinding,
                titleVisibility: .visible
            ) {
                chooseDialogButtons
            } message: {
                if let message = chooseDialogMessage {
                    Text(message)
                }
            }
            .alert(
                "Replace Media?",
                isPresented: replacementAlertBinding
            ) {
                replacementAlertButtons
            } message: {
                if let message = replacementAlertMessage {
                    Text(message)
                }
            }
    }

    private var chooseDialogBinding: Binding<Bool> {
        Binding(
            get: {
                guard let prompt else { return false }
                if case .choose = prompt.mode { return true }
                return false
            },
            set: { isPresented in
                guard !isPresented,
                      let current = prompt,
                      case .choose = current.mode else { return }
                cancel(current.request)
            }
        )
    }

    private var replacementAlertBinding: Binding<Bool> {
        Binding(
            get: {
                guard let prompt else { return false }
                if case .replace = prompt.mode { return true }
                return false
            },
            set: { isPresented in
                guard !isPresented,
                      let current = prompt,
                      case .replace = current.mode else { return }
                cancel(current.request)
            }
        )
    }

    private var chooseDialogTitle: String {
        guard let prompt, case .choose = prompt.mode else { return "Media" }
        return prompt.request.media.title
    }

    private var chooseDialogMessage: String? {
        guard let prompt, case .choose = prompt.mode else { return nil }
        switch prompt.request.media.mediaType {
        case .d64, .d71, .d81, .g64:
            return "Choose whether to insert the disk without resetting the C64 or autostart it."
        case .tap:
            return "Choose whether to insert the TAP image without resetting the C64 or autostart it."
        case .t64:
            return nil
        case .prg, .crt:
            return nil
        }
    }

    private var replacementAlertMessage: String? {
        guard let prompt,
              case .replace(_, let replacement) = prompt.mode else { return nil }
        return "\(replacement.destination) already contains “\(replacement.existingTitle)”. Replace it with “\(prompt.request.media.originalFilename)”?"
    }

    @ViewBuilder
    private var chooseDialogButtons: some View {
        if let prompt, case .choose = prompt.mode {
            ForEach(prompt.request.actions) { action in
                Button(action.title) {
                    select(action, request: prompt.request)
                }
            }

            Button("Cancel", role: .cancel) {
                cancel(prompt.request)
            }
        }
    }

    @ViewBuilder
    private var replacementAlertButtons: some View {
        if let prompt, case .replace(let action, _) = prompt.mode {
            Button("Replace", role: .destructive) {
                perform(action, request: prompt.request, replacingExisting: true)
            }

            Button("Cancel", role: .cancel) {
                cancel(prompt.request)
            }
        }
    }

    private func cancel(_ request: MediaActionRequest) {
        emulator.discardPreparedMedia(request.media)
        prompt = nil
    }

    private func select(_ action: MediaAction, request: MediaActionRequest) {
        if let replacement = emulator.replacementInfo(
            for: action,
            media: request.media
        ) {
            prompt = .replace(
                request,
                action: action,
                replacement: replacement
            )
            return
        }
        perform(action, request: request, replacingExisting: false)
    }

    private func perform(
        _ action: MediaAction,
        request: MediaActionRequest,
        replacingExisting: Bool
    ) {
        do {
            try emulator.performMediaAction(
                action,
                media: request.media,
                replacingExisting: replacingExisting
            )
            prompt = nil
            onComplete()
        } catch {
            emulator.discardPreparedMedia(request.media)
            prompt = nil
            emulator.presentMediaError(error)
        }
    }
}

private struct StartupErrorView: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(message)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding()
            }
            .navigationTitle("Core startup error")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
