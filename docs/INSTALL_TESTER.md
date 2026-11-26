# Panduan Instalasi, Extension & Auto-Refresh Personal Life Assistant (SideStore)

Panduan lengkap untuk developer dan tester (iPhone dengan **iOS 17.0+**, Apple ID gratis, setup awal sekali lewat PC Windows).

> **Penting sebelum mulai:**
> - Gunakan **Apple ID sendiri** (disarankan membuat Apple ID sekunder khusus sideload, jangan berbagi Apple ID).
> - Jika suatu saat ingin ganti Apple ID di SideStore atau menghapus app, **wajib backup JSON dulu** di `Pengaturan > Data & Backup > Backup Lengkap (JSON)` karena ganti Apple ID mengubah Bundle ID dan container data (`V-09`).

---

## 1. Setup Awal (Hanya 1× Memakai PC Windows)

1. **Install iTunes (bukan versi Microsoft Store)** di PC Windows dari situs resmi Apple (`apple.com/itunes`) agar driver USB iPhone tersedia (`V-18`).
2. **Install `iloader`** di PC Windows dari panduan resmi [docs.sidestore.io](https://docs.sidestore.io).
3. **Install `LocalDevVPN`** dari App Store langsung di iPhone.
4. Sambungkan iPhone ke PC via kabel USB, buka kunci layar, dan tap **Trust** di iPhone.
5. Buka **`iloader`** di PC → login dengan Apple ID Anda → pilih **Install SideStore** → `iloader` akan memasang SideStore sekaligus membuat dan menaruh **pairing file** otomatis.
6. Di iPhone, aktifkan **Developer Mode**: `Settings > Privacy & Security > Developer Mode` → nyalakan dan restart iPhone.
7. Percayai profil developer: `Settings > General > VPN & Device Management` → pilih Apple ID Anda → tap **Trust**.
8. Buka **`LocalDevVPN`** di iPhone dan tap **Connect** (wajib nyala setiap kali install/refresh di SideStore).
9. Buka **SideStore** → login dengan Apple ID yang sama → tap **Refresh All** pada SideStore itu sendiri terlebih dahulu.

---

## 2. Pasang Personal Life Assistant (PLA)

### Cara A — Via Source SideStore (Disarankan, Update Otomatis Terlihat)
1. Pastikan **LocalDevVPN** dalam keadaan **Connected**.
2. Buka **SideStore** → tab **Sources** → tap **`+`**.
3. Tempel URL source berikut:
   ```text
   https://raw.githubusercontent.com/Revlog15/personal-life-assistant/main/apps.json
   ```
   *(Atau buka langsung di Safari iPhone: `sidestore://source?url=https://raw.githubusercontent.com/Revlog15/personal-life-assistant/main/apps.json`)*
4. Buka **Personal Life Assistant Source** → pilih **Life Assistant** → tap **GET**.

### Pilihan App Extensions saat Install `v2.1.0` (Kuota App ID — `V-06` & `V-07`)
Rilis **`v2.1.0`** menyertakan 2 extension bawaan (**Share Extension OCR `P-06`** + **WidgetKit `P-07`**). Saat memasang di SideStore, akan muncul pilihan:
- **Keep App Extensions (Disarankan untuk fitur penuh):** memakai **3 dari 10 App ID** mingguan (`PLAApp` + `PLAShareExtension` + `PLAWidgetExtension`). Mengaktifkan Widget Home/Lock Screen dan Share Sheet native.
- **Remove App Extensions (Hemat App ID):** hanya memakai **1 App ID**. Aplikasi utama tetap 100% normal dan fitur scan struk tetap jalan lewat **Shortcut Share Sheet (`P-05`)**.
- *(Fallback permanen)*: rilis **`v2.0.0`** (0 App Extensions / 1 App ID) tetap tersedia di [GitHub Releases](https://github.com/Revlog15/personal-life-assistant/releases) jika suatu saat Apple ID gratis Anda menolak App Group.

### Cara B — Via File `.ipa` Manual
1. Unduh `PLAApp-x.y.z.ipa` dari halaman [GitHub Releases](https://github.com/Revlog15/personal-life-assistant/releases) ke aplikasi **Files**.
2. Nyalakan **LocalDevVPN** → buka **SideStore** → tab **My Apps** → tap **`+`** → pilih file `.ipa`.

---

## 3. Pasang Shortcuts Auto-Refresh (Agar Tidak Pernah Expired 7 Hari)

Sertifikat Apple ID gratis berlaku **7 hari**. Agar PLA selalu ter-refresh otomatis lewat Wi-Fi tanpa PC (`V-08`):

1. Buka aplikasi **Shortcuts** di iPhone → tab **Automation** → tap **`+`**.
2. Pilih pemicu **Time of Day** → atur ke **03:00**, ulangi **Daily**.
3. Pilih **Run Immediately** dan matikan **Notify When Run**.
4. Tambahkan urutan aksi berikut:
   1. **Connect VPN** (aksi dari **LocalDevVPN**)
   2. **Wait** `5 seconds`
   3. **Refresh All Apps** (aksi dari **SideStore**)
   4. **Wait** `20 seconds`
   5. *(Opsional)* **Disconnect VPN** (**LocalDevVPN**)
5. *(Opsional cadangan)* Buat automasi kedua dengan pemicu **Wi-Fi (jaringan rumah tersambung)** yang menjalankan aksi yang sama, jaga-jaga bila iOS menunda aksi saat layar terkunci.

PLA juga memiliki **pengaman bawaan**: banner di Beranda jika sisa berlaku ≤ 2 hari serta notifikasi lokal otomatis pada **H-2 dan H-1**.

---

## 4. Aktifkan Fitur Pintar `v2.1.0` (Widget, Share Extension, Siri & EventKit)

### A. Widget Home Screen & Lock Screen (`P-07`)
1. Buka **Life Assistant** minimal sekali agar snapshot tersinkron ke App Group.
2. Cek status App Group di `Pengaturan > Diagnostik > Uji Tulis/Baca App Group (Verifikasi V-07)`.
3. Tekan lama layar Home Screen → tap **`+`** → cari **Life Assistant** → pilih:
   - **Sisa Anggaran (2×2)** — otomatis menyamarkan nominal (`Rp••••••`) bila Kunci Face ID aktif.
   - **Agenda Hari Ini (4×2)** — menampilkan tugas terlambat, tugas hari ini, & tagihan 7 hari.
4. Untuk **Lock Screen**: tekan lama Lock Screen → **Customize** → tambah widget **Deadline Terdekat** (`Rectangular`, `Circular`, atau `Inline`).

### B. Scan Struk Langsung dari Share Sheet (`P-06` & `P-05`)
- **Cara 1 — Share Extension Native (`P-06`):** di aplikasi BCA / Mandiri / GoPay / OVO / DANA atau Photos, tap tombol **Share** pada screenshot bukti transfer → pilih **Catat ke Life Assistant** → periksa nominal & merchant → tap **Buka & Simpan di Life Assistant**. Foto diproses 100% offline oleh Apple Vision di memori dan langsung dibuang (tidak disimpan ke DB/disk).
- **Cara 2 — Jalur Shortcut Share Sheet (`P-05`, 0 Extension):** jika Anda memilih *Remove App Extensions*:
  1. Buka aplikasi **Shortcuts** → buat Shortcut baru bernama **Catat Struk ke PLA**.
  2. Nyalakan **Show in Share Sheet** (terima **Images**).
  3. Tambahkan aksi **Scan Struk ke Life Assistant** dari **Life Assistant** dengan input **Shortcut Input**.

### C. Siri, Action Button & Back Tap (`P-02`)
Aksi berikut otomatis terdaftar di aplikasi **Shortcuts** & **Siri** (tanpa perlu extension):
- *"Hey Siri, tambah tugas di Life Assistant"* (mendukung bahasa natural Indonesia, mis. `"rapat besok jam 3 sore #kerja !tinggi"`)
- *"Hey Siri, catat pengeluaran di Life Assistant"*
- *"Hey Siri, scan struk di Life Assistant"*
Anda bisa menautkan salah satunya ke **Action Button** (iPhone 15 Pro+) atau **Settings > Accessibility > Touch > Back Tap**.

### D. Smart Rescheduling + Kalender Apple (`P-08`)
Aktifkan opsional di `Pengaturan > Smart Rescheduling & Kalender` (izin **hanya-baca** / read-only) agar rekomendasi jadwal ulang menghindari hari yang penuh agenda kalender.

---

## 5. Agar Notifikasi Tidak Terblokir Focus / Do Not Disturb

1. Buka **Settings > Focus** → pilih mode Focus yang sering dipakai (mis. *Work* / *Do Not Disturb*).
2. Tap **Apps** → pilih **Allow Notifications From**.
3. Tap **Add** → pilih **Life Assistant**.

---

## 6. Troubleshooting & Kirim Masukan

- **Pairing file invalid (`V-19`)** (mis. setelah update iOS besar atau reset jaringan): sambungkan lagi iPhone ke PC Windows, buka `iloader`, hapus pairing lama, buat ulang pairing file dan kirim ke SideStore. Data PLA tidak hilang selama app tidak di-uninstall.
- **Lupa refresh lewat 7 hari (app tidak bisa dibuka):** **JANGAN hapus PLA!** Cukup nyalakan LocalDevVPN → buka SideStore → tap **Refresh** dengan Apple ID yang sama. Semua data tetap aman.
- **Widget kosong / App Group tidak tersedia (`V-07`):** buka `Pengaturan > Diagnostik` → jalankan **Uji Tulis/Baca App Group (V-07)**. Jika Apple ID gratis Anda tidak mendukung App Group, Anda tetap dapat memakai `Share Extension` via tautan `pla://` atau beralih ke Shortcut `P-05`.
- **Lapor bug ke developer:** buka `Pengaturan > Kirim Masukan` → tap **Salin Paket Diagnostik** (aman, bebas nominal uang & judul tugas) lalu kirim dengan format:
  1. Yang dilakukan: ...
  2. Yang diharapkan: ...
  3. Yang terjadi: ...
  4. Tempel Paket Diagnostik (+ screenshot bila masalah tampilan).
