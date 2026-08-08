import SwiftUI

@main
struct POKE64App: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var emulator = EmulatorModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(emulator)
                .onChange(of: scenePhase) { _, phase in
                    Task {
                        await emulator.handleScenePhase(phase)
                    }
                }
        }
    }
}
