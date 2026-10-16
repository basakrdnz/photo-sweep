import SwiftUI

@main
struct PhotoSweepApp: App {
    @State private var model = ScanModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
        }
    }
}
