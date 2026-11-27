# Hasil spike Sinkronisasi (PR 0)

Spike S1–S8 dari [sync-implementation-plan.md](sync-implementation-plan.md) (PR 0) dan [sync-plan.md](sync-plan.md) bagian 5. Tanggal: 27 November 2026.

## Ringkasan

| Spike | Hasil | Keputusan |
|---|---|---|
| S1 URL | **Lolos.** 91/91 series dan 9.532/9.532 chapter cocok persis. | Pemetaan lewat `sourceId` + `url` apa adanya, tanpa normalizer. |
| S2 `lastReadAt` | **Terdokumentasi**, dengan dua jebakan: satuan detik, dan `lastPageRead` dibuang kalau server belum pernah membuka chapter. | Progres yang dibuang didorong lewat `restoreBackup`. Kursor bertahap tidak boleh hanya memakai `lastReadAt`. |
| S3 Buat manga | **Lolos lewat `restoreBackup`** (50/50). SEARCH 47/50 (94%), di bawah ambang. | `restoreBackup` dengan backup minimal menjadi cara utama. SEARCH tidak dipakai. |
| S4 Auth | **Lolos.** UI login, basic auth, dan simple login berjalan lewat HTTP biasa, termasuk refresh token. | Klien sync ringan, tanpa `AccountSessionStartup`. |
| S5 Kinerja | **Lolos jauh di bawah ambang.** Pull penuh 50.533 chapter selesai dalam 0,6–1,0 detik. Pull bertahap 0,54 detik. | Pull penuh cukup murah untuk setiap sync manual dan rekonsiliasi harian. Paging opsional. |
| S6 iCloud | **Belum diuji di perangkat.** Dokumentasi Apple: Personal Team (Apple ID gratis) tidak mendapat kapabilitas iCloud. | iCloud menunggu distribusi App Store/TestFlight (PR 22+, sesuai rencana). |
| S7 Extension | **Lolos untuk `pkgName` dan `signingKey`.** Gagal untuk URL store: Kuchie dan server menyimpan URL berbeda untuk store yang sama. | Store dipetakan lewat `signingKey`, bukan URL. Extension lewat `pkgName`. |
| S8 Bukti unduhan | **Gagal di mode folder.** Saat disk penuh, server melaporkan `isDownloaded = true` dengan `pageCount` 7 dari 22. Mode CBZ aman. | Bukti = `isDownloaded` **dan** `pageCount` sama dengan jumlah halaman yang diketahui Kuchie sebelum mengantre. Detail Suwayomi menyarankan CBZ. |

Temuan di luar tabel spike, tapi berdampak ke desain:

