import Foundation

/// Generates automatic Smart Reminders for Tasks and Bills with Quiet Hours and anti-spam rules (PRD §9.4 & F-03).
public enum ReminderPlanner {
    /// Generates automatic reminders for a single task according to its priority, deadline, and user preferences.
    public static func planTaskReminders(
        for task: PLATask,
        now: LocalDateTime,
        settings: UserSettings
    ) -> [Reminder] {
        guard task.status == .active, let dueDate = task.dueDateLocal else {
            return []
        }

        let prefs = settings.reminderPreferences
        let sound = task.priority == .high ? settings.urgentTaskSound : settings.defaultTaskSound
        let deadlineDateTime = LocalDateTime(
            date: dueDate,
            minutesFromMidnight: task.dueTimeMinutes ?? (23 * 60 + 59)
        )

        struct RawSlot {
            let fire: LocalDateTime
            let offsetMinutes: Int
            let isDeadlineProximity: Bool
        }

        var rawSlots: [RawSlot] = []

        switch task.priority {
        case .high:
            if prefs.highEnableH7 {
                rawSlots.append(RawSlot(
                    fire: LocalDateTime(date: dueDate.addingDays(-7), hour: 9, minute: 0),
                    offsetMinutes: -7 * 1440,
                    isDeadlineProximity: false
                ))
            }
            if prefs.highEnableH3 {
                rawSlots.append(RawSlot(
                    fire: LocalDateTime(date: dueDate.addingDays(-3), hour: 9, minute: 0),
                    offsetMinutes: -3 * 1440,
                    isDeadlineProximity: false
                ))
            }
            if prefs.highEnableH1 {
                rawSlots.append(RawSlot(
                    fire: LocalDateTime(date: dueDate.addingDays(-1), hour: 9, minute: 0),
                    offsetMinutes: -1440,
                    isDeadlineProximity: false
                ))
            }
            if prefs.highEnableDayOf {
                rawSlots.append(RawSlot(
                    fire: LocalDateTime(date: dueDate, hour: 8, minute: 0),
                    offsetMinutes: 0,
                    isDeadlineProximity: false
                ))
            }
            if prefs.highEnableTwoHoursBefore, let dueMinutes = task.dueTimeMinutes {
                let twoHoursBefore = LocalDateTime(date: dueDate, minutesFromMidnight: dueMinutes).addingMinutes(-120)
                rawSlots.append(RawSlot(
                    fire: twoHoursBefore,
                    offsetMinutes: -120,
                    isDeadlineProximity: true
                ))
            }

        case .medium:
            if prefs.mediumEnableH3 {
                rawSlots.append(RawSlot(
                    fire: LocalDateTime(date: dueDate.addingDays(-3), hour: 9, minute: 0),
                    offsetMinutes: -3 * 1440,
                    isDeadlineProximity: false
                ))
            }
            if prefs.mediumEnableH1 {
                rawSlots.append(RawSlot(
                    fire: LocalDateTime(date: dueDate.addingDays(-1), hour: 9, minute: 0),
                    offsetMinutes: -1440,
                    isDeadlineProximity: false
                ))
            }
            if prefs.mediumEnableDayOf {
                rawSlots.append(RawSlot(
                    fire: LocalDateTime(date: dueDate, hour: 8, minute: 0),
                    offsetMinutes: 0,
                    isDeadlineProximity: false
                ))
            }

        case .low:
            if prefs.lowEnableDayOf {
                rawSlots.append(RawSlot(
                    fire: LocalDateTime(date: dueDate, hour: 9, minute: 0),
                    offsetMinutes: 0,
                    isDeadlineProximity: false
                ))
            }
        }

        // Apply quiet hours adjustment, filter past reminders, deduplicate, and enforce anti-spam
        var adjusted: [(fire: LocalDateTime, offset: Int, isDayOfHighProximity: Bool)] = []
        for slot in rawSlots {
            let shifted = adjustForQuietHours(
                slot.fire,
                deadline: deadlineDateTime,
                settings: settings
            )
            // AC-03.2: Drop reminders in the past (or after an explicit due time)
            guard shifted > now else { continue }
            if task.dueTimeMinutes != nil && shifted > deadlineDateTime {
                continue
            }
            adjusted.append((shifted, slot.offsetMinutes, task.priority == .high && slot.isDeadlineProximity))
        }

        // Sort chronologically
        adjusted.sort { lhs, rhs in
            if lhs.fire != rhs.fire { return lhs.fire < rhs.fire }
            // Keep closer offset (e.g., -120 over 0) if identical timestamp
            return abs(lhs.offset) < abs(rhs.offset)
        }

        // Deduplicate identical timestamps (AC-03.3) and enforce anti-spam (§9.4):
        // max 1 automatic notification per task per day, except High priority on Hari H.
        var results: [Reminder] = []
        var seenExactTimes = Set<LocalDateTime>()
        var seenDays = Set<LocalDate>()

        for item in adjusted {
            if seenExactTimes.contains(item.fire) {
                continue
            }
            let allowSecondOnDayH = (task.priority == .high && item.fire.date == dueDate && item.isDayOfHighProximity)
            if seenDays.contains(item.fire.date) && !allowSecondOnDayH {
                continue
            }
            seenExactTimes.insert(item.fire)
            seenDays.insert(item.fire.date)
            results.append(Reminder(
                id: deterministicReminderID(ownerId: task.id, salt: "task-\(item.fire.isoString)"),
                ownerType: .task,
                ownerId: task.id,
                triggerType: .automatic,
                offsetMinutes: item.offset,
                fireDateLocal: item.fire,
                soundName: sound,
                isEnabled: true
            ))
        }

        return results
    }

