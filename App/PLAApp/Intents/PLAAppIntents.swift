import Foundation
import AppIntents
import PLACore
import PLAData

// MARK: - P-02: AddTaskIntent (Siri / Shortcuts / Action Button — 0 App Extensions, 0 extra App IDs)

struct AddTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Tambah Tugas ke Life Assistant"
    static var description = IntentDescription("Mencatat tugas baru langsung dengan parsing bahasa Indonesia (mis. 'rapat besok jam 3 sore #kerja !tinggi').")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Judul atau Frasa Tugas", requestValueDialog: IntentDialog("Tugas apa yang ingin dicatat?"))
    var phrase: String

    static var parameterSummary: some ParameterSummary {
        Summary("Tambah tugas \(\.$phrase)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .result(dialog: "Judul tugas tidak boleh kosong.")
        }

        let clock = SystemClock()
        let settings = SettingsStore().loadSettings()
        let dbManager = try DatabaseManager()
        let store = GRDBStore(dbManager: dbManager)
        try store.ensureDefaultCategoriesExist()

        let categories = try store.fetchAllCategories()
        let parsed = NaturalLanguageTaskParser.parse(trimmed, today: clock.today, categories: categories)
        let defaultCatId = categories.first { $0.scope == .task && $0.name == "Umum" }?.id
            ?? categories.first { $0.scope == .task }?.id

        let task = PLATask(
            title: parsed.title,
            dueDateLocal: parsed.dueDate,
            dueTimeMinutes: parsed.dueTimeMinutes,
            priority: parsed.priority,
            status: .active,
            categoryId: parsed.matchedCategoryId ?? defaultCatId,
            createdAt: clock.now,
            updatedAt: clock.now
        )
        try store.saveTask(task)

        let autoReminders = ReminderPlanner.planTaskReminders(for: task, now: clock.currentLocalDateTime, settings: settings)
        try store.replaceReminders(forOwnerId: task.id, ownerType: .task, reminders: autoReminders)

        NotificationCenter.default.post(name: .plaExternalDataDidChange, object: nil)

        if let due = task.dueDateLocal {
            return .result(dialog: "Tugas \"\(task.title)\" tersimpan untuk \(PLAFormatters.shortDate(due)).")
        }
        return .result(dialog: "Tugas \"\(task.title)\" berhasil ditambahkan.")
    }
}

// MARK: - P-02: LogExpenseIntent (Siri / Shortcuts quick expense logging)

struct LogExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "Catat Pengeluaran di Life Assistant"
    static var description = IntentDescription("Mencatat transaksi pengeluaran baru ke akun utama tanpa membuka aplikasi.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Nominal (Rupiah)", requestValueDialog: IntentDialog("Berapa nominal pengeluarannya dalam Rupiah?"))
    var amount: Int

    @Parameter(title: "Catatan (Opsional)")
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
        let dbManager = try DatabaseManager()
        let store = GRDBStore(dbManager: dbManager)
        try store.ensureDefaultCategoriesExist()
        try store.ensureDefaultAccountsExist(now: clock.now)

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
        if chosenCat == nil, let noteText = note, !noteText.isEmpty {
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
            note: note?.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: clock.now,
            updatedAt: clock.now
        )
        try store.saveTransaction(tx)
        NotificationCenter.default.post(name: .plaExternalDataDidChange, object: nil)

        return .result(dialog: "Pengeluaran \(PLAFormatters.rupiah(rupiah)) di kategori \(category.name) (\(account.name)) tersimpan.")
    }
}

// MARK: - P-05: ScanReceiptIntent (Offline Apple Vision OCR via Shortcuts Share Sheet — 0 Share Extension!)

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
        // Only extracted text metadata is staged; raw photo bytes are never written to disk or DB (PRD §13.4).
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
                "Catat tugas di \(.applicationName)"
            ],
            shortTitle: "Tambah Tugas",
            systemImageName: "checklist"
        )
        AppShortcut(
            intent: LogExpenseIntent(),
            phrases: [
                "Catat pengeluaran di \(.applicationName)",
                "Tambah pengeluaran di \(.applicationName)"
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
