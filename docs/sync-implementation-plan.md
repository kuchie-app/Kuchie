# Rencana implementasi: Sinkronisasi Suwayomi

Dokumen ini menerjemahkan desain di [sync-plan.md](sync-plan.md) menjadi urutan pekerjaan yang bisa langsung dikerjakan. Penomoran bagian seperti "3.6" merujuk ke dokumen desain itu.

Basis kode: Kuchie 1.2.1 (`kuchie-app/Kuchie` main, `17c29a9`).

---

## 1. Cara kerja

### 1.1 Strategi rilis: satu rilis penuh (Kuchie 2.0)

Semua perubahan dirilis **sekaligus** sebagai Kuchie 2.0: satu library, Sinkronisasi Suwayomi, unduhan ke server, Pindahkan ke server, onboarding baru, dan mode Server dihapus.

**Saat ini belum ada pengguna selain developer sendiri.** Konsekuensinya untuk rencana ini:

- **Tidak ada migrasi pengguna mode Server.** Mode Server langsung dihapus. Tidak perlu kartu migrasi, migrasi otomatis, layar sambutan, pemindahan chapter `features/offline`, atau jalan mundur ke 1.2.1.
- **Tidak ada beta publik.** Pengujian cukup lewat QA di simulator dan pemakaian harian di iPhone sendiri sebelum rilis.
- **Tidak ada kompatibilitas mundur** untuk preferensi lama mode Server. Kunci SharedPreferences yang tidak dipakai lagi cukup dibiarkan atau dihapus di PR 19.
- **Yang tetap dijaga:**
  - migrasi skema `catalog.sqlite` v6 → v7 (kecil, dan melindungi library milik sendiri);
  - spike sebelum menulis kode, karena hasilnya bisa mengubah desain.

### 1.2 Branch

- Mulai dari **`kuchie/main`** (1.2.1), **bukan** `main` lokal. `main` lokal tertinggal dan punya banyak perubahan yang belum di-commit.

  ```sh
  git fetch kuchie
  git switch -c feature/sync kuchie/main      # branch integrasi 2.0
  ```

- Setiap PR di bagian 3 dibuat dari `feature/sync` dan digabung kembali ke `feature/sync`, supaya diff tetap kecil dan mudah direview. `main` tetap berisi aplikasi yang bisa dipakai sehari-hari selama pengerjaan.
- `feature/sync` digabung ke `main` sekali, di PR rilis.

### 1.3 Konvensi yang harus diikuti

- Lapisan: `data/`, `domain/`, dan `controller/` tidak boleh import `presentation/` (`test/architecture/layer_boundaries_test.dart`).
- Teks UI: `localText(context, 'English', 'Indonesia')` di area Local, seperti kode sekarang. Teks yang dipakai bersama masuk ke file ARB.
- GraphQL: dokumen `.graphql` di samping fitur, lalu `tool/bootstrap` untuk codegen (`graphql_codegen`, output `__generated__`). `test/graphql_operation_variables_test.dart` harus tetap hijau.
- Tes: `test/src/features/sync/...`. Fake memakai `test/helpers/local_collection_fakes.dart` dan `test/helpers/unreachable_server_stubs.dart`.
- Setiap PR harus lolos `flutter analyze`, `flutter test`, dan `flutter build ios --simulator --debug --no-codesign`.

---

## 2. Peta titik integrasi di kode

| Kebutuhan | Lokasi sekarang | Perubahan |
|---|---|---|
| Penulisan data library | `local_collection/data/local_catalog.dart`: `setInLibrary`, `setProgress`, `recordRemoteRead`, `removeFromHistory`, `clearHistory`, `setChapterMarks`, `setBookmark`, `setCategories`, `createCategory`, `deleteCategory`, `setRating`, `setNotes`, `setTags`. Semuanya lewat `_metadata.run` dan `db.transaction`. | Catat ke outbox di transaksi yang sama. |
| Skema DB | `_CatalogDatabase`, `schemaVersion => 6` | Naik ke 7. Semua tabel sync dibuat di versi ini (bagian 4). |
| Setelan reader per series | `manga_book/presentation/reader/controller/reader_settings_model.dart`: `_localNamespace = 'local.reader.manga.'`, `_patchLocalMeta` | Pindah ke `local_collection/data/local_series_reader_meta.dart`. |
| Tab More Local | `local_collection/presentation/local_collection_home.dart`, `_more()` sekitar baris 862 | Baris Sinkronisasi. |
| Judul Library Local | `local_collection_home.dart`, judul tab | Ikon status sync. |
| Memuat chapter untuk dibaca | `local_extension_browser.dart`, `_load()` sekitar baris 3903: salinan iPhone, lalu `sources.chapterPages`, lalu `LocalPreviewPages` | Dipindah ke `ChapterPageResolver` (data) dengan urutan iPhone → server → source. |
| Tombol Unduh | `local_extension_browser.dart` sekitar baris 3716: `services.downloads.enqueue(LocalDownloadRequest(...))` | Diarahkan ke server saat sync aktif. |
| Tracking Local | `local_extension_browser.dart` sekitar baris 3428: dialog "hubungkan server" | Membuka UI `features/tracking` dengan ID manga server. |
| Layanan Local | `local_collection/data/local_collection_services.dart` (`catalog`, `sources`, `downloads`) | Tambah `sync` (engine, status, resolver). |
| Halaman Penyimpanan | `local_collection/presentation/local_settings.dart`, `_LocalStorageSettings` | Aksi *Pindahkan ke server*. |
| Live Activity | `ios/Shared/DownloadActivityAttributes.swift`, `ContentState.source` (`.device` / server) | Dipakai ulang untuk unduhan server dan pemindahan. Kemungkinan butuh field `transfer`. |
| Koneksi server | `settings/data/server_connection/*`, `features/auth`, `settings/data/sign_in` | Klien GraphQL sync yang ringan. |
| Gerbang runtime Server | `onboarding/data/collection_mode.dart`, `serverCollectionRuntimeEnabledProvider`, `main.dart` sekitar baris 236–262 | Sync punya provider sendiri. Gerbang ini dihapus di PR 19. |
| Perubahan jaringan | `connectivity_plus` (sudah dipakai di `server_url.dart:230`) | Pemicu sync. |
| Background iOS | `workmanager` diinisialisasi di `main.dart:139`. `Info.plist` **belum** punya `BGTaskSchedulerPermittedIdentifiers`. | Tambah identifier dan registrasi di `AppDelegate.swift`. |
| Migrasi preferensi | `settings/data/preference_migrations.dart` | Tidak perlu langkah migrasi pengguna (1.1). |

---

## 3. Urutan PR

Perkiraan ukuran: **S** ≤ 1 hari, **M** 2–4 hari, **L** 1–2 minggu. Ini untuk satu developer.

Semua PR digabung ke `feature/sync`. Tidak ada yang dirilis sebelum PR 21.

| # | PR | Ukuran | Bergantung pada |
|---|---|---|---|
| 0 | Spike S1–S8 | M | — |
| **Tahap A: fondasi** | | | |
| 1 | Domain sync dan aturan merge | M | 0 |
| 2 | Skema v7 dan journal | L | 1 |
| 3 | Setelan reader per series ke lapisan data | S | 2 |
| 4 | State dan koneksi sync | M | 0 |
| 5 | Dokumen GraphQL sync | S | 4 |
| **Tahap B: sync inti** | | | |
| 6 | Halaman Sinkronisasi, diagram hidup per metode, dan ikon Library | L | 4 |
| 7 | Alur hubungkan dan analisis | M | 2, 5, 6 |
| 8 | Engine: library, kategori, progres, riwayat | L | 7 |
| 9 | Pemicu dan background | M | 8 |
| **Tahap C: cakupan lengkap** | | | |
| 10 | Metadata series dan reader | S | 3, 8 |
| 11 | Extension: saran dan Pasang ganda | M | 8 |
| 12 | Tracking lewat server | S | 8 |
| 13 | Perlu perhatian dan log | S | 8 |
| **Tahap D: unduhan dan baca lewat server** | | | |
| 14 | `ChapterPageResolver` dan baca lewat server | M | 8 |
| 15 | Unduhan ke server dan Simpan untuk offline | L | 14 |
| 16 | Pindahkan ke server | M | 15 |
| 17 | Putuskan koneksi | S | 15 |
| **Tahap E: satu aplikasi** | | | |
| 18 | Onboarding baru | S | 7 |
| 19 | Hapus mode Server | L | 14, 15, 18 |
| **Tahap F: rilis** | | | |
| 20 | QA penuh dan dokumentasi | M | 9–19 |
| 21 | **Rilis Kuchie 2.0**: gabung `feature/sync` ke `main` | S | 20 |
| 22+ | iCloud | L | S6, distribusi |

