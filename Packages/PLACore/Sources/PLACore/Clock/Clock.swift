@preconcurrency import Foundation

public protocol Clock: Sendable {
    var now: Date { get }
    var timeZone: TimeZone { get }
    var calendar: Calendar { get }
}

public extension Clock {
    var today: LocalDate {
        LocalDate.from(date: now, timeZone: timeZone)
    }

    var currentLocalDateTime: LocalDateTime {
        LocalDateTime.from(date: now, timeZone: timeZone)
    }
}

public struct SystemClock: Clock {
    public init() {}

    public var now: Date { Date() }

    public var timeZone: TimeZone { TimeZone.current }

    public var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        cal.firstWeekday = 2 // Monday (Indonesia standard)
        return cal
    }
}

public struct FixedClock: Clock {
    public let now: Date
    public let timeZone: TimeZone

    public init(now: Date, timeZone: TimeZone = TimeZone(secondsFromGMT: 7 * 3600) ?? .current) {
        self.now = now
        self.timeZone = timeZone
    }

    public init(localDateTime: LocalDateTime, timeZone: TimeZone = TimeZone(secondsFromGMT: 7 * 3600) ?? .current) {
        self.timeZone = timeZone
        self.now = localDateTime.toDate(timeZone: timeZone)
    }

    public var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        cal.firstWeekday = 2
        return cal
    }
}
