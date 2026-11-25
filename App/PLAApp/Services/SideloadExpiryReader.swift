import Foundation
import PLACore

enum SideloadExpirySource: Equatable {
    case provisioningProfile
    case manualFallback
    case unreadable
}

struct SideloadExpiryInfo: Equatable {
    let expirationDate: LocalDate?
    let source: SideloadExpirySource
    let teamIdentifier: String?

    func daysRemaining(from today: LocalDate) -> Int? {
        guard let exp = expirationDate else { return nil }
        return today.days(until: exp)
    }

    func shouldShowBanner(on today: LocalDate) -> Bool {
        guard let remaining = daysRemaining(from: today) else { return false }
        return remaining <= 2
    }

    func summaryText(today: LocalDate) -> String {
        guard let exp = expirationDate, let remaining = daysRemaining(from: today) else {
            return "Tidak terbaca"
        }
        let dateStr = PLAFormatters.fullDate(exp)
        if remaining < 0 {
            return "Kedaluwarsa sejak \(dateStr)"
        } else if remaining == 0 {
            return "Berlaku sampai hari ini (\(dateStr))"
        } else {
            return "Berlaku sampai \(dateStr) (\(remaining) hari lagi)"
        }
    }
}

/// Reads `embedded.mobileprovision` signed by SideStore to inspect 7-day ExpirationDate (PRD F-14, V-16).
enum SideloadExpiryReader {
    static func read(
        manualRefreshDate: LocalDate?,
        timeZone: TimeZone = .current
    ) -> SideloadExpiryInfo {
        if let profileURL = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
           let data = try? Data(contentsOf: profileURL),
           let parsed = parseProvisioningPlist(from: data, timeZone: timeZone) {
            return parsed
        }

        // V-16 fallback: if embedded.mobileprovision is unavailable, use user's recorded install/refresh date + 7 days
        if let manualRefresh = manualRefreshDate {
            return SideloadExpiryInfo(
                expirationDate: manualRefresh.addingDays(7),
                source: .manualFallback,
                teamIdentifier: nil
            )
        }

        return SideloadExpiryInfo(expirationDate: nil, source: .unreadable, teamIdentifier: nil)
    }

    private static func parseProvisioningPlist(from data: Data, timeZone: TimeZone) -> SideloadExpiryInfo? {
        guard let startRange = data.range(of: Data("<?xml".utf8)),
              let endRange = data.range(of: Data("</plist>".utf8), in: startRange.lowerBound..<data.endIndex) else {
            return nil
        }

        let plistData = data.subdata(in: startRange.lowerBound..<endRange.upperBound)
        guard let plistObj = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil),
              let dict = plistObj as? [String: Any],
              let expirationDate = dict["ExpirationDate"] as? Date else {
            return nil
        }

        let teamIds = dict["TeamIdentifier"] as? [String]
        let localExpiry = LocalDate.from(date: expirationDate, timeZone: timeZone)
        return SideloadExpiryInfo(
            expirationDate: localExpiry,
            source: .provisioningProfile,
            teamIdentifier: teamIds?.first
        )
    }
}
