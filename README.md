# Personal Life Assistant (PLA)

Asisten pribadi iOS (**minimum iOS 17.0**) yang menggabungkan **tugas & pengingat otomatis**, **tagihan berulang**, dan **keuangan pribadi** dengan analisis deterministik (rule-based) **100% lokal di perangkat** — tanpa akun, tanpa server, tanpa AI API eksternal.

Dibangun dari Windows tanpa Mac lokal: logika inti diuji lewat `PLACore` (Swift Package murni), persistensi di `PLAData` (GRDB SQLite), dan paket `.ipa` unsigned dikompilasi otomatis oleh GitHub Actions (`macos-15` + XcodeGen) untuk distribusi via **SideStore**.

## Arsitektur Modul

| Modul | Peran | Dependensi | Pengujian |
|---|---|---|---|
| `Packages/PLACore` | Domain models, `Money`, `AmountParser`, `LocalDate`/`LocalDateTime`, `RecurrenceEngine`, `ReminderPlanner`, `NotificationQueuePlanner` (64 slot), `BudgetCalculator`, `Forecaster`, `InsightEngine`, `RescheduleSuggester`, `CategorySuggester`, `NaturalLanguageTaskParser`, `ReceiptOCRParser`, `SavingsGoalCalculator`, `WhatIfSimulator`, `PersonalIntelligenceEngine`, `WidgetSnapshotBuilder`, `PLAURLRoute`, SHA-256 + Backup JSON/CSV codec | Swift stdlib + Foundation (lintas platform) | Windows / Linux CI (`core-tests.yml`) / macOS CI (`≥ 85%` coverage) |
| `Packages/PLAData` | Persistensi GRDB SQLite (`v1_initial_mvp` → `v2_savings_goal` → `v3_post_mvp_recurrence_and_trials`), backup pra-migrasi otomatis, static fixture `Fixtures/pla_v1_initial_mvp.sqlite`, `FileProtectionType.completeUntilFirstUserAuthentication` | `PLACore`, `GRDB.swift` (6.x, MIT) | macOS CI (`ios-build.yml`) |
| `App/PLAApp` | UI SwiftUI iOS 17 (`@Observable`), Design System (Light/Dark + Dynamic Type AX3 + VoiceOver), 4 tab, Face ID + passcode fallback + privacy blur, rolling 64-slot `UNUserNotificationCenter` + `BGAppRefreshTask`, App Intents, Vision OCR, EventKit read-only, 4 suara kustom `.caf`, Diagnostik + probe App Group (`V-07`) | `PLACore`, `PLAData` | Archive `.ipa` di macOS CI + uji perangkat iPhone |
| `App/PLAShareExtension` | Share Extension native (`P-06`): offline Apple Vision OCR di memori + handoff teks-saja lewat App Group & deep link `pla://ocr-draft` | `PLACore`, `Vision`, `SwiftUI` | Embedded di `PlugIns/PLAShareExtension.appex` |
| `App/PLAWidgetExtension` | WidgetKit (`P-07`): Home Screen 2×2 (Sisa Anggaran), Home Screen 4×2 (Agenda & Tagihan 7 Hari), dan Lock Screen (Deadline Terdekat) | `PLACore`, `WidgetKit`, `SwiftUI` | Embedded di `PlugIns/PLAWidgetExtension.appex` |

## Fitur MVP (F-01 s.d. F-15)

