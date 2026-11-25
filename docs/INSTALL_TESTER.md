# Panduan Instalasi & Auto-Refresh Personal Life Assistant (SideStore)

Panduan ringkas 1 halaman untuk developer dan tester (iPhone dengan **iOS 17.0+**, Apple ID gratis, setup awal sekali lewat PC Windows).

> **Penting sebelum mulai:**
> - Gunakan **Apple ID sendiri** (disarankan membuat Apple ID sekunder khusus sideload, jangan berbagi Apple ID).
> - Jika suatu saat ingin ganti Apple ID di SideStore atau menghapus app, **wajib backup JSON dulu** di `Pengaturan > Data & Backup > Backup Lengkap (JSON)` karena ganti Apple ID mengubah Bundle ID dan container data.

---

## 1. Setup Awal (Hanya 1× Memakai PC Windows)

1. **Install iTunes (bukan versi Microsoft Store)** di PC Windows dari situs resmi Apple (`apple.com/itunes`) agar driver USB iPhone tersedia.
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

### Cara B — Via File `.ipa` Manual
1. Unduh `PLAApp-x.y.z.ipa` dari halaman [GitHub Releases](https://github.com/Revlog15/personal-life-assistant/releases) ke aplikasi **Files**.
2. Nyalakan **LocalDevVPN** → buka **SideStore** → tab **My Apps** → tap **`+`** → pilih file `.ipa`.

---

## 3. Pasang Shortcuts Auto-Refresh (Agar Tidak Pernah Expired 7 Hari)

Sertifikat Apple ID gratis berlaku **7 hari**. Agar PLA selalu ter-refresh otomatis lewat Wi-Fi tanpa PC:

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

## 4. Agar Notifikasi Tidak Terblokir Focus / Do Not Disturb

1. Buka **Settings > Focus** → pilih mode Focus yang sering dipakai (mis. *Work* / *Do Not Disturb*).
2. Tap **Apps** → pilih **Allow Notifications From**.
3. Tap **Add** → pilih **Life Assistant**.

---

## 5. Troubleshooting & Kirim Masukan

- **Pairing file invalid** (mis. setelah update iOS besar atau reset jaringan): sambungkan lagi iPhone ke PC Windows, buka `iloader`, hapus pairing lama, buat ulang pairing file dan kirim ke SideStore. Data PLA tidak hilang selama app tidak di-uninstall.
- **Lupa refresh lewat 7 hari (app tidak bisa dibuka):** **JANGAN hapus PLA!** Cukup nyalakan LocalDevVPN → buka SideStore → tap **Refresh** dengan Apple ID yang sama. Semua data tetap aman.
- **Lapor bug ke developer:** buka `Pengaturan > Kirim Masukan` → tap **Salin Paket Diagnostik** (aman, bebas nominal uang & judul tugas) lalu kirim dengan format:
  1. Yang dilakukan: ...
  2. Yang diharapkan: ...
  3. Yang terjadi: ...
  4. Tempel Paket Diagnostik (+ screenshot bila masalah tampilan).
