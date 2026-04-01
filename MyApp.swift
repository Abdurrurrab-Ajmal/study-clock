import SwiftUI

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        // 🖥️ MAC: Removes the standard window title bar container
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        #endif
    }
}