    /// Generates automatic reminders for an active recurring Bill (H-3 09:00, H-1 09:00, Hari H 08:00).
    public static func planBillReminders(
        for bill: Bill,
        now: LocalDateTime,
        settings: UserSettings
    ) -> [Reminder] {
        guard bill.isActive else { return [] }
        let prefs = settings.reminderPreferences
        let due = bill.nextDueDateLocal
        let deadline = LocalDateTime(date: due, hour: 23, minute: 59)

        var raw: [(LocalDateTime, Int)] = []
        if prefs.billEnableH3 {
            raw.append((LocalDateTime(date: due.addingDays(-3), hour: 9, minute: 0), -3 * 1440))
        }
        if prefs.billEnableH1 {
            raw.append((LocalDateTime(date: due.addingDays(-1), hour: 9, minute: 0), -1440))
        }
        if prefs.billEnableDayOf {
            raw.append((LocalDateTime(date: due, hour: 8, minute: 0), 0))
        }

        var results: [Reminder] = []
        var seenDates = Set<LocalDate>()
        for (fire, offset) in raw {
            let shifted = adjustForQuietHours(fire, deadline: deadline, settings: settings)
            guard shifted > now else { continue }
            guard !seenDates.contains(shifted.date) else { continue }
            seenDates.insert(shifted.date)
            results.append(Reminder(
                id: deterministicReminderID(ownerId: bill.id, salt: "bill-\(shifted.isoString)"),
                ownerType: .bill,
                ownerId: bill.id,
                triggerType: .automatic,
                offsetMinutes: offset,
                fireDateLocal: shifted,
                soundName: settings.billSound,
                isEnabled: true
            ))
        }
        return results
    }

    /// Shifts an automatic reminder outside Quiet Hours (default 22:00 - 07:00).
    /// Manual user-picked reminders should NOT pass through this shift (PRD §9.4).
    public static func adjustForQuietHours(
        _ fire: LocalDateTime,
        deadline: LocalDateTime?,
        settings: UserSettings
    ) -> LocalDateTime {
        guard settings.quietHoursEnabled else { return fire }
        let start = settings.quietStartMinutes
        let end = settings.quietEndMinutes
        guard start != end else { return fire }

        let m = fire.minutesFromMidnight
        let isQuiet: Bool
        let nextWake: LocalDateTime
        let beforeQuiet: LocalDateTime

        if start > end {
            // Overnight window, e.g. 22:00 (1320) -> 07:00 (420)
            isQuiet = (m >= start) || (m < end)
            if m >= start {
                nextWake = LocalDateTime(date: fire.date.addingDays(1), minutesFromMidnight: end)
                beforeQuiet = LocalDateTime(date: fire.date, minutesFromMidnight: max(0, start - 5))
            } else {
                nextWake = LocalDateTime(date: fire.date, minutesFromMidnight: end)
                beforeQuiet = LocalDateTime(date: fire.date.addingDays(-1), minutesFromMidnight: max(0, start - 5))
            }
        } else {
            // Same-day window, e.g. 13:00 -> 15:00
            isQuiet = (m >= start) && (m < end)
            nextWake = LocalDateTime(date: fire.date, minutesFromMidnight: end)
            beforeQuiet = LocalDateTime(date: fire.date, minutesFromMidnight: max(0, start - 5))
        }

        guard isQuiet else { return fire }

        // If waking after quiet hours would land past the deadline, shift to 5 mins before quiet hours start (e.g. 21:55)
        if let dl = deadline, nextWake > dl {
            return beforeQuiet
        }
        return nextWake
    }

    /// Stable UUID derived from SHA-256 so repeated refills produce matching identifiers for UNUserNotificationCenter diffing.
    internal static func deterministicReminderID(ownerId: UUID, salt: String) -> UUID {
        let hashBytes = SHA256.digestBytes(Data("\(ownerId.uuidString)|\(salt)".utf8))
        var b = hashBytes
        // Mark as RFC 4122 version 5 style deterministic UUID
        b[6] = (b[6] & 0x0F) | 0x50
        b[8] = (b[8] & 0x3F) | 0x80
        return UUID(uuid: (
            b[0], b[1], b[2], b[3],
            b[4], b[5], b[6], b[7],
            b[8], b[9], b[10], b[11],
            b[12], b[13], b[14], b[15]
        ))
    }
}
