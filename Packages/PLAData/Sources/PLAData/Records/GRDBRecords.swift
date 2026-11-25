import Foundation
import GRDB
import PLACore

// MARK: - GRDB Record Models mapped 1:1 to PRD §11.3 SQLite Schema

struct CategoryRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "categories"
    var id: String
    var name: String
    var scope: Int
    var iconName: String
    var colorToken: String
    var isSystem: Bool
    var isArchived: Bool
    var sortOrder: Int

    init(domain: PLACategory) {
        self.id = domain.id.uuidString
        self.name = domain.name
        self.scope = domain.scope.rawValue
        self.iconName = domain.iconName
        self.colorToken = domain.colorToken
        self.isSystem = domain.isSystem
        self.isArchived = domain.isArchived
        self.sortOrder = domain.sortOrder
    }

    func toDomain() throws -> PLACategory {
        guard let uuid = UUID(uuidString: id), let sc = CategoryScope(rawValue: scope) else {
            throw PLADatabaseError.invalidStoredIdentifier(id)
        }
        return PLACategory(
            id: uuid, name: name, scope: sc, iconName: iconName,
            colorToken: colorToken, isSystem: isSystem, isArchived: isArchived, sortOrder: sortOrder
        )
    }
}

struct RecurrenceRuleRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "recurrence_rules"
    var id: String
    var frequency: Int
    var interval: Int
    var weekdaysMask: Int?
    var anchorDayOfMonth: Int?
    var anchorMonth: Int?
    var endDateLocal: String?
    var maxOccurrences: Int?

    init(domain: RecurrenceRule) {
        self.id = domain.id.uuidString
        self.frequency = domain.frequency.rawValue
        self.interval = domain.interval
        self.weekdaysMask = domain.weekdaysMask
        self.anchorDayOfMonth = domain.anchorDayOfMonth
        self.anchorMonth = domain.anchorMonth
        self.endDateLocal = domain.endDateLocal?.isoString
        self.maxOccurrences = domain.maxOccurrences
    }

    func toDomain() throws -> RecurrenceRule {
        guard let uuid = UUID(uuidString: id), let freq = RecurrenceFrequency(rawValue: frequency) else {
            throw PLADatabaseError.invalidStoredIdentifier(id)
        }
        return RecurrenceRule(
            id: uuid, frequency: freq, interval: interval, weekdaysMask: weekdaysMask,
            anchorDayOfMonth: anchorDayOfMonth, anchorMonth: anchorMonth,
            endDateLocal: endDateLocal.flatMap(LocalDate.init(isoString:)),
            maxOccurrences: maxOccurrences
        )
    }
}

struct AccountRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "accounts"
    var id: String
    var name: String
    var type: Int
    var initialBalance: Int64
    var iconName: String
    var colorToken: String
    var isDefault: Bool
    var isArchived: Bool
    var sortOrder: Int
    var createdAt: Double

    init(domain: Account) {
        self.id = domain.id.uuidString
        self.name = domain.name
        self.type = domain.type.rawValue
        self.initialBalance = domain.initialBalance
        self.iconName = domain.iconName
        self.colorToken = domain.colorToken
        self.isDefault = domain.isDefault
        self.isArchived = domain.isArchived
        self.sortOrder = domain.sortOrder
        self.createdAt = domain.createdAt.timeIntervalSince1970
    }

    func toDomain() throws -> Account {
        guard let uuid = UUID(uuidString: id), let accType = AccountType(rawValue: type) else {
            throw PLADatabaseError.invalidStoredIdentifier(id)
        }
        return Account(
            id: uuid, name: name, type: accType, initialBalance: initialBalance,
            iconName: iconName, colorToken: colorToken, isDefault: isDefault,
            isArchived: isArchived, sortOrder: sortOrder,
            createdAt: Date(timeIntervalSince1970: createdAt)
        )
    }
}

