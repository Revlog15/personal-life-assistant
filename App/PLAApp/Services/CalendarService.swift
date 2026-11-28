import Foundation
import EventKit
import PLACore

/// Optional read-only EventKit adapter for P-08 Smart Rescheduling (R-PER-03 daily calendar load).
@MainActor
@Observable
final class CalendarService {
    private let eventStore = EKEventStore()
    var authorizationStatus: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)

    var isAuthorizedForRead: Bool {
        authorizationStatus == .fullAccess
    }

    func refreshStatus() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
    }

    func requestReadAccess() async -> Bool {
        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            refreshStatus()
            return granted
        } catch {
            refreshStatus()
            return false
        }
    }

    /// Counts calendar events per day across [today + 1 ... today + 7] without modifying any calendar data.
    func eventCountsForNext7Days(from today: LocalDate, timeZone: TimeZone) -> [LocalDate: Int] {
        refreshStatus()
        guard isAuthorizedForRead else { return [:] }

        let startDate = today.addingDays(1).toDate(minutesFromMidnight: 0, timeZone: timeZone)
        let endDate = today.addingDays(8).toDate(minutesFromMidnight: 0, timeZone: timeZone)
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
        let events = eventStore.events(matching: predicate)

        var counts: [LocalDate: Int] = [:]
        for event in events where !event.isAllDay {
            let localDay = LocalDate.from(date: event.startDate, timeZone: timeZone)
            counts[localDay, default: 0] += 1
        }
        return counts
    }

    /// Reads non-all-day Apple Calendar busy time blocks on a specific date for conflict detection.
    func busySlots(on date: LocalDate, timeZone: TimeZone) -> [BusyTimeSlot] {
        refreshStatus()
        guard isAuthorizedForRead else { return [] }

        let startDate = date.toDate(minutesFromMidnight: 0, timeZone: timeZone)
        let endDate = date.addingDays(1).toDate(minutesFromMidnight: 0, timeZone: timeZone)
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
        let events = eventStore.events(matching: predicate)

        return events.compactMap { event in
            guard !event.isAllDay else { return nil }
            let s = LocalDateTime.from(date: max(event.startDate, startDate), timeZone: timeZone)
            let e = LocalDateTime.from(date: min(event.endDate, endDate), timeZone: timeZone)
            let startMin = s.date == date ? s.minutesFromMidnight : 0
            let endMin = e.date == date ? e.minutesFromMidnight : 1440
            guard endMin > startMin else { return nil }
            let title = (event.title?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "Acara Kalender"
            return BusyTimeSlot(
                id: event.eventIdentifier ?? UUID().uuidString,
                title: title,
                startMinutes: startMin,
                endMinutes: endMin,
                isCalendarEvent: true
            )
        }
    }
}
