import SwiftUI
import PLACore

/// Transfer between accounts with optional admin fee (AC-07.3 & AC-07.4).
struct TransferFormSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var sourceAccountId: UUID?
    @State private var destinationAccountId: UUID?
    @State private var amountText: String = ""
    @State private var adminFeeText: String = ""
    @State private var selectedDate: Date = Date()
    @State private var note: String = ""

    private var parsedAmount: Result<Money, AmountParseError> {
        AmountParser.parse(amountText)
    }

    private var parsedAdminFee: Result<Money, AmountParseError>? {
        let trimmed = adminFeeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return AmountParser.parse(trimmed)
    }

    private var isSameAccount: Bool {
        if let s = sourceAccountId, let d = destinationAccountId {
            return s == d
        }
        return false
    }

    private var canSave: Bool {
        guard case .success = parsedAmount,
              let s = sourceAccountId,
              let d = destinationAccountId,
              s != d else { return false }
        if let feeRes = parsedAdminFee, case .failure = feeRes {
            return false
        }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                if store.activeAccounts.count < 2 {
                    Section {
                        Text("Tambahkan minimal 2 akun aktif untuk mencatat transfer antar akun.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Akun Asal & Tujuan") {
                        Picker("Dari Akun", selection: $sourceAccountId) {
                            ForEach(store.activeAccounts) { acc in
                                Text(acc.name).tag(Optional(acc.id))
                            }
                        }

                        Picker("Ke Akun", selection: $destinationAccountId) {
                            ForEach(store.activeAccounts) { acc in
                                Text(acc.name).tag(Optional(acc.id))
                            }
                        }

                        // AC-07.4: Explicit validation if same account chosen
                        if isSameAccount {
                            Label("Pilih akun tujuan yang berbeda.", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(PLATokens.Colors.danger)
                        }
                    }

                    Section {
                        RupiahTextField(
                            placeholder: "Nominal transfer (mis. 500.000)",
                            text: $amountText,
                            font: .title3.weight(.bold),
                            accentColor: PLATokens.Colors.info
                        )

                        if case .failure(let err) = parsedAmount, !amountText.isEmpty {
                            Text(err.userMessage)
                                .font(.caption)
                                .foregroundStyle(PLATokens.Colors.danger)
                        }

                        RupiahTextField(
                            placeholder: "Biaya admin opsional (mis. 2.500)",
                            text: $adminFeeText,
                            font: .body.weight(.semibold),
                            accentColor: PLATokens.Colors.warning
                        )

                        if let feeRes = parsedAdminFee, case .failure(let err) = feeRes {
                            Text(err.userMessage)
                                .font(.caption)
                                .foregroundStyle(PLATokens.Colors.danger)
                        }

                        DatePicker("Tanggal", selection: $selectedDate, displayedComponents: .date)
                        TextField("Catatan (opsional)", text: $note)
                    } header: {
                        Text("Nominal Transfer")
                    } footer: {
                        Text("Nominal transfer tidak dihitung sebagai pengeluaran atau pemakaian anggaran. Jika biaya admin diisi, biaya tersebut dicatat sebagai pengeluaran kategori Biaya Admin.")
                    }
                }
            }
            .navigationTitle("Transfer Antar Akun")
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
                if sourceAccountId == nil {
                    sourceAccountId = store.defaultAccount?.id ?? store.activeAccounts.first?.id
                }
                if destinationAccountId == nil {
                    destinationAccountId = store.activeAccounts.first { $0.id != sourceAccountId }?.id
                }
            }
        }
    }

    private func save() {
        guard case .success(let money) = parsedAmount,
              let src = sourceAccountId,
              let dst = destinationAccountId,
              src != dst else { return }

        var feeValue: Int64? = nil
        if let feeRes = parsedAdminFee, case .success(let feeMoney) = feeRes {
            feeValue = feeMoney.rupiah
        }

        let localDate = LocalDate.from(date: selectedDate, timeZone: store.clock.timeZone)
        store.createTransfer(
            from: src,
            to: dst,
            amount: money.rupiah,
            adminFee: feeValue,
            date: localDate,
            note: note
        )
        dismiss()
    }
}
