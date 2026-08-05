import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var emulator: EmulatorModel
    @State private var showImporter = false
    @State private var showKeyboard = false
    @State private var showLibrary = false
    @State private var showPorts = false
    @State private var showSettings = false
    @State private var settingsInitialPanel: SettingsPanel = .system
    @State private var settingsFirmwareFingerprint = FirmwareStore.configurationFingerprint

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

                ZStack(alignment: .bottom) {
                    C64ScreenRepresentable()
                        .environmentObject(emulator)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .ignoresSafeArea(edges: .bottom)
            }

            if emulator.isStarting {
                bootOverlay
                    .transition(.opacity)
                    .zIndex(100)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: emulator.isStarting)
        .task {
            await emulator.startAutomatically()
        }
        .sheet(isPresented: $showKeyboard) {
            C64KeyboardView()
                .environmentObject(emulator)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showSettings, onDismiss: {
            Task {
                await emulator.settingsDidClose(
                    previousFirmwareFingerprint: settingsFirmwareFingerprint
                )
            }
        }) {
            SettingsView(initialPanel: settingsInitialPanel)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $showLibrary) {
            LibraryView(
                library: emulator.library,
                loadedItemID: emulator.loadedLibraryItemID,
                temporaryMedia: emulator.loadedTemporaryMedia,
                temporaryMediaAddedItemID: emulator.loadedTemporaryMediaLibraryItemID,
                onImport: { url in
                    try emulator.importIntoLibrary(url: url)
                },
                onAddTemporaryMedia: {
                    try emulator.addCurrentTemporaryMediaToLibrary()
                },
                onRun: { item in
                    try emulator.loadLibraryItem(item)
                }
            )
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.data, .archive],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    emulator.openTemporaryMedia(url: url)
                }
            case .failure(let error):
                print("File importer: \(error)")
            }
        }
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

    private var header: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                toolbarButtons
                    .frame(
                        minWidth: max(0, proxy.size.width - 32),
                        alignment: .center
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
        }
        .frame(height: 58)
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
    }

    @ViewBuilder
    private var toolbarButtons: some View {
        HStack(spacing: 10) {
            Button {
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
                showKeyboard = true
            } label: {
                toolbarLabel("Keyboard", systemImage: "keyboard")
            }
            .buttonStyle(.bordered)
            .disabled(!emulator.isRunning)

            Button {
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
                openSettings(.system)
            } label: {
                toolbarLabel("Settings", systemImage: "gearshape")
            }
            .buttonStyle(.bordered)

            Menu {
                Button("Soft Reset", systemImage: "arrow.counterclockwise") {
                    emulator.softReset()
                }
                Button("Hard Reset", systemImage: "power") {
                    Task {
                        await emulator.hardReset()
                    }
                }

                if emulator.hasLoadedCartridge {
                    Divider()
                    Button("Eject Cartridge and Reset", systemImage: "eject") {
                        Task {
                            await emulator.ejectCartridgeAndReset()
                        }
                    }
                }
            } label: {
                toolbarLabel("Reset", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(!emulator.isRunning)
        }
    }

    private func toolbarLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
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

private struct PortsToolbarLabel: View {
    let port1Title: String
    let port2Title: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "gamecontroller")
                .font(.body.weight(.semibold))

            Text("Ports")

            Text("1 \(port1Title) · 2 \(port2Title)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .contentShape(Rectangle())
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
                title: "Commodore Mouse",
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
