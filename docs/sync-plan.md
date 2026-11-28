# Rencana teknis: halaman Sinkronisasi

Basis kode: Kuchie 1.2.1 (`kuchie-app/Kuchie` main, `17c29a9`). Revisi 2.

## 0. Keputusan yang sudah diambil

| Topik | Keputusan |
|---|---|
| Lokasi | **More → Sinkronisasi**, ditambah ikon status di judul Library. |
| Halaman Sinkronisasi | Diagram hidup **berbeda per metode**, dengan kosakata token yang sama (cover = library, titik = progres, halaman = chapter, paket, pita, file), ditambah baris "Yang disinkronkan". Metode lain (iCloud, SyncYomi, KOReader Sync, Komga, Kavita, Google Drive) tampil berlabel *Segera hadir* (3.2, 3.9). |
| Metode | Suwayomi lebih dulu, lalu iCloud. **Hanya satu metode aktif** dalam satu waktu. |
| Pemeriksaan saat menghubungkan | Hanya muncul kalau iPhone dan server **sama-sama punya data yang berbeda**. Kalau salah satu kosong, sync langsung berjalan. |
| Cakupan | Library, kategori, progres, bookmark, rating/tag/catatan (opsional), setelan reader per series, daftar extension (berupa saran), status unduhan di server, setelan aplikasi (hanya lewat iCloud). |
| Konflik hapus-vs-baca | **Membaca menang**, otomatis tanpa bertanya. |
| Rilis | **Satu rilis penuh, Kuchie 2.0.** Mode Server dihapus di rilis yang sama, tanpa migrasi pengguna karena belum ada pengguna lain (bagian 7). |
| Prinsip UX | **Pengguna tidak memilih lokasi.** Kuchie selalu mendahulukan iPhone dan memakai server hanya sebagai cadangan otomatis. Tidak ada setelan "ambil lewat", "lokasi unduhan", atau "pasang di mana". |
| Server tidak terjangkau | Kuchie tetap berjalan normal dari data di iPhone. Perubahan diantre. Tidak ada dialog error kecuali pengguna perlu bertindak (3.8). |
| Pemasangan extension | Satu tombol **Pasang**: dipasang di iPhone, dan juga di server kalau sync aktif. Pengguna tidak memilih lokasi (3.5). |
| Unduhan | **Satu chapter disimpan di satu tempat saja, tidak pernah dobel otomatis.** Kalau terhubung ke server, unduhan disimpan di server. Kalau tidak, di iPhone. Simpan ke iPhone hanya terjadi kalau pengguna memintanya secara eksplisit lewat **Simpan untuk offline** (3.6). |
| Pindahkan unduhan ke server | Unduhan yang sudah ada di iPhone bisa **dipindahkan ke server**, dengan pilihan hapus dari iPhone (default) atau tetap simpan. Salinan iPhone baru dihapus setelah server terbukti punya chapternya (3.6). |

## 1. Tujuan dan batasan

**Tujuan**

- Satu library: database Local (`catalog.sqlite`) menjadi sumber kebenaran di iPhone.
- Pengguna selalu tahu apa yang disinkronkan, kapan terakhir berhasil, dan apa yang tidak bisa disinkronkan beserta alasannya.

**Bukan target**

- Menyalin file unduhan antara iPhone dan server secara otomatis. Penyalinan hanya terjadi lewat *Simpan untuk offline* atau dialog saat memutus koneksi (3.6).
- Dua metode aktif bersamaan.
- Mengirim import CBZ/folder, source repo Kuchie v1, atau source Shinigami bawaan ke Suwayomi. Server tidak punya source-nya. iCloud nanti bisa menangani semuanya.
- Memasang extension secara otomatis. Sync hanya memberi **saran**, dan pemasangan tetap lewat alur yang sudah ada, termasuk pemeriksaan tanda tangan APK.

**Catatan distribusi iCloud.** CloudKit dan iCloud Drive butuh entitlement iCloud dengan container yang terdaftar di akun Apple Developer berbayar. IPA unsigned yang di-sign pengguna sendiri lewat AltStore/SideStore dengan Apple ID gratis kemungkinan besar tidak bisa memakainya. Jadi iCloud realistisnya menunggu distribusi App Store atau TestFlight, sesuai roadmap. Ini perlu dipastikan di spike S6. Suwayomi tidak punya batasan ini.

## 2. Kondisi kode sekarang

| Area | Lokasi | Dampak ke sync |
|---|---|---|
| Pilihan mode | `features/onboarding/data/collection_mode.dart` | `serverCollectionRuntimeEnabledProvider` mematikan auth dan sesi server saat mode Local (`main.dart` sekitar baris 236–262). Sync butuh klien GraphQL yang hidup di mode Local tanpa menyalakan seluruh runtime Server. |
| Tab More Local | `local_collection/presentation/local_collection_home.dart` (`_more`, sekitar baris 862) | Tempat baris **Sinkronisasi**, di bawah *Backup & Pulihkan*. |
| Judul Library Local | `local_collection_home.dart`, judul tab dan `CollectionModePageTitle` | Tempat ikon status sync. Tombol pemilih mode di judul diganti ikon ini. |
| Database Local | `local_collection/data/local_catalog.dart`, skema v6 | Tabel `series`, `chapters`, `chapter_marks`, `remote_history`, `series_meta` (rating, notes, tags, cover), `categories`, `series_categories`. **Belum ada `updated_at` per baris dan belum ada tombstone.** |
| Titik tulis catalog | `setInLibrary`, `setProgress`, `recordRemoteRead`, `setChapterMarks`, `setBookmark`, `setCategories`, `createCategory`, `deleteCategory`, `removeFromHistory`, `clearHistory`, `setRating/Notes/Tags` | Setiap method ini harus mencatat perubahan ke outbox. |
| Setelan reader per series (Local) | `manga_book/presentation/reader/controller/reader_settings_model.dart`: JSON di SharedPreferences dengan kunci `local.reader.manga.<seriesId>`, ditulis lewat `_patchLocalMeta` | Isinya memakai **kunci yang sama dengan metadata manga Suwayomi** (`MangaMetaKeys`: `flutter_readerMode`, `flutter_readerNavigationLayout`, `flutter_readerPadding`, dll.), jadi bisa disalin satu-satu. Penyimpanan ini perlu dipindah ke lapisan data (lihat 4.1). |
| Rating dan tag (mode Server) | `MangaMetaKeys.rating` = `flutter_rating`, `MangaMetaKeys.tags` = `flutter_tags` | Pengguna mode Server sudah punya data ini di server. Sync memakai kunci yang sama supaya datanya langsung terbaca. |
| Koneksi server | `features/settings/data/server_connection/`, `features/auth/`, `settings/data/sign_in/` | Dipakai ulang. |
| Identitas server | `features/offline/data/graphql/server_identity.graphql` | Mendeteksi server yang diganti atau di-reset. |
| Background | `workmanager` sudah diinisialisasi di `main.dart:139` | Sync latar belakang (best effort). |

### 2.1 Pemetaan identitas

| Lokal | Suwayomi |
|---|---|
| `LocalSeriesSource.sourceId` = `"<paket>:<idSourceMihon>"` | `MangaType.sourceId` = `idSourceMihon` |
| `locator` (URL series dari extension), `mangaId = sha256(stableLocator)` | `MangaType.url` |
| ID chapter = `sha256(stableLocator chapter)` | `ChapterType.url` |
| Kategori berdasarkan nama | `CategoryType.id`, dipetakan lewat nama (tidak peka huruf besar/kecil) |
| Paket extension (`<paket>`) dan store | `ExtensionType.pkgName`, `ExtensionStoreType.indexUrl` + `signingKey` |

Tidak bisa dipetakan ke Suwayomi: import CBZ/folder, repo Kuchie v1, Shinigami bawaan. Semuanya ditampilkan sebagai "Hanya di iPhone".

