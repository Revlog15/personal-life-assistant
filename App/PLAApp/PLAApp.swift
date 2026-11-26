import SwiftUI
import PLACore

@main
struct PLAApp: App {
    @State private var store: AppStore
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let appStore = AppStore()
        appStore.backgroundRefresh.register()
        _store = State(initialValue: appStore)
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(store)
                .onOpenURL { url in
                    store.handleIncomingURL(url)
                }
                .onChange(of: scenePhase) { _, newPhase in
                    store.authService.handleScenePhaseChange(newPhase, settings: store.settings)
                    switch newPhase {
                    case .active:
                        store.refreshSystemStatusAndSyncNotifications()
                    case .background:
                        store.backgroundRefresh.scheduleNextRefresh()
                    case .inactive:
                        break
                    @unknown default:
                        break
                    }
                }
        }
    }
}
