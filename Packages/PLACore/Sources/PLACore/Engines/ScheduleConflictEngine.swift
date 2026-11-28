import Foundation

/// Represents an occupied time block on a specific calendar day (from an active PLA task or Apple Calendar event).
public struct BusyTimeSlot: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let startMinutes: Int
    public let endMinutes: Int
    public let isCalendarEvent: Bool

    public init(
        id: String,
        title: String,
        startMinutes: Int,
        endMinutes: Int,
        isCalendarEvent: Bool = false
    ) {
        let clampedStart = min(max(startMinutes, 0), 1439)
        let clampedEnd = min(max(endMinutes, clampedStart + 1), 1440)
        self.id = id
        self.title = title
        self.startMinutes = clampedStart
        self.endMinutes = clampedEnd
        self.isCalendarEvent = isCalendarEvent
    }
}

/// Represents a continuous available time window on a day where a new activity can be scheduled.
public struct FreeTimeWindow: Identifiable, Hashable, Sendable {
    public var id: String { "\(startMinutes)-\(endMinutes)" }
    public let startMinutes: Int
    public let endMinutes: Int
    public var durationMinutes: Int { max(0, endMinutes - startMinutes) }

    public init(startMinutes: Int, endMinutes: Int) {
        self.startMinutes = min(max(startMinutes, 0), 1439)
        self.endMinutes = min(max(endMinutes, self.startMinutes), 1440)
    }
}

/// Deterministic conflict detection and free-slot recommendation output for a proposed date and time.
public struct ScheduleConflictReport: Equatable, Sendable {
    public let date: LocalDate
    public let requestedStartMinutes: Int
    public let requestedEndMinutes: Int
    public let conflictingSlots: [BusyTimeSlot]
    public let allBusySlots: [BusyTimeSlot]
    public let freeWindows: [FreeTimeWindow]
    public let suggestedStartMinutes: [Int]

    public var hasConflict: Bool { !conflictingSlots.isEmpty }
}

/// Pure offline schedule conflict detector and free-time slot advisor (zero network, 100% deterministic).
public enum ScheduleConflictEngine {
    public static let defaultTaskDurationMinutes: Int = 60

    public static func evaluate(
        date: LocalDate,
        startMinutes: Int,
        durationMinutes: Int = defaultTaskDurationMinutes,
        tasks: [PLATask],
        excludingTaskId: UUID? = nil,
        calendarBusySlots: [BusyTimeSlot] = [],
        dayStartMinutes: Int = 7 * 60,
        dayEndMinutes: Int = 22 * 60,
        now: LocalDateTime? = nil
    ) -> ScheduleConflictReport {
        let safeDuration = max(15, min(durationMinutes, 480))
        let reqStart = min(max(startMinutes, 0), 1439)
        let reqEnd = min(1440, reqStart + safeDuration)

        // 1. Gather all active timed tasks on `date` (excluding the task being edited, if any)
        var busy: [BusyTimeSlot] = tasks.compactMap { task in
            guard task.status == .active,
                  task.id != excludingTaskId,
                  task.dueDateLocal == date,
                  let mins = task.dueTimeMinutes else {
                return nil
            }
            return BusyTimeSlot(
                id: task.id.uuidString,
                title: task.title,
                startMinutes: mins,
                endMinutes: min(1440, mins + defaultTaskDurationMinutes),
                isCalendarEvent: false
            )
        }
        busy.append(contentsOf: calendarBusySlots)
        busy.sort {
            if $0.startMinutes != $1.startMinutes { return $0.startMinutes < $1.startMinutes }
            return $0.endMinutes < $1.endMinutes
        }

        // 2. Detect overlapping conflicts: [reqStart, reqEnd) overlaps [slot.start, slot.end)
        let conflicts = busy.filter { slot in
            reqStart < slot.endMinutes && slot.startMinutes < reqEnd
        }

        // 3. Determine effective free-search bounds (avoid suggesting past times if evaluating today)
        let baseStart = min(max(dayStartMinutes, 0), 1439)
        let baseEnd = max(baseStart, min(dayEndMinutes, 1440))
        let effectiveStart: Int
        if let now, now.date == date {
            effectiveStart = max(baseStart, roundUpToNextHalfHour(now.minutesFromMidnight))
        } else {
            effectiveStart = baseStart
        }

        // 4. Merge busy intervals clamped to [effectiveStart, baseEnd]
        let freeWindows = computeFreeWindows(
            busySlots: busy,
            dayStart: effectiveStart,
            dayEnd: baseEnd,
            minimumDuration: safeDuration
        )

        // 5. Pick up to 4 well-spaced suggested start times closest to `reqStart`
        let suggestions = pickSuggestedStartTimes(
            freeWindows: freeWindows,
            requestedStart: reqStart,
            duration: safeDuration,
            limit: 4
        )

        return ScheduleConflictReport(
            date: date,
            requestedStartMinutes: reqStart,
            requestedEndMinutes: reqEnd,
            conflictingSlots: conflicts,
            allBusySlots: busy,
            freeWindows: freeWindows,
            suggestedStartMinutes: suggestions
        )
    }

