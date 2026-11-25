import Foundation
import GRDB
import PLACore

/// Default Indonesian categories and benchmark seeders (PRD AC-15.2 & SC-07).
public enum PLADefaultSeed {
    public static func defaultCategories() -> [PLACategory] {
        [
            // Expense categories (AC-15.2)
            PLACategory(id: UUID(uuidString: "10000000-0000-4000-8000-000000000001")!, name: "Makan & Minum", scope: .expense, iconName: "fork.knife", colorToken: "orange", isSystem: true, sortOrder: 1),
            PLACategory(id: UUID(uuidString: "10000000-0000-4000-8000-000000000002")!, name: "Transportasi", scope: .expense, iconName: "tram.fill", colorToken: "blue", isSystem: true, sortOrder: 2),
            PLACategory(id: UUID(uuidString: "10000000-0000-4000-8000-000000000003")!, name: "Tagihan & Utilitas", scope: .expense, iconName: "bolt.fill", colorToken: "amber", isSystem: true, sortOrder: 3),
            PLACategory(id: UUID(uuidString: "10000000-0000-4000-8000-000000000004")!, name: "Belanja", scope: .expense, iconName: "bag.fill", colorToken: "purple", isSystem: true, sortOrder: 4),
            PLACategory(id: UUID(uuidString: "10000000-0000-4000-8000-000000000005")!, name: "Kesehatan", scope: .expense, iconName: "cross.case.fill", colorToken: "red", isSystem: true, sortOrder: 5),
            PLACategory(id: UUID(uuidString: "10000000-0000-4000-8000-000000000006")!, name: "Hiburan", scope: .expense, iconName: "film.fill", colorToken: "pink", isSystem: true, sortOrder: 6),
            PLACategory(id: UUID(uuidString: "10000000-0000-4000-8000-000000000007")!, name: "Biaya Admin", scope: .expense, iconName: "percent", colorToken: "gray", isSystem: true, sortOrder: 7),
            PLACategory(id: UUID(uuidString: "10000000-0000-4000-8000-000000000008")!, name: "Lainnya", scope: .expense, iconName: "ellipsis.circle.fill", colorToken: "teal", isSystem: true, sortOrder: 8),

            // Income categories (AC-15.2)
            PLACategory(id: UUID(uuidString: "20000000-0000-4000-8000-000000000001")!, name: "Gaji", scope: .income, iconName: "briefcase.fill", colorToken: "green", isSystem: true, sortOrder: 1),
            PLACategory(id: UUID(uuidString: "20000000-0000-4000-8000-000000000002")!, name: "Bonus", scope: .income, iconName: "sparkles", colorToken: "teal", isSystem: true, sortOrder: 2),
            PLACategory(id: UUID(uuidString: "20000000-0000-4000-8000-000000000003")!, name: "Usaha", scope: .income, iconName: "storefront.fill", colorToken: "blue", isSystem: true, sortOrder: 3),
            PLACategory(id: UUID(uuidString: "20000000-0000-4000-8000-000000000004")!, name: "Lainnya", scope: .income, iconName: "plus.circle.fill", colorToken: "gray", isSystem: true, sortOrder: 4),

            // Task categories (AC-02.1 default = Umum)
            PLACategory(id: UUID(uuidString: "30000000-0000-4000-8000-000000000001")!, name: "Umum", scope: .task, iconName: "checklist", colorToken: "teal", isSystem: true, sortOrder: 1),
            PLACategory(id: UUID(uuidString: "30000000-0000-4000-8000-000000000002")!, name: "Kerja", scope: .task, iconName: "laptopcomputer", colorToken: "blue", isSystem: true, sortOrder: 2),
            PLACategory(id: UUID(uuidString: "30000000-0000-4000-8000-000000000003")!, name: "Pribadi", scope: .task, iconName: "person.fill", colorToken: "orange", isSystem: true, sortOrder: 3),
            PLACategory(id: UUID(uuidString: "30000000-0000-4000-8000-000000000004")!, name: "Belajar", scope: .task, iconName: "book.fill", colorToken: "purple", isSystem: true, sortOrder: 4)
        ]
    }

    public static func defaultAccounts(cashBalance: Int64 = 0, bankBalance: Int64 = 0, now: Date = Date()) -> [Account] {
        [
            Account(
                id: UUID(uuidString: "40000000-0000-4000-8000-000000000001")!,
                name: "Tunai",
                type: .cash,
                initialBalance: cashBalance,
                iconName: "banknote.fill",
                colorToken: "green",
                isDefault: true,
                isArchived: false,
                sortOrder: 1,
                createdAt: now
            ),
            Account(
                id: UUID(uuidString: "40000000-0000-4000-8000-000000000002")!,
                name: "Bank",
                type: .bank,
                initialBalance: bankBalance,
                iconName: "building.columns.fill",
                colorToken: "blue",
                isDefault: false,
                isArchived: false,
                sortOrder: 2,
                createdAt: now
            )
        ]
    }
}
