import Foundation
import SwiftUI
import PLACore

/// User-selectable app theme preference supporting System, Light (White-Blue), and Dark (Midnight-Blue) modes.
enum AppAppearanceMode: Int, CaseIterable, Identifiable {
    case system = 0
    case light = 1
    case dark = 2

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .system: return "Otomatis"
        case .light: return "Terang"
        case .dark: return "Gelap"
        }
    }

    var iconName: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Lightweight UserDefaults persistence for `UserSettings`, appearance preference, and optional manual sideload refresh date fallback.
final class SettingsStore {
    private let defaults: UserDefaults
    private let settingsKey = "id.revand.pla.user_settings.v1"
    private let manualSideloadDateKey = "id.revand.pla.manual_sideload_refresh_date"
    private let appearanceModeKey = "id.revand.pla.appearance_mode.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadSettings() -> UserSettings {
        guard let data = defaults.data(forKey: settingsKey),
              let decoded = try? JSONDecoder().decode(UserSettings.self, from: data) else {
            return .default
        }
        return decoded
    }

    func saveSettings(_ settings: UserSettings) {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: settingsKey)
        }
    }

    func loadManualSideloadRefreshDate() -> LocalDate? {
        guard let raw = defaults.string(forKey: manualSideloadDateKey) else { return nil }
        return LocalDate(isoString: raw)
    }

    func saveManualSideloadRefreshDate(_ date: LocalDate?) {
        if let date {
            defaults.set(date.isoString, forKey: manualSideloadDateKey)
        } else {
            defaults.removeObject(forKey: manualSideloadDateKey)
        }
    }

    func loadAppearanceMode() -> AppAppearanceMode {
        let raw = defaults.integer(forKey: appearanceModeKey)
        return AppAppearanceMode(rawValue: raw) ?? .system
    }

    func saveAppearanceMode(_ mode: AppAppearanceMode) {
        defaults.set(mode.rawValue, forKey: appearanceModeKey)
    }
}
