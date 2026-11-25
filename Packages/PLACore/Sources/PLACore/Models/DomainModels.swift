import Foundation

public enum TaskPriority: Int, Codable, CaseIterable, Comparable, Sendable {
    case low = 0
    case medium = 1
    case high = 2

    public static func < (lhs: TaskPriority, rhs: TaskPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum TaskStatus: Int, Codable, CaseIterable, Sendable {
    case active = 0
    case completed = 1
    case archived = 2
}

public struct PLATask: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var title: String
    public var notes: String?
    public var dueDateLocal: LocalDate?
    public var dueTimeMinutes: Int?
    public var priority: TaskPriority
    public var status: TaskStatus
    public var categoryId: UUID?
    public var recurrenceRuleId: UUID?
    public var completedAt: Date?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        notes: String? = nil,
        dueDateLocal: LocalDate? = nil,
        dueTimeMinutes: Int? = nil,
        priority: TaskPriority = .medium,
        status: TaskStatus = .active,
        categoryId: UUID? = nil,
        recurrenceRuleId: UUID? = nil,
        completedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.dueDateLocal = dueDateLocal
        self.dueTimeMinutes = dueTimeMinutes
        self.priority = priority
        self.status = status
        self.categoryId = categoryId
        self.recurrenceRuleId = recurrenceRuleId
        self.completedAt = completedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public static func isValidTitle(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= 200
    }

    public var dueDateTime: LocalDateTime? {
        guard let date = dueDateLocal else { return nil }
        return LocalDateTime(date: date, minutesFromMidnight: dueTimeMinutes ?? (23 * 60 + 59))
    }

    public func isOverdue(at now: LocalDateTime) -> Bool {
        guard status == .active, let dueDate = dueDateLocal else { return false }
        if let mins = dueTimeMinutes {
            return LocalDateTime(date: dueDate, minutesFromMidnight: mins) < now
        }
        return dueDate < now.date
    }
}

public enum ReminderOwnerType: Int, Codable, CaseIterable, Sendable {
    case task = 0
    case bill = 1
}

public enum ReminderTriggerType: Int, Codable, CaseIterable, Sendable {
    case automatic = 0
    case manual = 1
    case snooze = 2
}

public enum ReminderSound: String, Codable, CaseIterable, Sendable {
    case plaDefault = "pla_default.caf"
    case plaUrgent = "pla_urgent.caf"
    case plaBill = "pla_bill.caf"
    case plaDigest = "pla_digest.caf"
    case systemDefault = "default"
    case none = "none"
}

public struct Reminder: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var ownerType: ReminderOwnerType
    public var ownerId: UUID
    public var triggerType: ReminderTriggerType
    public var offsetMinutes: Int?
    public var fireDateLocal: LocalDateTime
    public var soundName: String
    public var isEnabled: Bool
    public var lastScheduledAt: Date?

    public init(
        id: UUID = UUID(),
        ownerType: ReminderOwnerType,
        ownerId: UUID,
        triggerType: ReminderTriggerType = .automatic,
        offsetMinutes: Int? = nil,
        fireDateLocal: LocalDateTime,
        soundName: String = ReminderSound.plaDefault.rawValue,
        isEnabled: Bool = true,
        lastScheduledAt: Date? = nil
    ) {
        self.id = id
        self.ownerType = ownerType
        self.ownerId = ownerId
        self.triggerType = triggerType
        self.offsetMinutes = offsetMinutes
        self.fireDateLocal = fireDateLocal
        self.soundName = soundName
        self.isEnabled = isEnabled
        self.lastScheduledAt = lastScheduledAt
    }
}

public enum RecurrenceFrequency: Int, Codable, CaseIterable, Sendable {
    case daily = 0
    case weekly = 1
    case monthly = 2
    case yearly = 3
}

