import Foundation
import LocalAuthentication
import SwiftUI
import PLACore

/// Handles Face ID / Touch ID authentication with automatic iPhone passcode fallback & auto-lock (PRD F-12 / AC-12.1..12.3).
@MainActor
@Observable
final class AuthService {
    var isFinanceUnlocked: Bool = false
    var isAuthenticating: Bool = false
    var lastErrorMessage: String?

    private var lastBackgroundedAt: Date?

    func unlockFinance(reason: String = "Buka halaman Keuangan Personal Life Assistant") async -> Bool {
        guard !isAuthenticating else { return isFinanceUnlocked }
        isAuthenticating = true
        lastErrorMessage = nil
        defer { isAuthenticating = false }

        let context = LAContext()
        context.localizedFallbackTitle = "Gunakan Passcode"

        var authError: NSError?
        // LAPolicy.deviceOwnerAuthentication automatically falls back to iPhone passcode (AC-12.2)
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) else {
            // If device has neither biometrics nor passcode configured, allow access with note
            lastErrorMessage = authError?.localizedDescription
            isFinanceUnlocked = true
            return true
        }

        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            isFinanceUnlocked = success
            if !success {
                lastErrorMessage = "Autentikasi dibatalkan."
            }
            return success
        } catch {
            isFinanceUnlocked = false
            lastErrorMessage = "Autentikasi gagal atau dibatalkan. Ketuk Coba Lagi."
            return false
        }
    }

    func lockImmediately() {
        isFinanceUnlocked = false
    }

    func handleScenePhaseChange(_ phase: ScenePhase, settings: UserSettings) {
        guard settings.financeLockEnabled else {
            isFinanceUnlocked = true
            return
        }

        switch phase {
        case .background:
            lastBackgroundedAt = Date()
            if settings.autoLockTimeout == .immediate {
                isFinanceUnlocked = false
            }
        case .active:
            if let bgTime = lastBackgroundedAt {
                let elapsed = Date().timeIntervalSince(bgTime)
                if elapsed >= Double(settings.autoLockTimeout.rawValue) {
                    isFinanceUnlocked = false
                }
                lastBackgroundedAt = nil
            }
        case .inactive:
            break
        @unknown default:
            break
        }
    }

    func biometryDisplayName() -> String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Passcode"
        }
    }
}
