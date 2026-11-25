import Foundation

/// Floating local calendar date (YYYY-MM-DD) independent of timezone shifts.
public struct LocalDate: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init?(year: Int, month: Int, day: Int) {
        guard (1...9999).contains(year), (1...12).contains(month) else { return nil }
        let maxDay = Self.daysInMonth(year: year, month: month)
        guard (1...maxDay).contains(day) else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    public init?(isoString: String) {
        let parts = isoString.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]),
              let m = Int(parts[1]),
              let d = Int(parts[2]) else {
            return nil
        }
        self.init(year: y, month: m, day: d)
    }

    public var isoString: String {
        "\(Self.pad(year, width: 4))-\(Self.pad(month, width: 2))-\(Self.pad(day, width: 2))"
    }

    public var yearMonthString: String {
        "\(Self.pad(year, width: 4))-\(Self.pad(month, width: 2))"
    }

    public var description: String { isoString }

    public static func isLeapYear(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0)
    }

    public static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 1, 3, 5, 7, 8, 10, 12: return 31
        case 4, 6, 9, 11: return 30
        case 2: return isLeapYear(year) ? 29 : 28
        default: return 0
        }
    }

    /// ISO weekday: 1 = Monday (Senin) ... 7 = Sunday (Minggu).
    public var weekdayISO: Int {
        let jdn = julianDayNumber
        // JDN 0 is Monday; ((jdn % 7) + 7) % 7 gives 0 = Mon .. 6 = Sun
        return ((jdn % 7) + 7) % 7 + 1
    }

    /// Bitmask bit for weekdayISO (bit 0 = Monday .. bit 6 = Sunday).
    public var weekdayBit: Int {
        1 << (weekdayISO - 1)
    }

    /// Julian Day Number (proleptic Gregorian calendar, Fliegel-Van Flandern algorithm).
    internal var julianDayNumber: Int {
        let a = (14 - month) / 12
        let y = year + 4800 - a
        let m = month + 12 * a - 3
        return day + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045
    }

    internal static func fromJulianDayNumber(_ jdn: Int) -> LocalDate {
        let a = jdn + 32044
        let b = (4 * a + 3) / 146097
        let c = a - (146097 * b) / 4
        let d = (4 * c + 3) / 1461
        let e = c - (1461 * d) / 4
        let m = (5 * e + 2) / 153
        let day = e - (153 * m + 2) / 5 + 1
        let month = m + 3 - 12 * (m / 10)
        let year = 100 * b + d - 4800 + m / 10
        return LocalDate(year: year, month: month, day: day)!
    }

    public func addingDays(_ delta: Int) -> LocalDate {
        Self.fromJulianDayNumber(julianDayNumber + delta)
    }

    public func days(until other: LocalDate) -> Int {
        other.julianDayNumber - self.julianDayNumber
    }

    /// Adds months while preserving anchor day clamping (29-31) or end-of-month (`anchorDay == -1`).
    public func addingMonths(_ delta: Int, anchorDay: Int? = nil) -> LocalDate {
        let totalMonths = (year * 12 + (month - 1)) + delta
        let targetYear = totalMonths >= 0 ? totalMonths / 12 : (totalMonths - 11) / 12
        let targetMonth = ((totalMonths % 12) + 12) % 12 + 1
        let maxDay = Self.daysInMonth(year: targetYear, month: targetMonth)
        let resolvedDay: Int
        if let anchor = anchorDay {
            if anchor == -1 {
                resolvedDay = maxDay
            } else {
                resolvedDay = min(max(anchor, 1), maxDay)
            }
        } else {
            resolvedDay = min(day, maxDay)
        }
        return LocalDate(year: targetYear, month: targetMonth, day: resolvedDay)!
    }

    /// Adds years while preserving leap-day anchor (e.g. 29 Feb -> 28 Feb -> 29 Feb).
    public func addingYears(_ delta: Int, anchorMonth: Int? = nil, anchorDay: Int? = nil) -> LocalDate {
        let targetYear = year + delta
        let targetMonth = min(max(anchorMonth ?? month, 1), 12)
        let maxDay = Self.daysInMonth(year: targetYear, month: targetMonth)
        let resolvedDay: Int
        if let anchor = anchorDay {
            if anchor == -1 {
                resolvedDay = maxDay
            } else {
                resolvedDay = min(max(anchor, 1), maxDay)
            }
        } else {
            resolvedDay = min(day, maxDay)
        }
        return LocalDate(year: targetYear, month: targetMonth, day: resolvedDay)!
    }

    public static func from(date: Date, timeZone: TimeZone) -> LocalDate {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let comps = cal.dateComponents([.year, .month, .day], from: date)
        return LocalDate(year: comps.year ?? 2026, month: comps.month ?? 1, day: comps.day ?? 1)!
    }

    public func toDate(minutesFromMidnight: Int = 0, timeZone: TimeZone) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let clampedMinutes = min(max(minutesFromMidnight, 0), 1439)
        var comps = DateComponents()
        comps.calendar = cal
        comps.timeZone = timeZone
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = clampedMinutes / 60
        comps.minute = clampedMinutes % 60
        comps.second = 0
        return cal.date(from: comps) ?? Date(timeIntervalSince1970: 0)
    }

    public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        if lhs.month != rhs.month { return lhs.month < rhs.month }
        return lhs.day < rhs.day
    }

    private static func pad(_ value: Int, width: Int) -> String {
        let raw = String(value)
        if raw.count >= width { return raw }
        return String(repeating: "0", count: width - raw.count) + raw
    }
}

