import SwiftUI
import PLACore

/// 3-step skippable onboarding (PRD F-15 / AC-15.1 & AC-15.2) with vibrant step headers & dot-formatted Rupiah inputs.
struct OnboardingView: View {
    @Environment(AppStore.self) private var store

    @State private var step: Int = 0
    @State private var cashText: String = ""
    @State private var bankText: String = ""
    @State private var budgetText: String = ""
    @State private var notificationRequested: Bool = false

    private var stepAccent: Color {
        switch step {
        case 0: return PLATokens.Colors.accent
        case 1: return PLATokens.Colors.violet
        default: return PLATokens.Colors.indigo
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(value: Double(step + 1), total: 3.0)
                    .tint(stepAccent)
                    .padding(.horizontal, PLATokens.Spacing.lg)
                    .padding(.top, PLATokens.Spacing.sm)

                Form {
                    if step == 0 {
                        stepAccounts
                    } else if step == 1 {
                        stepBudget
                    } else {
                        stepNotifications
                    }
                }
                .scrollContentBackground(.hidden)
                .background(PLATokens.Colors.canvas)
            }
            .background(PLATokens.Colors.canvas)
            .navigationTitle(stepTitle)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Lewati") {
                        if step < 2 {
                            step += 1
                        } else {
                            finishOnboarding()
                        }
                    }
                    .frame(minHeight: PLATokens.minTouchTarget)
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: PLATokens.Spacing.sm) {
                    Button {
                        if step < 2 {
                            step += 1
                        } else {
                            finishOnboarding()
                        }
                    } label: {
                        Text(step < 2 ? "Lanjut" : "Mulai Gunakan PLA")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: PLATokens.minTouchTarget)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(stepAccent)

                    if step == 0 {
                        Button("Lewati Semua Pengaturan Awal") {
                            store.skipOnboarding()
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(minHeight: PLATokens.minTouchTarget)
                    }
                }
                .padding(.horizontal, PLATokens.Spacing.lg)
                .padding(.vertical, PLATokens.Spacing.md)
                .background(.bar)
            }
        }
    }

    private var stepTitle: String {
        switch step {
        case 0: return "Akun Awal"
        case 1: return "Anggaran Bulanan"
        default: return "Pengingat Otomatis"
        }
    }

    @ViewBuilder
    private var stepAccounts: some View {
        Section {
            PLAHeroCard(gradient: PLATokens.heroGradient) {
                HStack(spacing: PLATokens.Spacing.md) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.20))
                            .frame(width: 48, height: 48)
                        Image(systemName: "lock.shield.fill")
                            .font(.title2)
                            .foregroundStyle(Color.white)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("100% Privat & Offline")
                            .font(.headline)
                            .foregroundStyle(Color.white)
                        Text("Semua data disimpan lokal di iPhone Anda — tanpa akun, tanpa server.")
                            .font(.footnote)
                            .foregroundStyle(Color.white.opacity(0.86))
                    }
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }

        Section {
            VStack(alignment: .leading, spacing: PLATokens.Spacing.xs) {
                HStack(spacing: PLATokens.Spacing.sm) {
                    PLAIconBadge(systemName: "banknote.fill", color: PLATokens.Colors.safe, size: 28, iconFont: .caption.weight(.bold))
                    Text("Tunai")
                        .font(.subheadline.weight(.semibold))
                }
                RupiahTextField(
                    placeholder: "Contoh: 250.000",
                    text: $cashText,
                    font: .body.weight(.semibold),
                    accentColor: PLATokens.Colors.safe
                )
            }
            VStack(alignment: .leading, spacing: PLATokens.Spacing.xs) {
                HStack(spacing: PLATokens.Spacing.sm) {
                    PLAIconBadge(systemName: "building.columns.fill", color: PLATokens.Colors.info, size: 28, iconFont: .caption.weight(.bold))
                    Text("Bank")
                        .font(.subheadline.weight(.semibold))
                }
                RupiahTextField(
                    placeholder: "Contoh: 2.500.000",
                    text: $bankText,
                    font: .body.weight(.semibold),
                    accentColor: PLATokens.Colors.info
                )
            }
        } header: {
            Text("Saldo Awal (Opsional)")
        } footer: {
            Text("Akun E-wallet dan rekening tambahan dapat ditambahkan kapan saja di tab Keuangan.")
        }
    }

    @ViewBuilder
    private var stepBudget: some View {
        Section {
            PLAHeroCard(gradient: PLATokens.savingsGradient) {
                HStack(spacing: PLATokens.Spacing.md) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.20))
                            .frame(width: 48, height: 48)
                        Image(systemName: "chart.bar.doc.horizontal.fill")
                            .font(.title2)
                            .foregroundStyle(Color.white)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Kontrol Belanja Otomatis")
                            .font(.headline)
                            .foregroundStyle(Color.white)
                        Text("PLA menghitung batas aman harian & proyeksi akhir bulan secara deterministik.")
                            .font(.footnote)
                            .foregroundStyle(Color.white.opacity(0.86))
                    }
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }

        Section {
            RupiahTextField(
                placeholder: "Contoh: 3.000.000",
                text: $budgetText,
                font: .title3.weight(.bold),
                accentColor: PLATokens.Colors.violet
            )
            if let parsed = parseOptionalPositiveAmount(budgetText) {
                Text("Batas bulanan: \(PLAFormatters.rupiah(parsed))")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(PLATokens.Colors.violet)
            }
        } header: {
            Text("Batas Anggaran Total (Opsional)")
        } footer: {
            Text("Siklus default dimulai tanggal 1 setiap bulan. Anda dapat mengubah ke tanggal gajian (1–28) di Pengaturan.")
        }
    }

    @ViewBuilder
    private var stepNotifications: some View {
        Section {
            VStack(alignment: .leading, spacing: PLATokens.Spacing.md) {
                HStack(spacing: PLATokens.Spacing.md) {
                    PLAIconBadge(systemName: "bell.badge.fill", color: PLATokens.Colors.indigo, size: 46, iconFont: .title3.weight(.semibold))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Smart Reminder & Tagihan")
                            .font(.headline)
                        Text("Pengingat H-7, H-3, H-1 hingga Hari H otomatis.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Text("Jam tenang aktif pukul 22.00 – 07.00 sehingga notifikasi otomatis tidak mengganggu waktu istirahat.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, PLATokens.Spacing.xs)
        }

        Section {
            Button {
                _Concurrency.Task {
                    await store.requestNotificationPermission()
                    notificationRequested = true
                }
            } label: {
                Label(
                    notificationRequested ? "Izin Notifikasi Diminta" : "Aktifkan Notifikasi Pengingat",
                    systemImage: notificationRequested ? "checkmark.circle.fill" : "bell.fill"
                )
                .frame(maxWidth: .infinity, minHeight: PLATokens.minTouchTarget)
            }
            .buttonStyle(.borderedProminent)
            .tint(notificationRequested ? PLATokens.Colors.safe : PLATokens.Colors.indigo)
            .disabled(notificationRequested)
        } footer: {
            Text("Anda tetap dapat menggunakan seluruh aplikasi walau menunda izin notifikasi.")
        }
    }

    private func parseOptionalPositiveAmount(_ raw: String) -> Int64? {
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        if case .success(let money) = AmountParser.parse(raw) {
            return money.rupiah
        }
        return nil
    }

    private func finishOnboarding() {
        let cash = parseOptionalPositiveAmount(cashText) ?? 0
        let bank = parseOptionalPositiveAmount(bankText) ?? 0
        let budget = parseOptionalPositiveAmount(budgetText)
        store.completeOnboarding(cashBalance: cash, bankBalance: bank, monthlyBudget: budget)
    }
}
