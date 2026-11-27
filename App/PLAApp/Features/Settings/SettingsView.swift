import SwiftUI
import UIKit
import UniformTypeIdentifiers
import PLACore

/// Settings tab covering Appearance (System/Light/Dark), Notifications & Sounds, Quiet Hours, Budget Cycle,
/// Security, Backup/Export JSON/CSV, Diagnostics, and About (PRD §7.2, F-13, F-14).
struct SettingsView: View {
    @Environment(AppStore.self) private var store

    // Export / Import state (F-13)
    @State private var jsonDocument: PLAJSONDocument?
    @State private var jsonFilename: String = "pla-backup.json"
    @State private var isExportingJSON = false

    @State private var csvStartDate: Date = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var csvEndDate: Date = Date()
    @State private var csvDocument: PLACSVDocument?
    @State private var isExportingCSV = false
    @State private var showCSVRangeSheet = false

    @State private var isImportingJSON = false
    @State private var pendingRestorePreview: BackupPreview?
    @State private var backupErrorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                // 0. Appearance Mode (Light White-Blue / Dark Midnight-Blue / System)
                Section {
                    VStack(alignment: .leading, spacing: PLATokens.Spacing.sm) {
                        HStack(spacing: PLATokens.Spacing.md) {
                            PLAIconBadge(systemName: store.appearanceMode.iconName, color: PLATokens.Colors.accent, size: 30, iconFont: .caption.weight(.bold))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Tema Aplikasi")
                                    .font(.subheadline.weight(.semibold))
                                Text("Putih Biru (Terang) atau Gelap Otomatis")
                                    .font(.caption)
                                    .foregroundStyle(PLATokens.Colors.textSecondary)
                            }
                        }

                        Picker("Mode Tampilan", selection: Binding(
                            get: { store.appearanceMode },
                            set: { store.setAppearanceMode($0) }
                        )) {
                            ForEach(AppAppearanceMode.allCases) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, PLATokens.Spacing.xs)
                } header: {
                    Text("Tampilan")
                }