### 2.2 Kemampuan Suwayomi yang relevan (dari `lib/src/graphql/schema.graphql`)

- Library dan progres: `mangas(condition: {inLibrary, sourceId, url})`, `chapters(condition: {mangaId})`, filter `lastReadAt`, `user.inLibraryAt`, `user.lastReadAt`, `updateMangas`, `updateMangasCategories`, `createCategory`, `updateChapters` (`isRead`, `isBookmarked`, `lastPageRead`).
- Metadata: `setMangaMetas`, `deleteMangaMetas`. Dipakai untuk rating, tag, catatan, dan setelan reader per series.
- Extension: `extensions(condition: {isInstalled: true})` (`pkgName`, `name`, `lang`), `extensionStores` (`indexUrl`, `signingKey`), `addExtensionStore`, `updateExtension`.
- Unduhan: `user.isDownloaded` per chapter, `enqueueChapterDownloads`, `dequeueChapterDownloads`, `deleteDownloadedChapters`.
- Pembuatan baris manga: `fetchSourceManga`, `fetchMangaAndChapters`.
- **Tidak ada feed perubahan.** Kuchie harus menarik data sendiri.
- **`UpdateChapterPatchInput` tidak menerima `lastReadAt`.** Terbukti di S2: server mengisi waktu mutasi (dalam **detik**) setiap kali patch membawa `lastPageRead`, tapi tidak untuk `isRead` atau `isBookmarked`. Aturan konflik tidak boleh hanya mengandalkan timestamp server.
- **`lastPageRead` dibuang (disimpan 0) kalau server belum pernah membuka chapter** (`pageCount = -1`). `restoreBackup` tidak punya batasan ini dan juga membawa waktu baca asli lewat riwayat (S2, S3).
- Skema di repo memakai `user { … }`, yang belum ada di Suwayomi Stable v2.4.2366. Versi minimum masih keputusan terbuka (9).

Hasil lengkap spike: [sync-spike-results.md](sync-spike-results.md).
- Suwayomi mendukung banyak pengguna. Sync berjalan sebagai pengguna yang login.

## 3. UX

### 3.1 Ikon status di Library

Ikon kecil di sebelah judul Library. Ketuk untuk membuka **Sinkronisasi**.

| Status | Ikon | Keterangan |
|---|---|---|
| Mati | tidak ada ikon | Judul Library bersih. |
| Tersinkron | awan dengan centang | |
| Sedang sync | awan dengan panah berputar | Animasi berhenti kalau *Reduce Motion* aktif. |
| Menunggu server | awan abu-abu | Server tidak terjangkau. Perubahan diantre. Ini kondisi normal, bukan error (3.8). |
| Perlu tindakan | awan merah dengan tanda seru | Hanya untuk login kedaluwarsa atau server yang berubah. Ketuk untuk membuka detail. |

Ikon ini menggantikan tombol pemilih mode yang sekarang ada di judul Library. Label aksesibilitasnya membacakan status lengkap, misalnya "Tersinkron dengan Suwayomi, 2 menit lalu".

### 3.2 More → Sinkronisasi

Halaman ini harus bisa dipahami tanpa membaca dokumentasi. Bagian atasnya adalah **diagram hidup** (3.9) yang menunjukkan cara kerja metode yang dipilih, dengan data sebenarnya. Di bawahnya ada pengaturan seperlunya, lalu FAQ.

Prototipe interaktif (versi 4): https://claude.ai/artifact/UgsfGprka4iH1t9dYFQoSN

```
Sinkronisasi                                         (?)
┌─────────────────────────────────────────────────────┐
│ [▤ Suwayomi]                           [● Aktif]    │  ← pill metode, pill status
│                                                     │
│        Source                      iPad · Kuchie    │
│           🌐                       [ 42/42 ]        │
│  [iPhone] ═══ • ▮ ═══ (Server) ═══ ┤                │  ← diagram hidup (3.9)
│  42/42                130 series   [ 42/42 ]        │
│                                    Mac · WebUI      │
│                                                     │
│ ✓ Library  ✓ Progres  ✓ Unduhan di server  ✓ ...   │  ← Yang disinkronkan
│ Tersinkron · 2 menit lalu                           │  ← satu kalimat status
│ Library dan progres bacamu sama di iPhone, server,  │  ← satu kalimat penjelasan
│ dan perangkat lain.                                 │
│ [ Sinkronkan sekarang ]                             │  ← satu aksi utama
└─────────────────────────────────────────────────────┘
Metode
  ○ Mati                  Semua tersimpan di iPhone ini
  ● Server Suwayomi       192.168.1.10:4567            ›
  ○ iCloud                Antar perangkat Apple          Segera hadir
  ○ SyncYomi              Server sync keluarga Tachiyomi Segera hadir
  ○ KOReader Sync         Posisi baca lewat kosync       Segera hadir
  ○ Komga                 Server komik dan manga         Segera hadir
  ○ Kavita                Server bacaan pribadi          Segera hadir
  ○ Google Drive          File sync berkala di Drive     Segera hadir
Kapan
  Saat membuka Kuchie                    [on]
  Setelah selesai membaca chapter        [on]
  Hanya lewat Wi-Fi                      [off]
Pertanyaan umum
  Apa itu Sinkronisasi?                   ⌄
  Apa saja yang disinkronkan?             ⌄
  Apa yang tidak disinkronkan?            ⌄
  Bagaimana kalau server mati atau aku di luar rumah?  ⌄
  Unduhan disimpan di mana?               ⌄
  Apakah extension perlu dipasang dua kali?            ⌄
  Bagaimana cara berhenti memakai server? ⌄
Lanjutan
  Log sinkronisasi                        ›
```

- **Pill metode** (kiri atas) berisi ikon dan nama metode: ponsel untuk Lokal, server untuk Suwayomi/SyncYomi/KOReader Sync/Komga/Kavita, awan untuk iCloud/Google Drive. **Pill status** (kanan atas) berisi kata singkat (Tanpa sync, Memeriksa, Berjalan, Aktif, Menunggu, Perlu tindakan) dan titik yang berdenyut saat ada pekerjaan. Teksnya kapitalisasi biasa, bukan huruf besar semua.
- **Baris "Yang disinkronkan"** berisi chip ✓/– yang berbeda per metode (3.9). Pengguna langsung melihat apa yang ikut dan apa yang tidak sebelum memilih metode.
- **Metode berlabel "Segera hadir"** tampil di daftar dengan satu baris keterangan dan lencana *Segera hadir*. Di aplikasi, baris ini belum bisa dipilih. Kalau diketuk, muncul lembar singkat berisi diagram metode itu dan keterangan "Segera hadir", supaya pengguna tetap paham bedanya.
- Tombol **(?)** di kanan atas memutar ulang mode *Penjelasan* (3.9).
- Aksi utama di kartu berubah sesuai status: **Hubungkan sinkronisasi** (Lokal), **Sinkronkan sekarang** (tersinkron), **Coba lagi** (menunggu), **Masuk lagi** (perlu tindakan), atau tombol nonaktif saat sedang berjalan.
- Label grup ditulis dengan kapitalisasi kalimat biasa.

Subtitle baris di More: "Mati", "Suwayomi · 2 menit lalu", "Menunggu server", atau "Perlu masuk lagi".

Mengganti metode, misalnya dari Suwayomi ke iCloud, menghapus link dan base milik metode lama. Data di iPhone tetap ada. Metode baru dimulai dari sambungan pertama.

### 3.3 Alur menghubungkan Suwayomi