- Jalur kritis: 0 → 1 → 2 → 7 → 8 → 14 → 15 → 19 → 20 → 21.
- PR 4–6 bisa paralel dengan 1–3. PR 10–13 saling independen setelah PR 8. PR 18 bisa dikerjakan kapan saja setelah PR 7. PR 16 dan 17 bisa paralel dengan 18.
- Perkiraan total untuk satu developer: kira-kira **2,5–3,5 bulan**. Jalur kritis kira-kira 8–10 minggu; sisanya tahap C dan pekerjaan paralel.

**Titik pemeriksaan internal.** Tidak dirilis, tapi diuji di perangkat sendiri dengan server nyata:

| Setelah | Yang dicek |
|---|---|
| PR 8 | Sync dua arah stabil selama seminggu pemakaian harian. |
| PR 15 | Unduhan ke server dan baca di luar rumah (server tidak terjangkau). |
| PR 19 | Aplikasi berjalan penuh tanpa mode Server: instalasi baru, hubungkan server, baca, unduh, dan pindahkan. |

---

## 4. Detail per PR

### PR 0: Spike

**Tujuan:** membuktikan asumsi sebelum membangun. Hasilnya dicatat di `docs/sync-spike-results.md`.

**Persiapan:**

- `python3 tool/qa/server.py --jar <Suwayomi-Server.jar>` (port 14567).
- `tool/qa/run_simulator_local.sh` dengan **satu extension Mihon yang sama** dipasang di simulator dan di server.
- Skrip di `tool/qa/sync_spike/`: skrip Dart CLI atau Python yang memanggil GraphQL langsung.

| Spike | Langkah | Lolos kalau | Kalau gagal |
|---|---|---|---|
| S1 URL | Ambil 20 series dan 200 chapter di simulator, catat `stableLocator`. Query `mangas(condition: {sourceId, url})` dan `chapters` di server. | ≥ 99% cocok persis. | Tulis normalizer URL per pola, lalu uji lagi. |
| S2 `lastReadAt` | `updateChapters(lastPageRead)`, lalu `updateChapters(isRead: false)`. Baca `user.lastReadAt` setiap kali. | Perilakunya terdokumentasi. | Aturan merge memakai base dan halaman terjauh saja. |
| S3 Buat manga | (a) `fetchSourceManga(SEARCH, judul)` lalu cocokkan URL. (b) `restoreBackup` dengan backup minimal. | Salah satu cara berhasil ≥ 95%. | Push series baru ditunda. v1 hanya menyinkronkan series yang sudah ada di kedua sisi. |
| S4 Auth | Login UI dan basic auth lewat klien ringan tanpa `AccountSessionStartup`. | Token valid dan refresh berjalan. | Pakai sesi penuh saat sync aktif. |
| S5 Kinerja | Seed 500 series dan 50 ribu chapter. Ukur pull penuh dan pull bertahap. | Pull penuh < 30 detik di LAN. Bertahap < 3 detik. | Paging per kategori dan rekonsiliasi bertahap. |
| S6 iCloud | Sign build dengan Apple ID gratis lewat SideStore, lalu dengan akun berbayar. Cek container CloudKit. | Terdokumentasi. | iCloud menunggu App Store. |
| S7 Extension | Bandingkan `pkgName` dan `signingKey` store server dengan `LocalSourcePackage`. | Cocok. | Pemetaan lewat nama dan bahasa (lebih lemah). |
| S8 Bukti unduhan | `enqueueChapterDownloads`, pantau `isDownloaded` dan `pageCount`. Ulangi dengan chapter yang sudah dihapus dari source dan dengan disk penuh. | Status gagal bisa dibedakan dari status sukses. | Tambah verifikasi `fetchChapterPages` dan cek jumlah halaman. |

**Selesai kalau:** semua hasil tercatat, keputusan untuk setiap kegagalan diambil, dan dokumen desain diperbarui.

**Status (27 November 2026):** selesai dengan server Stable v2.4.2366. Lihat [sync-spike-results.md](sync-spike-results.md). Dampaknya ke PR berikutnya:

- PR 1: aturan merge memperlakukan `lastReadAt` server sebagai pemecah seri dalam detik, bukan waktu baca.
- PR 5: dokumen GraphQL sync perlu encoder backup Mihon minimal untuk `restoreBackup` (rujukan: `tool/qa/sync_spike/backup.py`). Sebelum PR 5, ulangi S2, S3b, S4, dan S8 dengan JAR preview yang cocok dengan `schema.graphql` (`user { … }`), lalu putuskan versi minimum server.
- PR 8: push series baru lewat `restoreBackup`. Pull bertahap memakai sidik jari per series ditambah kursor `lastReadAt`.
- PR 15 dan 16: bukti unduhan = `isDownloaded` + `pageCount` sama dengan jumlah halaman yang diharapkan. Detail Suwayomi menampilkan saran CBZ.

### PR 1: Domain sync dan aturan merge

**File baru:**

```
lib/src/features/sync/domain/sync_method.dart     enum SyncMethod { none, suwayomi, icloud }
lib/src/features/sync/domain/sync_records.dart
lib/src/features/sync/domain/merge_rules.dart
lib/src/features/sync/domain/sync_status.dart     sealed: Off, Idle, Syncing, WaitingForServer,
                                                  Pending(count), ActionNeeded(reason)
test/src/features/sync/domain/merge_rules_test.dart
```

**Record** (immutable, dengan `==` dan `toJson`):

- `SeriesState { inLibrary, categories: Set<String>, changedAt }`
- `ChapterState { read, page, bookmarked, readAt }`
- `SeriesMeta { rating, tags, notes }`
- `ReaderMeta { Map<String, String> }`

**Fungsi murni:**

```dart
MergeOutcome<T> merge3<T>({required T? base, required T? local, required T? remote,
                           required ConflictRule<T> rule});
// MergeOutcome: keep | pushLocal(T) | applyRemote(T) | both(T merged)
```

Aturan konflik per jenis data mengikuti desain 4.2:

- **inLibrary**: membaca menang. Butuh input `readSinceBase` dari kedua sisi.
- **Chapter**: read/unread memakai waktu terbaru, dan *read* menang kalau waktunya tidak jelas. Halaman memakai waktu baca terbaru, lalu halaman terjauh. Bookmark: `true` menang.
- **Kategori**: per elemen, set tiga arah.
- **Meta**: per kunci, nilai terbaru menang. Kunci yang tidak dikenal dipertahankan.

**Tes:** tabel lengkap untuk setiap aturan, yaitu semua kombinasi (base, lokal, remote) sama/berubah/null, ditambah kasus hapus-vs-baca.

**Selesai kalau:** cakupan tes `merge_rules.dart` 100% baris, tanpa dependensi Flutter.

### PR 2: Skema v7 dan journal

**`local_catalog.dart`:**

- `schemaVersion => 7`, dan `onUpgrade` menambah `if (from < 7) await _createSyncTables();`. `onCreate` juga memanggilnya.
- Tabel (semuanya di versi ini, supaya tidak ada migrasi kedua untuk transfer):

  ```sql
  CREATE TABLE sync_changes (seq INTEGER PRIMARY KEY AUTOINCREMENT, kind TEXT NOT NULL,
    key TEXT NOT NULL, op TEXT NOT NULL, changed_at INTEGER NOT NULL);
  CREATE INDEX sync_changes_key ON sync_changes(kind, key);
  CREATE TABLE sync_links (backend TEXT NOT NULL, kind TEXT NOT NULL, local_key TEXT NOT NULL,
    remote_id TEXT NOT NULL, PRIMARY KEY (backend, kind, local_key));
  CREATE INDEX sync_links_remote ON sync_links(backend, kind, remote_id);
  CREATE TABLE sync_base (backend TEXT NOT NULL, kind TEXT NOT NULL, key TEXT NOT NULL,
    value TEXT NOT NULL, PRIMARY KEY (backend, kind, key));
  CREATE TABLE sync_transfers (series_id TEXT NOT NULL, chapter_id TEXT NOT NULL,
    remote_chapter_id INTEGER, keep_local INTEGER NOT NULL, state TEXT NOT NULL,
    -- queued | requested | verified | done | failed
    error TEXT, updated_at INTEGER NOT NULL, PRIMARY KEY (series_id, chapter_id));
  ```

