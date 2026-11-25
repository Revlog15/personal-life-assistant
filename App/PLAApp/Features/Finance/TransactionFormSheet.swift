import SwiftUI
import PLACore

/// Quick transaction entry form (<= 4 taps outside typing amount: AC-08.1..08.3).
struct TransactionFormSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let editingTransaction: PLATransaction?

    @State private var txType: TransactionType
    @State private var amountText: String
    @State private var selectedCategoryId: UUID?
    @State private var selectedAccountId: UUID?
    @State private var selectedDate: Date
    @State private var note: String

    @FocusState private var isAmountFocused: Bool

    init(initialType: TransactionType = .expense, editingTransaction: PLATransaction? = nil) {
        self.editingTransaction = editingTransaction
        _txType = State(initialValue: editingTransaction?.type ?? (initialType == .transfer ? .expense : initialType))
        _amountText = State(initialValue: editingTransaction.map { String($0.amount) } ?? "")
        _selectedCategoryId = State(initialValue: editingTransaction?.categoryId)
        _selectedAccountId = State(initialValue: editingTransaction?.accountId)
        let tz = TimeZone.current
        if let d = editingTransaction?.dateLocal {
            _selectedDate = State(initialValue: d.toDate(minutesFromMidnight: 12 * 60, timeZone: tz))
        } else {
            _selectedDate = State(initialValue: Date())
        }
        _note = State(initialValue: editingTransaction?.note ?? "")
    }

    private var parsedAmountResult: Result<Money, AmountParseError> {
        AmountParser.parse(amountText)
    }

    private var availableCategories: [Category] {
        txType == .income ? store.incomeCategories : store.expenseCategories
    }

    private var suggestedCategories: [Category] {
        CategorySuggester.suggestCategories(
            forNote: note,
            scope: txType == .income ? .income : .expense,
            transactions: store.transactions,
            categories: store.categories
        )
    }

    private var canSave: Bool {
        if case .success = parsedAmountResult,
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
                    Picker("Jenis", selection: $txType) {
                        Text("Pengeluaran").tag(TransactionType.expense)
                        Text("Pemasukan").tag(TransactionType.income)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: txType) { _, _ in
                        selectedCategoryId = availableCategories.first?.id
                    }

                    VStack(alignment: .leading, spacing: PLATokens.Spacing.xs) {
                        Text("Nominal (Rupiah)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Contoh: 50.000", text: $amountText)
                            .font(.title2.weight(.bold))
                            .monospacedDigit()
                            .keyboardType(.numbersAndPunctuation)
                            .focused($isAmountFocused)

                        switch parsedAmountResult {
                        case .success(let money):
                            Text(PLAFormatters.rupiah(money.rupiah))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(PLATokens.Colors.accent)
                        case .failure(let err):
                            if !amountText.isEmpty {
                                Text(err.userMessage)
                                    .font(.caption)
                                    .foregroundStyle(PLATokens.Colors.danger)
                            }
                        }
                    }

                    TextField("Catatan / Merchant (opsional, mis. Kopi)", text: $note)
                }

                // Smart Category Suggestions (AC-08.2)
                if !suggestedCategories.isEmpty {
                    Section("Saran Kategori Cepat") {
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

                Section("Kategori & Akun") {
                    Picker("Kategori", selection: $selectedCategoryId) {
                        ForEach(availableCategories) { cat in
                            Label(cat.name, systemImage: cat.iconName).tag(Optional(cat.id))
                        }
                    }

                    Picker("Akun", selection: $selectedAccountId) {
                        ForEach(store.activeAccounts) { acc in
                            Text(acc.name).tag(Optional(acc.id))
                        }
                    }

                    DatePicker("Tanggal", selection: $selectedDate, displayedComponents: .date)
                }
            }
            .navigationTitle(editingTransaction == nil ? "Catat Transaksi" : "Sunting Transaksi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Simpan") {
                        save()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
            .onAppear {
                if selectedAccountId == nil {
                    selectedAccountId = store.defaultAccount?.id
                }
                if selectedCategoryId == nil {
                    selectedCategoryId = availableCategories.first?.id
                }
                if editingTransaction == nil {
                    isAmountFocused = true
                }
            }
        }
    }

    private func save() {
        guard case .success(let money) = parsedAmountResult,
              let accountId = selectedAccountId,
              let categoryId = selectedCategoryId else { return }

        let localDate = LocalDate.from(date: selectedDate, timeZone: store.clock.timeZone)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

        let tx = PLATransaction(
            id: editingTransaction?.id ?? UUID(),
            type: txType,
            amount: money.rupiah,
            accountId: accountId,
            destinationAccountId: nil,
            categoryId: categoryId,
            billId: editingTransaction?.billId,
            dateLocal: localDate,
            note: trimmedNote.isEmpty ? nil : trimmedNote,
            createdAt: editingTransaction?.createdAt ?? store.clock.now,
            updatedAt: store.clock.now
        )
        store.saveTransaction(tx)
        dismiss()
    }
}