1. **Alamat server**: kolom alamat dan *Cari di jaringan saya*, memakai ulang UI langkah server di onboarding.
2. **Masuk**: tanpa auth, basic, atau login UI.
3. **Analisis (otomatis, tidak menulis apa pun)**: tarik library server dan petakan ke iPhone.
4. Cabang:
   - **Library iPhone kosong**: langsung salin dari server. Muncul toast "130 series disalin dari server".
   - **Library server kosong**: langsung kirim dari iPhone. Muncul toast "38 series dikirim ke server, 4 hanya di iPhone".
   - **Keduanya punya data, tapi semuanya sudah cocok**: langsung sync.
   - **Keduanya punya data yang berbeda**: tampilkan pemeriksaan.

     ```
     iPhone      42 series
     Server     130 series
     Cocok       30
     Hanya di iPhone   12  (8 bisa dikirim, 4 tidak bisa: import/repo Kuchie)
     Hanya di server  100  (95 extension terpasang di iPhone, 5 belum)

     ● Gabungkan
     ○ Pakai data server   (12 series dihapus dari library iPhone. Unduhan tetap ada.)
     ○ Pakai data iPhone   (100 series dihapus dari library server)
     ```

5. Kalau server punya extension store atau extension yang belum ada di iPhone, muncul kartu saran setelah sync pertama (lihat 3.5).

### 3.4 Detail Suwayomi

```
Server Suwayomi
  Alamat                 192.168.1.10:4567      ›
  Akun                   reza                   ›
PERLU PERHATIAN                (hanya muncul kalau ada isinya)
  4 series hanya di iPhone               ›
  5 extension bisa dipasang              ›
  Lanjutan                               ›
---
  Putuskan koneksi

Lanjutan
  YANG DISINKRONKAN
    Library & kategori                   [on]
    Progres baca & riwayat               [on]
    Bookmark chapter                     [on]
    Setelan reader per series            [on]
    Rating, tag & catatan                [off]
  Alamat cadangan (di luar rumah)        ›
  Pengaturan server Suwayomi             ›
```

- Halaman utama hanya berisi hal yang perlu diperhatikan. Semua toggle ada di **Lanjutan**, dengan default yang tidak perlu diubah oleh kebanyakan pengguna.
- **Tracker** tidak punya setelan. Kalau manga sudah punya track di server, server yang mengirim update. Kalau belum, iPhone yang mengirim. Dengan begitu progres tidak pernah terkirim dua kali.

- **Rating, tag & catatan** mati secara default. Pengecualian: dinyalakan otomatis kalau server sudah punya `flutter_rating` atau `flutter_tags`, misalnya untuk pengguna yang dimigrasi dari mode Server.
- **Putuskan koneksi**: data tetap di iPhone. Link dan base dihapus.

### 3.5 Saran extension

Sumber dan tampilannya:

- Detail Suwayomi → *Extension belum terpasang*.
- Kartu setelah sync pertama.

```
Extension di server yang belum ada di iPhone
  Store Keiyoushi            [Tambahkan store]
  MangaDex (en)      12 series   [Pasang]
  Asura Scans (en)    4 series   [Pasang]
Extension di iPhone yang belum ada di server
  Komikcast (id)      3 series   [Pasang di server]
```

- Diurutkan berdasarkan jumlah series yang akan bisa disinkronkan.
- *Tambahkan store* memakai `indexUrl` dan `signingKey` dari server, lalu meminta konfirmasi.
- Store di iPhone dan di server dianggap sama kalau `signingKey`-nya sama, **bukan** karena URL-nya sama. Untuk Keiyoushi, Kuchie menyimpan `…/repo/index.json`, sedangkan server menyimpan `…/raw/repo/index.pb` (S7). Extension dicocokkan lewat `pkgName`.
- Kuchie tidak pernah memasang apa pun tanpa ketukan pengguna.

**Di mana extension dipasang: pengguna tidak memilih.** Pilihan "pasang di iPhone atau di server" untuk setiap extension membuat pengguna harus paham arsitekturnya. Kuchie memakai aturan tetap:

| Situasi | Tombol **Pasang** melakukan |
|---|---|
| Sync Suwayomi mati | Pasang di iPhone (seperti sekarang). |
| Sync aktif, build punya Mihon runtime | Pasang di iPhone, **dan** di server kalau store yang sama ada di server. Keterangan kecil di bawah tombol: "Juga dipasang di server". |
| Sync aktif, build tanpa Mihon runtime | Pasang di server saja. Series dibaca lewat server. |
| Extension sudah ada di server, belum di iPhone | Pasang di iPhone. |

- Tujuannya supaya kedua sisi selalu punya extension yang sama, sehingga semua series bisa dipetakan dan klien lain yang memakai server juga bisa membacanya.
- Setiap baris extension menampilkan badge lokasi: `iPhone`, `Server`, atau `iPhone + Server`. Badge ini hanya informasi, bukan pilihan.
- **Hapus** hanya menghapus dari iPhone. Server bisa dipakai klien lain, jadi menghapus dari server tetap dilakukan di **Lanjutan → Pengaturan server Suwayomi**.
- Pemeriksaan tanda tangan APK di iPhone tetap berjalan seperti sekarang. Server memeriksa extensionnya sendiri.

**Dari mana chapter diambil: otomatis.**

1. Chapter yang sudah diunduh di iPhone dibaca dari iPhone.
2. Kalau extension terpasang di iPhone, chapter diambil langsung dari internet lewat iPhone. Ini tidak bergantung pada server, jadi tetap jalan di luar rumah.
3. Kalau extension hanya ada di server, chapter diambil lewat server.

### 3.6 Unduhan: disimpan di mana

**Aturan: satu chapter, satu tempat.** Tombol **Unduh** tetap satu. Lokasinya mengikuti apakah server terhubung:

| Kondisi | **Unduh** menyimpan ke | Alasan |
|---|---|---|
| Sync Suwayomi mati | iPhone | Tidak ada tempat lain. |
| Sync Suwayomi aktif | Server (`enqueueChapterDownloads`) | Ruang disk server biasanya jauh lebih besar, dan iPhone tidak ikut penuh. Klien lain juga bisa membaca chapter itu. |

Kuchie tidak pernah menyimpan chapter yang sama di dua tempat secara otomatis. Satu-satunya cara chapter ada di iPhone dan di server sekaligus adalah lewat aksi eksplisit di bawah.

**Simpan untuk offline** (menu chapter, aksi massal, dan menu series): menyimpan salinan di iPhone, misalnya sebelum bepergian atau naik pesawat.

- Kalau chapternya sudah ada di server, salinan diambil dari server. Di jaringan rumah ini lebih cepat dan tidak membebani situs source.
- Ada juga **Hapus salinan offline**. Setelan *Hapus setelah dibaca* yang sudah ada berlaku untuk salinan ini.

**Cara membaca chapter yang diunduh di server.** Urutan otomatis, tanpa pilihan untuk pengguna:

1. Ada salinan offline di iPhone: baca dari iPhone.
2. Server terjangkau: baca dari server, termasuk lewat alamat cadangan seperti Tailscale.
3. Server tidak terjangkau, tapi extension terpasang di iPhone (selalu benar untuk extension yang dipasang lewat aturan 3.5): **baca langsung dari source lewat internet**, sama seperti chapter yang belum diunduh.
4. Tidak ada internet sama sekali: chapter tidak bisa dibuka. Pesannya: "Chapter ini disimpan di server. Gunakan *Simpan untuk offline* supaya bisa dibaca tanpa internet."

Jadi chapter yang diunduh di server **tidak pernah terkunci menunggu server**. Yang hilang saat server tidak terjangkau hanya kemampuan membacanya tanpa internet.

**Penanda di daftar chapter** (satu ikon per chapter, tidak bertumpuk):

| Ikon | Arti |
|---|---|
| iPhone | Bisa dibaca tanpa internet. |
| Server | Tersimpan di server. |
| iPhone + Server | Ada salinan offline dari chapter yang juga ada di server. |

**Saat koneksi server diputus** (*Putuskan koneksi*):

