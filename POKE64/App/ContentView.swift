import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var emulator: EmulatorModel
    @State private var showImporter = false
    @State private var showKeyboard = false
    @State private var showGameControls = false
    @State private var showFirmwareSettings = false

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

                    if !emulator.firmwareReady {
                        firmwareRequiredOverlay
                    }

                    if showGameControls {
                        gameControlsOverlay
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .task {
            emulator.startAutomatically()
        }
        .sheet(isPresented: $showKeyboard) {
            C64KeyboardView()
                .environmentObject(emulator)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showFirmwareSettings, onDismiss: {
            emulator.firmwareConfigurationChanged()
        }) {
            FirmwareSettingsView()
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.data, .archive],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    emulator.importAndLoad(url: url)
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
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("POKE64")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(emulator.status)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Button {
                showImporter = true
            } label: {
                Label("Open File", systemImage: "folder")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!emulator.firmwareReady)

            Button {
                showFirmwareSettings = true
            } label: {
                Label("Firmware", systemImage: "memorychip")
            }
            .buttonStyle(.bordered)

            Button {
                showKeyboard = true
            } label: {
                Label("Keyboard", systemImage: "keyboard")
            }
            .buttonStyle(.bordered)
            .disabled(!emulator.isRunning)

            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    showGameControls.toggle()
                }
            } label: {
                Label(
                    showGameControls ? "Hide Controls" : "Controls",
                    systemImage: showGameControls ? "gamecontroller.fill" : "gamecontroller"
                )
            }
            .buttonStyle(.bordered)
            .disabled(!emulator.isRunning)

            Button("Reset") {
                emulator.reset()
            }
            .buttonStyle(.bordered)
            .disabled(!emulator.isRunning)

            Button(emulator.isRunning ? "Stop" : "Start") {
                if emulator.isRunning {
                    emulator.stop()
                    showGameControls = false
                } else {
                    emulator.startEmpty()
                }
            }
            .buttonStyle(.bordered)
            .disabled(!emulator.isRunning && !emulator.firmwareReady)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.black)
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
                showFirmwareSettings = true
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