                // 1. Notifications & Smart Reminders
                Section("Pengingat & Notifikasi") {
                    NavigationLink {
                        NotificationSettingsDetailView()
                            .environment(store)
                    } label: {
                        HStack(spacing: PLATokens.Spacing.md) {
                            PLAIconBadge(systemName: "bell.badge.fill", color: PLATokens.Colors.accent, size: 30, iconFont: .caption.weight(.bold))
                            Text("Pola Smart Reminder & Suara")
                        }
                    }

                    Toggle(isOn: Binding(
                        get: { store.settings.morningDigestEnabled },
                        set: { val in store.updateSettings { $0.morningDigestEnabled = val } }
                    )) {
                        HStack(spacing: PLATokens.Spacing.md) {
                            PLAIconBadge(systemName: "sun.horizon.fill", color: PLATokens.Colors.accent, size: 30, iconFont: .caption.weight(.bold))
                            Text("Ringkasan Pagi (07.30)")
                        }
                    }

                    Toggle(isOn: Binding(
                        get: { store.settings.quietHoursEnabled },
                        set: { val in store.updateSettings { $0.quietHoursEnabled = val } }
                    )) {
                        HStack(spacing: PLATokens.Spacing.md) {
                            PLAIconBadge(systemName: "moon.zzz.fill", color: PLATokens.Colors.accent, size: 30, iconFont: .caption.weight(.bold))
                            Text("Jam Tenang (\(PLAFormatters.time24(store.settings.quietStartMinutes)) - \(PLAFormatters.time24(store.settings.quietEndMinutes)))")
                        }
                    }

                    NavigationLink {
                        FocusModeGuideView()
                    } label: {
                        HStack(spacing: PLATokens.Spacing.md) {
                            PLAIconBadge(systemName: "moon.fill", color: PLATokens.Colors.accent, size: 30, iconFont: .caption.weight(.bold))
                            Text("Panduan Agar Tidak Terblokir Focus / DND")
                        }
                    }

                    NavigationLink {
                        SiriAndShortcutsGuideView()
                    } label: {
                        HStack(spacing: PLATokens.Spacing.md) {
                            PLAIconBadge(systemName: "mic.badge.plus", color: PLATokens.Colors.accent, size: 30, iconFont: .caption.weight(.bold))
                            Text("Siri Shortcuts & OCR Share Sheet")
                        }
                    }

                    Toggle(isOn: Binding(
                        get: { store.settings.useCalendarForReschedule },
                        set: { enabled in
                            if enabled {
                                _Concurrency.Task {
                                    let ok = await store.calendarService.requestReadAccess()
                                    store.updateSettings { $0.useCalendarForReschedule = ok }
                                }
                            } else {
                                store.updateSettings { $0.useCalendarForReschedule = false }
                            }
                        }
                    )) {
                        HStack(spacing: PLATokens.Spacing.md) {
                            PLAIconBadge(systemName: "calendar", color: PLATokens.Colors.accent, size: 30, iconFont: .caption.weight(.bold))
                            Text("Pertimbangkan Apple Calendar saat Reschedule")
                        }
                    }

                    if store.settings.preferredReminderMinutes != nil || !store.settings.extraEarlyReminderDaysByCategory.isEmpty {
                        Button("Reset Penyesuaian Personal Intelligence") {
                            store.updateSettings {
                                $0.preferredReminderMinutes = nil
                                $0.extraEarlyReminderDaysByCategory = [:]
                            }
                            store.showToast("Pola pengingat kembali ke default")
                        }
                        .foregroundStyle(PLATokens.Colors.warning)
                    }

                    if store.notificationAuthStatus == .denied {
                        Button {
                            store.notificationAdapter.openSystemSettings()
                        } label: {
                            Label("Izin Notifikasi Ditolak: Buka Settings iOS", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(PLATokens.Colors.warning)
                        }
                    } else if store.notificationAuthStatus == .notDetermined {
                        Button("Aktifkan Izin Notifikasi") {
                            _Concurrency.Task { await store.requestNotificationPermission() }
                        }
                    }
                }

                // 2. Budget Cycle & Security
                financeAndSecuritySection

                // 3. Data & Backup via iOS Files (F-13)
                Section {
                    Button {
                        prepareJSONBackup()
                    } label: {
                        HStack(spacing: PLATokens.Spacing.md) {
                            PLAIconBadge(systemName: "square.and.arrow.up.on.square.fill", color: PLATokens.Colors.accent, size: 30, iconFont: .caption.weight(.bold))
                            Text("Backup Lengkap (JSON)")
                                .foregroundStyle(PLATokens.Colors.textPrimary)
                        }
                    }

                    Button {
                        isImportingJSON = true
                    } label: {
                        HStack(spacing: PLATokens.Spacing.md) {
                            PLAIconBadge(systemName: "arrow.counterclockwise.circle.fill", color: PLATokens.Colors.safe, size: 30, iconFont: .caption.weight(.bold))
                            Text("Pulihkan Backup (JSON)")
                                .foregroundStyle(PLATokens.Colors.textPrimary)
                        }
                    }

                    Button {
                        showCSVRangeSheet = true
                    } label: {
                        HStack(spacing: PLATokens.Spacing.md) {
                            PLAIconBadge(systemName: "tablecells.fill", color: PLATokens.Colors.accent, size: 30, iconFont: .caption.weight(.bold))
                            Text("Ekspor Transaksi (CSV)")
                                .foregroundStyle(PLATokens.Colors.textPrimary)
                        }
                    }
                } header: {
                    Text("Data & Backup (iOS Files)")
                } footer: {
                    Text("Penting untuk pengguna SideStore: selalu ekspor Backup JSON sebelum mengganti Apple ID atau menghapus aplikasi.")
                }

                // 4. Diagnostics & Tester Feedback (F-14)
                Section("Diagnostik & Masukan") {
                    NavigationLink {
                        DiagnosticsView()
                            .environment(store)
                    } label: {
                        HStack(spacing: PLATokens.Spacing.md) {
                            PLAIconBadge(systemName: "stethoscope", color: PLATokens.Colors.accent, size: 30, iconFont: .caption.weight(.bold))
                            Text("Diagnostik, Sideload & Kirim Masukan")
                        }
                    }
                }

                // 5. About & Sideload Expiry (AC-14.1)
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(PLATokens.Colors.canvas)
            .contentMargins(.bottom, PLATokens.floatingDockClearance, for: .scrollContent)
            .navigationTitle("Pengaturan")
            // JSON Backup FileExporter (AC-13.1)
            .fileExporter(
                isPresented: $isExportingJSON,
                document: jsonDocument,
                contentType: .json,
                defaultFilename: jsonFilename
            ) { result in
                switch result {
                case .success:
                    store.showToast("Backup JSON berhasil disimpan")
                case .failure(let err):
                    backupErrorMessage = "Gagal menyimpan backup: \(err.localizedDescription)"
                }
            }
            // CSV FileExporter (AC-13.2)
            .fileExporter(
                isPresented: $isExportingCSV,
                document: csvDocument,
                contentType: .commaSeparatedText,
                defaultFilename: "pla-transaksi-\(store.today.isoString).csv"
            ) { result in
                switch result {
                case .success:
                    store.showToast("File CSV berhasil diekspor")
                case .failure(let err):
                    backupErrorMessage = "Gagal mengekspor CSV: \(err.localizedDescription)"
                }
            }
            // JSON Restore FileImporter (AC-13.3 & AC-13.4)
            .fileImporter(
                isPresented: $isImportingJSON,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                handleImportResult(result)
            }
            .sheet(isPresented: $showCSVRangeSheet) {
                csvExportRangeSheet
            }
            .sheet(item: Binding(
                get: { pendingRestorePreview.map(IdentifiedBackupPreview.init) },
                set: { if $0 == nil { pendingRestorePreview = nil } }
            )) { wrapper in
                restorePreviewSheet(wrapper.preview)
            }
            .alert("Backup / Restore", isPresented: Binding(
                get: { backupErrorMessage != nil },
                set: { if !$0 { backupErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { backupErrorMessage = nil }
            } message: {
                Text(backupErrorMessage ?? "")
            }
        }
    }

    @ViewBuilder
    private var financeAndSecuritySection: some View {
        Section {
            Stepper(
                "Mulai Siklus Anggaran: Tanggal \(store.settings.budgetCycleStartDay)",
                value: Binding(
                    get: { store.settings.budgetCycleStartDay },
                    set: { val in store.updateSettings { $0.budgetCycleStartDay = val } }
                ),
                in: 1...28
            )

            Toggle("Kunci Tab Keuangan (\(store.authService.biometryDisplayName()))", isOn: Binding(
                get: { store.settings.financeLockEnabled },
                set: { val in store.updateSettings { $0.financeLockEnabled = val } }
            ))

            if store.settings.financeLockEnabled {
                Picker("Kunci Otomatis Saat Keluar", selection: Binding(
                    get: { store.settings.autoLockTimeout },
                    set: { val in store.updateSettings { $0.autoLockTimeout = val } }
                )) {
                    Text("Segera").tag(AutoLockTimeout.immediate)
                    Text("1 Menit").tag(AutoLockTimeout.oneMinute)
                    Text("5 Menit").tag(AutoLockTimeout.fiveMinutes)
                }

                Toggle("Tampilkan Status Anggaran Saat Terkunci", isOn: Binding(
                    get: { store.settings.showBudgetStatusWhenLocked },
                    set: { val in store.updateSettings { $0.showBudgetStatusWhenLocked = val } }
                ))
            }
        } header: {
            Text("Keuangan & Keamanan")
        } footer: {
            Text("Periode aktif saat ini: \(PLAFormatters.periodRange(store.activePeriod)). Kunci Keuangan otomatis mendukung cadangan Passcode perangkat.")
        }
    }

    @ViewBuilder
    private var aboutSection: some View {
        Section("Tentang Aplikasi") {
            AdaptiveKeyValueRow {
                Text("Versi")
            } trailing: {
                let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
                let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
                Text("\(v) (Build \(b))")
                    .foregroundStyle(PLATokens.Colors.textSecondary)
            }

            AdaptiveKeyValueRow {
                Text("Masa Berlaku Sideload")
            } trailing: {
                Text(store.sideloadInfo.summaryText(today: store.today))
                    .font(.footnote)
                    .foregroundStyle(store.sideloadInfo.shouldShowBanner(on: store.today) ? PLATokens.Colors.warning : PLATokens.Colors.textSecondary)
                    .multilineTextAlignment(.trailing)
            }

            AdaptiveKeyValueRow {
                Text("Privasi")
            } trailing: {
                Text("100% Lokal & Offline")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(PLATokens.Colors.safe)
            }
        }
    }

    private func prepareJSONBackup() {
        do {
            let data = try store.exportBackupJSON()
            jsonFilename = BackupCodec.suggestedFilename(at: store.currentDateTime)
            jsonDocument = PLAJSONDocument(data: data)
            isExportingJSON = true
        } catch {
            backupErrorMessage = "Gagal membuat file backup: \(error.localizedDescription)"
        }
    }

    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let err):
            backupErrorMessage = "Gagal membuka file: \(err.localizedDescription)"
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                switch store.validateBackupFile(data: data) {
                case .success(let preview):
                    pendingRestorePreview = preview
                case .failure(let codecError):
                    // AC-13.4: Abort without modifying existing data
                    backupErrorMessage = codecError.userMessage
                }
            } catch {
                backupErrorMessage = "File tidak dapat dibaca: \(error.localizedDescription)"
            }
        }
    }

    private var csvExportRangeSheet: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Dari Tanggal", selection: $csvStartDate, displayedComponents: .date)
                    DatePicker("Sampai Tanggal", selection: $csvEndDate, displayedComponents: .date)
                } header: {
                    Text("Rentang Tanggal Transaksi")
                } footer: {
                    Text("Format UTF-8 dengan BOM agar rapi dibuka langsung di Microsoft Excel Windows maupun Apple Numbers.")
                }

                Section {
                    Button {
                        let start = LocalDate.from(date: csvStartDate, timeZone: store.clock.timeZone)
                        let end = LocalDate.from(date: csvEndDate, timeZone: store.clock.timeZone)
                        let data = store.exportTransactionsCSV(from: min(start, end), to: max(start, end))
                        csvDocument = PLACSVDocument(data: data)
                        showCSVRangeSheet = false
                        isExportingCSV = true
                    } label: {
                        Label("Ekspor CSV ke Files", systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: PLATokens.minTouchTarget)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .navigationTitle("Ekspor CSV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal") { showCSVRangeSheet = false }
                }
            }
        }
    }

    private func restorePreviewSheet(_ preview: BackupPreview) -> some View {
        NavigationStack {
            Form {
                Section("Ringkasan Isi Backup (Terverifikasi SHA-256)") {
                    AdaptiveKeyValueRow { Text("Versi Skema") } trailing: { Text("v\(preview.exportSchemaVersion)") }
                    AdaptiveKeyValueRow { Text("Jumlah Tugas") } trailing: { Text("\(preview.taskCount)") }
                    AdaptiveKeyValueRow { Text("Jumlah Transaksi") } trailing: { Text("\(preview.transactionCount)") }
                    AdaptiveKeyValueRow { Text("Jumlah Tagihan") } trailing: { Text("\(preview.billCount)") }
                    AdaptiveKeyValueRow { Text("Jumlah Target Tabungan") } trailing: { Text("\(preview.savingsGoalCount)") }
                    AdaptiveKeyValueRow { Text("Jumlah Akun") } trailing: { Text("\(preview.accountCount)") }
                    AdaptiveKeyValueRow { Text("Total Kekayaan Cair") } trailing: { MoneyText(amount: preview.totalLiquidWealth) }
                }

                Section {
                    Label(
                        "Memulihkan backup akan menimpa seluruh data saat ini secara atomik. Aplikasi akan membuat cadangan internal darurat terlebih dahulu.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.footnote)
                    .foregroundStyle(PLATokens.Colors.warning)

                    Button(role: .destructive) {
                        do {
                            try store.restoreBackup(preview: preview)
                            pendingRestorePreview = nil
                        } catch {
                            pendingRestorePreview = nil
                            backupErrorMessage = "Pemulihan gagal: \(error.localizedDescription)"
                        }
                    } label: {
                        Text("Pulihkan & Timpa Data Saat Ini")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: PLATokens.minTouchTarget)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .navigationTitle("Pratinjau Backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal") { pendingRestorePreview = nil }
                }
            }
        }
    }
}