- Chapter di server tetap ada di server dan tidak dihapus.
- Di iPhone, chapter itu kembali tampil sebagai chapter biasa yang bisa dibaca online lewat extension iPhone. Salinan offline tetap ada.
- Dialog konfirmasi menawarkan langkah opsional: "Ada 320 chapter di server. **Simpan semuanya ke iPhone** sebelum memutus koneksi? (2,4 GB, ruang kosong 18 GB)". Pilihan lainnya: *Putuskan saja*.
- Pengguna yang tidak mau terhubung ke server lagi tidak kehilangan akses. Library, progres, dan extension semuanya ada di iPhone.

**Kuota iPhone tetap aman.** Halaman *Penyimpanan* yang sudah ada menampilkan ukuran salinan offline secara terpisah dari cache.

#### Pindahkan unduhan iPhone ke server

Untuk pengguna yang sudah punya banyak unduhan di iPhone sebelum terhubung ke server, atau yang ingin melegakan ruang iPhone.

**Tempat aksi ini muncul:**

| Tempat | Bentuk |
|---|---|
| Setelah sambungan pertama, kalau iPhone punya unduhan | Kartu satu kali: "Ada 2,4 GB unduhan di iPhone. **Pindahkan ke server**?" |
| More → Penyimpanan (`_LocalStorageSettings`) | Baris **Pindahkan ke server**, ditambah tombol per series di daftar yang sudah diurutkan berdasarkan ukuran. |
| Menu series dan pilih banyak chapter | **Pindahkan ke server**. |

**Lembar konfirmasi** (satu lembar, dua pilihan jelas):

```
Pindahkan 86 chapter ke server
Server akan mengunduh chapter ini dari source-nya.

● Hapus dari iPhone setelah tersimpan di server
  Hemat 1,8 GB
○ Tetap simpan juga di iPhone
  Bisa dibaca tanpa internet

3 chapter tidak bisa dipindah (import file / repo Kuchie)   ›

[ Pindahkan ]
```

Default-nya *Hapus dari iPhone*, karena itu alasan utama pengguna memakai fitur ini.

**Cara kerjanya:**

- Suwayomi tidak punya API untuk mengunggah file chapter. Mutasi `Upload` hanya untuk file extension. Jadi Kuchie tidak mengunggah file. Kuchie meminta server mengunduh chapter yang sama dari source lewat `enqueueChapterDownloads`.
- Keuntungannya: kuota data iPhone tidak terpakai untuk upload, dan prosesnya tetap jalan walau Kuchie ditutup.
- Urutan per chapter:
  1. Pastikan chapter terpetakan ke server: series punya link, dan URL chapter cocok.
  2. Antrekan unduhan di server.
  3. Tunggu sampai server melaporkan `isDownloaded = true` dan `pageCount` sama dengan jumlah halaman di iPhone. Kedua syarat wajib: di mode folder, saat disk penuh, server melaporkan `isDownloaded = true` dengan `pageCount` sama dengan jumlah file yang sempat ditulis (S8: 7 dari 22). Status `ERROR` di antrean berarti gagal (source error atau chapter hilang). Alasan pastinya tidak tersedia lewat API.
  4. **Baru setelah itu** salinan iPhone dihapus, kalau pengguna memilih *Hapus dari iPhone*. Penanda chapter berubah dari `iPhone` menjadi `Server`, atau `iPhone + Server` kalau disimpan.
- **Salinan iPhone tidak pernah dihapus sebelum server terbukti punya chapternya.** Kalau server gagal mengunduh (chapter sudah dihapus dari source, source error, atau disk server penuh), salinan iPhone tetap ada. Chapter itu masuk daftar "Tidak bisa dipindah" dengan alasannya dan tombol *Coba lagi*.

- *Unduh ke server* biasa memakai bukti yang sama. Jumlah halaman yang diharapkan diambil dari `fetchChapterPages` sebelum chapter diantrekan.
- Detail Suwayomi menyarankan "Simpan unduhan server sebagai CBZ" kalau `downloadAsCbz = false`. Di mode CBZ, disk penuh menghasilkan `ERROR` yang jujur (S8). Kuchie tidak mengubah setelan ini tanpa ketukan pengguna.
- Halaman yang hilang dari disk server setelah sukses tetap dilayani server dari source tanpa tanda apa pun. Kasus ini tidak bisa dideteksi lewat API dan di luar jaminan Kuchie.

**Progres:**

- Baris di halaman Unduhan: "Memindahkan ke server · 34/86 · 0,7 GB dilegakan".
- Live Activity dan Dynamic Island yang sudah ada untuk unduhan dipakai ulang.

**Kalau server terputus di tengah proses:** pekerjaan dijeda dan dilanjutkan otomatis saat server terjangkau. Chapter yang belum terkonfirmasi tetap ada di iPhone. Status pekerjaan disimpan di catalog, jadi tetap aman kalau Kuchie ditutup paksa.

**Yang tidak bisa dipindah:** import CBZ/folder, repo Kuchie v1, dan Shinigami bawaan, karena server tidak punya source-nya. Chapter seperti ini tetap di iPhone dan disebut jelas di lembar konfirmasi. Mengunggahnya ke folder *local source* di server butuh akses file ke server (SMB/WebDAV), jadi bukan target rencana ini.

**Arah sebaliknya** sudah tercakup oleh *Simpan untuk offline*. Chapter di server sengaja tidak ikut dihapus, karena server berfungsi sebagai arsip dan bisa dipakai klien lain. Menghapus dari server tetap tersedia lewat menu chapter: **Hapus dari server**.

### 3.7 Onboarding

Pilihan Local/Server dihapus. Ada langkah opsional "Sudah punya server Suwayomi? **Hubungkan**" yang menuju alur 3.3. Selebihnya pengguna langsung masuk ke library Local.

### 3.8 Saat server tidak terjangkau

Suwayomi biasanya berjalan di jaringan rumah. Jadi berada di luar rumah adalah **kondisi normal, bukan error**. Karena library ada di iPhone, Kuchie tetap terbuka dan bisa dipakai seperti biasa.

| Fitur | Saat server tidak terjangkau |
|---|---|
| Library, kategori, riwayat, pencarian di library | Normal, karena semuanya dari iPhone. |
| Baca chapter yang sudah diunduh di iPhone (salinan offline) | Normal. |
| Baca chapter yang diunduh di server | Otomatis dibaca langsung dari source lewat extension iPhone. Butuh internet, tapi tidak butuh server (3.6). |
| Tombol **Unduh** | Diantre ke server, lalu terkirim saat server terjangkau. Butuh sekarang? Pakai *Simpan untuk offline*. |
| Baca chapter dari extension yang terpasang di iPhone | Normal, diambil langsung dari internet. |
| Browse dan cari di source iPhone, cek update | Normal. |
| Progres baca, tambah/hapus library, bookmark | Tersimpan di iPhone dan diantre. Terkirim otomatis saat server terjangkau lagi. |
| Series yang extensionnya hanya ada di server | Cover agak redup dengan label "Butuh server". Saat diketuk muncul pesan: "Server sedang tidak terjangkau. Chapter yang sudah diunduh tetap bisa dibaca." Pesannya disertai tombol *Coba lagi*. |
| Status antrean unduhan server | Menampilkan status terakhir yang diketahui, dengan keterangan "terakhir dilihat 2 jam lalu". |

Error dibedakan berdasarkan apakah pengguna perlu bertindak:

