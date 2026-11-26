import SwiftUI
import PLACore

/// Add/Edit Recurring Bill sheet (PRD F-10 / AC-10.1).
struct BillFormSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let editingBill: Bill?

    @State private var name: String
    @State private var amountText: String
    @State private var isVariableAmount: Bool
    @State private var dueDate: Date
    @State private var frequency: RecurrenceFrequency
    @State private var selectedAccountId: UUID?
    @State private var selectedCategoryId: UUID?
    @State private var isTrial: Bool
    @State private var trialEndDate: Date

    init(editingBill: Bill? = nil) {
        self.editingBill = editingBill
        _name = State(initialValue: editingBill?.name ?? "")
        _amountText = State(initialValue: editingBill.map { String($0.amount) } ?? "")
        _isVariableAmount = State(initialValue: editingBill?.isVariableAmount ?? false)
        let tz = TimeZone.current
        if let due = editingBill?.nextDueDateLocal {
            _dueDate = State(initialValue: due.toDate(minutesFromMidnight: 9 * 60, timeZone: tz))
        } else {
            _dueDate = State(initialValue: Date())
        }
        _frequency = State(initialValue: .monthly)
        _selectedAccountId = State(initialValue: editingBill?.defaultAccountId)
        _selectedCategoryId = State(initialValue: editingBill?.categoryId)
        _isTrial = State(initialValue: editingBill?.isTrial ?? false)
        if let tEnd = editingBill?.trialEndDateLocal {
            _trialEndDate = State(initialValue: tEnd.toDate(minutesFromMidnight: 9 * 60, timeZone: tz))
        } else {
            let plus14 = LocalDate.from(date: Date(), timeZone: tz).addingDays(14)
            _trialEndDate = State(initialValue: plus14.toDate(minutesFromMidnight: 9 * 60, timeZone: tz))
        }
    }

    private var parsedAmount: Result<Money, AmountParseError> {
        AmountParser.parse(amountText)
    }

    private var canSave: Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              case .success = parsedAmount,
              selectedAccountId != nil,
              selectedCategoryId != nil else { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Detail Tagihan") {
                    TextField("Nama tagihan (mis. Listrik PLN, Internet, Kos)", text: $name)
                    TextField("Nominal / estimasi (mis. 350.000)", text: $amountText)
                        .monospacedDigit()
                        .keyboardType(.numbersAndPunctuation)
                    if case .failure(let err) = parsedAmount, !amountText.isEmpty {
                        Text(err.userMessage)
                            .font(.caption)
                            .foregroundStyle(PLATokens.Colors.danger)
                    }
                    Toggle("Nominal Variabel (berubah tiap bulan)", isOn: $isVariableAmount)
                }

                Section {
                    DatePicker("Jatuh Tempo Berikutnya", selection: $dueDate, displayedComponents: .date)
                    Picker("Siklus", selection: $frequency) {
                        Text("Mingguan").tag(RecurrenceFrequency.weekly)
                        Text("Bulanan").tag(RecurrenceFrequency.monthly)
                        Text("Tahunan").tag(RecurrenceFrequency.yearly)
                    }
                    .pickerStyle(.segmented)

                    // P-11: Subscription trial end warning
                    Toggle("Ini Masa Trial Langganan", isOn: $isTrial)
                    if isTrial {
                        DatePicker("Tanggal Akhir Trial", selection: $trialEndDate, displayedComponents: .date)
                    }
                } header: {
                    Text("Jadwal & Siklus")
                } footer: {
                    Text(isTrial
                         ? "Pengingat tegas H-3 dan H-1 sebelum tanggal akhir trial agar Anda sempat membatalkan sebelum terdebit otomatis."
                         : "Pengingat otomatis akan dijadwalkan pada H-3, H-1, dan Hari H dengan suara kustom tagihan.")
                }

                Section("Pencatatan Otomatis Saat Lunas") {
                    Picker("Akun Default", selection: $selectedAccountId) {
                        ForEach(store.activeAccounts) { acc in
                            Text(acc.name).tag(Optional(acc.id))
                        }
                    }
                    Picker("Kategori Pengeluaran", selection: $selectedCategoryId) {
                        ForEach(store.expenseCategories) { cat in
                            Text(cat.name).tag(Optional(cat.id))
                        }
                    }
                }
            }
            .navigationTitle(editingBill == nil ? "Tagihan Baru" : "Sunting Tagihan")
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
                    selectedCategoryId = store.expenseCategories.first { $0.name == "Tagihan & Utilitas" }?.id
                        ?? store.expenseCategories.first?.id
                }
                if let ruleId = editingBill?.recurrenceRuleId,
                   let rule = store.recurrenceRule(for: ruleId) {
                    frequency = rule.frequency
                }
            }
        }
    }

    private func save() {
        guard case .success(let money) = parsedAmount,
              let accId = selectedAccountId,
              let catId = selectedCategoryId else { return }

        let localDue = LocalDate.from(date: dueDate, timeZone: store.clock.timeZone)
        let localTrialEnd = isTrial ? LocalDate.from(date: trialEndDate, timeZone: store.clock.timeZone) : nil
        let ruleId = editingBill?.recurrenceRuleId ?? UUID()
        let rule = RecurrenceRule(
            id: ruleId,
            frequency: frequency,
            interval: 1,
            anchorDayOfMonth: frequency == .monthly || frequency == .yearly ? localDue.day : nil,
            anchorMonth: frequency == .yearly ? localDue.month : nil
        )
        let bill = Bill(
            id: editingBill?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            amount: money.rupiah,
            isVariableAmount: isVariableAmount,
            nextDueDateLocal: localTrialEnd ?? localDue,
            recurrenceRuleId: rule.id,
            defaultAccountId: accId,
            categoryId: catId,
            isActive: editingBill?.isActive ?? true,
            lastPaidDateLocal: editingBill?.lastPaidDateLocal,
            isTrial: isTrial,
            trialEndDateLocal: localTrialEnd,
            createdAt: editingBill?.createdAt ?? store.clock.now,
            updatedAt: store.clock.now
        )
        store.saveBill(bill, rule: rule)
        dismiss()
    }
}

