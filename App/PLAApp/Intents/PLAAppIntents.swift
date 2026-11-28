import Foundation
import AppIntents
import WidgetKit
import PLACore
import PLAData

// MARK: - AppEnums for Guided Siri Prompts

enum TaskPriorityAppEnum: String, AppEnum {
    case high
    case medium
    case low

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Prioritas Tugas"

    static var caseDisplayRepresentations: [TaskPriorityAppEnum: DisplayRepresentation] = [
        .high: DisplayRepresentation(title: "Tinggi (Penting / Mendesak)"),
        .medium: DisplayRepresentation(title: "Sedang (Normal)"),
        .low: DisplayRepresentation(title: "Rendah (Santai)")
    ]

    var domainPriority: TaskPriority {
        switch self {
        case .high: return .high
        case .medium: return .medium
        case .low: return .low
        }
    }

    var labelIndonesian: String {
        switch self {
        case .high: return "Tinggi"
        case .medium: return "Sedang"
        case .low: return "Rendah"
        }
    }
}

enum TaskCategoryAppEnum: String, AppEnum {
    case kerja = "Kerja"
    case pribadi = "Pribadi"
    case belajar = "Belajar"
    case umum = "Umum"

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Kategori Tugas"

    static var caseDisplayRepresentations: [TaskCategoryAppEnum: DisplayRepresentation] = [
        .kerja: DisplayRepresentation(title: "Kerja"),
        .pribadi: DisplayRepresentation(title: "Pribadi"),
        .belajar: DisplayRepresentation(title: "Belajar"),
        .umum: DisplayRepresentation(title: "Umum")
    ]
}

// MARK: - P-02: Guided Conversational AddTaskIntent (Siri asks: ngapain, sama siapa, jam/tanggal, prioritas, kategori!)