| Penyebab | Tampilan | Perlu tindakan? |
|---|---|---|
| Server tidak terjangkau (offline, di luar rumah, server mati) | Ikon Library abu-abu "Menunggu server". **Tanpa dialog, tanpa banner.** | Tidak. Kuchie mencoba lagi saat app dibuka, saat jaringan berubah, dan dengan backoff. |
| Tidak terjangkau lebih dari 7 hari | Satu banner di halaman Sinkronisasi: "Belum tersinkron sejak 3 Nov. Perubahan aman di iPhone." | Tidak, hanya informasi. |
| Login kedaluwarsa atau password berubah | Ikon merah, ditambah satu banner di Library: "Masuk lagi ke server". | **Ya**. |
| Server berbeda atau sudah di-reset | Sync dijeda. Banner meminta pengguna memilih *Sambungkan ulang* atau *Putuskan*. | **Ya**. |
| Sebagian series gagal (misalnya source error) | Masuk ke *Perlu perhatian* di halaman Detail. | Opsional. |

**Alamat cadangan** (Lanjutan, opsional): alamat kedua untuk dipakai di luar rumah, misalnya alamat Tailscale atau reverse proxy. Kuchie mencoba alamat utama dulu, lalu alamat cadangan. Pengguna tetap tidak perlu memahami ini untuk memakai Kuchie.

### 3.9 Diagram hidup di halaman Sinkronisasi

Tujuannya menjelaskan **sistem yang sebenarnya untuk setiap metode** lewat gambar yang bergerak. Setiap metode bekerja berbeda, jadi setiap metode punya topologi, jenis data yang bergerak, dan ritme animasi sendiri. Pola "kartu hero dengan animasi perangkat" dari aplikasi lain hanya menjadi inspirasi.

Prototipe interaktif (versi 4): https://claude.ai/artifact/UgsfGprka4iH1t9dYFQoSN. Sumbernya ada di [design/sync-prototype/index.html](../design/sync-prototype/index.html); buka langsung di browser.

#### Kosakata visual

Satu bentuk selalu berarti satu jenis data, di semua metode:

| Token | Bentuk | Arti |
|---|---|---|
| Cover | Persegi panjang kecil berwarna aksen | Perubahan library (tambah, hapus, kategori) |
| Titik berekor | Titik dengan tiga titik mengecil di belakangnya | Perubahan progres baca |
| Halaman | Kertas dengan sudut terlipat dan dua garis | Isi chapter (gambar halaman) |
| Paket | Kotak dengan tutup | Satu paket berisi seluruh data library (SyncYomi) |
| Pita | Pita penanda berwarna aksen kedua | Posisi baca di dalam chapter (KOReader Sync) |
| File | Dokumen dengan panah ke atas | Satu file sync berkala (Google Drive) |

| Node | Bentuk |
|---|---|
| iPhone | Ponsel dengan layar berisi angka, kisi cover yang menyala sesuai progres, dan bar progres |
| iPad / tablet | Tablet mendatar dengan angka dan bar |
| Mac | Monitor dengan kaki, angka, dan bar |
| Android | Ponsel dengan kamera berlubang, warna layar aksen kedua |
| E-reader | Layar abu-abu dengan baris teks, untuk KOReader |
| Pusat | Lingkaran dengan orbit putus-putus dan satelit kecil. Ikon di dalamnya sesuai metode: server berisi dua laci dengan LED, awan, panah sinkron (SyncYomi), buku dengan penanda (kosync), rak buku (Komga/Kavita), atau awan dengan dokumen (Drive) |
| Source | Globe kecil dengan meridian yang berputar |
| Belum terhubung | Lingkaran putus-putus dengan tanda +, berdenyut pelan |

Garis antar-node berbentuk lengkung S, dan garis ke Source berbentuk busur. Garis aktif punya jalur samar dengan putus-putus yang berjalan ke arah data.

#### Diagram per metode

| Metode | Topologi | Yang bergerak saat sync | Yang disinkronkan |
|---|---|---|---|
| **Lokal** (sync mati) | iPhone dan Source, ditambah lingkaran "+ Sync" putus-putus di kanan | Halaman dari Source ke iPhone. Bar penyimpanan di layar iPhone terisi. Label: "42 series · 2,4 GB" | ✓ Library di iPhone, ✓ Progres di iPhone, ✓ Unduhan di iPhone, – Antar perangkat |
| **Suwayomi** | iPhone ↔ Server ↔ iPad (Kuchie) dan Mac (WebUI Suwayomi). Source terhubung ke iPhone dan ke server | Cover dan titik bergantian dari iPhone ke server (jalur atas), titik dari server ke iPhone (jalur bawah), lalu diteruskan ke iPad dan Mac. Angka iPad dan Mac naik sedikit di belakang iPhone | ✓ Library, ✓ Progres, ✓ Unduhan di server, ✓ Perangkat lain |
| **iCloud** | iPhone ↔ awan iCloud ↔ iPad dan Mac (keduanya Kuchie). Source ke iPhone, ditambah garis tipis putus-putus Source ke iPad | Hanya cover dan titik. Tidak ada halaman yang lewat awan: garis tipis ke iPad menunjukkan setiap perangkat mengambil chapter sendiri | ✓ Library, ✓ Progres, ✓ Setelan, – Unduhan (tiap perangkat sendiri) |
| **SyncYomi** | iPhone ↔ server SyncYomi ↔ Android (Mihon) dan tablet (fork Tachiyomi). Source ke iPhone | **Paket** melompat berkala (setiap ±3,6 detik): iPhone ke server, lalu ke Android, lalu ke tablet. Angka di perangkat lain berubah dari 38/42 ke 42/42 saat paket tiba | ✓ Library, ✓ Kategori, ✓ Progres, – Unduhan |
| **KOReader Sync** | iPhone ↔ server kosync ↔ e-reader (KOReader). Source ke iPhone | Hanya **pita**, dua arah. Layar menunjukkan persen chapter yang sudah dibaca (51% di iPhone, 45% di e-reader, lalu sama) | ✓ Posisi baca per chapter, – Library, – Unduhan |
| **Komga / Kavita** | iPhone ↔ server dengan rak buku ↔ Mac (WebUI) dan iPad. **Tanpa Source** | **Arah terbalik**: halaman dari server ke iPhone (layar menghitung halaman 4/24), titik progres dari iPhone ke server, dan halaman dari server ke iPad | ✓ Koleksi file di server, ✓ Progres, ✓ Baca langsung, – Extension (tidak perlu) |
| **Google Drive** | iPhone ↔ Drive ↔ iPad dan Mac (Kuchie). Source ke iPhone | **Satu file** melompat sesekali (setiap ±4 detik): iPhone ke Drive ("Mengunggah file"), lalu Drive ke iPad dan Mac. Tidak ada satelit orbit, karena metode ini tidak bekerja terus-menerus | ✓ Library, ✓ Progres, – Langsung (berkala), – Unduhan |

#### Status

Setiap metode punya status **Menyinkronkan**, **Tersinkron**, dan **Menunggu**. Suwayomi juga punya **Memeriksa**, **Perlu tindakan**, **Unduh di server**, **Pindahkan ke server**, dan **Simpan untuk offline**. Lokal hanya punya satu keadaan.

| Status | Animasi (berlaku untuk semua metode yang punya status ini) |
|---|---|
| **Menyinkronkan** | Aliran token metode itu aktif. Orbit berputar cepat, riak muncul setiap ±1,1 detik, LED server berkedip, dan putus-putus garis berjalan cepat. Setiap token yang tiba membuat layar node tujuan berkedip dan membesar sekitar 7%. Angka di layar naik |
| **Tersinkron** | Aliran berhenti. Orbit berputar sangat pelan dan riak muncul setiap 4 detik. Setiap 6 detik satu denyut berjalan dari iPhone ke pusat, lalu bercabang ke perangkat lain. Centang muncul bergantian di setiap perangkat. Metode berkala (Drive, SyncYomi) tanpa denyut |
| **Menunggu** | Garis iPhone ↔ pusat terputus di tengah dengan tanda patah. Tiga titik antrean memantul di sisi iPhone, dan perangkat lain redup. Kalau metode punya Source, garis Source ke iPhone menyala dan halaman terus mengalir. Di Komga/Kavita tidak ada cadangan, jadi teksnya menjelaskan bahwa hanya unduhan yang bisa dibaca |
| **Memeriksa** (Suwayomi) | Garis digambar dari iPhone ke server, lalu cabang ke perangkat lain. Satu denyut bolak-balik, dan layar perangkat lain menampilkan titik-titik |
| **Perlu tindakan** (Suwayomi) | Semua diam. Ikon kunci merah di server bergoyang sekali |
| **Unduh di server** (Suwayomi) | Halaman dari Source ke server, dan label server berbunyi "Mengunduh 2/4" |
| **Pindahkan ke server** (Suwayomi) | Halaman dari iPhone ke server. Angka iPhone turun, label server "Diterima 34/86", dan status menyebut GB yang dilegakan |
| **Simpan untuk offline** (Suwayomi) | Halaman dari server ke iPhone, dan layar iPhone menghitung chapter (1/3) |

