import Foundation
import PLACore

/// Diagnostic status of the App Group shared container (PRD V-07 verification probe).
struct PLAAppGroupStatus: Equatable, Sendable {
    let resolvedGroupId: String
    let resolutionSource: String
    let isContainerAccessible: Bool
    let lastWidgetSyncAt: Date?

    var summaryText: String {
        let accessText = isContainerAccessible ? "Tersedia" : "Tidak tersedia (fallback lokal)"
        return "\(resolvedGroupId) [\(resolutionSource)] — \(accessText)"
    }
}

/// Resolves the active App Group dynamically for both Xcode builds (`group.id.revand.pla`)
/// and SideStore/AltStore free Apple ID builds (which remap group IDs with a Team ID suffix via `ALTAppGroups` or `embedded.mobileprovision`).
/// Gracefully degrades when App Groups are unavailable so the app never crashes (PRD V-07 & R-07).
enum PLASharedContainer {
    static let defaultAppGroupId = "group.id.revand.pla"
    private static let widgetSnapshotFilename = "pla_widget_snapshot_v1.json"
    private static let pendingOCRDraftFilename = "pla_pending_ocr_draft_v1.json"
    private static let pendingOCRDefaultsKey = "id.revand.pla.pending_ocr_receipt_draft"
    private static let widgetSyncTimestampKey = "id.revand.pla.last_widget_sync_at"

    struct Resolution {
        let groupId: String
        let source: String
        let containerURL: URL?
    }