- Journal di dalam catalog:
  - `bool journalEnabled` diset oleh `SyncController`.
  - Penanda "sedang menerapkan data remote" lewat `Zone` value `#kuchieSyncApplying`, supaya perubahan dari server tidak masuk outbox.
  - Helper privat `_journal(db, kind, key, op)` dipanggil di dalam transaksi setiap method tulis.
- Method tulis yang diberi hook. `recordRemoteRead`, `removeFromHistory`, dan `clearHistory` saat ini belum memakai `db.transaction`, jadi bungkus dulu.

  | Method | kind | op |
  |---|---|---|
  | `setInLibrary` | `series` | upsert |
  | `setProgress`, `recordRemoteRead`, `setChapterMarks`, `setBookmark` | `chapter_state` | upsert |
  | `removeFromHistory`, `clearHistory` | `chapter_state` (`readAt` dikosongkan) | upsert. Riwayat tidak dihapus di server (dicatat sebagai keputusan). |
  | `setCategories` | `membership` | upsert |
  | `createCategory`, `deleteCategory` | `category` | upsert / delete |
  | `setRating`, `setNotes`, `setTags` | `series_meta` | upsert |

**File baru:**

```
lib/src/features/sync/data/sync_journal.dart
  pending({int limit}), coalesced(), trimThrough(seq),
  links(backend), putLink(...), removeLinks(backend),
  base(backend, kind, key), putBase(...), clearBackend(backend),
  transfers CRUD
lib/src/features/local_collection/data/local_catalog_sync.dart
  applyRemote(SyncApplyBatch)   satu transaksi, di dalam Zone #kuchieSyncApplying
  snapshot()                    kondisi lokal per series/chapter/kategori untuk merge
```

`applyRemote` perlu kemampuan yang belum ada di catalog:

- Membuat `series` dari `LocalSeriesSource` tanpa chapter tersimpan.
- Mengisi state chapter yang belum disimpan ke `chapter_marks` dan `remote_history`. Judul chapter boleh kosong; `chapter_title` diisi dari server.

**Tes** (`test/src/features/sync/data/`):

- Migrasi v6 → v7 dengan DB fixture: data lama utuh.
- Setiap method di tabel menghasilkan tepat satu entri.
- `journalEnabled = false` tidak menghasilkan entri.
- `applyRemote` tidak menghasilkan entri.
- `trimThrough` dan `coalesced` benar.

**Selesai kalau:** `local_catalog_test.dart` dan `local_history_test.dart` yang sudah ada tetap hijau.

**Status (27 November 2026):** skema v7, `sync_journal.dart`, dan hook outbox selesai. Keputusan yang diambil saat mengerjakan:

- `local_catalog_sync.dart` (`applyRemote`, `snapshot`) pindah ke PR 8. Bentuk `SyncApplyBatch` ditentukan engine. Penanda Zone sudah ada sebagai `runApplyingRemote(body)` di `local_catalog.dart`, dan tesnya membuktikan tulisan di dalamnya tidak masuk outbox.
- Nama kind, op, dan format key ada di `sync/domain/sync_change.dart`. Key `chapter_state` adalah array JSON `[seriesId, chapterId]`, key `category` adalah `categoryKey(name)`.
- `LocalCatalog.incognito` hanya menahan progres baca (`setProgress`, `recordRemoteRead`). Reader memang tidak menulis progres saat penyamaran, jadi ini pengaman. Tanda baca dan bookmark yang diset manual tetap ikut sync.
- `deleteCategory` juga mencatat `membership` untuk series yang ada di kategori itu.
- `restoreMetadata` mencatat kategori, favorit, chapter yang dipulihkan, dan keanggotaan.
- Tidak dicatat: `renameSeries`, `setCover`, import/unduh chapter, dan `removeChapter`. Semuanya di luar data sync.
- Tulisan yang tidak mengubah apa pun (chapter tidak ada, kategori tidak ada) tidak menghasilkan entri.
- Tes migrasi memakai `test/src/features/sync/data/fixtures/catalog_v6/`, yang ditulis oleh catalog 1.2.1.

### PR 3: Setelan reader per series ke lapisan data

- Baru: `local_collection/data/local_series_reader_meta.dart`, berisi `read(seriesId)` dan `patch(seriesId, key, value)`. Format SharedPreferences `local.reader.manga.<id>` tetap sama.
- `reader_settings_model.dart`: `_readLocalMeta` dan `_patchLocalMeta` memanggil kelas baru ini.
- `patch` memberi tahu journal (`kind = reader_meta`) lewat callback yang disuntikkan, karena data SharedPreferences tidak ada di DB catalog.

**Selesai kalau:** `local_reader_preferences_test.dart` hijau dan ada tes baru untuk patch → journal.

**Status (27 November 2026):** selesai. Callback-nya `LocalCatalog.recordReaderMetaChange(seriesId)`, yang mengikuti aturan journal yang sama (sync aktif, bukan `runApplyingRemote`). `localSeriesReaderMetaProvider` memanggilnya lewat `activeLocalCatalogProvider`. Provider itu diisi saat koleksi Local dibuka, mengikuti pola `ActiveLocalDownloadQueue`, jadi menyimpan setelan reader tidak membuka koleksi. `ref.exists` tidak dipakai karena sudah deprecated di Riverpod 3.5.

### PR 4: State dan koneksi sync

**File baru:**

```
lib/src/features/sync/data/sync_state_store.dart
  SharedPreferences: sync.method, sync.suwayomi.serverIdentity, sync.suwayomi.userId,
  sync.lastSuccessAt, sync.lastError, sync.cursor.chapters, sync.backupUrl,
  sync.prefs.{library,progress,bookmarks,readerMeta,seriesMeta}
lib/src/features/sync/data/suwayomi/suwayomi_sync_client.dart
  suwayomiSyncClientProvider: GraphQLClient dari provider server_connection
  (URL, port, kredensial, timeout), tidak bergantung pada
  serverCollectionRuntimeEnabledProvider
lib/src/features/sync/data/suwayomi/suwayomi_reachability.dart
  probe(primary) → probe(backup); hasil: reachable(uri) | unreachable | authFailed | identityChanged
```

- Identitas server: memakai `offline/data/graphql/server_identity.graphql`.
- Sumber konfigurasi server sama dengan mode Server (keputusan desain 9.2).

**Catatan pengerjaan:**

- Tidak ada kunci `sync.backupUrl`. Alamat cadangan memakai pasangan yang sudah ada: alamat utama `ServerExternalUrl` dan alamat LAN `ServerLanUrl`, dicoba berurutan (`syncServerAddresses`).
- `authCoordinator` tidak memasang refresh berkala saat runtime Server mati, tapi `usableUiAccessToken` dan `refreshUiAccessToken` tetap berjalan, jadi klien sync memakainya sesuai kebutuhan.
- Klien sync memasang `LegacyUserFieldsLink`, tanpa `reachabilityLink` atau banner milik mode Server.
- Probe membaca meta identitas, yang sekaligus memeriksa auth. Batas waktu per alamat 6 detik.

**Tes:** reachability dengan `unreachable_server_stubs.dart`, fallback ke alamat cadangan, dan deteksi identitas berubah.

### PR 5: Dokumen GraphQL sync

`lib/src/features/sync/data/suwayomi/graphql/sync.graphql`:

| Operasi | Isi |
|---|---|
| `SyncLibraryPage(first, after)` | `mangas(condition: {inLibrary: true})`: id, sourceId, url, title, thumbnailUrl, `user.inLibraryAt`, categories { id name }, meta { key value } |
| `SyncCategories` | id, name, order, default |
| `SyncChaptersSince(mangaIds, lastReadAfter, first, after)` | id, mangaId, url, name, pageCount, `user { isRead isBookmarked lastPageRead lastReadAt isDownloaded }` |
| `SyncChaptersOfManga(mangaId)` | sama, untuk rekonsiliasi penuh |
| `MangaBySourceUrl(sourceId, url)` | id |
| `SyncExtensions`, `SyncExtensionStores` | pkgName, name, lang, isInstalled; indexUrl, signingKey, name |
| `ChapterDownloadState(ids)` | id, `user.isDownloaded`, pageCount |
| Mutasi | `updateMangas`, `updateMangasCategories`, `createCategory`, `updateChapters`, `setMangaMetas`, `fetchMangaAndChapters`, `fetchSourceManga`, `enqueueChapterDownloads`, `deleteDownloadedChapters`, `fetchChapterPages`, `updateExtension` |

Jalankan `tool/bootstrap`.

**Selesai kalau:** codegen bersih, `graphql_operation_variables_test.dart` hijau, dan semua field yang dipakai tidak `@deprecated`. Pakai `user.*`, bukan field lama di `ChapterType`.

**Status (27 November 2026):** dokumen selesai. Semua operasi dan fragment diberi awalan `Sync` supaya tidak bentrok dengan dokumen mode Server. `MangaBySourceUrl` menjadi `SyncMangaBySourceUrl`, dan `ChapterDownloadState` menjadi `SyncChapterDownloadState`. `sync_graphql_test.dart` menolak field atau input field yang `@deprecated` atau tidak ada di skema. `SyncExtensions` juga mengambil `storeIndexUrl`. Belum diuji ke server nyata, karena dokumen ini baru dipakai di PR 7–8. Uji ulang S2/S3b/S4/S8 dengan JAR preview masih perlu dilakukan sebelum PR 8.

### PR 6: Halaman Sinkronisasi, diagram hidup, dan ikon Library

Desain: [sync-plan.md](sync-plan.md) bagian 3.1, 3.2, dan 3.9. Prototipe acuan (versi 4): https://claude.ai/artifact/UgsfGprka4iH1t9dYFQoSN, sumbernya di `design/sync-prototype/index.html`. Logika animasi prototipe (scene per metode, token, kedatangan, orbit) bisa langsung diterjemahkan ke Dart.

**File baru:**

```
lib/src/features/sync/controller/sync_controller.dart       Notifier: metode, status, sync now
lib/src/features/sync/presentation/diagram/
  sync_methods.dart          definisi metode: node, garis, aliran, legenda (data murni)
  sync_scene.dart            SyncScene = metode + status → nilai target, aliran, teks
  sync_diagram.dart          widget: ticker, interpolasi, umpan balik kedatangan, label node
  sync_diagram_painter.dart  CustomPainter: garis, node, token, orbit, riak, latar titik
  sync_paths.dart            jalur bezier + panjang busur (posisi token di sepanjang garis)
  sync_explainer.dart        mode Penjelasan tiga langkah
lib/src/features/sync/presentation/sync_settings_screen.dart
lib/src/features/sync/presentation/sync_hero_card.dart      pill, diagram, Yang disinkronkan, teks, aksi
lib/src/features/sync/presentation/sync_method_list.dart    termasuk baris Segera hadir + lembar pratinjau
lib/src/features/sync/presentation/sync_faq.dart
lib/src/features/sync/presentation/sync_status_icon.dart
```

**Definisi metode** (`sync_methods.dart`). Satu metode = data, bukan kode gambar khusus:

```dart
enum SyncMethodKind { local, suwayomi, icloud, syncyomi, kosync, komga, kavita, drive }
enum NodeKind { phone, tablet, mac, android, ereader, hub, ghost, source }
enum HubGlyph { server, cloud, syncyomi, kosync, media, drive }
enum TokenKind { cover, dot, mix, page, bundle, mark, file }
enum LinkRole { sync, fan, source, source2, sourceOther, ghost }

class DiagramNode { final String id; final NodeKind kind; final Offset slot; // x: fraksi lebar, y: px
                    final String label, sub; }
class DiagramLink { final String a, b; final LinkRole role; }
class DiagramFlow { final String from, to; final TokenKind token;
                    final int count; final double speed; final double lane;          // aliran kontinu
                    final Duration? every, travel, delay; }                          // aliran berkala
class SyncMethodSpec { final SyncMethodKind kind; final String name; final HubGlyph glyph;
                       final List<DiagramNode> nodes; final List<DiagramLink> links;
                       final List<DiagramFlow> syncFlows; final List<LegendItem> legend;
                       final Set<SyncStatusKind> statuses; final bool available; }
```

Isi untuk tujuh metode mengikuti tabel "Diagram per metode" di desain 3.9. Kavita memakai spesifikasi Komga dengan nama berbeda.

**Scene** (`sync_scene.dart`, murni):

```dart
SyncScene sceneFor(SyncMethodSpec method, SyncStatusKind status, SyncProgress? progress, TransferProgress? transfer);
// → target opasitas (hub, sync, fan, others, src, srcHot, src2, dashed, broken, lock, check),
//   aliran aktif, kecepatan orbit, periode riak, kecepatan putus-putus, denyut, antrean,
//   isi layar tiap node (teks + progres), label pusat, teks status/penjelasan, aksi utama, pill
```

**Diagram** (`sync_diagram.dart` dan painter):

- Satu `Ticker`. Nilai scene diinterpolasi eksponensial (sekitar 90 ms per langkah, mendekati target dalam ±300 ms).
- Ganti metode: `topoFade` 0 ke 1 selama 350 ms, lalu jalur dan label dibangun ulang.
- Jalur: bezier kubik dari tepi node ke tepi node (`anchor` memotong kotak atau lingkaran node), disampel 48 titik dengan panjang kumulatif, supaya token bergerak dengan kecepatan konstan.
- **Umpan balik kedatangan**: saat token menyelesaikan siklus, node tujuan mendapat `bump` 0,8 yang meluruh sekitar 3,2/detik. Layar berkedip warna aksen dan node membesar `1 + 0.07 × bump`.
- Aliran kontinu (posisi = `(t × speed + i / count) mod 1`) dan berkala (`every`/`travel`/`delay`, dengan lintasan sedikit melengkung ke atas).
- Ambien: orbit pusat (satelit hanya untuk metode kontinu), riak, putus-putus garis berjalan, LED server, perangkat melayang ±2 px, globe berputar, dan latar titik bergeser.
- Label node berupa widget `Text` di atas canvas (lewat `Stack`), supaya mengikuti Dynamic Type. Label di atas node untuk slot kanan atas, dan di bawah node untuk yang lain.
- Reduce Motion: ticker tidak berjalan, dan painter menggambar frame statis dengan panah arah di tengah garis.
- Ticker berhenti saat kartu tidak terlihat (`TickerMode`, `RouteAware`). Status diam dibatasi sekitar 30 fps, dan ambien dimatikan saat Low Power Mode aktif (`ProcessInfo.isLowPowerModeEnabled` lewat platform channel).

**Daftar metode** (`sync_method_list.dart`): baris *Segera hadir* belum bisa dipilih. Mengetuknya membuka lembar kecil berisi `SyncDiagram` metode itu dalam status Menyinkronkan, baris Yang disinkronkan, dan teks "Segera hadir".

**Mode Penjelasan** (`sync_explainer.dart`): tiga langkah (Lokal → Suwayomi menyinkronkan → Suwayomi menunggu), sekitar 3,8 detik per langkah, bisa diketuk. Muncul sekali (`sync.explainerSeen`) dan setiap kali tombol (?) diketuk.

**FAQ** (`sync_faq.dart`): tujuh pertanyaan dari desain 3.2, dalam bahasa Inggris dan Indonesia.

**Diubah:**

- `local_collection_home.dart`, `_more()`: baris *Sinkronisasi* dengan subtitle status, di bawah *Backup & Pulihkan*.
- `local_collection_home.dart`, judul Library: `SyncStatusIcon`.