- **Beranda (F-01):** Banner peringatan, tugas terlambat, agenda hari ini, tagihan ≤ 7 hari, ringkasan keuangan (bisa disamarkan saat terkunci), maks. 3 kartu insight, tambah cepat `+`.
- **Tugas & Pengingat (F-02 s.d. F-06):** Buat tugas ≤ 3 tap, Smart Reminder otomatis (H-7/H-3/H-1/Hari H/2 jam sebelum sesuai prioritas), tugas berulang (Harian/Mingguan/Bulanan dengan anchor tgl 29–31 & kabisat/Tahunan), antrean rolling 64 notifikasi + suara kustom `.caf` + aksi notifikasi + ringkasan pagi + jam tenang, reschedule cepat dengan saran hari paling longgar.
- **Keuangan & Tagihan (F-07 s.d. F-12):** Dompet (Cash/Bank/E-wallet) + transfer bebas distorsi anggaran (dengan biaya admin opsional), catat transaksi ≤ 4 tap + saran kategori dari histori, anggaran bulanan total & per kategori dengan tanggal siklus fleksibel (1–28), tagihan berulang (Tandai Lunas ≤ 2 tap / nominal variabel / lewati siklus), proyeksi akhir bulan & batas aman harian dengan proteksi cold start, kunci Face ID + fallback passcode + blur App Switcher.
- **Backup, Diagnostik & Onboarding (F-13 s.d. F-15):** Ekspor/pulihkan JSON ber-checksum SHA-256 (skema v2 kompatibel mundur v1) & ekspor CSV UTF-8 BOM via iOS Files, pembaca masa berlaku sertifikat `embedded.mobileprovision` + pengingat H-2/H-1, paket diagnostik aman bebas data pribadi, katalog preview komponen UI, onboarding 3 langkah yang dapat dilewati.

## Fitur Pasca-MVP Lengkap (Fase 5–7, `P-01..P-11`)

- **Quick Add Bahasa Natural (P-01):** Ketik *"rapat besok jam 3 sore #kerja !tinggi"* dengan pratinjau chip real-time sebelum simpan (diuji pada 100 frasa Bahasa Indonesia, SC-P2).
- **Siri Shortcuts / App Intents (P-02):** `AddTaskIntent`, `LogExpenseIntent`, dan `ScanReceiptIntent` langsung di target utama (`0` App ID tambahan).
- **Target Tabungan (P-03) & Simulasi "Bagaimana Jika" (P-04):** Migrasi SQLite `v2_savings_goal` + hitung setoran bulanan & simulasi dampak rencana pembelian tanpa mengubah saldo.
- **OCR Struk/Bukti Transfer Offline (P-05 & P-06):** `Apple Vision` (`VNRecognizeTextRequest`) + parser struk Indonesia (BCA, Mandiri, GoPay, OVO, DANA, QRIS, retail) lewat PhotosPicker, Shortcut Share Sheet (`P-05`), maupun **Share Extension Native (`P-06`)** dengan handoff teks-saja (foto tidak pernah disimpan).
- **WidgetKit Home Screen & Lock Screen (P-07):** Widget Home 2×2 (Sisa Anggaran + privasi Face ID), Home 4×2 (Agenda Hari Ini & Tagihan 7 Hari), dan Lock Screen (Deadline Terdekat) via App Group dinamis SideStore (`ALTAppGroups` / `embedded.mobileprovision`).
- **Smart Rescheduling Lanjutan (P-08) & Personal Intelligence (P-09):** Skor beban harian `(Tinggi×3 + Sedang×2 + Rendah×1)` + integrasi `EventKit` read-only opsional, serta usulan jam produktif (`R-PER-01`) dan pencegahan keterlambatan kategori (`R-PER-02`) dengan konfirmasi pengguna.
- **Recurring "Dari Tanggal Selesai" (P-10) & Peringatan Akhir Masa Trial (P-11):** Migrasi SQLite `v3` untuk siklus relatif pasca-selesai dan pengingat tegas H-3 & H-1 sebelum trial langganan terdebit.

## Dokumentasi

- [PRD v0.2](docs/PRD_v0.2.md)
- [Panduan Instalasi Tester, Extension & Auto-Refresh (SideStore)](docs/INSTALL_TESTER.md)
- [Checklist QA Perangkat Fisik & Survei Tester](docs/QA_CHECKLIST.md)
- SideStore Source URL: `https://raw.githubusercontent.com/Revlog15/personal-life-assistant/main/apps.json`