    static func resolve() -> Resolution {
        // 1. SideStore / AltStore remapped App Group IDs in Info.plist (`ALTAppGroups`)
        if let altGroups = Bundle.main.infoDictionary?["ALTAppGroups"] as? [String],
           let first = altGroups.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: first)
            return Resolution(groupId: first, source: "ALTAppGroups", containerURL: url)
        }

        // 2. Provisioning profile entitlements (`embedded.mobileprovision`) — works in main app & extensions
        if let profileGroup = readAppGroupFromEmbeddedProvisioningProfile() {
            let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: profileGroup)
            return Resolution(groupId: profileGroup, source: "embedded.mobileprovision", containerURL: url)
        }

        // 3. Default App Group ID (standard Xcode / paid team builds)
        let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: defaultAppGroupId)
        return Resolution(groupId: defaultAppGroupId, source: "default", containerURL: url)
    }

    static func status() -> PLAAppGroupStatus {
        let res = resolve()
        let defaults = UserDefaults(suiteName: res.groupId) ?? UserDefaults.standard
        let ts = defaults.double(forKey: widgetSyncTimestampKey)
        let lastSync = ts > 0 ? Date(timeIntervalSince1970: ts) : nil
        return PLAAppGroupStatus(
            resolvedGroupId: res.groupId,
            resolutionSource: res.source,
            isContainerAccessible: res.containerURL != nil,
            lastWidgetSyncAt: lastSync
        )
    }

    // MARK: - WidgetKit Snapshot (P-07)

    @discardableResult
    static func saveWidgetSnapshot(_ snapshot: PLAWidgetSnapshot) -> Bool {
        let res = resolve()
        guard let dir = res.containerURL else { return false }
        let fileURL = dir.appendingPathComponent(widgetSnapshotFilename)
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
            #if os(iOS)
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: fileURL.path
            )
            #endif
            if let suite = UserDefaults(suiteName: res.groupId) {
                suite.set(snapshot.generatedAt.timeIntervalSince1970, forKey: widgetSyncTimestampKey)
                suite.synchronize()
            }
            return true
        } catch {
            return false
        }
    }

    static func loadWidgetSnapshot() -> PLAWidgetSnapshot? {
        let res = resolve()
        guard let dir = res.containerURL else { return nil }
        let fileURL = dir.appendingPathComponent(widgetSnapshotFilename)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(PLAWidgetSnapshot.self, from: data)
    }

    // MARK: - Pending OCR Receipt Handoff (P-05 Intent + P-06 Share Extension — Text Only, Zero Image Bytes)

    @discardableResult
    static func savePendingOCRDraft(_ draft: SharedOCRReceiptPayload) -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(draft) else { return false }

        let res = resolve()
        var wroteShared = false
        if let dir = res.containerURL {
            let fileURL = dir.appendingPathComponent(pendingOCRDraftFilename)
            if (try? data.write(to: fileURL, options: .atomic)) != nil {
                wroteShared = true
            }
        }
        if let suite = UserDefaults(suiteName: res.groupId) {
            suite.set(data, forKey: pendingOCRDefaultsKey)
            suite.synchronize()
            wroteShared = true
        }
        UserDefaults.standard.set(data, forKey: pendingOCRDefaultsKey)
        return wroteShared
    }

    static func consumePendingOCRDraft() -> SharedOCRReceiptPayload? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let res = resolve()

        // 1. Check App Group file first (written by Share Extension)
        if let dir = res.containerURL {
            let fileURL = dir.appendingPathComponent(pendingOCRDraftFilename)
            if let data = try? Data(contentsOf: fileURL),
               let draft = try? decoder.decode(SharedOCRReceiptPayload.self, from: data) {
                try? FileManager.default.removeItem(at: fileURL)
                UserDefaults(suiteName: res.groupId)?.removeObject(forKey: pendingOCRDefaultsKey)
                UserDefaults.standard.removeObject(forKey: pendingOCRDefaultsKey)
                return draft
            }
        }

        // 2. Check App Group UserDefaults
        if let suite = UserDefaults(suiteName: res.groupId),
           let data = suite.data(forKey: pendingOCRDefaultsKey),
           let draft = try? decoder.decode(SharedOCRReceiptPayload.self, from: data) {
            suite.removeObject(forKey: pendingOCRDefaultsKey)
            suite.synchronize()
            UserDefaults.standard.removeObject(forKey: pendingOCRDefaultsKey)
            return draft
        }

        // 3. Fallback: standard UserDefaults (written by in-app ScanReceiptIntent)
        if let data = UserDefaults.standard.data(forKey: pendingOCRDefaultsKey) {
            UserDefaults.standard.removeObject(forKey: pendingOCRDefaultsKey)
            if let draft = try? decoder.decode(SharedOCRReceiptPayload.self, from: data) {
                return draft
            }
        }

        return nil
    }

    /// 1-tap V-07 diagnostic probe: tests write + read + delete inside the resolved App Group container.
    static func runAppGroupSelfTest() -> (ok: Bool, detail: String) {
        let res = resolve()
        guard let dir = res.containerURL else {
            return (
                false,
                "Container App Group '\(res.groupId)' (\(res.source)) tidak tersedia. Jika di SideStore akun gratis, gunakan opsi Shortcuts/URL scheme fallback."
            )
        }
        let probeURL = dir.appendingPathComponent("pla_v07_probe_\(UUID().uuidString).txt")
        let token = "PLA-V07-\(Int(Date().timeIntervalSince1970))"
        do {
            try Data(token.utf8).write(to: probeURL, options: .atomic)
            let readBack = try String(contentsOf: probeURL, encoding: .utf8)
            try? FileManager.default.removeItem(at: probeURL)
            if readBack == token {
                return (true, "LULUS V-07: tulis/baca App Group '\(res.groupId)' (\(res.source)) berhasil.")
            }
            return (false, "Isi file probe tidak cocok pada '\(res.groupId)'.")
        } catch {
            try? FileManager.default.removeItem(at: probeURL)
            return (false, "Gagal tulis/baca App Group '\(res.groupId)': \(error.localizedDescription)")
        }
    }

    // MARK: - Provisioning Profile XML Parser

    private static func readAppGroupFromEmbeddedProvisioningProfile() -> String? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let rawData = try? Data(contentsOf: url),
              let content = String(data: rawData, encoding: .isoLatin1),
              let startRange = content.range(of: "<plist"),
              let endRange = content.range(of: "</plist>") else {
            return nil
        }

        let plistString = String(content[startRange.lowerBound..<endRange.upperBound])
        guard let plistData = plistString.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any],
              let groups = entitlements["com.apple.security.application-groups"] as? [String] else {
            return nil
        }
        return groups.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }
}