Perpindahan antar status dianimasikan sekitar 300 ms (opasitas node dan garis, warna). Perpindahan antar metode memudarkan seluruh diagram selama sekitar 350 ms, lalu membangun topologi baru.

#### Mode Penjelasan (pertama kali dan tombol ?)

Saat halaman dibuka pertama kali, atau saat pengguna mengetuk **(?)**, diagram memutar tiga langkah. Setiap langkah berdurasi sekitar 3,8 detik dan bisa diketuk untuk lanjut:

1. **"Tanpa sync, semuanya di iPhone."** Diagram Lokal.
2. **"Dengan sync, library dan progres ikut tersalin."** Diagram Suwayomi, status Menyinkronkan.
3. **"Server tidak terjangkau? Tetap bisa baca."** Diagram Suwayomi, status Menunggu.

Selama penjelasan, label node, baris Yang disinkronkan, teks status, dan tombol utama disembunyikan. Pill status berbunyi "Penjelasan 1/3", dan indikator tiga titik tampil di bawah diagram. Setelah langkah ketiga, diagram kembali ke metode dan status sebenarnya.

#### Kiri

Kiri muncul kecil di pojok kartu hanya di dua momen, memakai pose lavender di `assets/kuchie/character/`:

- `complete` sekali saat sync pertama selesai, selama sekitar 2,6 detik;
- `offline` beserta banner "Belum tersinkron sejak …" saat status Menunggu lebih dari 7 hari.

Pose model gelap tidak dipakai.

#### Gaya

- Mengikuti tema aplikasi (terang, gelap, hitam pekat) dan warna aksen yang dipilih pengguna. Kartu memakai warna permukaan tema, dengan latar titik-titik halus yang bergeser pelan untuk memberi kedalaman.
- Tidak ada latar gradien, *glow*, *blob* dekoratif, teks bergradien, atau lencana huruf besar seperti "LIVE"/"SYNC".
- Angka di layar perangkat memakai huruf tebal dengan lebar angka tetap.

#### Aksesibilitas dan performa

- **Reduce Motion** (`lib/src/utils/motion/reduce_motion.dart`): diagram menjadi frame statis per metode dan status. Aliran digambar sebagai panah di tengah garis, dan tidak ada orbit, riak, melayang, maupun kedipan. Mode Penjelasan menjadi tiga langkah yang diketuk manual.
- **VoiceOver**: diagram adalah satu node semantik yang membacakan teks status dan kalimat penjelasan. Baris Yang disinkronkan dibacakan sebagai daftar.
- Dibangun dengan `CustomPainter` dan satu ticker. Animasi berhenti saat kartu tidak terlihat atau app di background (`TickerMode`). Status diam tetap punya gerakan ambien pelan (orbit, latar). Gerakan ambien ini dibatasi sekitar 30 fps dan berhenti sama sekali saat Low Power Mode aktif.
- Teks tersedia dalam bahasa Inggris dan Indonesia.

#### Ikon status di Library (3.1)

Ikon kecil di judul Library adalah versi mini diagram: awan dengan centang, panah berputar, titik abu-abu, atau tanda seru merah. Mode Lokal tidak punya ikon. Mengetuk ikon membuka halaman Sinkronisasi dengan diagram pada metode dan status yang sama.

## 4. Arsitektur

Fitur baru di `lib/src/features/sync/` dan tetap mematuhi `test/architecture/layer_boundaries_test.dart`:

```
sync/
  domain/
    sync_method.dart          enum SyncMethod { none, suwayomi, icloud }
    sync_records.dart         SeriesRecord, ChapterStateRecord, CategoryRecord,
                              SeriesMetaRecord, ReaderMetaRecord, ExtensionRecord,
                              AppSettingRecord
    merge_rules.dart          fungsi murni, diuji secara tabel
  data/
    sync_journal.dart         outbox, link, base (tabel di catalog.sqlite)
    sync_backend.dart         interface SyncBackend
    suwayomi/
      graphql/sync.graphql
      suwayomi_backend.dart
      suwayomi_identity.dart  pemetaan source/url/kategori/extension
      suwayomi_downloads.dart status dan antrean unduhan server
    icloud/                   (setelah 2.0)
  controller/
    sync_engine.dart          pull → map → merge → apply → push → commit
    sync_scheduler.dart       pemicu
    sync_status.dart          provider status untuk ikon Library dan halaman
  presentation/
    sync_status_icon.dart
    sync_settings_screen.dart
    suwayomi_connect_flow.dart
    suwayomi_detail_screen.dart
    extension_suggestions.dart
    unsynced_series_screen.dart
```

```dart
abstract interface class SyncBackend {
  Set<SyncRecordKind> get supportedKinds; // Suwayomi: tanpa AppSetting
  bool canSync(LocalSeriesSource? source); // Suwayomi: hanya Mihon; iCloud: semua
  Future<RemoteSnapshot> pull({SyncCursor? since});
  Future<PushReport> push(List<SyncChange> changes, SyncLinks links);
}
```

### 4.1 Pencatatan perubahan

**Skema catalog v7** (`onUpgrade`, `if (from < 7)`):

```sql
CREATE TABLE sync_changes (
  seq INTEGER PRIMARY KEY AUTOINCREMENT,
  kind TEXT NOT NULL,   -- series | chapter_state | category | membership
                        -- | series_meta | reader_meta | app_setting
  key TEXT NOT NULL,
  op TEXT NOT NULL,     -- upsert | delete
  changed_at INTEGER NOT NULL
);
CREATE INDEX sync_changes_key ON sync_changes(kind, key);

CREATE TABLE sync_links (
  backend TEXT NOT NULL,
  kind TEXT NOT NULL,   -- series | chapter | category
  local_key TEXT NOT NULL,
  remote_id TEXT NOT NULL,
  PRIMARY KEY (backend, kind, local_key)
);

CREATE TABLE sync_base (
  backend TEXT NOT NULL,
  kind TEXT NOT NULL,
  key TEXT NOT NULL,
  value TEXT NOT NULL,  -- JSON kondisi terakhir yang disepakati
  PRIMARY KEY (backend, kind, key)
);
```

**Memindahkan setelan reader per series ke lapisan data.** Sekarang JSON `local.reader.manga.<id>` dibaca dan ditulis langsung di `reader_settings_model.dart`, yang ada di bawah `presentation/`. Buat `local_collection/data/local_series_reader_meta.dart` yang memegang baca/tulis dan mencatat ke outbox (`kind = reader_meta`). Reader settings model lalu memanggil kelas ini. Format dan kunci SharedPreferences tidak berubah, jadi tidak perlu migrasi data.

**Setelan aplikasi** (hanya untuk iCloud): allowlist eksplisit kunci SharedPreferences, misalnya tema, setelan reader global, dan tab. Yang **tidak** boleh ikut: kredensial, alamat server, pengaturan keamanan (app lock), path file, dan status per perangkat. Perubahan dicatat sebagai `app_setting` hanya saat metode iCloud aktif.

Aturan umum:

- Outbox hanya ditulis saat sync aktif. Saat pertama diaktifkan, pemindaian penuh menggantikan outbox.
- Mode penyamaran tidak menulis outbox.
- Perubahan yang diterapkan engine dari remote tidak masuk outbox (flag transaksi).
- Beberapa perubahan untuk key yang sama digabung saat push.

### 4.2 Aturan merge

Merge tiga arah: bandingkan nilai lokal, nilai remote, dan base.

| Lokal vs base | Remote vs base | Hasil |
|---|---|---|
| sama | sama | tidak ada perubahan |
| berubah | sama | lokal dikirim |
| sama | berubah | remote diterapkan |
| berubah | berubah | aturan konflik per field, di bawah |

| Data | Aturan konflik |
|---|---|
| **inLibrary** | **Membaca menang.** Kalau satu sisi menghapus dari library sementara sisi lain membaca series itu setelah sync terakhir, series tetap ada. Selain kasus itu, pakai waktu perubahan terbaru. |
| Read / unread chapter | Paling baru menang. Kalau waktunya tidak jelas, *read* menang. |
| Halaman terakhir | Pilih nilai dengan waktu baca terbaru. Kalau tidak bisa dibedakan, pilih halaman terjauh. |
| Bookmark | `true` menang. |
| Keanggotaan kategori | Diproses per elemen. Penambahan dan penghapusan digabung dari kedua sisi. |
| Riwayat | Digabung (union), dengan `last_read_at` terbesar. |
| Rating, tag, catatan | Per field, nilai terbaru menang. Kunci server: `flutter_rating`, `flutter_tags`, `kuchie_notes` (baru). |
| Setelan reader per series | Per kunci meta, nilai terbaru menang. Kunci yang tidak dikenal dari server (misalnya milik WebUI) dibiarkan dan tidak dihapus. |
| Daftar extension | Tidak di-merge. Hanya menghasilkan saran (3.5). |
| Status unduhan server | Hanya dibaca dari server, tidak ada merge. |
| Setelan aplikasi (iCloud) | Per kunci, nilai terbaru menang. |
| Nama series lokal | Hanya lokal, tidak dikirim. |

**Waktu dari server (S2).**

- `lastReadAt` di server dalam **detik** epoch, dan nilainya adalah waktu server menerima mutasi terakhir yang membawa `lastPageRead`, bukan waktu baca sebenarnya. Mengubah `isRead` atau bookmark tidak menggesernya.
- Jadi "paling baru menang" hanya pemecah seri setelah base tiga arah. Kalau waktu tidak bisa dibandingkan dengan jujur, pakai fallback di tabel (read menang, halaman terjauh).
- `inLibraryAt` diisi ulang setiap kali `inLibrary: true` dikirim, juga saat series sudah ada di library. Kuchie hanya mengirimnya saat series benar-benar belum ada di library server.

### 4.3 Satu siklus sync

1. **Preflight**: identitas server cocok, auth valid, dan aturan jaringan terpenuhi. Kalau identitas server berubah, sync dihentikan dan pengguna ditanya.
2. **Pull**:
   - Library beserta kategori dan metadata (`meta` dengan kunci rating/tag/catatan/reader).
   - State chapter secara bertahap: sidik jari per series (`unreadCount`, `bookmarkCount`, `downloadCount`, `lastReadChapter { id lastReadAt }`) ditambah chapter dengan `lastReadAt > kursor`, lalu chapter dari series yang sidik jarinya berubah dimuat ulang. Kursor `lastReadAt` saja tidak cukup, karena perubahan `isRead`/bookmark dari klien lain tidak menggesernya (S2). Untuk 554 series / 50 ribu chapter: 0,54 detik (S5).
   - Rekonsiliasi penuh saat sync manual dan sekali sehari: semua chapter library dalam satu query, sekitar 1 detik dan 0,3 MB gzip untuk 50 ribu chapter (S5). Kalau perlu paging, pakai cursor tanpa `orderBy`: kombinasi filter `inLibrary` + `orderBy` + `first` memicu bug H2 di server.
   - `fetchMangaAndChapters` yang menjawab error `No chapters found` diperlakukan sebagai daftar kosong.
   - Status unduhan untuk series yang sedang dibuka saja, tidak untuk seluruh library, supaya pull tetap ringan.
   - Daftar extension dan store, setiap hari atau saat halaman Detail dibuka.
3. **Pemetaan**: manga server tanpa pasangan lokal dibuat sebagai `series` kalau extensionnya terpasang di iPhone. Kalau belum, masuk daftar saran.
4. **Merge**, lalu **terapkan lokal** dalam satu transaksi lewat antrean serial catalog.
5. **Push**:
   - Series baru: cari `mangas(condition: {sourceId, url})`. Kalau belum ada, buat lewat `restoreBackup` dengan backup Mihon minimal (`source`, `url`, `title`, `favorite`; S3: 50/50, tanpa akses source), lalu `fetchMangaAndChapters`. `restoreStatus` tidak melaporkan jumlah dengan benar, jadi hasilnya dicek dengan query ulang.
   - Kirim batch `updateMangas`, `updateMangasCategories`, `updateChapters`, `setMangaMetas`.
   - Progres yang tidak bisa dikirim lewat `updateChapters`, yaitu `lastPageRead` pada chapter yang belum pernah dibuka server dan waktu baca asli dari iPhone, dikirim lewat `restoreBackup` (chapter + riwayat). Restore hanya bisa menaikkan nilai: halaman terjauh, read, bookmark, dan waktu terbaru. Unread dan penurunan nilai tetap lewat `updateChapters`.
   - `isRead: true` dikirim bersama `lastPageRead`, supaya riwayat server ikut terisi.
   - Kegagalan per series dicatat dan dicoba lagi dengan backoff.
6. **Commit**: perbarui base dan kursor, lalu pangkas outbox.

Hanya satu sync boleh berjalan dalam satu waktu. Pemicu baru yang datang saat sync berjalan ditandai supaya ada satu putaran lagi setelahnya.

### 4.4 Pemicu

- Foreground, dengan jeda minimal 5 menit.
- Reader ditutup atau chapter selesai: push saja, ditunda sekitar 10 detik.
- Manual: tombol *Sinkronkan sekarang*, ikon Library, dan pull-to-refresh di Library.
- Background: `workmanager` / `BGAppRefreshTask`, best effort.

### 4.5 Runtime koneksi

- `suwayomiSyncEnabledProvider` membuat klien GraphQL ringan dari provider `server_connection`, tanpa `AccountSessionStartup`. Terbukti di S4 untuk UI login (Bearer + refresh), basic auth, dan simple login (cookie).
- Token kedaluwarsa dijawab sebagai error GraphQL `Unauthorized` dengan HTTP 200, bukan 401. Klien refresh sekali, lalu menampilkan banner login kalau masih gagal. Refresh token tidak dirotasi.
- Preflight memeriksa auth dengan query data library. `aboutServer` tetap terbuka di semua mode.
- Selama transisi, satu konfigurasi server dipakai bersama oleh Sync dan mode Server.

### 4.6 Tracker

Tidak ada setelan. Collection Local saat ini **tidak punya tracker sendiri**: tombol Tracking di series Local hanya menampilkan dialog "hubungkan server" (`local_extension_browser.dart`, sekitar baris 3428).

- Saat sync Suwayomi aktif, tombol Tracking untuk series yang terhubung ke server membuka UI tracking server yang sudah ada (`features/tracking`), memakai ID manga di server. Server yang mengirim update ke AniList, MAL, dan tracker lain, berdasarkan progres yang disinkronkan.
- Series yang tidak terhubung (import, repo Kuchie) tetap menampilkan dialog dengan alasan yang lebih jelas.
- Karena hanya server yang mengirim update, progres tidak pernah terkirim dua kali.

## 5. Spike

