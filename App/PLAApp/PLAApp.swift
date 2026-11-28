import SwiftUI
import PLACore

@main
struct PLAApp: App {
    @State private var store: AppStore
    @State private var isSplashVisible: Bool
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let appStore = AppStore()
        appStore.backgroundRefresh.register()
        _store = State(initialValue: appStore)
        _isSplashVisible = State(initialValue: appStore.pendingOCRReceipt == nil)
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootTabView(isSplashFinished: !isSplashVisible)
                    .environment(store)

                if isSplashVisible {
                    LaunchSplashView {
                        withAnimation(.easeInOut(duration: 0.32)) {
                            isSplashVisible = false
                        }
                    }
                    .transition(.opacity)
                    .zIndex(10)
                }
            }
            .preferredColorScheme(isSplashVisible ? .dark : store.appearanceMode.colorScheme)
            .onOpenURL { url in
                isSplashVisible = false
                store.handleIncomingURL(url)
            }
            .onChange(of: store.pendingOCRReceipt) { _, draft in
                if draft != nil && isSplashVisible {
                    isSplashVisible = false
                }
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