**Tes:**

- `sync_scene_test.dart`: setiap metode × setiap status yang didukung menghasilkan scene yang valid. Aliran hanya merujuk ke garis yang ada. Metode tanpa Source tidak punya aliran Source saat Menunggu.
- `sync_paths_test.dart`: `at(u)` monoton dan berkecepatan konstan, dan anchor berada di tepi node.
- Golden test `sync_diagram` untuk 7 metode × status utama (Menyinkronkan, Tersinkron, Menunggu) ditambah 5 status khusus Suwayomi, di tema terang, gelap, dan hitam pekat, dengan waktu dibekukan di t = 1,5 detik.
- Tes widget:
  - Reduce Motion tidak menjalankan ticker;
  - semantics kartu membacakan status dan penjelasan;
  - aksi utama berubah sesuai status;
  - baris Segera hadir membuka lembar pratinjau;
  - mode Penjelasan muncul sekali dan bisa diulang lewat (?).

**Selesai kalau:**

- Semua tes hijau.
- Di perangkat nyata, animasi stabil di 60/120 fps saat Menyinkronkan, sekitar 30 fps saat diam, dan tanpa repaint saat Reduce Motion aktif.
- Semua scene bisa dicoba lewat menu debug dengan status palsu, karena engine baru ada di PR 8.

**Status (27 November 2026):** kode dan tes selesai. Belum diukur di perangkat nyata (60/120 fps dan 30 fps). Keputusan yang diambil:

- `sync_methods.dart` dan `sync_scene.dart` pindah ke `sync/domain/diagram/`. Keduanya Dart murni, dan `sync_controller.dart` membutuhkannya, sementara `layer_boundaries_test.dart` melarang controller mengimpor `presentation/`. Status animasi ada di `sync_diagram_motion.dart`, sehingga painter hanya membaca.
- Diagram mengganti scene hanya saat metode atau status berubah. Perubahan angka saja tidak mereset animasi.
- Low Power Mode dibaca lewat channel `kuchie/power` (`AppDelegate.swift`, `lib/src/utils/power/low_power_mode.dart`). Saat aktif, gerakan ambien berhenti setelah transisi selesai.
- Tombol utama dan pilihan metode belum punya aksi di luar pratinjau. Hubungkan (PR 7) dan sync (PR 8) belum ada. Menu "Preview (debug)" hanya muncul di build debug dan bisa memutar alur Memeriksa → Menyinkronkan → Tersinkron, termasuk Kiri `complete`.
- Bagian *Kapan* (pemicu) dan *Lanjutan → Log* belum ditampilkan. Keduanya ikut PR 9 dan PR 13, supaya tidak ada toggle tanpa efek.
- Ikon status ditaruh di sebelah pemilih mode di judul Library. Pemilih mode baru hilang di PR 19.
- Golden: 24 scene × 3 tema = 72 gambar di `test/src/features/sync/presentation/diagram/goldens/`, dengan toleransi 0,5% untuk perbedaan antialiasing antara macOS dan runner Linux.

### PR 7: Alur hubungkan dan analisis (dry-run)

**File baru:**

```
lib/src/features/sync/data/suwayomi/suwayomi_identity.dart
  parseLocalSource("<pkg>:<id>") → (pkg, sourceId)
  matchSeries(local snapshot, remote library) → links + onlyLocal + onlyRemote
  alasan tidak terpetakan: importedFile | kuchieRepo | builtIn | extensionMissing(pkg)
lib/src/features/sync/controller/connect_analysis.dart
  → ConnectAnalysis { localCount, remoteCount, matched, onlyLocal[], onlyRemote[],
                      branch: localEmpty | remoteEmpty | allMatched | differs }
lib/src/features/sync/presentation/suwayomi_connect_flow.dart
```

- Langkah alamat dan login memakai ulang widget server dari onboarding (`onboarding/presentation/collection_choice_step.dart`, termasuk *Cari di jaringan saya*). Ekstrak widget-nya kalau perlu, tanpa mengubah perilaku onboarding.
- Cabang sesuai desain 3.3. Pada PR ini tombol akhir hanya menyimpan pilihan (`merge`, `useServer`, `useLocal`) dan menampilkan ringkasan. **Belum ada data yang ditulis.**

**Tes:** `suwayomi_identity` dengan fixture dari hasil S1, dan keempat cabang.

**Selesai kalau:** pengguna bisa menghubungkan server QA dan melihat laporan yang angkanya benar.

**Status (28 November 2026):** kode dan tes selesai. Belum dicoba ke server QA nyata. Keputusan yang diambil:

- Langkah server di onboarding menjadi `ServerStep` publik dengan `ServerStepHost`, yang berisi awalan kunci draf dan cara menyelesaikan sign-in. Onboarding tetap memakai `ServerStepHost.onboarding` dengan kunci dan perilaku yang sama persis. Alur sync memakai awalan `sync.connect.` dan tidak menulis `onboarding.step`. Seluruh tes `test/onboarding/` tetap hijau.
- Sign-in di alur sync memakai koneksi yang sama dengan bagian lain aplikasi (alamat, kredensial, keputusan 9.2).
- `suwayomi_library_reader.dart` membaca library server per halaman (`SyncLibraryPage`) dan extension yang terpasang (`SyncExtensions`). Tidak ada yang ditulis ke server.
- Pencocokan memakai `sourceId` dan URL apa adanya (spike S1). Satu manga server hanya terhubung ke satu series lokal. Series yang hanya ada di iPhone diberi alasan: `ImportedFile`, `KuchieRepo`, `BuiltIn` (Shinigami bawaan), `ExtensionMissing(pkg)` (server belum punya extension-nya), atau `Sendable`.
- Tombol akhir menyimpan `ConnectChoice` di `sync.suwayomi.connectChoice` (`SyncStateStore`, ikut terhapus saat putuskan koneksi). Metode sync belum diubah ke Suwayomi; engine di PR 8 yang menyalakannya setelah sync pertama.
- Fixture S1 MangaDex memuat satu series dua kali, karena halaman popular bisa mengulang. Tesnya menghapus duplikat dulu, karena library tidak bisa berisi duplikat.

### PR 8: Engine

**File baru:**

```
lib/src/features/sync/data/sync_backend.dart
lib/src/features/sync/data/suwayomi/suwayomi_backend.dart   pull/push memakai operasi PR 5
lib/src/features/sync/controller/sync_engine.dart
```

**Siklus** (desain 4.3):

1. Preflight memakai reachability. `identityChanged` dan `authFailed` menghentikan siklus dan memunculkan status ActionNeeded.
2. **Pull:** semua halaman `SyncLibraryPage`, `SyncCategories`, dan `SyncChaptersSince(cursor)`. Rekonsiliasi penuh lewat `SyncChaptersOfManga` per series terhubung, maksimal setiap 24 jam atau saat sync manual.
3. **Pemetaan:** `suwayomi_identity`.
4. **Merge:** `merge_rules` untuk setiap key, ditambah keputusan sambungan pertama (`merge`, `useServer`, `useLocal`).
5. **Terapkan lokal:** `applyRemote` dalam satu transaksi.
6. **Push** per batch 50:
   - Series tanpa link: `MangaBySourceUrl`. Kalau belum ada di server, pakai cara pembuatan yang lolos S3, lalu `fetchMangaAndChapters`.
   - Kategori yang belum ada: `createCategory`.
   - `updateMangas`, `updateMangasCategories`, dan `updateChapters` dikelompokkan berdasarkan nilai yang sama.
7. **Commit:** `putBase`, kursor, `trimThrough(seq)`, dan `lastSuccessAt`.

**Ketahanan:**

- Single flight dengan flag `rerun`.
- Error per series dicatat di journal (tabel kecil atau kolom di `sync_links`).
- Backoff eksponensial 1, 5, 15, 60 menit untuk unreachable.
- Pembatalan saat app masuk background, dengan commit parsial yang aman karena base hanya diperbarui untuk key yang sudah terkirim.

**Tes** (`test/src/features/sync/controller/sync_engine_test.dart`) dengan fake backend: skenario 1–6 dan 12–14 dari desain bagian 8, ditambah idempotensi (sync dua kali tanpa perubahan menghasilkan nol mutasi).

