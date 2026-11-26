import Foundation

public enum ScheduledNotificationKind: String, Codable, Hashable, Sendable {
    case sideloadExpiry = "SIDELOAD_EXPIRY"
    case morningDigest = "MORNING_DIGEST"
    case taskReminder = "TASK_REMINDER"
    case billReminder = "BILL_REMINDER"
    case queueRefillNudge = "QUEUE_REFILL_NUDGE"
}

public struct ScheduledNotificationItem: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let kind: ScheduledNotificationKind
    public let title: String
    public let body: String
    public let fireDateLocal: LocalDateTime
    public let soundName: String
    public let categoryIdentifier: String
    public let ownerId: UUID?

    public init(
        id: String,
        kind: ScheduledNotificationKind,
        title: String,
        body: String,
        fireDateLocal: LocalDateTime,
        soundName: String,
        categoryIdentifier: String,
        ownerId: UUID? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.body = body
        self.fireDateLocal = fireDateLocal
        self.soundName = soundName
        self.categoryIdentifier = categoryIdentifier
        self.ownerId = ownerId
    }
}

public struct NotificationQueuePlan: Equatable, Sendable {
    public let items: [ScheduledNotificationItem]
    public let totalCandidatesInHorizon: Int
    public let overflowGuardInserted: Bool

    public var count: Int { items.count }
}

/// Rolling 64-slot local notification planner (PRD §9.2):
/// 2 System (sideload H-2, H-1) + 7 Morning Digest + 55 Task/Bill reminders <= 64 hard limit.
public enum NotificationQueuePlanner {
    public static let maxTotalSlots = 64
    public static let maxSystemSlots = 2
    public static let maxDigestSlots = 7
    public static let maxReminderSlots = 55
    public static let horizonDays = 30

    public static func buildQueue(
        now: LocalDateTime,
        tasks: [PLATask],
        bills: [Bill],
        reminders: [Reminder],
        settings: UserSettings,
        sideloadExpiryDate: LocalDate? = nil
    ) -> NotificationQueuePlan {
        // 1. System slots (max 2): Sideload expiry H-2 and H-1 at 09:00
        let systemItems = buildSideloadExpiryItems(
            now: now,
            expiryDate: sideloadExpiryDate,
            soundName: settings.urgentTaskSound
        )

        // 2. Morning Digest slots (max 7): next 7 days with >= 1 active task or active bill due
        let digestItems = buildMorningDigestItems(
            now: now,
            tasks: tasks,
            bills: bills,
            settings: settings
        )

        // 3. Task & Bill reminder candidates within 30-day horizon
        let horizonEnd = LocalDateTime(date: now.date.addingDays(horizonDays), hour: 23, minute: 59)
        let taskMap = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        let billMap = Dictionary(uniqueKeysWithValues: bills.map { ($0.id, $0) })

        struct RankedCandidate {
            let item: ScheduledNotificationItem
            /// Higher rank wins ties at identical fireDate: High Task (3) > Bill (2) > Medium Task (1) > Low Task (0)
            let priorityRank: Int
        }

        var candidates: [RankedCandidate] = []
        var seenIds = Set<String>()

        for reminder in reminders where reminder.isEnabled {
            let fire: LocalDateTime
            if reminder.triggerType == .automatic {
                fire = ReminderPlanner.adjustForQuietHours(
                    reminder.fireDateLocal,
                    deadline: deadlineFor(reminder: reminder, taskMap: taskMap, billMap: billMap),
                    settings: settings
                )
            } else {
                fire = reminder.fireDateLocal
            }

            guard fire > now && fire <= horizonEnd else { continue }

            switch reminder.ownerType {
            case .task:
                guard let task = taskMap[reminder.ownerId], task.status == .active else { continue }
                let id = reminder.id.uuidString
                guard seenIds.insert(id).inserted else { continue }

                let rank: Int
                switch task.priority {
                case .high: rank = 3
                case .medium: rank = 1
                case .low: rank = 0
                }
                let item = ScheduledNotificationItem(
                    id: id,
                    kind: .taskReminder,
                    title: task.priority == .high ? "Tugas Prioritas Tinggi" : "Pengingat Tugas",
                    body: task.title,
                    fireDateLocal: fire,
                    soundName: reminder.soundName,
                    categoryIdentifier: "PLA_TASK_ACTION",
                    ownerId: task.id
                )
                candidates.append(RankedCandidate(item: item, priorityRank: rank))

            case .bill:
                guard let bill = billMap[reminder.ownerId], bill.isActive else { continue }
                let id = reminder.id.uuidString
                guard seenIds.insert(id).inserted else { continue }

                let title = bill.isTrial ? "Masa Trial Segera Berakhir" : "Pengingat Tagihan"
                let body = bill.isTrial
                    ? "Trial \(bill.name) berakhir \(bill.effectiveDueOrTrialEndDate.isoString) — batalkan sebelum terdebit otomatis."
                    : "\(bill.name) jatuh tempo \(bill.nextDueDateLocal.isoString)"
                let item = ScheduledNotificationItem(
                    id: id,
                    kind: .billReminder,
                    title: title,
                    body: body,
                    fireDateLocal: fire,
                    soundName: reminder.soundName,
                    categoryIdentifier: "PLA_BILL_ACTION",
                    ownerId: bill.id
                )
                candidates.append(RankedCandidate(item: item, priorityRank: bill.isTrial ? 3 : 2))
            }
        }

        // Sort ascending by fireDate, tie-break descending by priorityRank, then deterministic ID
        candidates.sort { lhs, rhs in
            if lhs.item.fireDateLocal != rhs.item.fireDateLocal {
                return lhs.item.fireDateLocal < rhs.item.fireDateLocal
            }
            if lhs.priorityRank != rhs.priorityRank {
                return lhs.priorityRank > rhs.priorityRank
            }
            return lhs.item.id < rhs.item.id
        }

        let totalCandidates = candidates.count
        var selectedReminders: [ScheduledNotificationItem]
        var overflowGuardInserted = false

        if candidates.count > maxReminderSlots {
            let fiftyFifthFire = candidates[maxReminderSlots - 1].item.fireDateLocal
            let sevenDaysOut = now.addingMinutes(7 * 1440)

            // PRD §9.2 overflow safety guard:
            // If slot #55 falls < 7 days from now, replace slot #55 with a refill nudge right before slot #54 ends.
            if fiftyFifthFire < sevenDaysOut {
                selectedReminders = Array(candidates.prefix(maxReminderSlots - 1)).map(\.item)
                let slot54Fire = selectedReminders.last?.fireDateLocal ?? fiftyFifthFire
                let nudgeFire = max(now.addingMinutes(1), slot54Fire.addingMinutes(-1))
                let nudge = ScheduledNotificationItem(
                    id: "pla-system-queue-refill",
                    kind: .queueRefillNudge,
                    title: "Muat Pengingat Berikutnya",
                    body: "Buka PLA untuk memuat pengingat berikutnya.",
                    fireDateLocal: nudgeFire,
                    soundName: settings.defaultTaskSound,
                    categoryIdentifier: "PLA_SYSTEM_ACTION",
                    ownerId: nil
                )
                selectedReminders.append(nudge)
                overflowGuardInserted = true
            } else {
                selectedReminders = Array(candidates.prefix(maxReminderSlots)).map(\.item)
            }
        } else {
            selectedReminders = candidates.map(\.item)
        }

        var combined: [ScheduledNotificationItem] = []
        combined.reserveCapacity(systemItems.count + digestItems.count + selectedReminders.count)
        combined.append(contentsOf: systemItems.prefix(maxSystemSlots))
        combined.append(contentsOf: digestItems.prefix(maxDigestSlots))
        combined.append(contentsOf: selectedReminders.prefix(maxReminderSlots))

        // Hard runtime invariant guarantee (SC-06)
        if combined.count > maxTotalSlots {
            combined = Array(combined.prefix(maxTotalSlots))
        }
        assert(combined.count <= maxTotalSlots, "NotificationQueuePlanner violated 64-notification hard limit!")

        return NotificationQueuePlan(
            items: combined,
            totalCandidatesInHorizon: totalCandidates,
            overflowGuardInserted: overflowGuardInserted
        )
    }

