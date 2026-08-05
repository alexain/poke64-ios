import SwiftUI

@main
struct POKE64App: App {
    @StateObject private var emulator = EmulatorModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(emulator)
        }
    }
}