struct AddTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Tambah Tugas ke Life Assistant"
    static var description = IntentDescription("Mencatat tugas baru lewat tanya-jawab Siri (kegiatan, dengan siapa, tanggal & jam, tingkat prioritas, dan kategori) serta mendukung parsing bahasa Indonesia & Inggris.")
    static var openAppWhenRun: Bool = false

    @Parameter(
        title: "Kegiatan / Judul Tugas",
        requestValueDialog: IntentDialog("Mau catat kegiatan atau tugas apa?")
    )
    var taskTitle: String

    @Parameter(title: "Sama Siapa / Catatan Tambahan")
    var peopleOrNotes: String?

    @Parameter(title: "Jadwal (Tanggal & Jam)")
    var scheduledDate: Date?

    @Parameter(title: "Prioritas / Tingkat Kepentingan")
    var priorityLevel: TaskPriorityAppEnum?

    @Parameter(title: "Kategori")
    var categoryOption: TaskCategoryAppEnum?

    static var parameterSummary: some ParameterSummary {
        Summary("Tambah tugas \(\.$taskTitle) pada \(\.$scheduledDate)") {
            \.$peopleOrNotes
            \.$priorityLevel
            \.$categoryOption
        }
    }

    private static let skipTokens: Set<String> = [
        "tidak ada", "tidak", "ga ada", "gak ada", "nggak ada", "nggak", "gak", "ga",
        "lewati", "skip", "none", "no", "nothing", "kosong", "-"
    ]

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let rawTitle = taskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawTitle.isEmpty else {
            return .result(dialog: "Judul tugas tidak boleh kosong.")
        }

        let clock = SystemClock()
        let settings = SettingsStore().loadSettings()
        let dbManager = try DatabaseManager()
        let store = GRDBStore(dbManager: dbManager)
        try store.ensureDefaultCategoriesExist()

        let categories = try store.fetchAllCategories()
        // Parse bilingual ID + EN hints embedded in the first answer (e.g. "meeting with dimas at 3 oclock")
        let parsed = NaturalLanguageTaskParser.parse(rawTitle, today: clock.today, categories: categories)

        // 1. Ask follow-up: "Sama siapa / catatan tambahan?" (skip if already provided or mentioned in title)
        var resolvedNotes: String? = cleanOptionalNote(peopleOrNotes)
        let titleLower = parsed.title.lowercased()
        let alreadyMentionsCompanion = titleLower.contains(" with ") ||
            titleLower.contains(" sama ") ||
            titleLower.contains(" dengan ") ||
            titleLower.contains(" bareng ")

        if resolvedNotes == nil && !alreadyMentionsCompanion {
            if let answer = try? await $peopleOrNotes.requestValue(
                IntentDialog("Dengan siapa atau ada catatan tambahan? Sebut 'tidak ada' untuk lewati.")
            ) {
                resolvedNotes = cleanOptionalNote(answer)
            }
        }

        // 2. Ask follow-up: "Kapan jadwal & jamnya?" (uses native Siri Date parsing for both EN & ID!)
        var finalDueDate: LocalDate? = parsed.dueDate
        var finalDueTimeMinutes: Int? = parsed.dueTimeMinutes

        if let explicitDate = scheduledDate {
            let ldt = LocalDateTime.from(date: explicitDate, timeZone: clock.timeZone)
            finalDueDate = ldt.date
            finalDueTimeMinutes = ldt.minutesFromMidnight
        } else if finalDueDate == nil {
            if let pickedDate = try? await $scheduledDate.requestValue(
                IntentDialog("Kapan jadwal dan jamnya? Sebutkan hari dan jam, misalnya hari ini jam 3 sore atau besok jam 9 pagi.")
            ) {
                let ldt = LocalDateTime.from(date: pickedDate, timeZone: clock.timeZone)
                finalDueDate = ldt.date
                finalDueTimeMinutes = ldt.minutesFromMidnight
            }
        }

        // 3. Ask follow-up: "Seberapa berat / prioritasnya?"
        let finalPriority: TaskPriority
        if let explicitPrio = priorityLevel {
            finalPriority = explicitPrio.domainPriority
        } else if parsed.priorityExplicitlySet {
            finalPriority = parsed.priority
        } else if let askedPrio = try? await $priorityLevel.requestValue(
            IntentDialog("Seberapa penting atau berat tugas ini? Tinggi, Sedang, atau Rendah?")
        ) {
            finalPriority = askedPrio.domainPriority
        } else {
            finalPriority = .medium
        }

        // 4. Ask follow-up: "Masuk kategori mana?"
        let taskCategories = categories.filter { $0.scope == .task && !$0.isArchived }
        var finalCategoryId: UUID? = parsed.matchedCategoryId
        if let chosenCat = categoryOption {
            finalCategoryId = taskCategories.first { $0.name.lowercased() == chosenCat.rawValue.lowercased() }?.id
        } else if finalCategoryId == nil {
            if let askedCat = try? await $categoryOption.requestValue(
                IntentDialog("Masuk kategori mana? Kerja, Pribadi, Belajar, atau Umum?")
            ) {
                finalCategoryId = taskCategories.first { $0.name.lowercased() == askedCat.rawValue.lowercased() }?.id
            }
        }
        let resolvedCategoryId = finalCategoryId
            ?? taskCategories.first { $0.name == "Umum" }?.id
            ?? taskCategories.first?.id
        let resolvedCategoryName = taskCategories.first { $0.id == resolvedCategoryId }?.name ?? "Umum"

        let existingTasks = (try? store.fetchAllTasks()) ?? []
        var conflictNote: String? = nil
        if let due = finalDueDate, let mins = finalDueTimeMinutes {
            let dayStart = settings.quietHoursEnabled ? settings.quietEndMinutes : 7 * 60
            let dayEnd = settings.quietHoursEnabled ? settings.quietStartMinutes : 22 * 60
            let resolvedStart = dayStart < dayEnd ? dayStart : 7 * 60
            let resolvedEnd = dayStart < dayEnd ? dayEnd : 22 * 60
            let report = ScheduleConflictEngine.evaluate(
                date: due,
                startMinutes: mins,
                tasks: existingTasks,
                dayStartMinutes: resolvedStart,
                dayEndMinutes: resolvedEnd,
                now: clock.currentLocalDateTime
            )
            if report.hasConflict {
                let conflictTitles = report.conflictingSlots.prefix(2).map {
                    "\"\($0.title)\" pukul \(PLAFormatters.time24($0.startMinutes))"
                }.joined(separator: " dan ")
                if !report.suggestedStartMinutes.isEmpty {
                    let freeSlots = report.suggestedStartMinutes.prefix(3).map {
                        PLAFormatters.time24($0)
                    }.joined(separator: ", ")
                    conflictNote = "Catatan bentrok: di hari itu sudah ada \(conflictTitles). Kamu kosong pada jam \(freeSlots)."
                } else {
                    conflictNote = "Catatan bentrok: di hari itu sudah ada \(conflictTitles) dan jadwal hari itu cukup padat."
                }
            }
        }

        let task = PLATask(
            title: parsed.title,
            notes: resolvedNotes,
            dueDateLocal: finalDueDate,
            dueTimeMinutes: finalDueTimeMinutes,
            priority: finalPriority,
            status: .active,
            categoryId: resolvedCategoryId,
            createdAt: clock.now,
            updatedAt: clock.now
        )
        try store.saveTask(task)

        let autoReminders = ReminderPlanner.planTaskReminders(for: task, now: clock.currentLocalDateTime, settings: settings)
        try store.replaceReminders(forOwnerId: task.id, ownerType: .task, reminders: autoReminders)

        Self.refreshWidgetSnapshotFromStore(store: store, settings: settings, clock: clock)
        NotificationCenter.default.post(name: .plaExternalDataDidChange, object: nil)

        var summaryParts: [String] = ["Tugas \"\(task.title)\" tersimpan"]
        if let due = task.dueDateLocal {
            if let mins = task.dueTimeMinutes {
                summaryParts.append("jadwal \(PLAFormatters.shortDate(due)) pukul \(PLAFormatters.time24(mins))")
            } else {
                summaryParts.append("jadwal \(PLAFormatters.shortDate(due))")
            }
        }
        summaryParts.append("prioritas \(PLATokens.label(for: task.priority))")
        summaryParts.append("kategori \(resolvedCategoryName)")
        if let notes = task.notes {
            summaryParts.append("catatan: \(notes)")
        }

        var dialogText = "\(summaryParts.joined(separator: ", "))."
        if let conflictNote {
            dialogText += " \(conflictNote)"
        }
        return .result(dialog: "\(dialogText)")
    }

    private func cleanOptionalNote(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        if Self.skipTokens.contains(trimmed.lowercased()) {
            return nil
        }
        return trimmed
    }

    static func refreshWidgetSnapshotFromStore(store: GRDBStore, settings: UserSettings, clock: any PLAClock) {
        guard let tasks = try? store.fetchAllTasks(),
              let bills = try? store.fetchAllBills(),
              let transactions = try? store.fetchAllTransactions(),
              let budgets = try? store.fetchAllBudgets(),
              let categories = try? store.fetchAllCategories() else { return }
        let currentPeriod = BudgetPeriod.current(for: clock.today, cycleStartDay: settings.budgetCycleStartDay)
        let summary = BudgetCalculator.summarize(
            today: clock.today,
            cycleStartDay: settings.budgetCycleStartDay,
            transactions: transactions,
            budgets: budgets,
            bills: bills,
            categories: categories,
            openingSpent: settings.openingSpent(for: currentPeriod.periodKey)
        )
        let snapshot = WidgetSnapshotBuilder.build(
            today: clock.today,
            now: clock.currentLocalDateTime,
            summary: summary,
            tasks: tasks,
            bills: bills,
            settings: settings,
            generatedAt: clock.now
        )
        if PLASharedContainer.saveWidgetSnapshot(snapshot) {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}

// MARK: - P-02: LogExpenseIntent (Siri / Shortcuts quick expense logging)

struct LogExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "Catat Pengeluaran di Life Assistant"
    static var description = IntentDescription("Mencatat transaksi pengeluaran baru ke akun utama tanpa membuka aplikasi.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Nominal (Rupiah)", requestValueDialog: IntentDialog("Berapa nominal pengeluarannya dalam Rupiah?"))
    var amount: Int

    @Parameter(title: "Catatan / Untuk Apa")
    var note: String?

    @Parameter(title: "Kategori (Opsional)")
    var categoryName: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Catat pengeluaran Rp\(\.$amount) untuk \(\.$note)") {
            \.$categoryName
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let rupiah = Int64(amount)
        guard rupiah > 0 && rupiah <= Money.maxAllowedRupiah else {
            return .result(dialog: "Nominal harus lebih dari Rp0 dan maksimal Rp999.999.999.999.")
        }

        let clock = SystemClock()
        let settings = SettingsStore().loadSettings()
        let dbManager = try DatabaseManager()
        let store = GRDBStore(dbManager: dbManager)
        try store.ensureDefaultCategoriesExist()
        try store.ensureDefaultAccountsExist(now: clock.now)

        var resolvedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        if resolvedNote == nil || resolvedNote?.isEmpty == true {
            if let askedNote = try? await $note.requestValue(
                IntentDialog("Pengeluaran ini untuk apa? Misalnya kopi, makan siang, atau parkir.")
            ) {
                let trimmed = askedNote.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty && trimmed.lowercased() != "lewati" && trimmed.lowercased() != "tidak ada" {
                    resolvedNote = trimmed
                }
            }
        }

        let accounts = try store.fetchAllAccounts().filter { !$0.isArchived }
        let categories = try store.fetchAllCategories()
        let expenseCats = categories.filter { $0.scope == .expense && !$0.isArchived }
        guard let account = accounts.first(where: \.isDefault) ?? accounts.first else {
            return .result(dialog: "Belum ada akun aktif. Buka Life Assistant terlebih dahulu.")
        }

        var chosenCat: PLACategory? = nil
        if let catName = categoryName?.trimmingCharacters(in: .whitespacesAndNewlines), !catName.isEmpty {
            chosenCat = expenseCats.first { $0.name.lowercased().contains(catName.lowercased()) }
        }
        if chosenCat == nil, let noteText = resolvedNote, !noteText.isEmpty {
            let history = try store.fetchAllTransactions()
            chosenCat = CategorySuggester.suggestCategories(
                forNote: noteText,
                scope: .expense,
                transactions: history,
                categories: categories
            ).first
        }
        let finalCat = chosenCat ?? expenseCats.first { $0.name == "Lainnya" } ?? expenseCats.first
        guard let category = finalCat else {
            return .result(dialog: "Kategori pengeluaran tidak ditemukan.")
        }

        let tx = PLATransaction(
            type: .expense,
            amount: rupiah,
            accountId: account.id,
            categoryId: category.id,
            dateLocal: clock.today,
            note: resolvedNote,
            createdAt: clock.now,
            updatedAt: clock.now
        )
        try store.saveTransaction(tx)
        AddTaskIntent.refreshWidgetSnapshotFromStore(store: store, settings: settings, clock: clock)
        NotificationCenter.default.post(name: .plaExternalDataDidChange, object: nil)

        return .result(dialog: "Pengeluaran \(PLAFormatters.rupiah(rupiah)) di kategori \(category.name) (\(account.name)) tersimpan.")
    }
}