**Selesai kalau:** sync berjalan dua arah terhadap server QA nyata. Cek manual dengan WebUI Suwayomi.

**Dari spike S4b (28 November 2026, preview v2.4.2512):** library dan progres per pengguna. `restoreBackup` hanya berefek untuk token dengan role ADMIN (atau server Stable tanpa pengguna). Untuk pengguna biasa, engine membuat manga lewat `fetchSourceManga` + `updateMangas(inLibrary: true)`, dan mengirim `lastPageRead` setelah `fetchChapterPages`. `sync.suwayomi.userId` diisi dari klaim `sub` di JWT. Lihat [sync-spike-results.md](sync-spike-results.md#s4b-multi-pengguna-preview-v242512).

**Status (28 November 2026):** engine, backend Suwayomi, dan tes fake backend selesai. Sudah dicoba ke server QA nyata, Stable v2.4.2366 dan preview v2.4.2512, lewat `tool/qa/sync_spike/sync_engine_qa_test.dart` (source lokal server, tanpa extension). Keduanya lolos semua langkah:

1. Sync pertama (merge): series di server masuk ke iPhone beserta progres chapter-nya, dan series di iPhone yang ada di server tapi di luar library masuk ke library server.
2. Baca di iPhone sampai halaman 7 pada chapter yang belum pernah dibuka server: halaman sampai di server (percobaan ulang S2 lewat `fetchChapterPages` berjalan).
3. Dua sync manual tanpa perubahan: nol mutasi dan nol tulisan lokal.
4. Read dan bookmark dari server sampai di iPhone.
5. Unread di iPhone sampai di server.
6. Kategori baru di iPhone dibuat di server dan series masuk ke kategori itu.
7. Series dihapus dari library server tanpa dibaca di iPhone: ikut keluar dari library iPhone, lalu sync berikutnya tenang.

Belum dicoba lewat aplikasi di simulator dengan extension Mihon sungguhan, dan belum dengan server yang memakai login. Keputusan yang diambil:

- `LocalCatalog` mendapat `syncSeries()`, `syncChapterStates()`, dan `applySync()`. `applySync` menulis semua hasil pull dalam satu transaksi dan tidak menulis outbox.
- ID chapter lokal adalah SHA-256 dari URL chapter (`kuchieLocatorId`), jadi chapter server dicocokkan lewat `url` tanpa tabel link. Hanya series yang disimpan di `sync_links`.
- Base chapter menyimpan `lastReadAt` milik server. Waktu baca server yang masih sama dengan base dianggap waktu baca iPhone, supaya stempel server dari push Kuchie sendiri tidak terbaca sebagai bacaan baru.
- Pull bertahap: `SyncChaptersSince(kursor)` ditambah `SyncChaptersOfManga` untuk series yang punya perubahan chapter di outbox. Pull penuh saat sync manual, sync pertama, atau setiap 24 jam. Sidik jari per series belum dipakai; perubahan `isRead`/bookmark dari klien lain menunggu pull penuh.
- `lastPageRead` yang dibuang server (S2) dicoba lagi lewat `fetchChapterPages`, paling banyak 10 chapter per siklus. Base chapter disimpan sesuai jawaban server, jadi yang masih ditolak dikirim lagi di siklus berikutnya.
- Jenis data yang dimatikan (progres, bookmark, library) tidak ikut merge. Base untuk field itu tetap nilai server, supaya saat dinyalakan lagi perubahan di iPhone ikut terkirim.
- Outbox hanya dipangkas kalau siklus tanpa error per series. Base tetap sumber kebenaran.
- Status engine masuk ke `SyncController`. Tombol *Sinkronkan sekarang* dan *Coba lagi* menjalankan siklus manual, dan alur hubungkan memulai sync pertama setelah pilihan disimpan.
- **Membuat manga baru di server (PR 8b):** series yang belum ada di server (`MangaBySourceUrl` kosong) dikirim dalam satu `restoreBackup` berisi backup Mihon minimal (`mihon_backup.dart`, mengikuti `backup.py`), lalu dicek ulang. Yang masih belum ada dicari lewat `fetchSourceManga(SEARCH, judul)`, lalu dimasukkan ke library lewat `updateMangas`. Kalau keduanya gagal, series dilaporkan `notOnServer` dan dicoba lagi. Harness QA membuat "QA - Night Ferry" lewat restore di Stable dan preview.
- Gagal memuat chapter satu series (source di server mati) menjadi error per series, bukan kegagalan siklus.
- Belum: `sync.suwayomi.userId` dari klaim `sub` dan penghapusan kategori.

### PR 9: Pemicu dan background

- `sync_scheduler.dart`:
  - `AppLifecycleListener.onShow`, dengan jeda minimal 5 menit.
  - `Connectivity().onConnectivityChanged`.
  - `notifyChapterRead()`: push tertunda 10 detik.
  - Manual.
- `local_reader.dart`: panggil `notifyChapterRead()` di `_pause()` dan saat chapter selesai. Tambahkan lewat callback, karena reader ada di presentation dan scheduler di controller.
- Pull-to-refresh di Library Local memicu `syncNow()`.
- **Background:**
  - `ios/Runner/Info.plist`: `BGTaskSchedulerPermittedIdentifiers` = `app.kuchie.reader.sync`.
  - Registrasi workmanager iOS di `AppDelegate.swift`.
  - `Workmanager().registerPeriodicTask` saat sync aktif.
  - Callback background menjalankan siklus push dan pull bertahap tanpa UI.

**Selesai kalau:** tes scheduler dengan clock palsu, dan background task terverifikasi di perangkat lewat `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"app.kuchie.reader.sync"]`.

**Status (28 November 2026):** selesai. Keputusan yang diambil:

- `SyncScheduler` (controller) menerima kejadian lewat method (`appShown`, `appHidden`, `notifyChapterRead`) dan aliran konektivitas yang disuntikkan, jadi dites dengan clock palsu dan `fakeAsync`. Provider-nya memasang `AppLifecycleListener` dan `Connectivity().onConnectivityChanged`.
- App masuk background membatalkan siklus yang berjalan dan push yang tertunda. Yang sudah terkirim tetap tersimpan.
- Reader memberi tahu scheduler saat berhenti (`_pause`), saat ditutup, dan saat chapter selesai. Presentation boleh memanggil controller langsung, jadi tidak perlu callback.
- Library Local: scheduler dimulai saat Library dibuka; pull-to-refresh menjalankan sync manual saat sync aktif; Library dimuat ulang setiap kali siklus selesai.
- Background iOS: `BGTaskSchedulerPermittedIdentifiers` dan `UIBackgroundModes: fetch` di `Info.plist`; `WorkmanagerPlugin.registerPeriodicTask` di `AppDelegate`; `Workmanager` sekarang diinisialisasi juga di iOS, dengan dispatcher yang sama untuk task Android. Task dijadwalkan setiap 30 menit selama sync aktif dan dibatalkan saat mati. Callback background membuat `ProviderContainer` sendiri, memuat kredensial seperti `main()`, lalu menjalankan satu siklus.
- **Belum terverifikasi:** BGTaskScheduler tidak berjalan di simulator, jadi perintah `_simulateLaunchForTaskWithIdentifier` di atas perlu dijalankan di iPhone. Sync saat foreground tetap jalur utama (risiko di bagian 5).

### PR 10: Metadata series dan reader

- Pull meta: `flutter_rating` → `rating`, `flutter_tags` → `tags`, `kuchie_notes` → `notes`. Kunci `flutter_reader*` dan kunci lain dari `MangaMetaKeys` disalin ke `local_series_reader_meta`.
- Push: `setMangaMetas`.
- Auto-enable *Rating, tag & catatan* kalau server sudah punya `flutter_rating` atau `flutter_tags` (desain 3.4).

**Tes:** merge per kunci, dan kunci yang tidak dikenal tetap utuh.

**Status (28 November 2026):** selesai. Rating (`flutter_rating`, teks angka), tag (`flutter_tags`, array JSON), dan catatan (`kuchie_notes`) di-merge per field; setelan reader per kunci dari daftar `readerMetaKeys` (semua `MangaMetaKeys` kecuali rating, tag, dan cover server; tes menjaganya tetap sama). Kunci lain, misalnya milik WebUI, tidak pernah diubah atau dihapus. Nilai kosong menghapus kunci di server lewat `deleteMangaMetas`. Rating/tag/catatan ditulis lewat `applySync`; setelan reader lewat `LocalSeriesReaderMeta.replaceSynced`, jadi keduanya tidak masuk outbox. *Rating, tag & catatan* dan *Setelan reader* menyala secara default, jadi tidak perlu auto-enable. Harness QA lolos di Stable dan preview: rating dari server masuk ke iPhone, catatan dan mode reader dari iPhone masuk ke server, lalu sync berikutnya tenang.

### PR 11: Extension

- `extension_suggestions.dart` (controller):
  - Bandingkan `SyncExtensions` dan `SyncExtensionStores` dengan `LocalSources`.
  - Hitung jumlah series terdampak dari `onlyRemote` dan `onlyLocal`.
- UI: kartu setelah sync pertama, dan *Perlu perhatian → extension*.
- **Pasang ganda** di alur pemasangan Local (`local_extension_browser.dart` dan `local_sources.dart`, method install):
  - Setelah berhasil terpasang di iPhone, kalau sync aktif dan store yang sama ada di server, panggil `updateExtension(install: true)` di server. Kegagalan di server tidak menggagalkan pemasangan di iPhone; dicatat di *Perlu perhatian*.
  - Build tanpa runtime (`local_mihon_runtime` tidak tersedia): pasang di server saja.
- Badge lokasi di baris extension.

**Status (28 November 2026):** selesai, kecuali badge lokasi per baris extension, yang dipindah ke *Perlu perhatian*: halaman Sinkronisasi dan detail Suwayomi menampilkan extension yang hanya ada di iPhone (sekali ketuk dipasang di server, lalu satu siklus berjalan), yang hanya ada di server, dan yang tidak ada di store server. Pasang ganda: memasang extension baru di iPhone juga memasangnya di server saat sync aktif; kegagalan di server tidak menggagalkan pemasangan di iPhone. Jumlah series terdampak tidak ditampilkan, karena `SyncExtensions` tidak memetakan paket ke source id. Belum diuji ke server nyata: server QA tidak punya extension store.

### PR 12: Tracking lewat server

- `local_extension_browser.dart` sekitar baris 3428: kalau series punya link Suwayomi, buka sheet tracking dari `features/tracking` dengan `mangaId` server. Kalau tidak punya link, tampilkan dialog dengan alasan spesifik ("Series ini dari file import…").
- Tidak ada tracker lokal yang perlu dimatikan, karena Local memang belum punya tracker.

**Status (28 November 2026):** selesai. `serverSeriesProvider` mencari link series di `sync_links`. Dengan link, tombol Tracking membuka `showTrackSheet` dengan ID manga server; tanpa link, dialog menyebut alasannya: sync mati, series dari impor atau repo Kuchie, atau belum tersinkron. Sheet tracking memakai klien GraphQL aplikasi, yang membaca alamat dan kredensial yang sama dengan Sync.

### PR 13: Perlu perhatian dan log

- `unsynced_series_screen.dart`: daftar per alasan, dengan aksi *Pasang extension* dan *Coba lagi*.
- `sync_log_screen.dart`: 200 kejadian terakhir di ring buffer (SharedPreferences atau tabel kecil), berisi waktu, jenis, jumlah perubahan, dan error.
- Halaman detail Suwayomi sesuai desain 3.4, dengan toggle di *Lanjutan* dan *Alamat cadangan*.

**Status (28 November 2026):** selesai. Log disimpan di SharedPreferences (`sync.log`, 200 siklus terbaru, ikut terhapus saat putuskan koneksi); setiap siklus, termasuk yang gagal atau tidak terjangkau, mencatat hasil, jumlah masuk/keluar, error per series, dan pesannya. Error per series siklus terakhir disimpan di `sync.seriesErrors`. *Perlu perhatian* mengelompokkan series per alasan (impor, repo Kuchie, Shinigami bawaan, tidak bisa ditambahkan server, permintaan gagal, menunggu sync) dengan *Coba lagi*. Detail Suwayomi: alamat, status, Perlu perhatian, extension, Lanjutan (toggle *Yang disinkronkan* dan alamat cadangan lewat layar Koneksi yang sudah ada), dan log. Sesuai desain 3.4, *Rating, tag & catatan* sekarang mati secara default dan menyala sendiri kalau server sudah punya `flutter_rating` atau `flutter_tags`. Merge meta tanpa base sekarang mulai dari kosong, jadi nilai yang hanya ada di satu sisi tidak kalah oleh sisi yang kosong.

### PR 14: `ChapterPageResolver` dan baca lewat server

- Baru: `local_collection/data/chapter_page_resolver.dart`. Logika `_load()` di `local_extension_browser.dart` dipindah ke sini:
  1. Ada salinan iPhone: `LocalReaderChapterContent(chapter)`.
  2. Sync aktif, chapter punya link, dan server terjangkau: `fetchChapterPages`, lalu `LocalPreviewPages` dengan URL server dan header auth.
  3. Extension terpasang di iPhone: `sources.chapterPages` (perilaku sekarang).
  4. Tidak ada jalan: error bertipe `NeedsServer` atau `Offline`, yang ditampilkan sesuai desain 3.6 dan 3.8.
- Series yang extensionnya hanya ada di server: tambah state "Butuh server" (cover redup) di library dan detail.
- Build tanpa runtime: langkah 2 menjadi jalur utama.

**Tes:** resolver dengan fake untuk setiap cabang, dan urutan fallback saat server timeout (batas 3 detik sebelum turun ke langkah 3).

**Status (28 November 2026):** selesai untuk membaca. `ChapterPageResolver` (data) mendapat `ServerChapterPages` sebagai interface, jadi Local tidak bergantung pada Sync; implementasinya `SuwayomiChapterPages` (controller) mencari link series, memetakan chapter lewat SHA-256 URL ke ID server (di-cache per manga), lalu memanggil `fetchChapterPages` dan menyusun URL halaman dengan header auth dan header kustom yang sama dengan klien sync. Server yang lambat lebih dari 3 detik, menolak, atau tidak terjangkau memberi jalan ke extension di iPhone. Pesan `ChapterNeedsServer` dan `ChapterOffline` sesuai desain 3.6 tampil di layar baca. Harness QA memuat 18 halaman lewat server dan mengambil gambarnya di Stable dan preview. **Belum:** state "Butuh server" dan daftar chapter dari server untuk series yang extension-nya tidak ada di iPhone. Engine hanya membuat series lokal untuk source yang terpasang di iPhone, jadi kasus ini baru muncul kalau extension dicopot setelahnya.

### PR 15: Unduhan ke server dan Simpan untuk offline

- `local_extension_browser.dart` sekitar baris 3716: kalau sync aktif dan chapter punya link, panggil `enqueueChapterDownloads`. Kalau server tidak terjangkau, masukkan ke antrean server di journal. Selain itu, perilaku sekarang (`LocalDownloadQueue`).
- **Simpan untuk offline:** `LocalDownloadRequest` baru dengan sumber `server`. Halaman diambil dari URL `fetchChapterPages` lewat `catalog.saveRemoteChapter`, dengan header auth.
- Penanda lokasi chapter: `iPhone`, `Server`, atau `iPhone + Server`. Data server dari `ChapterDownloadState`, hanya untuk series yang sedang dibuka.
- Halaman Unduhan: bagian antrean server (status terakhir diketahui, dengan keterangan "terakhir dilihat …").
- Menu chapter: *Hapus dari server* (`deleteDownloadedChapters`) dan *Hapus salinan offline*.
- Live Activity: `ContentState.source = server` untuk antrean server.

**Status (28 November 2026):** selesai, kecuali Live Activity untuk antrean server. Keputusan yang diambil:

- Unduhan ke server dan *Pindahkan ke server* (PR 16) memakai satu job, `ServerTransfers`, dengan tabel `sync_transfers` sebagai antrean. Unduhan ke server adalah transfer dengan `keep_local = 1`. Server yang tidak terjangkau membuat antrean menunggu, dan app yang ditutup melanjutkan dari state di DB.
- Tombol Unduh di daftar chapter mengunduh ke server kalau sync aktif dan series terhubung; selain itu tetap ke iPhone. Menu chapter: *Simpan untuk offline* (salinan iPhone, mengambil halaman dari server lebih dulu lewat `LocalDownloadQueue.serverPages`), *Unduh ke server*, dan *Hapus dari server* (`deleteDownloadedChapters`).
- Penanda lokasi: ikon awan-centang untuk chapter di server, dan label `Server` atau `iPhone + Server`. Status server dibaca hanya untuk series yang sedang dibuka.
- Halaman Unduhan: kartu *Di server* dengan jumlah yang sedang diunduh, selesai, dan gagal, plus "terakhir dilihat", *Coba lagi*, dan *Bersihkan*.
- Scheduler menjalankan job setelah setiap siklus sync. Job memeriksa server setiap 10 detik selama ada unduhan yang berjalan, dan berhenti saat app ke background.
- QA: server Stable menerima permintaan unduh (`requested`), tapi Suwayomi tidak menyelesaikan unduhan chapter dari source lokal (sama dengan catatan spike S4b). **Penyelesaian unduhan di server nyata perlu dicek dengan source sungguhan (S8).** Di tes, unduhan baru dianggap selesai setelah server melaporkan `isDownloaded` dengan jumlah halaman yang benar.

### PR 16: Pindahkan ke server

- Baru: `sync/controller/server_transfer_job.dart`, yang memakai tabel `sync_transfers`. State per chapter:

  ```
  queued → requested (enqueueChapterDownloads)
         → verified  (isDownloaded && pageCount == jumlah halaman iPhone)
         → done      (kalau keep_local = 0: catalog.removeChapter)
  failed (error)  ← dari mana saja; salinan iPhone tidak pernah disentuh
  ```

- Pemantauan: polling `ChapterDownloadState` setiap 10 detik saat app aktif, dan dilanjutkan oleh scheduler saat app dibuka kembali.
- UI:
  - Kartu setelah sambungan pertama (kalau ada unduhan di iPhone).
  - `_LocalStorageSettings`: *Pindahkan ke server*, untuk semua atau per series.
  - Menu series dan pilih banyak chapter.
  - Lembar konfirmasi sesuai desain 3.6, dengan default *Hapus dari iPhone*. Ukuran yang dihemat dihitung dari ukuran folder chapter.
  - Progres di halaman Unduhan dan Live Activity. `DownloadActivityAttributes` mungkin butuh field `transfer: Bool?`; field opsional supaya kompatibel dengan versi lama.
- Chapter yang tidak terpetakan (import, repo Kuchie) dikecualikan dan disebut di lembar konfirmasi.

**Tes:**

- State machine dengan fake server: sukses, gagal di source, disk penuh, terputus, dan ditutup paksa (state dibaca ulang dari DB).
- Properti utama: **tidak ada `removeChapter` sebelum `verified`**.

### PR 17: Putuskan koneksi

- Dialog berisi jumlah dan ukuran chapter di server, ruang kosong iPhone, serta pilihan *Simpan semuanya ke iPhone* (antrean Simpan untuk offline) atau *Putuskan saja*.
- `clearBackend('suwayomi')`: menghapus link, base, transfer yang belum selesai, dan antrean server. Data library tidak disentuh.
- `sync.method = none`, lalu status berubah menjadi Off.

### PR 18: Onboarding baru

- Langkah pilihan collection dihapus, diganti langkah opsional "Sudah punya server Suwayomi? **Hubungkan**" yang membuka alur PR 7.
- `seedCollectionMode` dan logika onboarding ulang dihapus.
- Tidak ada migrasi pengguna (lihat 1.1). Untuk iPhone developer sendiri yang dulu memakai mode Server: hubungkan lewat alur biasa, lalu pilih *Pakai data server*.

**Tes:** onboarding dari instalasi baru, dengan dan tanpa menghubungkan server.

### PR 19: Hapus mode Server

- Hapus `CollectionMode`, `collection_mode.dart`, `collection_mode_picker.dart`, dan `serverCollectionRuntimeEnabledProvider`, beserta percabangannya di `main.dart`, `router_config.dart`, `library_screen.dart`, dan `more_screen.dart`.
- Hapus layar khusus mode Server yang sudah digantikan Local: Library, Updates, History, Browse, More, dan detail series versi server. Inventaris dulu lewat `grep` untuk rute yang tidak lagi dipakai.
- Pindahkan UI server yang masih berguna ke **Sinkronisasi → Suwayomi → Lanjutan → Server**: extension di server, backup server, pengaturan Suwayomi, akun, dan antrean unduhan server.
- `AccountSessionStartup` hanya dijalankan saat sync aktif.
- Hapus kunci preferensi lama mode Server yang tidak lagi dibaca (`collectionMode` dan sejenisnya).
- Kerjakan per area (rute, library, browse, settings, offline), masing-masing satu PR kecil ke `feature/sync`.

**Selesai kalau:**

- `layer_boundaries_test.dart` dan semua tes hijau.
- Tidak ada referensi ke `CollectionMode`.
- Ukuran bundle tercatat sebelum dan sesudah.

### PR 20: QA penuh dan dokumentasi

- Jalankan semua skenario di desain bagian 8 (termasuk 11a–11c):
  - di simulator dan iPhone sendiri;
  - dengan server di LAN dan lewat alamat cadangan.
- Pemakaian harian di iPhone sendiri minimal satu minggu dengan build `feature/sync`, tanpa bug kehilangan data.
- Dokumentasi:
  - `docs/sync.md` untuk pengguna: cara menghubungkan, apa yang disinkronkan, unduhan, Pindahkan ke server, dan pemecahan masalah.
  - README ditulis ulang: satu library, *Getting started* dengan bagian "Sinkronisasi dengan Suwayomi", dan bagian dua collection dihapus.
  - CHANGELOG 2.0.

### PR 21: Rilis Kuchie 2.0

- Gabung `feature/sync` ke `main`.
- Bump `pubspec.yaml` ke `2.0.0`, lalu tag `v2.0.0` (`release.yml`).

---

## 5. Risiko dan gerbang keputusan

| Risiko | Gerbang | Rencana cadangan |
|---|---|---|
| URL tidak cocok antara Kuchie dan Suwayomi | S1 | Normalizer URL. Kalau tetap gagal untuk extension tertentu, extension itu ditandai "tidak didukung sync". |
| Server tidak bisa membuat manga baru | S3 | 2.0 hanya menyinkronkan series yang sudah ada di kedua sisi, ditambah tarik dari server. Push series baru di 2.x. |
| Bug sync merusak library sendiri | PR 20 | Backup Local (`local_backups.dart`) sebelum sync pertama, dan pemakaian harian satu minggu sebelum rilis. |
| Timestamp server tidak bisa diandalkan | S2 | Merge berbasis base dan halaman terjauh saja. |
| Library besar lambat | S5 | Paging, rekonsiliasi bertahap per kategori, dan status unduhan hanya untuk series yang dibuka. |
| Penghapusan salinan iPhone yang keliru | S8 dan tes properti PR 16 | Verifikasi tambahan lewat `fetchChapterPages`. |
| iOS jarang menjalankan background | PR 9 | Sync saat foreground tetap jadi jalur utama. Background hanya bonus. |
| iCloud tidak tersedia untuk sideload | S6 | iCloud menunggu distribusi App Store/TestFlight. |

---

## 6. Langkah pertama

1. `git fetch kuchie && git switch -c feature/sync kuchie/main`, lalu `git switch -c spike/sync` dari situ.
2. Jalankan server QA dan simulator dengan satu extension Mihon yang sama (bagian PR 0).
3. Tulis `tool/qa/sync_spike/` untuk S1, S2, S3, dan S8. Keempatnya menentukan apakah desain bisa jalan apa adanya.
4. Catat hasilnya di `docs/sync-spike-results.md`, lalu sesuaikan dokumen desain kalau perlu.
5. Mulai PR 1 dan PR 4 secara paralel.