private struct IdentifiedBackupPreview: Identifiable {
    let id = UUID()
    let preview: BackupPreview
}

// MARK: - Sub-Screens for Notifications & Focus Mode Guide

struct NotificationSettingsDetailView: View {
    @Environment(AppStore.self) private var store

    private let soundOptions: [String] = [
        ReminderSound.plaDefault.rawValue,
        ReminderSound.plaUrgent.rawValue,
        ReminderSound.plaBill.rawValue,
        ReminderSound.plaDigest.rawValue,
        ReminderSound.systemDefault.rawValue,
        ReminderSound.none.rawValue
    ]

    var body: some View {
        Form {
            Section("Smart Reminder: Prioritas Tinggi") {
                Toggle("H-7 (09.00)", isOn: prefBinding(\.highEnableH7))
                Toggle("H-3 (09.00)", isOn: prefBinding(\.highEnableH3))
                Toggle("H-1 (09.00)", isOn: prefBinding(\.highEnableH1))
                Toggle("Hari H (08.00)", isOn: prefBinding(\.highEnableDayOf))
                Toggle("2 Jam Sebelum Deadline", isOn: prefBinding(\.highEnableTwoHoursBefore))
            }

            Section("Smart Reminder: Prioritas Sedang & Rendah") {
                Toggle("Sedang: H-3 (09.00)", isOn: prefBinding(\.mediumEnableH3))
                Toggle("Sedang: H-1 (09.00)", isOn: prefBinding(\.mediumEnableH1))
                Toggle("Sedang: Hari H (08.00)", isOn: prefBinding(\.mediumEnableDayOf))
                Toggle("Rendah: Hari H (09.00)", isOn: prefBinding(\.lowEnableDayOf))
            }

            Section("Smart Reminder: Tagihan") {
                Toggle("Tagihan: H-3 (09.00)", isOn: prefBinding(\.billEnableH3))
                Toggle("Tagihan: H-1 (09.00)", isOn: prefBinding(\.billEnableH1))
                Toggle("Tagihan: Hari H (08.00)", isOn: prefBinding(\.billEnableDayOf))
            }

            Section {
                soundPickerRow("Tugas Standar", keyPath: \.defaultTaskSound)
                soundPickerRow("Tugas Prioritas Tinggi", keyPath: \.urgentTaskSound)
                soundPickerRow("Tagihan", keyPath: \.billSound)
                soundPickerRow("Ringkasan Pagi", keyPath: \.digestSound)
            } header: {
                Text("Suara Kustom (.caf)")
            } footer: {
                Text("Ketuk ikon speaker untuk mendengar pratinjau suara notifikasi. Perubahan pola Smart Reminder berlaku untuk tugas baru.")
            }
        }
        .contentMargins(.bottom, PLATokens.floatingDockClearance, for: .scrollContent)
        .navigationTitle("Pengingat & Suara")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func prefBinding(_ keyPath: WritableKeyPath<SmartReminderPreferences, Bool>) -> Binding<Bool> {
        Binding(
            get: { store.settings.reminderPreferences[keyPath: keyPath] },
            set: { val in store.updateSettings { $0.reminderPreferences[keyPath: keyPath] = val } }
        )
    }

    private func soundPickerRow(_ title: String, keyPath: WritableKeyPath<UserSettings, String>) -> some View {
        HStack {
            Picker(title, selection: Binding(
                get: { store.settings[keyPath: keyPath] },
                set: { val in store.updateSettings { $0[keyPath: keyPath] = val } }
            )) {
                ForEach(soundOptions, id: \.self) { name in
                    Text(PLAFormatters.soundLabel(name)).tag(name)
                }
            }

            Button {
                store.notificationAdapter.playPreviewSound(named: store.settings[keyPath: keyPath])
            } label: {
                Image(systemName: "speaker.wave.2.fill")
                    .frame(minWidth: PLATokens.minTouchTarget, minHeight: PLATokens.minTouchTarget)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Putar pratinjau suara \(title)")
        }
    }
}

/// 3-step Focus / Do Not Disturb guide (PRD §9.5).
struct FocusModeGuideView: View {
    var body: some View {
        Form {
            Section {
                Text("Karena PLA dipasang dengan sertifikat Apple ID gratis (tanpa entitlement Time Sensitive khusus), ikuti 3 langkah ini agar notifikasi penting tetap masuk saat mode Focus atau Do Not Disturb aktif:")
                    .font(.subheadline)
                    .foregroundStyle(PLATokens.Colors.textSecondary)
            }

            Section("3 Langkah Mengizinkan PLA di Focus Mode") {
                Label("1. Buka aplikasi Settings iPhone, lalu pilih Focus.", systemImage: "1.circle.fill")
                Label("2. Pilih mode Focus yang biasa dipakai (mis. Do Not Disturb atau Work), lalu ketuk Apps.", systemImage: "2.circle.fill")
                Label("3. Pilih Allow Notifications From, ketuk Add, lalu pilih Life Assistant.", systemImage: "3.circle.fill")
            }

            Section {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("Buka Settings iPhone", systemImage: "gear")
                        .frame(maxWidth: .infinity, minHeight: PLATokens.minTouchTarget)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .contentMargins(.bottom, PLATokens.floatingDockClearance, for: .scrollContent)
        .navigationTitle("Panduan Focus Mode")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// P-02 & P-05: Guide for Siri Shortcuts & Share Sheet OCR.
struct SiriAndShortcutsGuideView: View {
    var body: some View {
        Form {
            Section {
                Label("\"Hey Siri, Tambah tugas di Life Assistant\" (atau \"Add task in Life Assistant\")", systemImage: "checklist")
                Label("\"Hey Siri, Catat pengeluaran di Life Assistant\"", systemImage: "banknote")
                Label("\"Hey Siri, Scan struk di Life Assistant\"", systemImage: "doc.text.viewfinder")
            } header: {
                Text("Siri & Action Button (App Intents)")
            } footer: {
                Text("Siri akan memandu langkah demi langkah: kegiatan apa, dengan siapa atau catatan, tanggal dan jam, tingkat prioritas, serta kategori. Mendukung frasa Indonesia dan Inggris.")
            }

            Section {
                Label("1. Dari screenshot bukti transfer BCA/Mandiri/GoPay/OVO/DANA atau Photos, ketuk Share lalu pilih 'Catat ke Life Assistant'.", systemImage: "1.circle.fill")
                Label("2. Periksa hasil OCR offline lalu ketuk 'Simpan Draft & Buka Life Assistant'.", systemImage: "2.circle.fill")
                Label("3. Alternatif 0-Extension (Shortcuts): buat Shortcut baru, aktifkan 'Show in Share Sheet' (Images), lalu tambahkan aksi 'Scan Struk ke Life Assistant'.", systemImage: "3.circle.fill")
            } header: {
                Text("Share Extension Native & Shortcut OCR")
            } footer: {
                Text("Semua pemrosesan OCR memakai Apple Vision secara offline di memori dan foto tidak pernah disimpan di aplikasi.")
            }
        }
        .contentMargins(.bottom, PLATokens.floatingDockClearance, for: .scrollContent)
        .navigationTitle("Siri & Shortcuts")
        .navigationBarTitleDisplayMode(.inline)
    }
}