// MARK: - P-05: ScanReceiptIntent (Offline Apple Vision OCR via Shortcuts Share Sheet)

struct ScanReceiptIntent: AppIntent {
    static var title: LocalizedStringResource = "Scan Struk ke Life Assistant"
    static var description = IntentDescription("Mengekstrak nominal, tanggal, dan merchant dari foto struk atau bukti transfer secara offline lalu membuka layar Review Transaksi.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Gambar Struk atau Bukti Transfer", supportedTypeIdentifiers: ["public.image"])
    var imageFile: IntentFile

    static var parameterSummary: some ParameterSummary {
        Summary("Scan struk \(\.$imageFile) ke Life Assistant")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let clock = SystemClock()
        let parsed = await VisionReceiptOCRService.recognizeAndParse(
            imageData: imageFile.data,
            fallbackDate: clock.today
        )
        let draft = PendingOCRReceiptDraft(parsed: parsed)
        PendingOCRReceiptStore.save(draft)
        NotificationCenter.default.post(name: .plaPendingOCRReceiptArrived, object: nil)

        if let amt = parsed.amount {
            return .result(dialog: "Struk terbaca: \(PLAFormatters.rupiah(amt)). Silakan tinjau dan simpan di Life Assistant.")
        }
        return .result(dialog: "Struk diproses. Silakan lengkapi nominal di layar tinjau Life Assistant.")
    }
}

// MARK: - AppShortcutsProvider (Siri & Shortcuts Discovery)

struct PLAAppShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddTaskIntent(),
            phrases: [
                "Tambah tugas di \(.applicationName)",
                "Catat tugas di \(.applicationName)",
                "Add task in \(.applicationName)"
            ],
            shortTitle: "Tambah Tugas",
            systemImageName: "checklist"
        )
        AppShortcut(
            intent: LogExpenseIntent(),
            phrases: [
                "Catat pengeluaran di \(.applicationName)",
                "Tambah pengeluaran di \(.applicationName)",
                "Log expense in \(.applicationName)"
            ],
            shortTitle: "Catat Pengeluaran",
            systemImageName: "banknote"
        )
        AppShortcut(
            intent: ScanReceiptIntent(),
            phrases: [
                "Scan struk di \(.applicationName)",
                "Catat struk di \(.applicationName)"
            ],
            shortTitle: "Scan Struk OCR",
            systemImageName: "doc.text.viewfinder"
        )
    }
}