/// 2-tap "Tandai Lunas" confirmation sheet supporting variable bill amounts (AC-10.2 & §12).
struct PayBillSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let bill: Bill

    @State private var actualAmountText: String
    @State private var updateEstimateGoingForward: Bool = false

    init(bill: Bill) {
        self.bill = bill
        _actualAmountText = State(initialValue: String(bill.amount))
    }

    private var parsedAmount: Result<Money, AmountParseError> {
        AmountParser.parse(actualAmountText)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Konfirmasi Pelunasan") {
                    AdaptiveKeyValueRow {
                        Text("Tagihan")
                            .foregroundStyle(.secondary)
                    } trailing: {
                        Text(bill.name).fontWeight(.semibold)
                    }
                    AdaptiveKeyValueRow {
                        Text("Akun Terpotong")
                            .foregroundStyle(.secondary)
                    } trailing: {
                        Text(store.accountName(for: bill.defaultAccountId))
                    }
                    AdaptiveKeyValueRow {
                        Text("Kategori")
                            .foregroundStyle(.secondary)
                    } trailing: {
                        Text(store.categoryName(for: bill.categoryId))
                    }
                }

                Section(bill.isVariableAmount ? "Nominal Aktual Bulan Ini" : "Nominal Tagihan") {
                    TextField("Nominal aktual", text: $actualAmountText)
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                        .keyboardType(.numbersAndPunctuation)

                    if case .failure(let err) = parsedAmount {
                        Text(err.userMessage)
                            .font(.caption)
                            .foregroundStyle(PLATokens.Colors.danger)
                    }

                    if bill.isVariableAmount {
                        Toggle("Perbarui nominal estimasi ke depannya", isOn: $updateEstimateGoingForward)
                    }
                }

                Section {
                    Button {
                        if case .success(let money) = parsedAmount {
                            store.markBillPaid(
                                bill: bill,
                                actualAmount: money.rupiah,
                                updateEstimatedAmount: updateEstimateGoingForward
                            )
                            dismiss()
                        }
                    } label: {
                        Label("Konfirmasi Lunas", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: PLATokens.minTouchTarget)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled({
                        if case .success = parsedAmount { return false }
                        return true
                    }())
                } footer: {
                    Text("Transaksi pengeluaran akan langsung tercatat, saldo akun berkurang, realisasi anggaran bertambah, dan jatuh tempo maju ke siklus berikutnya.")
                }
            }
            .navigationTitle("Tandai Lunas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal") { dismiss() }
                }
            }
        }
    }
}
