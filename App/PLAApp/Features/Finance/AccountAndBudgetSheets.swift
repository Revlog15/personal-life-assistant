import SwiftUI
import PLACore

/// Add/Edit Account sheet (F-07 / AC-07.1).
struct AccountFormSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let editingAccount: Account?

    @State private var name: String
    @State private var type: AccountType
    @State private var initialBalanceText: String
    @State private var isDefault: Bool
    @State private var colorToken: String

    private let colorOptions = ["teal", "blue", "green", "orange", "purple", "gray"]

    init(editingAccount: Account? = nil) {
        self.editingAccount = editingAccount
        _name = State(initialValue: editingAccount?.name ?? "")
        _type = State(initialValue: editingAccount?.type ?? .ewallet)
        _initialBalanceText = State(initialValue: editingAccount.map { String($0.initialBalance) } ?? "0")
        _isDefault = State(initialValue: editingAccount?.isDefault ?? false)
        _colorToken = State(initialValue: editingAccount?.colorToken ?? "teal")
    }

    private var parsedInitialBalance: Int64? {
        let trimmed = initialBalanceText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "0" { return 0 }
        if case .success(let money) = AmountParser.parse(trimmed) {
            return money.rupiah
        }
        return nil
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && parsedInitialBalance != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Informasi Akun") {
                    TextField("Nama akun (mis. BCA, GoPay, Tunai)", text: $name)
                    Picker("Tipe", selection: $type) {
                        Text("Tunai").tag(AccountType.cash)
                        Text("Bank").tag(AccountType.bank)
                        Text("E-wallet").tag(AccountType.ewallet)
                    }
                    .pickerStyle(.segmented)
                }

                Section("Saldo Awal (≥ Rp0)") {
                    RupiahTextField(
                        placeholder: "0",
                        text: $initialBalanceText,
                        allowZero: true,
                        font: .title3.weight(.bold),
                        accentColor: PLATokens.color(forToken: colorToken)
                    )
                    if let bal = parsedInitialBalance {
                        Text("Saldo awal: \(PLAFormatters.rupiah(bal))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Masukkan angka bulat ≥ 0.")
                            .font(.caption)
                            .foregroundStyle(PLATokens.Colors.danger)
                    }
                }

                Section("Tampilan & Default") {
                    Toggle("Jadikan Akun Utama (Default)", isOn: $isDefault)

                    Picker("Warna Penanda", selection: $colorToken) {
                        ForEach(colorOptions, id: \.self) { token in
                            Text(token.capitalized).tag(token)
                        }
                    }
                }
            }
            .navigationTitle(editingAccount == nil ? "Akun Baru" : "Sunting Akun")
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

    private func iconForType(_ type: AccountType) -> String {
        switch type {
        case .cash: return "banknote.fill"
        case .bank: return "building.columns.fill"
        case .ewallet: return "iphone.gen3"
        }
    }

    private func save() {
        guard let bal = parsedInitialBalance else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let account = Account(
            id: editingAccount?.id ?? UUID(),
            name: trimmed,
            type: type,
            initialBalance: bal,
            iconName: iconForType(type),
            colorToken: colorToken,
            isDefault: isDefault,
            isArchived: editingAccount?.isArchived ?? false,
            sortOrder: editingAccount?.sortOrder ?? (store.accounts.count + 1),
            createdAt: editingAccount?.createdAt ?? store.clock.now
        )
        store.saveAccount(account)
        dismiss()
    }
}

/// Set/Edit Total or Per-Category Monthly Budget sheet (F-09 / AC-09.1).
struct BudgetFormSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let category: PLACategory?
    let currentAmount: Int64?

    @State private var amountText: String

    init(category: PLACategory?, currentAmount: Int64?) {
        self.category = category
        self.currentAmount = currentAmount
        _amountText = State(initialValue: currentAmount.map { String($0) } ?? "")
    }

    private var parsedResult: Result<Money, AmountParseError> {
        AmountParser.parse(amountText)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    RupiahTextField(
                        placeholder: "Contoh: 3.000.000",
                        text: $amountText,
                        font: .title3.weight(.bold),
                        accentColor: PLATokens.Colors.accent
                    )

                    switch parsedResult {
                    case .success(let money):
                        Text("Batas periode aktif: \(PLAFormatters.rupiah(money.rupiah))")
                            .font(.caption)
                            .foregroundStyle(PLATokens.Colors.accent)
                    case .failure(let err):
                        if !amountText.isEmpty {
                            Text(err.userMessage)
                                .font(.caption)
                                .foregroundStyle(PLATokens.Colors.danger)
                        }
                    }
                } header: {
                    Text(category == nil ? "Anggaran Total Bulanan" : "Anggaran Kategori: \(category?.name ?? "")")
                } footer: {
                    Text("Berlaku mulai periode \(store.activePeriod.periodKey) ke depan tanpa mengubah histori bulan sebelumnya.")
                }

                if currentAmount != nil,
                   let activeBudget = BudgetCalculator.resolveEffectiveBudget(
                       categoryId: category?.id,
                       periodKey: store.activePeriod.periodKey,
                       budgets: store.budgets
                   ) {
                    Section {
                        Button("Hapus Batas Anggaran Ini", role: .destructive) {
                            store.deleteBudget(id: activeBudget.id)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(category == nil ? "Anggaran Bulanan" : category!.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Simpan") {
                        if case .success(let money) = parsedResult {
                            store.saveBudget(categoryId: category?.id, amount: money.rupiah)
                            dismiss()
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled({
                        if case .success = parsedResult { return false }
                        return true
                    }())
                }
            }
        }
    }
}
