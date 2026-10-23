import SwiftUI
import TipKit

@main
struct FrameTrailApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var library: LibraryStore
    @State private var model = AppModel()

    init() {
        if !ProcessInfo.processInfo.arguments.contains("--uitesting") { try? Tips.configure([.displayFrequency(.daily)]) }
        URLCache.shared = URLCache(memoryCapacity: 8 * 1024 * 1024, diskCapacity: 16 * 1024 * 1024, diskPath: "FrameTrailImages")
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
                .environment(\.locale, Locale(identifier: model.localeIdentifier))
                .tint(Theme.accent)
                .preferredColorScheme(.dark)
                .task { await model.restoreAccount(library: library) }
                .onChange(of: library.cloudItems()) { _, _ in model.sync?.schedule(library: library) }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active && !model.isUITesting { Task { await model.sync?.syncNow(library: library) } }
                }
        }
    }
}
