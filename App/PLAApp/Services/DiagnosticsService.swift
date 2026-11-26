import Foundation
import UIKit
import os
import PLACore

/// Collects sanitized technical diagnostics, cold-start timing (`os_signpost`), BG refresh logs, and notification drift (F-14, SC-05, SC-07).
final class DiagnosticsService {
    struct LogEntry: Identifiable, Hashable {
        let id = UUID()
        let timestamp: Date
        let level: String
        let category: String
        let message: String
    }

    private let lock = NSLock()
    private let signpostLog = OSLog(subsystem: "id.revand.pla", category: "Performance")
    private let launchStartTime: CFAbsoluteTime
    private var coldStartDurationMs: Double?
    private var entries: [LogEntry] = []
    private let maxEntries = 50
    private let defaults = UserDefaults.standard

    private let lastBGRefreshKey = "id.revand.pla.diag.last_bg_refresh"
    private let driftSamplesKey = "id.revand.pla.diag.notif_drift_samples"

    init() {
        self.launchStartTime = CFAbsoluteTimeGetCurrent()
        os_signpost(.begin, log: signpostLog, name: "ColdStart")
    }

    func markDashboardInteractive() {
        lock.lock()
        defer { lock.unlock() }
        guard coldStartDurationMs == nil else { return }
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - launchStartTime) * 1000.0
        coldStartDurationMs = elapsedMs
        os_signpost(.end, log: signpostLog, name: "ColdStart", "%.1f ms", elapsedMs)
        appendLocked(level: "INFO", category: "Launch", message: "Cold start selesai dalam \(String(format: "%.0f", elapsedMs)) ms")
    }

    var lastColdStartMs: Double? {
        lock.lock()
        defer { lock.unlock() }
        return coldStartDurationMs
    }

    func log(level: String = "INFO", category: String, message: String) {
        lock.lock()
        defer { lock.unlock() }
        appendLocked(level: level, category: category, message: message)
    }

    func recentEntries(limit: Int = 20) -> [LogEntry] {
        lock.lock()
        defer { lock.unlock() }
        return Array(entries.suffix(limit))
    }

    func recordBackgroundRefreshRun(at date: Date = Date()) {
        defaults.set(date.timeIntervalSince1970, forKey: lastBGRefreshKey)
        log(category: "BGTask", message: "BGAppRefreshTask selesai men-sinkronkan antrean")
    }

    var lastBackgroundRefreshDate: Date? {
        let ts = defaults.double(forKey: lastBGRefreshKey)
        return ts > 0 ? Date(timeIntervalSince1970: ts) : nil
    }

    /// Records delivery drift in seconds for SC-05 soak test verification.
    func recordNotificationDeliveryDrift(scheduledTimestamp: TimeInterval, deliveredDate: Date) {
        let driftSec = deliveredDate.timeIntervalSince1970 - scheduledTimestamp
        var samples = defaults.array(forKey: driftSamplesKey) as? [Double] ?? []
        samples.append(driftSec)
        if samples.count > 120 {
            samples = Array(samples.suffix(120))
        }
        defaults.set(samples, forKey: driftSamplesKey)
        log(category: "NotifDrift", message: "Selisih kirim notifikasi: \(String(format: "%.1f", driftSec)) detik")
    }

    var notificationDriftSummary: (count: Int, withinOneMinutePct: Double) {
        let samples = defaults.array(forKey: driftSamplesKey) as? [Double] ?? []
        guard !samples.isEmpty else { return (0, 100.0) }
        let ok = samples.filter { abs($0) <= 60.0 }.count
        return (samples.count, (Double(ok) / Double(samples.count)) * 100.0)
    }

    /// Builds privacy-safe diagnostic report (AC-14.3: zero money amounts, zero task titles, zero personal notes).
    @MainActor
    func buildSanitizedBundle(
        pendingNotifications: Int,
        sideloadStatusText: String,
        databaseReady: Bool,
        appGroupSummary: String = PLASharedContainer.status().summaryText
    ) -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        let device = UIDevice.current
        let coldStartText = lastColdStartMs.map { String(format: "%.0f ms", $0) } ?? "belum diukur"
        let bgText: String
        if let bg = lastBackgroundRefreshDate {
            let formatter = ISO8601DateFormatter()
            bgText = formatter.string(from: bg)
        } else {
            bgText = "belum pernah jalan"
        }
        let drift = notificationDriftSummary
        let recent = recentEntries(limit: 20)

        var lines: [String] = [
            "=== PAKET DIAGNOSTIK PLA (BEBAS DATA PRIBADI) ===",
            "Versi App: \(version) (Build \(build))",
            "Perangkat: \(device.model) | iOS \(device.systemVersion)",
            "Database: \(databaseReady ? "OK" : "ERROR")",
            "App Group (V-07): \(appGroupSummary)",
            "Cold Start Terakhir: \(coldStartText)",
            "Pending Notifikasi: \(pendingNotifications) / 64",
            "Soak Drift Notifikasi: \(drift.count) sampel (\(String(format: "%.1f", drift.withinOneMinutePct))% dalam ±60 dtk)",
            "BGAppRefresh Terakhir: \(bgText)",
            "Sertifikat Sideload: \(sideloadStatusText)",
            "--- 20 Log Teknis Terakhir ---"
        ]

        if recent.isEmpty {
            lines.append("(tidak ada log error)")
        } else {
            let iso = ISO8601DateFormatter()
            for entry in recent {
                lines.append("[\(iso.string(from: entry.timestamp))] [\(entry.level)] [\(entry.category)] \(entry.message)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func appendLocked(level: String, category: String, message: String) {
        entries.append(LogEntry(timestamp: Date(), level: level, category: category, message: message))
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }
}
