import SwiftUI
import PLACore

// MARK: - P-03: Savings Goal Add/Edit Sheet

struct SavingsGoalFormSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let editingGoal: SavingsGoal?

    @State private var name: String
    @State private var targetAmountText: String
    @State private var currentAmountText: String
    @State private var hasTargetDate: Bool
    @State private var targetDate: Date
    @State private var linkedAccountId: UUID?

    init(editingGoal: SavingsGoal? = nil) {
        self.editingGoal = editingGoal
        _name = State(initialValue: editingGoal?.name ?? "")
        _targetAmountText = State(initialValue: editingGoal.map { String($0.targetAmount) } ?? "")
        _currentAmountText = State(initialValue: editingGoal.map { String($0.currentAmount) } ?? "0")
        _hasTargetDate = State(initialValue: editingGoal?.targetDateLocal != nil)
        let tz = TimeZone.current
        if let d = editingGoal?.targetDateLocal {
            _targetDate = State(initialValue: d.toDate(minutesFromMidnight: 12 * 60, timeZone: tz))
        } else {
            let sixMonths = LocalDate.from(date: Date(), timeZone: tz).addingMonths(6)
            _targetDate = State(initialValue: sixMonths.toDate(minutesFromMidnight: 12 * 60, timeZone: tz))
        }
        _linkedAccountId = State(initialValue: editingGoal?.linkedAccountId)
    }

    private var parsedTarget: Result<Money, AmountParseError> {
        AmountParser.parse(targetAmountText)
    }

    private var parsedCurrent: Int64? {
        let trimmed = currentAmountText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "0" { return 0 }
        if case .success(let money) = AmountParser.parse(trimmed) { return money.rupiah }
        return nil
    }

    private var canSave: Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              case .success = parsedTarget,
              parsedCurrent != nil else { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Detail Target Tabungan") {
                    TextField("Nama target (mis. Dana Darurat, Laptop Baru)", text: $name)
                    RupiahTextField(
                        placeholder: "Target nominal (mis. 10.000.000)",
                        text: $targetAmountText,
                        font: .title3.weight(.bold),
                        accentColor: PLATokens.Colors.violet
                    )
                    if case .failure(let err) = parsedTarget, !targetAmountText.isEmpty {
                        Text(err.userMessage)
                            .font(.caption)
                            .foregroundStyle(PLATokens.Colors.danger)
                    }
                    RupiahTextField(
                        placeholder: "Terkumpul saat ini (default 0)",
                        text: $currentAmountText,
                        allowZero: true,
                        font: .body.weight(.semibold),
                        accentColor: PLATokens.Colors.safe
                    )
                }

                Section("Tanggal Target & Akun (Opsional)") {
                    Toggle("Tetapkan Tanggal Target", isOn: $hasTargetDate)
                    if hasTargetDate {
                        DatePicker("Tanggal Target", selection: $targetDate, displayedComponents: .date)
                    }

                    Picker("Akun Tertaut", selection: $linkedAccountId) {
                        Text("Tidak Tertaut").tag(UUID?.none)
                        ForEach(store.activeAccounts) { acc in
                            Text(acc.name).tag(Optional(acc.id))
                        }
                    }
                }
            }
            .navigationTitle(editingGoal == nil ? "Target Tabungan Baru" : "Sunting Target")
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
        }
    }

    private func save() {
        guard case .success(let target) = parsedTarget,
              let current = parsedCurrent else { return }
        let localTargetDate = hasTargetDate ? LocalDate.from(date: targetDate, timeZone: store.clock.timeZone) : nil
        let status: SavingsGoalStatus = current >= target.rupiah ? .achieved : .active

        let goal = SavingsGoal(
            id: editingGoal?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            targetAmount: target.rupiah,
            currentAmount: current,
            targetDateLocal: localTargetDate,
            linkedAccountId: linkedAccountId,
            status: status,
            createdAt: editingGoal?.createdAt ?? store.clock.now,
            updatedAt: store.clock.now
        )
        store.saveSavingsGoal(goal)
        dismiss()
    }
}

struct SavingsAllocateSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let goal: SavingsGoal
    let isWithdraw: Bool

    @State private var amountText: String = ""

    private var parsedAmount: Result<Money, AmountParseError> {
        AmountParser.parse(amountText)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    AdaptiveKeyValueRow {
                        Text("Target")
                            .foregroundStyle(.secondary)
                    } trailing: {
                        Text(goal.name).fontWeight(.semibold)
                    }
                    AdaptiveKeyValueRow {
                        Text("Terkumpul Saat Ini")
                            .foregroundStyle(.secondary)
                    } trailing: {
                        MoneyText(amount: goal.currentAmount)
                    }
                }

                Section(isWithdraw ? "Nominal Penarikan" : "Nominal Setoran") {
                    RupiahTextField(
                        placeholder: "Contoh: 500.000",
                        text: $amountText,
                        font: .title3.weight(.bold),
                        accentColor: isWithdraw ? PLATokens.Colors.coral : PLATokens.Colors.violet
                    )
                    if case .failure(let err) = parsedAmount, !amountText.isEmpty {
                        Text(err.userMessage)
                            .font(.caption)
                            .foregroundStyle(PLATokens.Colors.danger)
                    }
                }

                Section {
                    Button {
                        if case .success(let money) = parsedAmount {
                            store.adjustSavingsGoal(goal, delta: isWithdraw ? -money.rupiah : money.rupiah)
                            dismiss()
                        }
                    } label: {
                        Text(isWithdraw ? "Konfirmasi Penarikan" : "Konfirmasi Setoran")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: PLATokens.minTouchTarget)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled({
                        if case .success = parsedAmount { return false }
                        return true
                    }())
                }
            }
            .navigationTitle(isWithdraw ? "Tarik Dana" : "Setor Tabungan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal") { dismiss() }
                }
            }
        }
    }
}