public struct RecurrenceRule: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var frequency: RecurrenceFrequency
    public var interval: Int
    /// Bitmask: bit 0 = Monday (Senin) ... bit 6 = Sunday (Minggu)
    public var weekdaysMask: Int?
    /// 1...31 or -1 for last day of month
    public var anchorDayOfMonth: Int?
    /// 1...12 for yearly rules
    public var anchorMonth: Int?
    public var endDateLocal: LocalDate?
    public var maxOccurrences: Int?

    public init(
        id: UUID = UUID(),
        frequency: RecurrenceFrequency,
        interval: Int = 1,
        weekdaysMask: Int? = nil,
        anchorDayOfMonth: Int? = nil,
        anchorMonth: Int? = nil,
        endDateLocal: LocalDate? = nil,
        maxOccurrences: Int? = nil
    ) {
        self.id = id
        self.frequency = frequency
        self.interval = max(1, interval)
        self.weekdaysMask = weekdaysMask
        self.anchorDayOfMonth = anchorDayOfMonth
        self.anchorMonth = anchorMonth
        self.endDateLocal = endDateLocal
        self.maxOccurrences = maxOccurrences
    }
}

public enum AccountType: Int, Codable, CaseIterable, Sendable {
    case cash = 0
    case bank = 1
    case ewallet = 2
}

public struct Account: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var type: AccountType
    public var initialBalance: Int64
    public var iconName: String
    public var colorToken: String
    public var isDefault: Bool
    public var isArchived: Bool
    public var sortOrder: Int
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        type: AccountType,
        initialBalance: Int64 = 0,
        iconName: String = "banknote",
        colorToken: String = "teal",
        isDefault: Bool = false,
        isArchived: Bool = false,
        sortOrder: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.initialBalance = initialBalance
        self.iconName = iconName
        self.colorToken = colorToken
        self.isDefault = isDefault
        self.isArchived = isArchived
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }
}

public enum CategoryScope: Int, Codable, CaseIterable, Sendable {
    case expense = 0
    case income = 1
    case task = 2
}

public struct PLACategory: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var scope: CategoryScope
    public var iconName: String
    public var colorToken: String
    public var isSystem: Bool
    public var isArchived: Bool
    public var sortOrder: Int

    public init(
        id: UUID = UUID(),
        name: String,
        scope: CategoryScope,
        iconName: String = "tag",
        colorToken: String = "teal",
        isSystem: Bool = false,
        isArchived: Bool = false,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.scope = scope
        self.iconName = iconName
        self.colorToken = colorToken
        self.isSystem = isSystem
        self.isArchived = isArchived
        self.sortOrder = sortOrder
    }
}

public enum TransactionType: Int, Codable, CaseIterable, Sendable {
    case expense = 0
    case income = 1
    case transfer = 2
}

public enum TransactionValidationError: Error, Equatable, Sendable {
    case nonPositiveAmount
    case amountExceedsLimit
    case missingCategory
    case missingDestinationAccount
    case sameSourceAndDestination
    case categoryNotAllowedForTransfer
}

public struct PLATransaction: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var type: TransactionType
    public var amount: Int64
    public var accountId: UUID
    public var destinationAccountId: UUID?
    public var categoryId: UUID?
    public var billId: UUID?
    public var dateLocal: LocalDate
    public var note: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        type: TransactionType,
        amount: Int64,
        accountId: UUID,
        destinationAccountId: UUID? = nil,
        categoryId: UUID? = nil,
        billId: UUID? = nil,
        dateLocal: LocalDate,
        note: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.amount = amount
        self.accountId = accountId
        self.destinationAccountId = destinationAccountId
        self.categoryId = categoryId
        self.billId = billId
        self.dateLocal = dateLocal
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public func validate() throws {
        guard amount > 0 else { throw TransactionValidationError.nonPositiveAmount }
        guard amount <= Money.maxAllowedRupiah else { throw TransactionValidationError.amountExceedsLimit }
        switch type {
        case .expense, .income:
            guard categoryId != nil else { throw TransactionValidationError.missingCategory }
        case .transfer:
            guard let dest = destinationAccountId else {
                throw TransactionValidationError.missingDestinationAccount
            }
            guard dest != accountId else {
                throw TransactionValidationError.sameSourceAndDestination
            }
            if categoryId != nil {
                throw TransactionValidationError.categoryNotAllowedForTransfer
            }
        }
    }
}