struct TaskRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "tasks"
    var id: String
    var title: String
    var notes: String?
    var dueDateLocal: String?
    var dueTimeMinutes: Int?
    var priority: Int
    var status: Int
    var categoryId: String?
    var recurrenceRuleId: String?
    var completedAt: Double?
    var createdAt: Double
    var updatedAt: Double

    init(domain: PLATask) {
        self.id = domain.id.uuidString
        self.title = domain.title
        self.notes = domain.notes
        self.dueDateLocal = domain.dueDateLocal?.isoString
        self.dueTimeMinutes = domain.dueTimeMinutes
        self.priority = domain.priority.rawValue
        self.status = domain.status.rawValue
        self.categoryId = domain.categoryId?.uuidString
        self.recurrenceRuleId = domain.recurrenceRuleId?.uuidString
        self.completedAt = domain.completedAt?.timeIntervalSince1970
        self.createdAt = domain.createdAt.timeIntervalSince1970
        self.updatedAt = domain.updatedAt.timeIntervalSince1970
    }

    func toDomain() throws -> PLATask {
        guard let uuid = UUID(uuidString: id),
              let prio = TaskPriority(rawValue: priority),
              let stat = TaskStatus(rawValue: status) else {
            throw PLADatabaseError.invalidStoredIdentifier(id)
        }
        return PLATask(
            id: uuid, title: title, notes: notes,
            dueDateLocal: dueDateLocal.flatMap(LocalDate.init(isoString:)),
            dueTimeMinutes: dueTimeMinutes, priority: prio, status: stat,
            categoryId: categoryId.flatMap(UUID.init(uuidString:)),
            recurrenceRuleId: recurrenceRuleId.flatMap(UUID.init(uuidString:)),
            completedAt: completedAt.map { Date(timeIntervalSince1970: $0) },
            createdAt: Date(timeIntervalSince1970: createdAt),
            updatedAt: Date(timeIntervalSince1970: updatedAt)
        )
    }
}

struct ReminderRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "reminders"
    var id: String
    var ownerType: Int
    var ownerId: String
    var triggerType: Int
    var offsetMinutes: Int?
    var fireDateLocal: String
    var soundName: String
    var isEnabled: Bool
    var lastScheduledAt: Double?

    init(domain: Reminder) {
        self.id = domain.id.uuidString
        self.ownerType = domain.ownerType.rawValue
        self.ownerId = domain.ownerId.uuidString
        self.triggerType = domain.triggerType.rawValue
        self.offsetMinutes = domain.offsetMinutes
        self.fireDateLocal = domain.fireDateLocal.isoString
        self.soundName = domain.soundName
        self.isEnabled = domain.isEnabled
        self.lastScheduledAt = domain.lastScheduledAt?.timeIntervalSince1970
    }

    func toDomain() throws -> Reminder {
        guard let uuid = UUID(uuidString: id),
              let ownerUUID = UUID(uuidString: ownerId),
              let oType = ReminderOwnerType(rawValue: ownerType),
              let tType = ReminderTriggerType(rawValue: triggerType),
              let fire = LocalDateTime(isoString: fireDateLocal) else {
            throw PLADatabaseError.invalidStoredIdentifier(id)
        }
        return Reminder(
            id: uuid, ownerType: oType, ownerId: ownerUUID, triggerType: tType,
            offsetMinutes: offsetMinutes, fireDateLocal: fire, soundName: soundName,
            isEnabled: isEnabled, lastScheduledAt: lastScheduledAt.map { Date(timeIntervalSince1970: $0) }
        )
    }
}

struct TransactionRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "transactions"
    var id: String
    var type: Int
    var amount: Int64
    var accountId: String
    var destinationAccountId: String?
    var categoryId: String?
    var billId: String?
    var dateLocal: String
    var note: String?
    var createdAt: Double
    var updatedAt: Double

    init(domain: PLATransaction) {
        self.id = domain.id.uuidString
        self.type = domain.type.rawValue
        self.amount = domain.amount
        self.accountId = domain.accountId.uuidString
        self.destinationAccountId = domain.destinationAccountId?.uuidString
        self.categoryId = domain.categoryId?.uuidString
        self.billId = domain.billId?.uuidString
        self.dateLocal = domain.dateLocal.isoString
        self.note = domain.note
        self.createdAt = domain.createdAt.timeIntervalSince1970
        self.updatedAt = domain.updatedAt.timeIntervalSince1970
    }

    func toDomain() throws -> PLATransaction {
        guard let uuid = UUID(uuidString: id),
              let accUUID = UUID(uuidString: accountId),
              let txType = TransactionType(rawValue: type),
              let date = LocalDate(isoString: dateLocal) else {
            throw PLADatabaseError.invalidStoredIdentifier(id)
        }
        return PLATransaction(
            id: uuid, type: txType, amount: amount, accountId: accUUID,
            destinationAccountId: destinationAccountId.flatMap(UUID.init(uuidString:)),
            categoryId: categoryId.flatMap(UUID.init(uuidString:)),
            billId: billId.flatMap(UUID.init(uuidString:)),
            dateLocal: date, note: note,
            createdAt: Date(timeIntervalSince1970: createdAt),
            updatedAt: Date(timeIntervalSince1970: updatedAt)
        )
    }
}

