import SwiftUI
import SwiftData

@main
struct Book2FlashcardsApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(model.settings)
                .environment(model.store)
                .modelContainer(model.container)
                // A new container (iCloud sync toggled) must rebuild the view tree.
                .id(model.containerGeneration)
                .task { await model.start() }
                .onOpenURL { url in model.pendingOpenURL = url }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await model.store.refreshEntitlements() }
            }
        }
    }
}