extension LocalDate: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let parsed = LocalDate(isoString: raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid LocalDate string: \(raw)"
            )
        }
        self = parsed
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(isoString)
    }
}

/// Floating local date + time (YYYY-MM-DDTHH:mm) for reminders and scheduling.
public struct LocalDateTime: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let date: LocalDate
    public let minutesFromMidnight: Int // 0...1439

    public init(date: LocalDate, minutesFromMidnight: Int) {
        let dayCarry: Int
        let normalizedMinutes: Int
        if minutesFromMidnight >= 0 {
            dayCarry = minutesFromMidnight / 1440
            normalizedMinutes = minutesFromMidnight % 1440
        } else {
            let absMin = -minutesFromMidnight
            dayCarry = -((absMin + 1439) / 1440)
            normalizedMinutes = ((minutesFromMidnight % 1440) + 1440) % 1440
        }
        self.date = dayCarry == 0 ? date : date.addingDays(dayCarry)
        self.minutesFromMidnight = normalizedMinutes
    }

    public init(date: LocalDate, hour: Int, minute: Int) {
        self.init(date: date, minutesFromMidnight: hour * 60 + minute)
    }

    public init?(isoString: String) {
        let parts = isoString.split(separator: "T", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let date = LocalDate(isoString: String(parts[0])) else {
            return nil
        }
        let timeParts = parts[1].split(separator: ":", omittingEmptySubsequences: false)
        guard timeParts.count == 2,
              timeParts[0].count == 2, timeParts[1].count == 2,
              let hour = Int(timeParts[0]),
              let minute = Int(timeParts[1]),
              (0...23).contains(hour),
              (0...59).contains(minute) else {
            return nil
        }
        self.date = date
        self.minutesFromMidnight = hour * 60 + minute
    }

    public var hour: Int { minutesFromMidnight / 60 }
    public var minute: Int { minutesFromMidnight % 60 }

    public var isoString: String {
        let h = hour < 10 ? "0\(hour)" : "\(hour)"
        let m = minute < 10 ? "0\(minute)" : "\(minute)"
        return "\(date.isoString)T\(h):\(m)"
    }

    public var description: String { isoString }

    public func addingMinutes(_ delta: Int) -> LocalDateTime {
        LocalDateTime(date: date, minutesFromMidnight: minutesFromMidnight + delta)
    }

    public func minutes(until other: LocalDateTime) -> Int {
        date.days(until: other.date) * 1440 + (other.minutesFromMidnight - minutesFromMidnight)
    }

    public func toDate(timeZone: TimeZone) -> Date {
        date.toDate(minutesFromMidnight: minutesFromMidnight, timeZone: timeZone)
    }

    public static func from(date: Date, timeZone: TimeZone) -> LocalDateTime {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let localDate = LocalDate(year: comps.year ?? 2026, month: comps.month ?? 1, day: comps.day ?? 1)!
        let mins = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        return LocalDateTime(date: localDate, minutesFromMidnight: mins)
    }

    public static func < (lhs: LocalDateTime, rhs: LocalDateTime) -> Bool {
        if lhs.date != rhs.date { return lhs.date < rhs.date }
        return lhs.minutesFromMidnight < rhs.minutesFromMidnight
    }
}

extension LocalDateTime: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let parsed = LocalDateTime(isoString: raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid LocalDateTime string: \(raw)"
            )
        }
        self = parsed
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(isoString)
    }
}