struct BudgetRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "budgets"
    var id: String
    var categoryId: String?
    var amount: Int64
    var effectiveFromMonth: String
    var isActive: Bool
    var createdAt: Double
    var updatedAt: Double

    init(domain: Budget) {
        self.id = domain.id.uuidString
        self.categoryId = domain.categoryId?.uuidString
        self.amount = domain.amount
        self.effectiveFromMonth = domain.effectiveFromMonth
        self.isActive = domain.isActive
        self.createdAt = domain.createdAt.timeIntervalSince1970
        self.updatedAt = domain.updatedAt.timeIntervalSince1970
    }

    func toDomain() throws -> Budget {
        guard let uuid = UUID(uuidString: id) else {
            throw PLADatabaseError.invalidStoredIdentifier(id)
        }
        return Budget(
            id: uuid,
            categoryId: categoryId.flatMap(UUID.init(uuidString:)),
            amount: amount, effectiveFromMonth: effectiveFromMonth, isActive: isActive,
            createdAt: Date(timeIntervalSince1970: createdAt),
            updatedAt: Date(timeIntervalSince1970: updatedAt)
        )
    }
}

struct BillRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "bills"
    var id: String
    var name: String
    var amount: Int64
    var isVariableAmount: Bool
    var nextDueDateLocal: String
    var recurrenceRuleId: String
    var defaultAccountId: String
    var categoryId: String
    var isActive: Bool
    var lastPaidDateLocal: String?
    var createdAt: Double
    var updatedAt: Double

    init(domain: Bill) {
        self.id = domain.id.uuidString
        self.name = domain.name
        self.amount = domain.amount
        self.isVariableAmount = domain.isVariableAmount
        self.nextDueDateLocal = domain.nextDueDateLocal.isoString
        self.recurrenceRuleId = domain.recurrenceRuleId.uuidString
        self.defaultAccountId = domain.defaultAccountId.uuidString
        self.categoryId = domain.categoryId.uuidString
        self.isActive = domain.isActive
        self.lastPaidDateLocal = domain.lastPaidDateLocal?.isoString
        self.createdAt = domain.createdAt.timeIntervalSince1970
        self.updatedAt = domain.updatedAt.timeIntervalSince1970
    }

    func toDomain() throws -> Bill {
        guard let uuid = UUID(uuidString: id),
              let ruleUUID = UUID(uuidString: recurrenceRuleId),
              let accUUID = UUID(uuidString: defaultAccountId),
              let catUUID = UUID(uuidString: categoryId),
              let due = LocalDate(isoString: nextDueDateLocal) else {
            throw PLADatabaseError.invalidStoredIdentifier(id)
        }
        return Bill(
            id: uuid, name: name, amount: amount, isVariableAmount: isVariableAmount,
            nextDueDateLocal: due, recurrenceRuleId: ruleUUID, defaultAccountId: accUUID,
            categoryId: catUUID, isActive: isActive,
            lastPaidDateLocal: lastPaidDateLocal.flatMap(LocalDate.init(isoString:)),
            createdAt: Date(timeIntervalSince1970: createdAt),
            updatedAt: Date(timeIntervalSince1970: updatedAt)
        )
    }
}

struct InsightDBRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "insights"
    var id: String
    var ruleCode: String
    var periodKey: String
    var subjectId: String?
    var severity: Int
    var dismissedAt: Double?
    var feedback: Int?
    var generatedAt: Double

    init(domain: InsightRecord) {
        self.id = domain.id.uuidString
        self.ruleCode = domain.ruleCode
        self.periodKey = domain.periodKey
        self.subjectId = domain.subjectId?.uuidString
        self.severity = domain.severity.rawValue
        self.dismissedAt = domain.dismissedAt?.timeIntervalSince1970
        self.feedback = domain.feedback
        self.generatedAt = domain.generatedAt.timeIntervalSince1970
    }

    func toDomain() throws -> InsightRecord {
        guard let uuid = UUID(uuidString: id), let sev = InsightSeverity(rawValue: severity) else {
            throw PLADatabaseError.invalidStoredIdentifier(id)
        }
        return InsightRecord(
            id: uuid, ruleCode: ruleCode, periodKey: periodKey,
            subjectId: subjectId.flatMap(UUID.init(uuidString:)),
            severity: sev,
            dismissedAt: dismissedAt.map { Date(timeIntervalSince1970: $0) },
            feedback: feedback,
            generatedAt: Date(timeIntervalSince1970: generatedAt)
        )
    }
}