public struct Budget: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    /// nil = Total monthly budget; non-nil = specific expense category budget
    public var categoryId: UUID?
    public var amount: Int64
    /// YYYY-MM
    public var effectiveFromMonth: String
    public var isActive: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        categoryId: UUID? = nil,
        amount: Int64,
        effectiveFromMonth: String,
        isActive: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.categoryId = categoryId
        self.amount = amount
        self.effectiveFromMonth = effectiveFromMonth
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct Bill: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var amount: Int64
    public var isVariableAmount: Bool
    public var nextDueDateLocal: LocalDate
    public var recurrenceRuleId: UUID
    public var defaultAccountId: UUID
    public var categoryId: UUID
    public var isActive: Bool
    public var lastPaidDateLocal: LocalDate?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        amount: Int64,
        isVariableAmount: Bool = false,
        nextDueDateLocal: LocalDate,
        recurrenceRuleId: UUID,
        defaultAccountId: UUID,
        categoryId: UUID,
        isActive: Bool = true,
        lastPaidDateLocal: LocalDate? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.amount = amount
        self.isVariableAmount = isVariableAmount
        self.nextDueDateLocal = nextDueDateLocal
        self.recurrenceRuleId = recurrenceRuleId
        self.defaultAccountId = defaultAccountId
        self.categoryId = categoryId
        self.isActive = isActive
        self.lastPaidDateLocal = lastPaidDateLocal
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public func isOverdue(on today: LocalDate) -> Bool {
        isActive && nextDueDateLocal < today
    }

    public func isDueWithin(days: Int, from today: LocalDate) -> Bool {
        guard isActive else { return false }
        let diff = today.days(until: nextDueDateLocal)
        return diff <= days
    }
}

public enum InsightSeverity: Int, Codable, CaseIterable, Comparable, Sendable {
    case info = 0
    case medium = 1
    case high = 2
    case critical = 3

    public static func < (lhs: InsightSeverity, rhs: InsightSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct InsightRecord: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var ruleCode: String
    public var periodKey: String
    public var subjectId: UUID?
    public var severity: InsightSeverity
    public var dismissedAt: Date?
    /// 1 = useful (thumbs up), -1 = not useful (thumbs down)
    public var feedback: Int?
    public var generatedAt: Date

    public init(
        id: UUID = UUID(),
        ruleCode: String,
        periodKey: String,
        subjectId: UUID? = nil,
        severity: InsightSeverity,
        dismissedAt: Date? = nil,
        feedback: Int? = nil,
        generatedAt: Date = Date()
    ) {
        self.id = id
        self.ruleCode = ruleCode
        self.periodKey = periodKey
        self.subjectId = subjectId
        self.severity = severity
        self.dismissedAt = dismissedAt
        self.feedback = feedback
        self.generatedAt = generatedAt
    }
}

public enum AutoLockTimeout: Int, Codable, CaseIterable, Sendable {
    case immediate = 0
    case oneMinute = 60
    case fiveMinutes = 300
}

public struct SmartReminderPreferences: Hashable, Codable, Sendable {
    public var highEnableH7: Bool
    public var highEnableH3: Bool
    public var highEnableH1: Bool
    public var highEnableDayOf: Bool
    public var highEnableTwoHoursBefore: Bool

    public var mediumEnableH3: Bool
    public var mediumEnableH1: Bool
    public var mediumEnableDayOf: Bool

    public var lowEnableDayOf: Bool

    public var billEnableH3: Bool
    public var billEnableH1: Bool
    public var billEnableDayOf: Bool