    private static func buildSideloadExpiryItems(
        now: LocalDateTime,
        expiryDate: LocalDate?,
        soundName: String
    ) -> [ScheduledNotificationItem] {
        guard let expiry = expiryDate else { return [] }
        var items: [ScheduledNotificationItem] = []

        for daysBefore in [2, 1] {
            let fire = LocalDateTime(date: expiry.addingDays(-daysBefore), hour: 9, minute: 0)
            guard fire > now else { continue }
            items.append(ScheduledNotificationItem(
                id: "pla-system-sideload-h\(daysBefore)-\(expiry.isoString)",
                kind: .sideloadExpiry,
                title: "Masa Berlaku Aplikasi Tinggal \(daysBefore) Hari",
                body: "Buka SideStore untuk memperpanjang PLA agar tidak kedaluwarsa.",
                fireDateLocal: fire,
                soundName: soundName,
                categoryIdentifier: "PLA_SYSTEM_ACTION",
                ownerId: nil
            ))
        }
        return Array(items.prefix(maxSystemSlots))
    }

    private static func buildMorningDigestItems(
        now: LocalDateTime,
        tasks: [PLATask],
        bills: [Bill],
        settings: UserSettings
    ) -> [ScheduledNotificationItem] {
        guard settings.morningDigestEnabled else { return [] }

        let activeTasks = tasks.filter { $0.status == .active }
        let activeBills = bills.filter { $0.isActive }

        var items: [ScheduledNotificationItem] = []
        for dayOffset in 0..<8 where items.count < maxDigestSlots {
            let targetDate = now.date.addingDays(dayOffset)
            let fire = LocalDateTime(date: targetDate, minutesFromMidnight: settings.morningDigestMinutes)
            guard fire > now else { continue }

            let taskCount = activeTasks.filter { $0.dueDateLocal == targetDate }.count
            let billCount = activeBills.filter { $0.nextDueDateLocal == targetDate }.count

            // AC-05.5: Do not send morning digest if 0 tasks and 0 bills for that day
            guard (taskCount + billCount) > 0 else { continue }

            let body = "Hari ini: \(taskCount) tugas, \(billCount) tagihan jatuh tempo."
            items.append(ScheduledNotificationItem(
                id: "pla-digest-\(targetDate.isoString)",
                kind: .morningDigest,
                title: "Ringkasan Pagi",
                body: body,
                fireDateLocal: fire,
                soundName: settings.digestSound,
                categoryIdentifier: "PLA_SYSTEM_ACTION",
                ownerId: nil
            ))
        }
        return items
    }

    private static func deadlineFor(
        reminder: Reminder,
        taskMap: [UUID: PLATask],
        billMap: [UUID: Bill]
    ) -> LocalDateTime? {
        switch reminder.ownerType {
        case .task:
            return taskMap[reminder.ownerId]?.dueDateTime
        case .bill:
            guard let due = billMap[reminder.ownerId]?.nextDueDateLocal else { return nil }
            return LocalDateTime(date: due, hour: 23, minute: 59)
        }
    }
}
