# MotorQu Solid

Aplikasi Android untuk mencatat ganti oli motor bersama keluarga. Fiturnya
setara dengan [MotorQu](https://github.com/ridlofw/motorqu) (versi Firebase),
tetapi seluruh data disimpan di **Solid Pod** milik masing-masing pengguna,
bukan di server pusat.

## Fitur

- Daftar motor pribadi & motor grup keluarga dalam satu beranda, lengkap
  dengan status oli (aman / perlu dicek) dan ringkasan garasi.
- Catat ganti oli (tanggal + KM), riwayat dengan selisih KM antar catatan,
  hapus catatan.
- Pengingat lokal 30 hari per motor, ketuk notifikasi langsung ke form oli.
- Grup keluarga: banyak grup, banyak owner/admin, undang lewat **QR** atau
  **kode undangan** yang dikirim lewat chat, keluarkan anggota, bagikan /
  tarik motor.
- Auto-update APK dari GitHub Release, tema terang/gelap.

## Cara kerja data di Solid Pod

Semua file Turtle (`.ttl`, tidak dienkripsi) berada di
`<pod>/motorqu-solid/data/`:

```
motorcycles/<motorId>/motorcycle.ttl        data motor
motorcycles/<motorId>/records/<id>.ttl      catatan ganti oli
groups/<groupId>.ttl                        data grup (di Pod host grup)
group_requests/<groupId>/                   permintaan bergabung (Append-only)
joined_groups/<groupId>.ttl                 pointer ke grup yang diikuti
```

**Model akses**

- **Host grup** = pemilik Pod tempat `group.ttl` disimpan (pembuat grup).
  Hanya host yang bisa mengubah ACL file grup, jadi host yang menyetujui
  permintaan bergabung. Host baru bisa keluar setelah semua anggota lain
  dikeluarkan.
- Setiap pemilik motor menulis ACL motornya sendiri sesuai anggota grup.
  ACL ditulis **utuh** (bukan ditambah), jadi kick / keluar / motor
  dijadikan pribadi otomatis mencabut akses saat aplikasi pemilik resource
  berjalan.
- Pointer grup & motor hanya dibuang dengan **bukti pasti** (404 asli, atau
  file grup terbaca tapi kita bukan anggota). 403 disembunyikan dulu dengan
  masa tenggang 7 hari.
- Perubahan file bersama memakai **ETag + `If-Match`** dengan retry saat
  konflik (HTTP 412), sehingga perubahan dari dua HP tidak saling menimpa.
- Tidak ada push realtime: data dimuat ulang saat aplikasi kembali aktif dan
  berkala selama aplikasi terbuka (beranda 2 menit, detail motor 45 detik,
  grup 2 menit). Sinkronisasi ACL di latar dibatasi 10 menit.

Kode terkait: `lib/services/pod_atomic.dart`, `access_policy.dart`,
`group_service.dart`, `app_refresh.dart`, `invite_codec.dart`.

## Pengembangan

Kebutuhan: Flutter **3.47.7** (sama dengan CI), JDK 17, Android SDK.

```bash
flutter pub get
flutter run
flutter test
flutter analyze
```

Ikon launcher dibuat dari `tool/launcher/` dengan:

```bash
dart run flutter_launcher_icons
```

## Rilis

Setiap push ke `main` menjalankan `.github/workflows/build.yaml`: tes, build
APK release, lalu GitHub Release berisi `app-release.apk` + `latest.json`
(dibaca fitur auto-update di aplikasi).

1. **Naikkan `version` di `pubspec.yaml`** (angka setelah `+` = versionCode).
   Tanpa itu, HP pengguna tidak melihat ada pembaruan.
2. **Keystore rilis permanen** (sekali saja):

   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts\create-release-keystore.ps1
   ```

   Lalu isi secret repository: `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`,
   `KEY_ALIAS`, `KEY_PASSWORD` (nama lama `ANDROID_*` juga diterima). CI
   sengaja gagal bila secret kosong, karena APK bertanda tangan debug key
   tidak bisa meng-update aplikasi yang sudah terpasang.
3. **Cadangkan keystore & password-nya.** Bila hilang, auto-update ke HP
   pengguna putus selamanya.

`applicationId` = `com.motorqu.solid`. Jangan diganti setelah rilis.

## Checklist uji manual (dua akun Pod)

Pakai akun Pod **uji**, bukan Pod keluarga: sinkronisasi pertama menulis
ulang ACL semua data. ACL lama dicetak di `adb logcat` dengan awalan
`[ACL] Menimpa`.

Siapkan HP **A** (host), HP **B** (anggota), dan bila ada HP **C**.

**Dasar**
- [ ] A: login, tambah motor pribadi, catat oli, hapus catatan.
- [ ] A: edit nama motor → tersimpan; KM oli tidak berubah.
- [ ] Log menampilkan `[PodAtomic] ... ETag: ...`. Bila `TANPA ETag`,
      penyimpanan tetap jalan tetapi tanpa perlindungan konflik.

**Grup & undangan**
- [ ] A: buat grup, buka QR undangan (biarkan terbuka). B: scan → langsung
      masuk.
- [ ] A: bagikan kode undangan lewat chat. C: Masuk Grup → Tempel Kode
      Undangan → status "menunggu". A buka beranda → C masuk ≤ ±2 menit.
- [ ] Kode yang sama dipakai lagi → ditolak.
- [ ] A: masukkan motor ke grup. B & C melihat motor itu dan bisa mencatat oli.
- [ ] B: masukkan motornya ke grup. A & C melihatnya setelah aplikasi B
      berjalan.

**Hak akses**
- [ ] B: Edit Motor milik A → bagian Kepemilikan terkunci, nama tetap bisa
      diubah.
- [ ] A: keluarkan C → C mendapat 403 ke grup; motor C kembali pribadi;
      A & B tetap punya akses.
- [ ] B: keluar grup → motor B kembali pribadi, A tidak lagi bisa membukanya
      (setelah aplikasi B berjalan).
- [ ] A (host) mencoba keluar saat masih ada anggota → ditolak dengan pesan
      jelas.

**Sinkronisasi & konflik**
- [ ] A di background ±1 menit, B mengubah data, A dibuka lagi → perubahan
      muncul dalam beberapa detik.
- [ ] Detail motor terbuka di A, B mencatat oli → muncul di A ≤ ±75 detik.
- [ ] A & B mengganti nama grup bersamaan → keduanya tersimpan tanpa error
      (salah satu menang, tidak ada data rusak).

**Rilis**
- [ ] Pasang APK versi N dari CI, lalu update ke N+1 lewat menu cek
      pembaruan → terpasang tanpa uninstall.

## Batasan yang diketahui

- Pencabutan akses tidak seketika: menunggu aplikasi pemilik resource
  berjalan.
- Bila host grup tidak pernah membuka aplikasi, permintaan bergabung tidak
  diproses.
- Grup lama yang `ownerId`-nya sudah berpindah dari host (versi sebelum
  perbaikan ACL) tidak punya pengelola akses.
- Belum ada deep link yang bisa diklik dari WhatsApp (skema kustom tidak
  di-link-kan oleh WhatsApp; link https butuh hosting + `assetlinks.json`).
- Semua anggota keluarga perlu memakai versi aplikasi yang sama (QR/kode
  dari versi lama ditolak).
