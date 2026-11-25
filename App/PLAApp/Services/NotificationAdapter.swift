import Foundation
import UserNotifications
import AVFoundation
import UIKit
import PLACore

enum NotificationActionID {
    static let taskCategory = "PLA_TASK_ACTION"
    static let billCategory = "PLA_BILL_ACTION"
    static let systemCategory = "PLA_SYSTEM_ACTION"

    static let markTaskDone = "PLA_ACTION_MARK_TASK_DONE"
    static let snoozeOneHour = "PLA_ACTION_SNOOZE_1H"
    static let markBillPaid = "PLA_ACTION_MARK_BILL_PAID"
}

enum NotificationActionEvent: Sendable {
    case completeTask(UUID)
    case snoozeTaskOneHour(UUID)
    case markBillPaid(UUID)
}

/// Bridges `NotificationQueuePlan` (<= 64 slots) to `UNUserNotificationCenter`, custom `.caf` sounds, and lock-screen actions (PRD §9).
final class NotificationAdapter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    private let center = UNUserNotificationCenter.current()
    private let diagnostics: DiagnosticsService
    private var audioPlayer: AVAudioPlayer?
    var onActionReceived: (@MainActor (NotificationActionEvent) -> Void)?

    init(diagnostics: DiagnosticsService) {
        self.diagnostics = diagnostics
        super.init()
        center.delegate = self
        registerCategories()
    }

    private func registerCategories() {
        let completeAction = UNNotificationAction(
            identifier: NotificationActionID.markTaskDone,
            title: "Tandai Selesai",
            options: []
        )
        let snoozeAction = UNNotificationAction(
            identifier: NotificationActionID.snoozeOneHour,
            title: "Tunda 1 Jam",
            options: []
        )
        let billPaidAction = UNNotificationAction(
            identifier: NotificationActionID.markBillPaid,
            title: "Tandai Lunas",
            options: []
        )

        let taskCat = UNNotificationCategory(
            identifier: NotificationActionID.taskCategory,
            actions: [completeAction, snoozeAction],
            intentIdentifiers: [],
            options: []
        )
        let billCat = UNNotificationCategory(
            identifier: NotificationActionID.billCategory,
            actions: [billPaidAction],
            intentIdentifiers: [],
            options: []
        )
        let sysCat = UNNotificationCategory(
            identifier: NotificationActionID.systemCategory,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([taskCat, billCat, sysCat])
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus
    }

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            diagnostics.log(category: "NotifAuth", message: "Izin notifikasi: \(granted ? "diizinkan" : "ditolak")")
            return granted
        } catch {
            diagnostics.log(level: "ERROR", category: "NotifAuth", message: "Gagal meminta izin notifikasi: \(error.localizedDescription)")
            return false
        }
    }

    @MainActor
    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// Diffs desired rolling queue (<= 64) against pending iOS requests and synchronizes cleanly.
    func syncQueue(plan: NotificationQueuePlan, timeZone: TimeZone) async -> Int {
        assert(plan.count <= NotificationQueuePlanner.maxTotalSlots, "Queue exceeded iOS 64 limit")

        let status = await authorizationStatus()
        guard status == .authorized || status == .provisional else {
            return 0
        }

        let pending = await center.pendingNotificationRequests()
        let desiredMap = Dictionary(uniqueKeysWithValues: plan.items.map { ($0.id, $0) })

        // Remove stale or changed pending requests
        var idsToRemove: [String] = []
        var unchangedIds = Set<String>()

        for req in pending {
            if let target = desiredMap[req.identifier] {
                let existingFire = req.content.userInfo["fireISO"] as? String
                let existingTitle = req.content.title
                let existingBody = req.content.body
                if existingFire == target.fireDateLocal.isoString &&
                    existingTitle == target.title &&
                    existingBody == target.body {
                    unchangedIds.insert(req.identifier)
                } else {
                    idsToRemove.append(req.identifier)
                }
            } else {
                idsToRemove.append(req.identifier)
            }
        }

        if !idsToRemove.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: idsToRemove)
        }

        // Schedule new or updated items (guaranteed total <= 64)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        for item in plan.items where !unchangedIds.contains(item.id) {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.categoryIdentifier = item.categoryIdentifier
            // PRD §9.5 & V-10: Use standard .active interruptionLevel for free Apple ID signing compatibility
            content.interruptionLevel = .active

            if item.soundName == ReminderSound.none.rawValue {
                content.sound = nil
            } else if item.soundName == ReminderSound.systemDefault.rawValue {
                content.sound = .default
            } else {
                content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: item.soundName))
            }

            let fireDate = item.fireDateLocal.toDate(timeZone: timeZone)
            var userInfo: [String: Any] = [
                "kind": item.kind.rawValue,
                "fireISO": item.fireDateLocal.isoString,
                "scheduledTimestamp": fireDate.timeIntervalSince1970
            ]
            if let ownerId = item.ownerId {
                userInfo["ownerId"] = ownerId.uuidString
            }
            content.userInfo = userInfo

            var comps = DateComponents()
            comps.calendar = calendar
            comps.timeZone = timeZone
            comps.year = item.fireDateLocal.date.year
            comps.month = item.fireDateLocal.date.month
            comps.day = item.fireDateLocal.date.day
            comps.hour = item.fireDateLocal.hour
            comps.minute = item.fireDateLocal.minute
            comps.second = 0

            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(identifier: item.id, content: content, trigger: trigger)

            do {
                try await center.add(request)
            } catch {
                diagnostics.log(level: "ERROR", category: "NotifSync", message: "Gagal menjadwalkan slot: \(error.localizedDescription)")
            }
        }

        let finalPending = await center.pendingNotificationRequests().count
        diagnostics.log(category: "NotifSync", message: "Antrean sinkron: \(finalPending)/64 pending (kandidat horizon: \(plan.totalCandidatesInHorizon))")
        return finalPending
    }

    /// Plays a short preview of a bundled `.caf` notification sound inside Pengaturan.
    func playPreviewSound(named soundName: String) {
        guard soundName != ReminderSound.none.rawValue,
              soundName != ReminderSound.systemDefault.rawValue else {
            return
        }
        let stem = (soundName as NSString).deletingPathExtension
        let ext = (soundName as NSString).pathExtension
        guard let url = Bundle.main.url(forResource: stem, withExtension: ext.isEmpty ? "caf" : ext) else {
            diagnostics.log(level: "WARN", category: "Audio", message: "File suara tidak ditemukan: \(soundName)")
            return
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            player.play()
            self.audioPlayer = player
        } catch {
            diagnostics.log(level: "ERROR", category: "Audio", message: "Gagal memutar pratinjau suara: \(error.localizedDescription)")
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        if let scheduledTs = notification.request.content.userInfo["scheduledTimestamp"] as? TimeInterval {
            diagnostics.recordNotificationDeliveryDrift(scheduledTimestamp: scheduledTs, deliveredDate: notification.date)
        }
        return [.banner, .sound, .list]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        if let scheduledTs = userInfo["scheduledTimestamp"] as? TimeInterval {
            diagnostics.recordNotificationDeliveryDrift(scheduledTimestamp: scheduledTs, deliveredDate: response.notification.date)
        }

        guard let ownerRaw = userInfo["ownerId"] as? String,
              let ownerId = UUID(uuidString: ownerRaw) else {
            return
        }

        let event: NotificationActionEvent?
        switch response.actionIdentifier {
        case NotificationActionID.markTaskDone:
            event = .completeTask(ownerId)
        case NotificationActionID.snoozeOneHour:
            event = .snoozeTaskOneHour(ownerId)
        case NotificationActionID.markBillPaid:
            event = .markBillPaid(ownerId)
        default:
            event = nil
        }

        if let event {
            let handler = self.onActionReceived
            await MainActor.run {
                handler?(event)
            }
        }
    }
}
