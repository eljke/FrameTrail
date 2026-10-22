import SwiftUI

@main
struct FrameTrailApp: App {
    @State private var library: LibraryStore
    @State private var model = AppModel()

    init() {
        let testDirectory = ProcessInfo.processInfo.arguments.contains("--uitesting")
            ? FileManager.default.temporaryDirectory.appendingPathComponent("FrameTrail-" + UUID().uuidString, isDirectory: true)
            : nil
        _library = State(initialValue: LibraryStore(directory: testDirectory))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
                .environment(model)
                .tint(Theme.accent)
                .preferredColorScheme(.dark)
                .task { await model.restoreAccount(library: library) }
        }
    }
}
