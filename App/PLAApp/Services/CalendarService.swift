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
}
