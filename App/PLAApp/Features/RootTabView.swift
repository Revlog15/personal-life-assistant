import SwiftUI
import PLACore

enum AppTab: Int, Hashable {
    case dashboard = 0
    case tasks = 1
    case finance = 2
    case settings = 3
}

enum QuickAddSheetKind: Identifiable {
    case task
    case expense
    case income
    case transfer
    case scanReceipt
    case whatIf

    var id: String {
        switch self {
        case .task: return "task"
        case .expense: return "expense"
        case .income: return "income"
        case .transfer: return "transfer"
        case .scanReceipt: return "scanReceipt"
        case .whatIf: return "whatIf"
        }
    }
}

struct RootTabView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectedTab: AppTab = .dashboard
    @State private var activeQuickAdd: QuickAddSheetKind?

    var body: some View {
        ZStack(alignment: .bottom) {
            // Keep all 4 tab hierarchies mounted so scroll offset, search filters, segments, and calendar dates persist across tab switches.
            ZStack {
                DashboardView(
                    selectedTab: $selectedTab,
                    onQuickAdd: { activeQuickAdd = $0 }
                )
                .opacity(selectedTab == .dashboard ? 1 : 0)
                .allowsHitTesting(selectedTab == .dashboard)
                .accessibilityHidden(selectedTab != .dashboard)

                TasksView()
                    .opacity(selectedTab == .tasks ? 1 : 0)
                    .allowsHitTesting(selectedTab == .tasks)
                    .accessibilityHidden(selectedTab != .tasks)

                FinanceGateView(isActive: selectedTab == .finance)
                    .opacity(selectedTab == .finance ? 1 : 0)
                    .allowsHitTesting(selectedTab == .finance)
                    .accessibilityHidden(selectedTab != .finance)

                SettingsView()
                    .opacity(selectedTab == .settings ? 1 : 0)
                    .allowsHitTesting(selectedTab == .settings)
                    .accessibilityHidden(selectedTab != .settings)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(PLATokens.Colors.canvas.ignoresSafeArea())
            .tint(PLATokens.Colors.accent)

            // Detached Floating Liquid Glass Bottom Dock (stays anchored behind keyboard while typing)
            VStack(spacing: PLATokens.Spacing.sm) {
                if let message = store.toastMessage {
                    ToastBannerView(
                        message: message,
                        undoTitle: store.toastUndoTitle,
                        onUndo: store.toastUndoTitle != nil ? { store.triggerToastUndo() } : nil
                    )
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }

                PLAFloatingGlassTabBar(selectedTab: $selectedTab)
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)

            // AC-12.3: Blur privacy cover in App Switcher whenever Finance tab is visible or finance lock is active
            if scenePhase != .active && selectedTab == .finance && store.settings.financeLockEnabled {
                privacyOverlay
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: store.toastMessage)
        .fullScreenCover(isPresented: Binding(
            get: { !store.settings.hasCompletedOnboarding },
            set: { _ in }
        )) {
            OnboardingView()
                .environment(store)
        }
        .sheet(item: $activeQuickAdd) { kind in
            switch kind {
            case .task:
                TaskFormSheet()
                    .environment(store)
            case .expense:
                TransactionFormSheet(initialType: .expense)
                    .environment(store)
            case .income:
                TransactionFormSheet(initialType: .income)
                    .environment(store)
            case .transfer:
                TransferFormSheet()
                    .environment(store)
            case .scanReceipt:
                ReceiptOCRReviewSheet()
                    .environment(store)
            case .whatIf:
                WhatIfSimulatorSheet()
                    .environment(store)
            }
        }
        .sheet(item: Binding(
            get: { store.pendingOCRReceipt },
            set: { store.pendingOCRReceipt = $0 }
        )) { draft in
            ReceiptOCRReviewSheet(initialDraft: draft)
                .environment(store)
        }
        .onChange(of: store.pendingTabNavigation) { _, tab in
            if let tab {
                selectedTab = tab
                store.pendingTabNavigation = nil
            }
        }
        .onChange(of: store.pendingQuickAddRoute) { _, route in
            if let route {
                activeQuickAdd = route
                store.pendingQuickAddRoute = nil
            }
        }
    }

    private var privacyOverlay: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            VStack(spacing: PLATokens.Spacing.md) {
                Image(systemName: "lock.shield.fill")
                    .font(.largeTitle)
                    .foregroundStyle(PLATokens.Colors.accent)
                Text("Keuangan Terlindungi")
                    .font(.headline)
                    .foregroundStyle(PLATokens.Colors.textPrimary)
                Text("Data finansial disembunyikan saat berpindah aplikasi.")
                    .font(.footnote)
                    .foregroundStyle(PLATokens.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(PLATokens.Spacing.xl)
        }
    }
}