// MARK: - P-04: "Bagaimana Jika" (What-If) Financial Simulator Sheet

struct WhatIfSimulatorSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var plannedAmountText: String = ""
    @State private var itemLabel: String = ""

    private var parsedAmount: Int64? {
        if case .success(let money) = AmountParser.parse(plannedAmountText) {
            return money.rupiah
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Rencana pembelian (opsional, mis. Headphone)", text: $itemLabel)
                    RupiahTextField(
                        placeholder: "Nominal rencana (mis. 750.000)",
                        text: $plannedAmountText,
                        font: .title3.weight(.bold),
                        accentColor: PLATokens.Colors.violet
                    )
                } header: {
                    Text("Simulasi \"Bagaimana Jika\"")
                } footer: {
                    Text("Simulasi ini tidak mencatat transaksi maupun mengubah saldo. Gunakan untuk melihat dampaknya terhadap anggaran periode aktif.")
                }

                if let amount = parsedAmount {
                    let sim = WhatIfSimulator.simulatePurchase(summary: store.financialSummary, plannedAmount: amount)

                    Section("Hasil Simulasi") {
                        verdictBanner(for: sim)

                        AdaptiveKeyValueRow {
                            Text("Pengeluaran Periode")
                                .foregroundStyle(.secondary)
                        } trailing: {
                            Text("\(PLAFormatters.rupiah(sim.beforeTotalExpense)) → \(PLAFormatters.rupiah(sim.afterTotalExpense))")
                                .font(.footnote.weight(.semibold))
                                .monospacedDigit()
                        }

                        if let beforeFree = sim.beforeFreeRemaining, let afterFree = sim.afterFreeRemaining {
                            AdaptiveKeyValueRow {
                                Text("Sisa Anggaran Bebas")
                                    .foregroundStyle(.secondary)
                            } trailing: {
                                Text("\(PLAFormatters.rupiah(beforeFree)) → \(PLAFormatters.rupiah(afterFree))")
                                    .font(.footnote.weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(afterFree < 0 ? PLATokens.Colors.danger : .primary)
                            }
                        }

                        if let beforeDaily = sim.beforeSafeDailyLimit, let afterDaily = sim.afterSafeDailyLimit {
                            AdaptiveKeyValueRow {
                                Text("Batas Aman Harian")
                                    .foregroundStyle(.secondary)
                            } trailing: {
                                Text("\(PLAFormatters.rupiah(beforeDaily)) → \(PLAFormatters.rupiah(afterDaily))")
                                    .font(.footnote.weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(PLATokens.Colors.accent)
                            }
                        }

                        AdaptiveKeyValueRow {
                            Text("Proyeksi Akhir Periode")
                                .foregroundStyle(.secondary)
                        } trailing: {
                            Text("\(PLAFormatters.rupiah(sim.beforeForecastTotal)) → \(PLAFormatters.rupiah(sim.afterForecastTotal))")
                                .font(.footnote.weight(.semibold))
                                .monospacedDigit()
                        }
                    }
                }
            }
            .navigationTitle("Simulasi Pembelian")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Tutup") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func verdictBanner(for sim: WhatIfSimulationResult) -> some View {
        switch sim.verdict {
        case .comfortable:
            Label(
                "Masih dalam batas aman anggaran. Batas harian Anda turun \(PLAFormatters.rupiah(sim.safeDailyDrop ?? 0))/hari.",
                systemImage: "checkmark.circle.fill"
            )
            .font(.subheadline)
            .foregroundStyle(PLATokens.Colors.safe)

        case .tightenDaily:
            Label(
                "Perlu berhemat: setelah membeli ini, batas aman harian menjadi \(PLAFormatters.rupiah(sim.afterSafeDailyLimit ?? 0))/hari.",
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.subheadline)
            .foregroundStyle(PLATokens.Colors.warning)

        case .exceedsBudget:
            Label(
                "Melebihi batas anggaran periode ini! Pertimbangkan menunda pembelian ke periode berikutnya.",
                systemImage: "xmark.octagon.fill"
            )
            .font(.subheadline)
            .foregroundStyle(PLATokens.Colors.danger)

        case .noBudgetSet:
            Label(
                "Anggaran bulanan belum diatur, tetapi total pengeluaran periode akan menjadi \(PLAFormatters.rupiah(sim.afterTotalExpense)).",
                systemImage: "info.circle.fill"
            )
            .font(.subheadline)
            .foregroundStyle(PLATokens.Colors.info)
        }
    }
}
