import SwiftUI
import PLACore

/// Face ID / Touch ID + automatic Passcode fallback guard for the Finance tab (PRD F-12 / AC-12.1..12.3).
/// Only prompts automatically when `isActive` becomes true so keeping tabs mounted never triggers Face ID on Beranda launch.
struct FinanceGateView: View {
    @Environment(AppStore.self) private var store
    var isActive: Bool = true
    @State private var hasAutoPromptedThisVisit = false

    private var isLocked: Bool {
        store.settings.financeLockEnabled && !store.authService.isFinanceUnlocked
    }

    var body: some View {
        Group {
            if isLocked {
                NavigationStack {
                    VStack(spacing: PLATokens.Spacing.xl) {
                        Spacer()

                        PLACard(padding: PLATokens.Spacing.xl, cornerRadius: PLATokens.Radius.xl) {
                            VStack(spacing: PLATokens.Spacing.lg) {
                                ZStack {
                                    Circle()
                                        .fill(PLATokens.Colors.softBlueTint)
                                        .frame(width: 88, height: 88)
                                    Image(systemName: "lock.shield.fill")
                                        .font(.system(size: 40))
                                        .foregroundStyle(PLATokens.Colors.accent)
                                }
                                .accessibilityHidden(true)

                                VStack(spacing: PLATokens.Spacing.xs) {
                                    Text("Keuangan Terkunci")
                                        .font(.title3.weight(.bold))
                                        .foregroundStyle(PLATokens.Colors.textPrimary)
                                    Text("Autentikasi dengan \(store.authService.biometryDisplayName()) atau Passcode iPhone untuk melihat saldo, tagihan, dan transaksi Anda.")
                                        .font(.subheadline)
                                        .foregroundStyle(PLATokens.Colors.textSecondary)
                                        .multilineTextAlignment(.center)
                                }

                                if let err = store.authService.lastErrorMessage {
                                    Text(err)
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(PLATokens.Colors.danger)
                                        .multilineTextAlignment(.center)
                                }

                                PLAPrimaryPillButton(
                                    title: store.authService.lastErrorMessage == nil ? "Buka Keuangan" : "Coba Lagi",
                                    systemImage: "faceid",
                                    isDisabled: store.authService.isAuthenticating
                                ) {
                                    _Concurrency.Task {
                                        _ = await store.authService.unlockFinance()
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .padding(.horizontal, PLATokens.Spacing.lg)

                        Spacer()
                    }
                    .padding(.bottom, PLATokens.floatingDockClearance)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(PLATokens.Colors.canvas.ignoresSafeArea())
                    .toolbar(.hidden, for: .navigationBar)
                    .onAppear {
                        triggerAutoPromptIfNeeded()
                    }
                    .onChange(of: isActive) { _, active in
                        if active {
                            triggerAutoPromptIfNeeded()
                        } else {
                            hasAutoPromptedThisVisit = false
                        }
                    }
                }
            } else {
                FinanceView()
            }
        }
    }

    private func triggerAutoPromptIfNeeded() {
        guard isActive, isLocked, !hasAutoPromptedThisVisit else { return }
        hasAutoPromptedThisVisit = true
        _Concurrency.Task {
            _ = await store.authService.unlockFinance()
        }
    }
}
