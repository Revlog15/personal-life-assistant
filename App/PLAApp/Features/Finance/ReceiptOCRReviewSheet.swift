import SwiftUI
import PhotosUI
import PLACore

/// P-05: Offline Apple Vision OCR receipt scanner & Review Transaksi sheet.
/// Photo bytes are processed strictly in memory and discarded immediately after text extraction (PRD §13.4).
struct ReceiptOCRReviewSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let initialDraft: PendingOCRReceiptDraft?

    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isProcessingOCR = false
    @State private var hasExtractedOnce = false
    @State private var detectedSourceApp: String?
    @State private var rawLineCount: Int = 0

    // Editable transaction review fields
    @State private var amountText: String = ""
    @State private var merchantNote: String = ""
    @State private var selectedDate: Date = Date()
    @State private var selectedCategoryId: UUID?
    @State private var selectedAccountId: UUID?

    init(initialDraft: PendingOCRReceiptDraft? = nil) {
        self.initialDraft = initialDraft
    }

    private var parsedAmount: Result<Money, AmountParseError> {
        AmountParser.parse(amountText)
    }

    private var suggestedCategories: [PLACategory] {
        CategorySuggester.suggestCategories(
            forNote: merchantNote,
            scope: .expense,
            transactions: store.transactions,
            categories: store.categories
        )
    }

    private var canSave: Bool {
        if case .success = parsedAmount,
           selectedCategoryId != nil,
           selectedAccountId != nil {
            return true
        }
        return false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                        HStack {
                            Image(systemName: "doc.text.viewfinder")
                                .font(.title2)
                                .foregroundStyle(PLATokens.Colors.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(hasExtractedOnce ? "Pilih Foto Struk Lain" : "Pilih Foto Struk / Bukti Transfer")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text("Diproses 100% offline dengan Apple Vision. Foto langsung dihapus dari memori setelah teks diekstrak.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(minHeight: PLATokens.minTouchTarget)
                    }

                    if isProcessingOCR {
                        HStack(spacing: PLATokens.Spacing.sm) {
                            ProgressView()
                            Text("Membaca teks struk secara lokal...")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if hasExtractedOnce {
                        HStack(spacing: PLATokens.Spacing.sm) {
                            StatusBadge(
                                text: "Teks terbaca (\(rawLineCount) baris)",
                                icon: "checkmark.seal.fill",
                                color: PLATokens.Colors.safe
                            )
                            if let app = detectedSourceApp {
                                StatusBadge(text: app, icon: "building.columns", color: PLATokens.Colors.info)
                            }
                        }
                    }
                } header: {
                    Text("Sumber Struk (Offline OCR)")
                } footer: {
                    Text("Anda juga dapat memakai Shortcut iOS 'Scan Struk ke Life Assistant' langsung dari Share Sheet bukti transfer bank/e-wallet.")
                }

                Section("Tinjau & Koreksi Transaksi") {
                    VStack(alignment: .leading, spacing: PLATokens.Spacing.xs) {
                        Text("Nominal (Rupiah)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Nominal pengeluaran", text: $amountText)
                            .font(.title3.weight(.bold))
                            .monospacedDigit()
                            .keyboardType(.numbersAndPunctuation)
                        if case .failure(let err) = parsedAmount, !amountText.isEmpty {
                            Text(err.userMessage)
                                .font(.caption)
                                .foregroundStyle(PLATokens.Colors.danger)
                        }
                    }

                    TextField("Merchant / Catatan", text: $merchantNote)
                    DatePicker("Tanggal Transaksi", selection: $selectedDate, displayedComponents: .date)

                    Picker("Kategori", selection: $selectedCategoryId) {
                        ForEach(store.expenseCategories) { cat in
                            Label(cat.name, systemImage: cat.iconName).tag(Optional(cat.id))
                        }
                    }

                    Picker("Akun", selection: $selectedAccountId) {
                        ForEach(store.activeAccounts) { acc in
                            Text(acc.name).tag(Optional(acc.id))
                        }
                    }
                }

                if !suggestedCategories.isEmpty {
                    Section("Saran Kategori") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: PLATokens.Spacing.sm) {
                                ForEach(suggestedCategories) { cat in
                                    let active = selectedCategoryId == cat.id
                                    Button {
                                        selectedCategoryId = cat.id
                                    } label: {
                                        Label(cat.name, systemImage: cat.iconName)
                                            .font(.subheadline.weight(.medium))
                                            .padding(.horizontal, PLATokens.Spacing.md)
                                            .frame(minHeight: PLATokens.minTouchTarget)
                                            .background(active ? PLATokens.Colors.accent : Color(uiColor: .tertiarySystemFill))
                                            .foregroundStyle(active ? Color.white : Color.primary)
                                            .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Review Struk OCR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Simpan") {
                        saveTransaction()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
            .onAppear {
                selectedAccountId = store.defaultAccount?.id
                selectedCategoryId = store.expenseCategories.first?.id
                if let draft = initialDraft {
                    applyParsed(
                        amount: draft.amount,
                        date: draft.date,
                        merchant: draft.merchant,
                        sourceApp: draft.detectedSourceApp,
                        lineCount: draft.rawLineCount
                    )
                }
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                guard let newItem else { return }
                _Concurrency.Task {
                    await processPickedPhoto(newItem)
                }
            }
        }
    }

    private func processPickedPhoto(_ item: PhotosPickerItem) async {
        isProcessingOCR = true
        defer {
            isProcessingOCR = false
            selectedPhotoItem = nil
        }

        guard let rawData = try? await item.loadTransferable(type: Data.self) else {
            store.showToast("Gagal memuat gambar untuk OCR")
            return
        }

        let parsed = await VisionReceiptOCRService.recognizeAndParse(
            imageData: rawData,
            fallbackDate: store.today
        )
        applyParsed(
            amount: parsed.amount,
            date: parsed.date,
            merchant: parsed.merchant,
            sourceApp: parsed.detectedSourceApp,
            lineCount: parsed.rawLineCount
        )
    }

    private func applyParsed(
        amount: Int64?,
        date: LocalDate?,
        merchant: String?,
        sourceApp: String?,
        lineCount: Int
    ) {
        hasExtractedOnce = true
        rawLineCount = lineCount
        detectedSourceApp = sourceApp

        if let amount {
            amountText = String(amount)
        }
        if let date {
            selectedDate = date.toDate(minutesFromMidnight: 12 * 60, timeZone: store.clock.timeZone)
        }
        if let merchant {
            merchantNote = merchant
        }
        // Auto-select matching user account if detectedSourceApp matches (e.g. "BCA", "GoPay", "OVO", "DANA")
        if let app = sourceApp?.lowercased(),
           let matchedAcc = store.activeAccounts.first(where: { $0.name.lowercased().contains(app) }) {
            selectedAccountId = matchedAcc.id
        }
        // Auto-select suggested category from merchant note history
        if let topCat = suggestedCategories.first {
            selectedCategoryId = topCat.id
        }
    }

    private func saveTransaction() {
        guard case .success(let money) = parsedAmount,
              let accId = selectedAccountId,
              let catId = selectedCategoryId else { return }

        let localDate = LocalDate.from(date: selectedDate, timeZone: store.clock.timeZone)
        let trimmedNote = merchantNote.trimmingCharacters(in: .whitespacesAndNewlines)

        let tx = PLATransaction(
            type: .expense,
            amount: money.rupiah,
            accountId: accId,
            categoryId: catId,
            dateLocal: localDate,
            note: trimmedNote.isEmpty ? nil : trimmedNote,
            createdAt: store.clock.now,
            updatedAt: store.clock.now
        )
        store.saveTransaction(tx)
        dismiss()
    }
}