    public static let `default` = SmartReminderPreferences(
        highEnableH7: true,
        highEnableH3: true,
        highEnableH1: true,
        highEnableDayOf: true,
        highEnableTwoHoursBefore: true,
        mediumEnableH3: true,
        mediumEnableH1: true,
        mediumEnableDayOf: true,
        lowEnableDayOf: true,
        billEnableH3: true,
        billEnableH1: true,
        billEnableDayOf: true
    )

    public init(
        highEnableH7: Bool = true,
        highEnableH3: Bool = true,
        highEnableH1: Bool = true,
        highEnableDayOf: Bool = true,
        highEnableTwoHoursBefore: Bool = true,
        mediumEnableH3: Bool = true,
        mediumEnableH1: Bool = true,
        mediumEnableDayOf: Bool = true,
        lowEnableDayOf: Bool = true,
        billEnableH3: Bool = true,
        billEnableH1: Bool = true,
        billEnableDayOf: Bool = true
    ) {
        self.highEnableH7 = highEnableH7
        self.highEnableH3 = highEnableH3
        self.highEnableH1 = highEnableH1
        self.highEnableDayOf = highEnableDayOf
        self.highEnableTwoHoursBefore = highEnableTwoHoursBefore
        self.mediumEnableH3 = mediumEnableH3
        self.mediumEnableH1 = mediumEnableH1
        self.mediumEnableDayOf = mediumEnableDayOf
        self.lowEnableDayOf = lowEnableDayOf
        self.billEnableH3 = billEnableH3
        self.billEnableH1 = billEnableH1
        self.billEnableDayOf = billEnableDayOf
    }
}

public struct UserSettings: Hashable, Codable, Sendable {
    public var quietHoursEnabled: Bool
    public var quietStartMinutes: Int
    public var quietEndMinutes: Int
    public var morningDigestEnabled: Bool
    public var morningDigestMinutes: Int
    /// 1...28 (default 1 per OQ-05)
    public var budgetCycleStartDay: Int
    public var financeLockEnabled: Bool
    public var showBudgetStatusWhenLocked: Bool
    public var autoLockTimeout: AutoLockTimeout
    public var reminderPreferences: SmartReminderPreferences
    public var defaultTaskSound: String
    public var urgentTaskSound: String
    public var billSound: String
    public var digestSound: String
    public var hasCompletedOnboarding: Bool

    public static let `default` = UserSettings()

    public init(
        quietHoursEnabled: Bool = true,
        quietStartMinutes: Int = 22 * 60,
        quietEndMinutes: Int = 7 * 60,
        morningDigestEnabled: Bool = true,
        morningDigestMinutes: Int = 7 * 60 + 30,
        budgetCycleStartDay: Int = 1,
        financeLockEnabled: Bool = true,
        showBudgetStatusWhenLocked: Bool = true,
        autoLockTimeout: AutoLockTimeout = .immediate,
        reminderPreferences: SmartReminderPreferences = .default,
        defaultTaskSound: String = ReminderSound.plaDefault.rawValue,
        urgentTaskSound: String = ReminderSound.plaUrgent.rawValue,
        billSound: String = ReminderSound.plaBill.rawValue,
        digestSound: String = ReminderSound.plaDigest.rawValue,
        hasCompletedOnboarding: Bool = false
    ) {
        self.quietHoursEnabled = quietHoursEnabled
        self.quietStartMinutes = min(max(quietStartMinutes, 0), 1439)
        self.quietEndMinutes = min(max(quietEndMinutes, 0), 1439)
        self.morningDigestEnabled = morningDigestEnabled
        self.morningDigestMinutes = min(max(morningDigestMinutes, 0), 1439)
        self.budgetCycleStartDay = min(max(budgetCycleStartDay, 1), 28)
        self.financeLockEnabled = financeLockEnabled
        self.showBudgetStatusWhenLocked = showBudgetStatusWhenLocked
        self.autoLockTimeout = autoLockTimeout
        self.reminderPreferences = reminderPreferences
        self.defaultTaskSound = defaultTaskSound
        self.urgentTaskSound = urgentTaskSound
        self.billSound = billSound
        self.digestSound = digestSound
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }
}