    private static func roundUpToNextHalfHour(_ minutes: Int) -> Int {
        let clamped = max(0, minutes)
        let remainder = clamped % 30
        if remainder == 0 { return min(1440, clamped + 30) }
        return min(1440, clamped + (30 - remainder))
    }

    private static func computeFreeWindows(
        busySlots: [BusyTimeSlot],
        dayStart: Int,
        dayEnd: Int,
        minimumDuration: Int
    ) -> [FreeTimeWindow] {
        guard dayEnd - dayStart >= minimumDuration else { return [] }

        var merged: [(Int, Int)] = []
        for slot in busySlots {
            let s = max(dayStart, slot.startMinutes)
            let e = min(dayEnd, slot.endMinutes)
            guard e > s else { continue }
            if let last = merged.last, s <= last.1 {
                merged[merged.count - 1].1 = max(last.1, e)
            } else {
                merged.append((s, e))
            }
        }

        var windows: [FreeTimeWindow] = []
        var cursor = dayStart
        for (bStart, bEnd) in merged {
            if bStart - cursor >= minimumDuration {
                windows.append(FreeTimeWindow(startMinutes: cursor, endMinutes: bStart))
            }
            cursor = max(cursor, bEnd)
        }
        if dayEnd - cursor >= minimumDuration {
            windows.append(FreeTimeWindow(startMinutes: cursor, endMinutes: dayEnd))
        }
        return windows
    }

    private static func pickSuggestedStartTimes(
        freeWindows: [FreeTimeWindow],
        requestedStart: Int,
        duration: Int,
        limit: Int
    ) -> [Int] {
        var candidates: [Int] = []
        for window in freeWindows {
            let firstSlot: Int
            if window.startMinutes % 30 == 0 {
                firstSlot = window.startMinutes
            } else {
                firstSlot = window.startMinutes + (30 - (window.startMinutes % 30))
            }
            var t = firstSlot
            while t + duration <= window.endMinutes {
                candidates.append(t)
                t += 30
            }
        }
        guard !candidates.isEmpty else { return [] }

        let ranked = candidates.sorted { lhs, rhs in
            let dl = abs(lhs - requestedStart)
            let dr = abs(rhs - requestedStart)
            if dl != dr { return dl < dr }
            // Slight preference for after the conflicting meeting when equidistant
            if (lhs >= requestedStart) != (rhs >= requestedStart) {
                return lhs >= requestedStart
            }
            return lhs < rhs
        }

        var selected: [Int] = []
        for candidate in ranked {
            if selected.allSatisfy({ abs($0 - candidate) >= 60 }) {
                selected.append(candidate)
                if selected.count >= limit { break }
            }
        }
        return selected.sorted()
    }
}
