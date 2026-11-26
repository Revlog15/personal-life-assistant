import SwiftUI
import PLACore

/// Face ID / Touch ID + automatic Passcode fallback guard for the Finance tab (PRD F-12 / AC-12.1..12.3).
struct FinanceGateView: View {
    @Environment(AppStore.self) private var store
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

                        ZStack {
                            Circle()
                                .fill(PLATokens.Colors.accent.opacity(0.14))
                                .frame(width: 112, height: 112)
                            Image(systemName: "lock.shield.fill")
                                .font(.system(size: 50))
                                .foregroundStyle(PLATokens.Colors.accent)
                        }
                        .accessibilityHidden(true)

                        VStack(spacing: PLATokens.Spacing.sm) {
                            Text("Keuangan Terkunci")
                                .font(.title2.weight(.bold))
                            Text("Autentikasi dengan \(store.authService.biometryDisplayName()) atau Passcode iPhone untuk melihat saldo, tagihan, dan transaksi Anda.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, PLATokens.Spacing.xl)
                        }

                        if let err = store.authService.lastErrorMessage {
                            Text(err)
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(PLATokens.Colors.danger)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, PLATokens.Spacing.xl)
                        }

                        Button {
                            _Concurrency.Task {
                                _ = await store.authService.unlockFinance()
                            }
                        } label: {
                            Label(
                                store.authService.lastErrorMessage == nil ? "Buka Keuangan" : "Coba Lagi",
                                systemImage: "faceid"
                            )
                            .font(.headline)
                            .frame(maxWidth: 260, minHeight: PLATokens.minTouchTarget)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(PLATokens.Colors.accent)
                        .disabled(store.authService.isAuthenticating)

                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(PLATokens.Colors.canvas)
                    .navigationTitle("Keuangan")
                    .onAppear {
                        if !hasAutoPromptedThisVisit {
                            hasAutoPromptedThisVisit = true
                            _Concurrency.Task {
                                _ = await store.authService.unlockFinance()
                            }
                        }
                    }
                    .onDisappear {
                        hasAutoPromptedThisVisit = false
                    }
                }
            } else {
                FinanceView()
            }
        }
    }
}