- **Versi server.** JAR yang tersedia di Mac ini adalah Suwayomi **v2.4.2366 Stable**. Skemanya belum punya `user { … }` (`ChapterUserType`, `MangaUserType`), sedangkan `lib/src/graphql/schema.graphql` dan fragment mode Server sekarang memakai `user.isRead`, `user.lastReadAt`, dan field sejenis. Semua field yang dipakai spike tersedia di kedua versi sebagai field level atas (di skema baru ditandai deprecated). `LegacyUserFieldsLink` di aplikasi sudah menjembatani keduanya. Lihat [Keputusan terbuka](#keputusan-terbuka).
- **Bug paging server:** `chapters(filter: {inLibrary: …}, first: N, orderBy: ID)` melempar `NullPointerException` H2, baik dengan `after` maupun `offset`. Tanpa `orderBy`, paging dengan cursor berjalan (urutan bawaan sudah berdasarkan ID).
- **Halaman yang hilang dari disk** tetap dilayani server dari source tanpa tanda apa pun. `isDownloaded` hanya flag di database.

## Lingkungan

- Server: `tool/qa/server.py` dengan `Suwayomi-Server-v2.4.2366.jar` (Stable), OpenJDK 21.0.13 (Homebrew), `-Xmx512m`, H2, loopback `127.0.0.1:14567`.
- Sisi Kuchie: runtime extension Mac yang dipakai build Simulator (`tool/qa/ensure_simulator_runtime.sh`, `127.0.0.1:14569`). Ini bridge yang sama dengan yang dipanggil `LocalMihonRuntime`. Skrip mengirim permintaan `/dalvik` yang sama dengan aplikasi, termasuk user agent WKWebView iPhone. Weeb Central menolak user agent bawaan JVM dengan HTTP 403, sama seperti di aplikasi tanpa header WebView.
- Extension (store Keiyoushi, dipasang di server lewat `updateExtension`; APK yang sama dari `apkUrl` dipakai runtime):
  - MangaDex `eu.kanade.tachiyomi.extension.all.mangadex` 1.6.5, source `en` `2499283573021220255`.
  - Weeb Central `eu.kanade.tachiyomi.extension.en.weebcentral` 1.6.27, source `2131019126180322627`.
- Skrip: `tool/qa/sync_spike/` (lihat [Menjalankan ulang](#menjalankan-ulang)). Hasil mentah: `tool/qa/sync_spike/results/*.json`.

Catatan metode S1: library Local di Simulator masih kosong, jadi skrip memanggil runtime yang sama secara langsung, bukan lewat ketukan UI. `stable_locator` dan `mihon_locator_id` di `common.py` menyalin `_stableLocator`, `_chapterLocator`, dan `_mihonLocatorId` dari Dart baris per baris. Source ID dan `pkgName` dari `extensionInfo` runtime sama persis dengan di server: 62 source MangaDex dan 1 Weeb Central.

---

## S1 URL

**Langkah:** `getPopularManga` lewat runtime, lalu `fetchSourceManga(POPULAR)` untuk halaman yang sama di server. Setiap `stableLocator` dicari dengan `mangas(condition: {sourceId, url})`. Untuk series yang cocok, `fetchMangaAndChapters` dijalankan, lalu URL chapter dibandingkan dengan `getChapterList` dari runtime.

| Extension | Series | Chapter |
|---|---|---|
| MangaDex (en) | 71/71 | 218/218 |
| Weeb Central | 20/20 | 9.314/9.314 |

- Format: MangaDex `/manga/<uuid>`, `/chapter/<uuid>`. Weeb Central `/series/<id>/<slug>`, `/chapters/<ulid>`.
- Satu series MangaDex tidak punya chapter. Server menjawab `fetchMangaAndChapters` dengan error `No chapters found`, bukan daftar kosong. Engine harus memperlakukan error itu sebagai daftar kosong.

**Keputusan:** lolos. Tidak perlu normalizer. Kalau suatu saat ada extension yang berbeda, `results/s1-*.json` menyimpan contoh yang tidak cocok untuk diuji ulang.

## S2 `lastReadAt`

Hasil per langkah: `results/s2-last-read-at.json` (chapter belum pernah dibuka server) dan `results/s2-last-read-at-pages.json` (setelah `fetchChapterPages`).

| Mutasi | `lastReadAt` | Catatan |
|---|---|---|
| `updateChapters(lastPageRead: n)` | Diisi waktu server saat mutasi diterima, **dalam detik** epoch | Juga untuk nilai yang sama, nilai mundur, dan `0`. |
| `isRead: true/false` | Tidak berubah | `lastPageRead` juga tidak direset. |
| `isBookmarked` | Tidak berubah | |
| `lastPageRead` saat `pageCount = -1` | Tetap diisi | **Tapi `lastPageRead` disimpan 0.** Server memotong nilai ke rentang `[0, pageCount]`, dan `pageCount` bernilai -1 sampai server membuka chapter. |
| `lastPageRead` melewati akhir | Diisi | Dipotong ke `pageCount` (bukan `pageCount - 1`). `isRead` tidak ikut berubah. |
| `updateManga(inLibrary: true)` | — | `inLibraryAt` diisi ulang **setiap kali**, juga saat series sudah ada di library. Menghapus dari library tidak mereset `inLibraryAt`. |
| `restoreBackup` dengan `BackupHistory.lastRead` | Diisi dari backup (ms → detik) | `lastPageRead` dari backup **tetap tersimpan** meski `pageCount = -1`. |

`restoreBackup` ke chapter yang sudah punya progres (`results/s3b-merge-*.json`) selalu mengambil nilai terbesar:

- halaman: nilai terbesar menang;
- `isRead`: tidak bisa kembali ke belum dibaca lewat restore;
- `isBookmarked`: hanya bisa ditambah;
- `lastReadAt`: nilai terbaru menang.

**Keputusan:**

- Waktu server dibandingkan dalam detik. Kuchie menyimpan milidetik, jadi konversi dilakukan di lapisan GraphQL sync.
- `lastReadAt` server bukan waktu baca yang sebenarnya, melainkan waktu mutasi terakhir yang membawa `lastPageRead`. Aturan konflik tetap memakai base tiga arah (4.2). Waktu hanya pemecah seri, dan halaman terjauh menjadi fallback.
- Push progres:
  - `updateChapters` untuk `isRead`, unread, bookmark, dan `lastPageRead` pada chapter yang `pageCount`-nya sudah diketahui server.
  - `restoreBackup` (backup minimal berisi chapter dan riwayat) untuk `lastPageRead` pada chapter yang belum dibuka server, dan untuk membawa waktu baca asli dari iPhone. Restore tidak dipakai untuk menurunkan nilai atau menandai belum dibaca.
  - Saat mendorong `isRead: true`, `lastPageRead` ikut dikirim supaya riwayat server terisi.
- Pull bertahap tidak bisa hanya memakai `chapters(filter: {lastReadAt > kursor})`. Perubahan `isRead`/bookmark dari klien lain (WebUI, Mihon) tidak menggeser `lastReadAt`. Lihat S5 untuk penggantinya.
- `inLibraryAt` tidak bisa dipakai sebagai "waktu ditambahkan ke library" yang stabil. Kuchie tidak mengirim `inLibrary: true` untuk series yang sudah ada di library server, supaya urutan "Ditambahkan" di klien lain tidak teracak.

## S3 Buat manga

Calon: series dari daftar Latest yang belum ada di server. 25 diuji per cara per extension.

| Cara | MangaDex | Weeb Central | Total |
|---|---|---|---|
| (a) `fetchSourceManga(SEARCH, judul)`, lalu cocokkan URL | 25/25 | 22/25 | 47/50 (94%) |
| (b) `restoreBackup` dengan backup minimal (`source`, `url`, `title`, `favorite`) | 25/25 | 25/25 | **50/50** |

- Tiga kegagalan SEARCH di Weeb Central ("So I'm a Spider, So What", "Bijin Onna Joushi Takizawa-san", "Ushiro no Shoumen Kamui-san") juga mengembalikan 0 hasil di runtime iPhone. Pencarian source-nya yang lemah, bukan server.
- Restore 25 series selesai dalam ~0,5 detik dan tidak mengakses source. Baris yang dibuat sudah `inLibrary = true`, tapi masih `initialized = false` dan belum punya chapter. Perlu `fetchMangaAndChapters` setelahnya. Restore yang membawa chapter juga membuat baris chapter (dipakai untuk seed S5). `sourceOrder` dibalik dari urutan di backup.
- `restoreStatus` selalu melaporkan `totalManga = 0` dan `mangaProgress = 0`, meski berhasil. Hasil harus dicek dengan query ulang.

**Keputusan:** cara utama adalah `restoreBackup` dengan backup minimal yang dibuat Kuchie (`tool/qa/sync_spike/backup.py` menjadi rujukan nomor field protobuf). Setelah itu jalankan `fetchMangaAndChapters`. Push series baru tidak perlu ditunda. SEARCH tidak dipakai.

## S4 Auth

`results/s4-auth.json`. Kredensial acak sekali pakai di server QA. Server dikembalikan ke `NONE` setelahnya.

| Mode | Klien ringan | Catatan |
|---|---|---|
| UI_LOGIN | Lolos | `login` menghasilkan `accessToken` dan `refreshToken`. Header `Authorization: Bearer`. Token kedaluwarsa (uji: 20 detik) dijawab sebagai **error GraphQL `Unauthorized` dengan HTTP 200**, bukan 401. `refreshToken` menghasilkan access token baru. Refresh token tidak dirotasi dan bisa dipakai ulang (masa berlaku bawaan 60 hari). Refresh token yang dipakai sebagai access token ditolak dengan HTTP 400. Basic auth ditolak di mode ini. |
| BASIC_AUTH | Lolos | Tanpa header atau dengan kredensial salah: HTTP 401. |
| SIMPLE_LOGIN | Lolos | `POST /login.html` menghasilkan 303 dengan cookie sesi, dan cookie itu cukup untuk GraphQL. |

- `aboutServer` tetap terbuka di semua mode. Pemeriksaan "auth valid" di preflight harus memakai query data library, bukan `aboutServer`.
- JWT di v2.4.2366 tidak punya klaim pengguna (`sub`). Server ini masih satu pengguna.

**Keputusan:** lolos. Klien sync memakai kredensial dari `features/auth` (`auth_credentials_store`), mendeteksi `Unauthorized` di body GraphQL, refresh sekali, lalu menampilkan banner "Login kedaluwarsa" (8, kasus 11a) kalau masih gagal.

## S5 Kinerja

Seed: 500 series × 100 chapter lewat `restoreBackup` (URL palsu di bawah source MangaDex, tanpa akses jaringan), sekitar 0,5 detik per 100 series. Total library 554 series dan 50.533 chapter. `results/s5-performance.json`.

| Pengukuran (loopback) | Waktu | Ukuran |
|---|---|---|
| Series library (`mangas(condition: {inLibrary: true})` + kategori) | 0,02–0,09 dtk | 89 KB |
| Semua chapter library dalam satu query (8 field) | 0,63–1,04 dtk | 8,5 MB JSON, **0,31 MB gzip** |
| Paging cursor 10.000 / 5.000 / 2.000 | 1,7 / 2,8 / 5,5 dtk | sama |
| Pull bertahap: sidik jari per series + `lastReadAt > kursor` + chapter series yang berubah | **0,54 dtk** | 72 KB sidik jari |

- Data nyata (9.703 chapter dari S1/S3) juga terkompresi sekitar 10×. Dart `HttpClient` meminta gzip secara otomatis.
- Pengukuran di loopback. Untuk Wi-Fi LAN, transfer 0,3–0,9 MB hasil gzip hanya menambah sekitar 0,1–0,5 detik. Masih jauh di bawah ambang 30 detik.
- Sidik jari per series: `unreadCount`, `bookmarkCount`, `downloadCount`, `lastReadChapter { id lastReadAt }`. Perubahan `isRead` dan bookmark dari klien lain terdeteksi lewat jumlahnya, dan perubahan halaman lewat `lastReadAt`. Kasus yang lolos: membaca satu chapter dan membatalkan chapter lain di series yang sama dalam satu interval (jumlah tetap). Rekonsiliasi penuh menutup celah itu.

**Keputusan:** lolos. Pull bertahap = sidik jari series + chapter dengan `lastReadAt > kursor`, lalu muat ulang chapter untuk series yang sidik jarinya berubah. Rekonsiliasi penuh (satu query, tanpa paging) dijalankan saat sync manual dan sekali sehari. Kalau paging dibutuhkan untuk server yang lebih lambat, pakai cursor **tanpa** `orderBy` (bug H2 di atas).

## S6 iCloud

Tidak bisa diuji di sesi ini. Pengujiannya butuh Apple ID pengguna, pendaftaran container CloudKit di akun developer, dan iPhone fisik.

- Dokumentasi Apple dan jawaban DTS di Developer Forums: Personal Team (Apple ID gratis) tidak mendapat kapabilitas iCloud dan Push. Kapabilitas profil bergantung pada keanggotaan Apple Developer Program ([Supported capabilities (iOS)](https://developer.apple.com/help/account/reference/supported-capabilities-ios/), [Developer Forums](https://developer.apple.com/forums/thread/811929)).
- IPA Kuchie dirilis tanpa tanda tangan dan di-sign ulang oleh tim masing-masing pengguna (README). Container CloudKit terikat ke tim yang menandatangani. Jadi iCloud lewat AltStore/SideStore paling baik hanya berjalan untuk pengguna dengan akun berbayar, dan tiap pengguna punya container sendiri. Ini tidak bisa diandalkan sebagai fitur umum.

**Keputusan:** sesuai jalur gagal di rencana, iCloud menunggu distribusi App Store/TestFlight (PR 22+). Kalau ingin bukti di perangkat, ujinya: sign build dengan Personal Team, lalu `codesign -d --entitlements :- Runner.app` untuk melihat apakah `com.apple.developer.icloud-services` dipertahankan. Uji ini butuh akun pengguna.

## S7 Extension

- `pkgName` server = `LocalSourcePackage.id` = bagian `<paket>` di `sourceId` Local (`'${manifest.id}:${runtimeSource.id}'`, `local_sources.dart:124`). Source ID Mihon sama di kedua sisi.
- `signingKey` server (`ExtensionStoreType.signingKey`) adalah hex SHA-256 huruf kecil tanpa titik dua: `9add655a…4da2`. Formatnya sama dengan hasil `_mihonSigningKey` dan dengan fingerprint signer yang diverifikasi `verifyApkSigners` untuk kedua APK (`dart run tool/qa/sync_spike/s7_signer.dart <apk>`).
- **URL store berbeda untuk store yang sama.** Server mengikuti `index_v2` di `repo.json` dan menyimpan `https://github.com/keiyoushi/extensions/raw/repo/index.pb`. Kuchie menyimpan Keiyoushi sebagai `https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.json` (`_keiyoushiIndex`). `ExtensionType.storeIndexUrl` di server memakai URL server.

**Keputusan:** store dicocokkan lewat `signingKey`, extension lewat `pkgName`, dan source lewat ID Mihon. Pemetaan lewat nama dan bahasa tidak diperlukan. *Tambahkan store* (3.5) memakai `indexUrl` server, karena Kuchie sudah bisa membaca index v2.

## S8 Bukti unduhan

`results/s8-*.json`. Chapter Weeb Central yang belum pernah dibuka server.

| Skenario | Status antrean | `isDownloaded` | `pageCount` | Bisa dibedakan dari sukses? |
|---|---|---|---|---|
| Normal (One Piece ch. 3) | `DOWNLOADING` → hilang dari antrean (~1,5 dtk) | true | 22 (benar) | — |
| Chapter sudah dihapus dari source (URL palsu) | `ERROR`, `tries` 3–4, tetap di antrean, downloader `STOPPED` | false | -1 | **Ya** |
| Disk penuh, mode folder (volume 2 MB) | Sama seperti sukses: hilang dari antrean | **true** | **7** (source: 22) | **Tidak**, kecuali jumlah halaman dibandingkan |
| Disk penuh, mode CBZ | `ERROR` setelah 3 percobaan | false | 20 (benar) | Ya. File `.cbz` parsial tertinggal di disk. |
| File halaman dihapus setelah sukses | — | true | 22 | Tidak. Halaman yang hilang dilayani dari source. |

- Log server mencatat `java.io.IOException: No space left on device`, tapi tidak ada field error di `DownloadType`.
- Di mode folder, server menimpa `pageCount` dengan jumlah file yang berhasil ditulis. Ini bug Suwayomi v2.4.2366 dan layak dilaporkan ke upstream.

**Keputusan:**

- Bukti chapter tersimpan di server = `isDownloaded = true` **dan** `pageCount` sama dengan jumlah halaman yang Kuchie ketahui sebelum mengantre:
  - *Pindahkan ke server*: jumlah halaman salinan iPhone (sudah tertulis di 3.6);
  - *Unduh ke server*: panjang `fetchChapterPages` yang dicatat sebelum `enqueueChapterDownloads`.
- Status `ERROR` di antrean menjadi alasan "Tidak bisa dipindah" (source error atau chapter hilang). Alasan pastinya tidak tersedia lewat API, jadi teksnya umum dengan tombol *Coba lagi*.
- Detail Suwayomi menampilkan saran "Simpan unduhan server sebagai CBZ" kalau `downloadAsCbz = false`. Kuchie tidak mengubah setelan server tanpa ketukan pengguna.
- File yang hilang setelah sukses tidak bisa dideteksi lewat API. Ini di luar jaminan Kuchie: salinan iPhone hanya dihapus setelah bukti di atas terpenuhi.

---

## Keputusan terbuka

1. **Versi Suwayomi minimum untuk Kuchie 2.0.** Skema di repo (`user { … }`) berasal dari build yang lebih baru daripada Stable v2.4.2366. Preview terbaru saat ini adalah v2.4.2512. Kuchie sudah menangani perbedaan ini: `LegacyUserFieldsLink` (`lib/src/utils/graphql/legacy_user_fields_link.dart`) memeriksa `ChapterType` lewat introspeksi, lalu menulis ulang `user { … }` menjadi field level atas untuk server lama. Klien sync (PR 4) memakai link yang sama, jadi dokumen sync bisa ditulis dengan `user.*`. Yang belum diuji adalah perilaku server multi-pengguna: apakah `lastReadAt`, restore, dan unduhan per pengguna atau global. Rekomendasi: ulangi S2, S3b, S4, dan S8 dengan JAR preview sebelum PR 5.
2. **Bug H2 paging dan `pageCount` saat disk penuh**: laporkan ke Suwayomi? Kuchie sudah punya jalan memutar untuk keduanya.

## Menjalankan ulang

```sh
python3 tool/qa/server.py --jar ~/development/suwayomi/Suwayomi-Server-v2.4.2366.jar \
  --java /opt/homebrew/opt/openjdk@21/bin/java        # cetak "QA catalog: <root>"
# Runtime Simulator: dijalankan otomatis oleh build Simulator, atau tool/qa/run_simulator_local.sh
cd tool/qa/sync_spike
python3 s1_urls.py --apk <mangadex.apk> --source 2499283573021220255
python3 s1_urls.py --apk <weebcentral.apk> --source 2131019126180322627
python3 s2_last_read_at.py --manga-id <id> --fetch-pages
python3 s3_create_manga.py --apk <apk> --source <id> --name "<nama source>"
python3 s3b_restore_merge.py --source 2499283573021220255 --name MangaDex
python3 s4_auth.py
python3 s5_performance.py
python3 s8_download_proof.py --server-root <root>
python3 s8_download_proof.py --scenario full --downloads-path <volume kecil>
dart run tool/qa/sync_spike/s7_signer.dart <apk>...   # dari root repo
```

Store dan extension di server: `addExtensionStore(indexUrl: "https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json")`, `fetchExtensions`, lalu `updateExtension(id: <pkgName>, patch: {install: true})`. APK untuk runtime diambil dari `apkUrl` extension yang sama.
