import Foundation
import PLACore

/// Lightweight UserDefaults persistence for `UserSettings` and optional manual sideload refresh date fallback.
final class SettingsStore {
    private let defaults: UserDefaults
    private let settingsKey = "id.revand.pla.user_settings.v1"
    private let manualSideloadDateKey = "id.revand.pla.manual_sideload_refresh_date"

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
}