| # | Pertanyaan | Kenapa penting |
|---|---|---|
| S1 | Apakah `stableLocator` Kuchie sama persis dengan `url` manga dan chapter di Suwayomi untuk extension yang sama? | Seluruh pemetaan bergantung pada ini. |
| S2 | Apa yang dilakukan `updateChapters` terhadap `lastReadAt`? | Aturan konflik dan pull bertahap. |
| S3 | Cara paling andal membuat baris manga di server: `fetchSourceManga(SEARCH)` lalu cocokkan URL, atau `restoreBackup` dengan backup minimal? | Push series baru dan "Pakai data iPhone". |
| S4 | Apakah token login UI bisa dipakai klien ringan? | Bagian 4.5. |
| S5 | Kinerja pull untuk library 500+ series dengan 50.000+ chapter. | Ukuran halaman query. |
| S6 | Apakah entitlement iCloud tersedia untuk IPA yang di-sign lewat AltStore/SideStore dengan Apple ID gratis maupun berbayar? | Menentukan apakah iCloud harus menunggu App Store. |
| S7 | Apakah `pkgName` di Suwayomi sama dengan `<paket>` di `sourceId` Local, dan apakah `signingKey` store di server cocok dengan format yang diperiksa Kuchie? | Saran extension (3.5). |

| S8 | Apakah `enqueueChapterDownloads` lalu `isDownloaded` dan `pageCount` cukup sebagai bukti bahwa chapter utuh di server? Bagaimana server melaporkan chapter yang sudah dihapus dari source? | Syarat aman sebelum menghapus salinan iPhone. |

S1–S3, S7, dan S8 diuji dengan `tool/qa/server.py` ditambah extension Mihon yang sama di simulator (`tool/qa/run_simulator_local.sh`).

**Hasil (27 November 2026), detail di [sync-spike-results.md](sync-spike-results.md):**

- S1 lolos 100%.
- S2 terdokumentasi.
- S3 lolos lewat `restoreBackup`.
- S4 lolos.
- S5 lolos jauh di bawah ambang.
- S6 belum diuji di perangkat. Apple tidak memberi kapabilitas iCloud ke Personal Team, jadi iCloud menunggu App Store/TestFlight.
- S7 lolos lewat `signingKey` dan `pkgName`. URL store berbeda.
- S8 gagal di mode folder saat disk penuh. Ditangani dengan pemeriksaan jumlah halaman dan saran CBZ.

## 6. Fase

Semua fase dikerjakan di branch integrasi `feature/sync` dan **dirilis sekaligus sebagai Kuchie 2.0**. Fase di bawah adalah urutan kerja, bukan rilis terpisah. Rincian per PR ada di [sync-implementation-plan.md](sync-implementation-plan.md).

| Fase | Isi |
|---|---|
| 0 | Spike S1–S8 |
| 1 | Skema v7, hook outbox di semua titik tulis catalog, `local_series_reader_meta.dart`, `merge_rules` beserta tesnya |
| 2 | Halaman Sinkronisasi, alur hubungkan dengan analisis dan pemeriksaan, ikon status Library |
| 3 | Engine: library, kategori, progres, bookmark, riwayat. Pemicu foreground, manual, selesai baca, dan background. |
| 4 | Rating/tag/catatan, setelan reader per series, saran extension dan Pasang ganda, tracking lewat server, Perlu perhatian, log |
| 5 | Unduh ke server, *Simpan untuk offline*, **Pindahkan ke server**, penanda lokasi, **Ambil chapter lewat Server**, urutan baca otomatis, Putuskan koneksi |
| 6 | Onboarding baru dan **hapus mode Server** |
| 7 | QA penuh, pemakaian harian satu minggu, dokumentasi, lalu **rilis 2.0** |
| 8 | Backend iCloud setelah 2.0, bergantung pada S6 dan distribusi App Store/TestFlight |

## 7. Migrasi pengguna mode Server

**Tidak ada.** Saat ini belum ada pengguna selain developer sendiri, jadi mode Server langsung dihapus di 2.0 tanpa jalur migrasi, tanpa layar sambutan, dan tanpa kompatibilitas mundur.

- iPhone developer yang dulu memakai mode Server cukup menghubungkan server lewat alur biasa (3.3) lalu memilih *Pakai data server*. Rating, tag, dan setelan reader ikut tersalin karena kuncinya sama.
- Migrasi skema `catalog.sqlite` v6 → v7 tetap ada untuk melindungi library Local.
- UI server yang masih berguna (extension server, backup server, pengaturan Suwayomi, antrean unduhan server) pindah ke **Sinkronisasi → Suwayomi → Lanjutan → Server**.

## 8. Pengujian

- **Unit**:
  - Tabel kombinasi merge tiga arah untuk setiap jenis data.
  - Pemetaan identitas source/URL/kategori/extension.
  - Setiap titik tulis, termasuk `local_series_reader_meta`, menghasilkan outbox, dan penerapan dari remote tidak menghasilkannya.
  - Allowlist setelan aplikasi menolak kunci sensitif.
- **Integrasi** dengan server Suwayomi QA:
  1. Sambungan pertama: iPhone kosong, server kosong, sudah cocok, dan berbeda (ketiga cara gabung).
  2. Baca di iPhone, lalu cek di WebUI.
  3. Baca di WebUI, lalu cek di iPhone.
  4. Tandai unread.
  5. Hapus di satu sisi sambil membaca di sisi lain (membaca menang).
  6. Kategori: ganti nama dan pindahkan series.
  7. Ubah mode reader per series di satu sisi, lalu cek di sisi lain.
  8. Rating/tag dari data mode Server lama.
  9. Saran extension, lalu pasang, lalu series yang sebelumnya tidak cocok ikut tersinkron.
  10. Unduh di server dan status muncul di iPhone.
  11. Offline lalu sambung kembali. Selama offline: library, baca dari extension iPhone, dan baca unduhan tetap jalan, tanpa dialog error. Series yang hanya ada di server menampilkan "Butuh server".
  11a. Login kedaluwarsa memunculkan banner. Server di-reset menjeda sync.
  11b. Pasang extension saat sync aktif: extension terpasang di kedua sisi, dan badge lokasi benar.
  11c. Pindahkan ke server:
       - dengan *Hapus dari iPhone* dan dengan *Tetap simpan*;
       - server terputus di tengah proses;
       - Kuchie ditutup paksa;
       - chapter sudah dihapus dari source (salinan iPhone harus tetap ada);
       - disk server penuh.
  12. Server di-reset.
  13. Login sebagai pengguna lain.
  14. Ganti metode sync.
- **UI**: ikon status Library di kelima status, dengan VoiceOver dan Reduce Motion.
- **Arsitektur**: `layer_boundaries_test.dart` tetap hijau.

## 9. Keputusan yang masih terbuka

1. Nama kunci catatan di server: `kuchie_notes` atau `flutter_notes`, supaya seragam dengan kunci lama?
2. Selama transisi, apakah Sync dan mode Server memakai satu konfigurasi server? Rekomendasi: ya.
3. ~~Interval rekonsiliasi penuh: harian atau hanya saat sync manual?~~ Diputuskan: keduanya. Biayanya sekitar 1 detik untuk 50 ribu chapter (S5).
4. iCloud: CloudKit (record per series/chapter) atau file database di iCloud Drive? Rekomendasi: CloudKit, karena aman dari konflik file.
5. Daftar persis kunci setelan aplikasi yang ikut sync lewat iCloud.
6. Versi Suwayomi minimum untuk 2.0. `schema.graphql` di repo memakai `user { … }` dari build yang lebih baru daripada Stable v2.4.2366 yang dipakai spike. `LegacyUserFieldsLink` sudah menulis ulang field itu untuk server lama, tapi perilaku server multi-pengguna belum diuji. S2, S3b, S4, dan S8 perlu diulang dengan JAR preview sebelum PR 5.
