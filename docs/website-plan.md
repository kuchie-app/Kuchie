# Rencana Website Kuchie

Status: **draft v2 untuk direview** · Diperbarui: 18 November 2026 · Basis: Kuchie v1.0.0

Perubahan dari v1: repo terpisah `kuchie-app/website`, domain `kuchie.app`, 24 bahasa sesuai app, halaman lebih lengkap (mengacu ke mihon.app dan tachimanga.app), arah visual yang lebih modern dengan banyak animasi tetapi tetap ringan, dan perkiraan biaya.

> File ini dipindah ke repo `kuchie-app/website` (sebagai `PLAN.md`) begitu repo itu dibuat.

---

## 1. Tujuan

1. **Menjelaskan Kuchie dalam 5 detik**: pembaca manga & webtoon untuk iPhone, koleksi Local atau Server (Suwayomi), Liquid Glass di iOS 26, gratis dan open source.
2. **Membuat orang berhasil memasang app**: Kuchie dibagikan sebagai IPA unsigned, jadi halaman Download dan panduan instal paling menentukan.
3. **Membangun kepercayaan**: open source (MPL-2.0), verifikasi tanda tangan APK, tanpa konten bawaan, kebijakan privasi yang jelas, kredit ke proyek upstream.
4. **Menjadi rumah dokumentasi** dalam bahasa pengguna: panduan, FAQ, changelog, berita rilis.
5. **Terasa lebih hidup daripada situs pembaca lain**: banyak animasi yang bermakna, tetapi tetap cepat di iPhone lama dan koneksi seluler.

### Indikator keberhasilan
- Tombol Download terlihat tanpa scroll di semua ukuran layar.
- Lighthouse mobile ≥ 95 (Performance, Accessibility, Best Practices, SEO) di Home, Download, dan satu halaman docs, **walaupun animasinya banyak**.
- Animasi stabil 60 fps di iPhone 11 / Safari dan Android kelas menengah.
- Issue GitHub bertipe "cara install" / "server tidak terdeteksi" berkurang setelah docs live.
- `kuchie.app/privacy` dan `kuchie.app/translate` dipakai sebagai `KUCHIE_PRIVACY_URL` dan `KUCHIE_TRANSLATIONS_URL` di app.

## 2. Pelajaran dari situs referensi

| | mihon.app | tachimanga.app | Untuk Kuchie |
| --- | --- | --- | --- |
| Teknologi | VitePress (tema default) | situs docs statis | Statis juga, tetapi landing dirancang sendiri, bukan tema default |
| Navigasi | Download, Changelogs, Docs, News + sosial | Getting Started, FAQ, Guides (11), App Store, GitHub, Weblate | Gabungkan: Download, Features, Docs, Changelog, News, plus GitHub/terjemahan |
| Hero | nama + tagline, CTA Get started & Help center, versi terbaru | deskripsi + CTA App Store, screenshot Mac/iPad/iPhone | Hero animasi, versi otomatis, CTA Download + AltStore |
| Konten | 3 kartu fitur, guides + FAQ, privacy | 11 guide topik, FAQ, changelog | Panduan per topik seperti Tachimanga, FAQ per kategori seperti Mihon, ditambah halaman khusus sideload |
| Kekurangan | landing sangat minim, statis | landing satu layar, hampir tanpa visual | Di sinilah Kuchie bisa unggul: visual, cerita fitur, animasi, multibahasa |

Kesimpulannya: pertahankan kekuatan mereka (docs terstruktur, versi terbaru di depan, changelog, privacy), lalu ungguli di landing page dan pengalaman visual.

## 3. Audiens

| Segmen | Yang dicari | Halaman utama |
| --- | --- | --- |
| Pembaca iPhone baru | "Apa ini, bagus nggak, gimana pasangnya?" | Home, Download |
| Pengguna Tachiyomi/Mihon yang pindah ke iPhone | dukungan extension store, keamanan APK | Features, Guides → Extensions |
| Self-hoster Suwayomi | cara connect, auth, tracker, backup | Guides → Server |
| Sideloader berpengalaman | IPA terbaru, SHA-256, source AltStore | Download |
| Kontributor & penerjemah | build from source, cara menerjemahkan | Contribute, Translate |
| Media & kreator konten | logo, screenshot, deskripsi singkat | Press kit |

## 4. Batasan konten (penting)

Kuchie memuat extension Mihon, jadi website tidak boleh terlihat mempromosikan pembajakan:

- **Kuchie tidak menyediakan atau meng-host konten.** Tulis ini jelas di Home, FAQ, dan Legal.
- **Tidak menampilkan atau menautkan situs/sumber manga tertentu.** Nama store (Keiyoushi, Suwayomi, Yūzōnō) hanya disebut di Credits dan guide teknis.
- **Semua screenshot dan animasi tanpa manga berhak cipta.** Gunakan fixture QA (`tool/qa/local_source.py`) berisi ilustrasi buatan sendiri, Kiri, atau karya public domain / Creative Commons yang lisensinya dicatat di Credits.
- Sediakan **kontak laporan hak cipta & keamanan** (`legal@kuchie.app` / `security@kuchie.app`, diteruskan gratis lewat Cloudflare Email Routing).
- Hormati lisensi: MPL-2.0 (Kuchie, Suwayomi-Tsumiru), Apache-2.0 (bagian dari Mangayomi), atribusi lain dari `NOTICE.md` dan README → Credits.

## 5. Peta situs

```
/                         Home
/features                 Semua fitur + perbandingan Local vs Server
/download                 Rilis terbaru, SHA-256, tab AltStore / SideStore / Xcode, rilis lama
/guides                   Indeks panduan (kartu bergambar per topik)
  getting-started         Instal pertama, pilih koleksi, tur singkat
  ── Koleksi Local
  local                   Cara kerja koleksi Local
  import                  Impor CBZ/ZIP dan folder gambar dari Files
  extension-stores        Menambah store Mihon & repo Kuchie, link mihon:// / tachiyomi://
  extension-safety        Bagaimana Kuchie memutuskan APK aman (tanda tangan v2/v3, trust signer)
  compatibility           Laporan kompatibilitas extension
  ── Koleksi Server
  server                  Menyiapkan Suwayomi-Server
  server-connect          Alamat, network discovery, auth no-auth/basic/UI-login
  tracking                Tracker (lewat server)
  backups                 Backup & restore server
  migration               Migrasi antar sumber
  ── Membaca
  reader                  Mode baca, arah, zoom, gestur, chapter berikutnya
  library                 Kategori, filter, sortir, duplikat, rating, catatan, tag
  updates-history         Updates, history, lanjutkan dari terakhir dibaca
  downloads               Unduhan offline, Live Activities & Dynamic Island
  ── Lainnya
  appearance              Tema, pure black, Liquid Glass, ikon alternatif
  languages               Mengganti bahasa app
  updating                Memperbarui Kuchie tanpa kehilangan data, refresh sertifikat
  troubleshooting
/faq                      FAQ per kategori: Umum · Instalasi · Local & Extensions · Server · Reader
/changelog                Semua versi, anchor per versi, feed RSS
/news                     Pengumuman rilis & berita proyek (blog ringan), feed RSS
/translate                Cara menerjemahkan app & website, progres per bahasa
/contribute               Kode, desain, laporan bug, build from source
/press                    Press kit: logo, ikon, Kiri, screenshot, deskripsi singkat (unduh ZIP)
/privacy                  Kebijakan privasi app & website
/legal                    Disclaimer konten, lisensi, merek, kontak laporan
/credits                  Proyek upstream, store maintainer, penerjemah, aset pihak ketiga
/altstore.json            Source AltStore/SideStore (dibuat otomatis)
/rss.xml                  Feed changelog + news
/404                      Halaman tidak ditemukan (Kiri)
```

Setiap halaman tersedia di semua bahasa (lihat §8). Header: Download (tombol), Features, Guides, FAQ, Changelog, News, pemilih bahasa, toggle tema, GitHub. Footer: semua halaman di atas, sosial (jika ada Discord/Reddit), lisensi, disclaimer satu kalimat.

## 6. Isi dan animasi tiap halaman

Prinsip: setiap animasi harus **menjelaskan sesuatu** (cara kerja fitur, perpindahan mode, status), bukan hanya hiasan.

### 6.1 Home

| # | Section | Isi | Animasi |
| --- | --- | --- | --- |
| 1 | **Header** | logo, menu, bahasa, tema, tombol Download | header glass muncul blur saat scroll; menu mobile terbuka dengan transisi "panel" |
| 2 | **Hero** | judul *"Manga & webtoon, beautifully on iPhone."*, subjudul, CTA **Download v1.0.0** + **Add to AltStore** + GitHub, badge "iOS 15+ · Free · Open source" | panel-panel manga (ilustrasi sendiri) menyusun diri menjadi grid lalu satu panel "masuk" ke layar iPhone; mockup iPhone sedikit miring 3D mengikuti kursor (desktop); Kiri mengintip dari belakang ponsel lalu melambai; latar gradien ungu bergerak pelan; judul muncul per kata |
| 3 | **Angka** | 24 bahasa · 80 store diuji · 211 extension diuji · iOS 15+ | angka menghitung naik saat terlihat |
| 4 | **Dua koleksi** | Local vs Server, bisa ganti kapan saja | section *sticky*: saat scroll, layar ponsel berganti dari Local ke Server dengan transisi geser, ikon awan/ponsel bertukar; teks penjelas ikut berganti |
| 5 | **Reader** | webtoon, paged RTL/LTR/vertikal, slider Liquid Glass | isi layar ponsel ikut bergulir sesuai scroll halaman (simulasi webtoon); tombol mode mengganti tampilan dengan animasi balik halaman 3D; slider halaman bergerak |
| 6 | **Grid fitur** | Library · Updates & History · Offline · Extensions · Server tools · Tampilan | kartu glass muncul bertahap; cahaya rim mengikuti kursor; ikon beranimasi kecil saat hover |
| 7 | **Dynamic Island** | unduhan offline dengan Live Activities | mock Dynamic Island membesar, progress unduhan berjalan, lalu Kiri pose "complete" |
| 8 | **Keamanan extension** | setiap APK dicek terhadap kunci store | diagram alur APK → cek tanda tangan → install / ditolak; garis SVG "tergambar" saat terlihat, centang hijau / silang |
| 9 | **Personalisasi** | tema, pure black, Liquid Glass, ikon alternatif | carousel 6 ikon app; klik ikon → ikon di mockup hero ikut berganti; toggle terang/gelap mengubah screenshot dengan transisi lingkaran |
| 10 | **Bahasa** | 24 bahasa | kata "Library" dalam banyak bahasa bergulir seperti marquee |
| 11 | **Open source** | MPL-2.0, dibangun di atas Suwayomi-Tsumiru, Mihon, M-Extension-Server | logo proyek muncul bertahap, jumlah bintang GitHub (diambil saat build) |
| 12 | **FAQ singkat** | 5 pertanyaan + link | accordion dengan animasi tinggi yang halus |
| 13 | **CTA penutup** | Kiri + Download + AltStore | Kiri melompat kecil saat tombol di-hover |
| 14 | **Footer** | link, disclaimer, lisensi | — |

### 6.2 Features
Versi panjang per kelompok (Reader, Library, Updates & History, Offline, Extensions, Server tools, Appearance) dengan screenshot dan animasi pendek. Tabel interaktif **Local vs Server** dengan filter fitur. Navigasi samping yang menyorot kelompok aktif saat scroll.

### 6.3 Download (paling kritis)
- Kartu rilis terbaru: versi, tanggal, ukuran, tombol unduh, SHA-256 dengan tombol salin, link catatan rilis.
- Persyaratan: iOS 15+, Liquid Glass butuh iOS 26.
- **Wizard instal** bertab: AltStore · SideStore · Xcode. Langkah bernomor dengan screenshot; progres langkah beranimasi.
- Tombol **Add to AltStore** (`altstore://source?url=https://kuchie.app/altstore.json`) dan SideStore.
- Verifikasi: perintah `shasum -a 256` untuk macOS/Linux dan PowerShell `Get-FileHash` untuk Windows.
- Catatan sertifikat Apple ID gratis (7 hari) dan cara update tanpa kehilangan data.
- Daftar rilis sebelumnya.
- Animasi: Kiri pose "complete" + konfeti kecil setelah tombol unduh / salin SHA diklik.

### 6.4 Guides dan FAQ
- Dibangun dengan tema docs yang dikustom penuh agar senada dengan landing (lihat §9).
- Indeks `/guides` berupa kartu bergambar per topik, dikelompokkan seperti peta situs.
- Setiap halaman: daftar isi, pencarian, "Edit this page on GitHub", tanggal update, halaman sebelum/berikutnya, callout (tips/peringatan) bergaya Kuchie.
- FAQ dibagi kategori dengan pencarian. Draf pertanyaan:
  - Umum: Gratis? Ada di App Store? Apakah Kuchie menyediakan manga? Ada versi Android/iPad?
  - Instalasi: Kenapa harus sideload? AltStore vs SideStore? Sertifikat kedaluwarsa? Update tanpa kehilangan data?
  - Local & Extensions: Apakah extension Mihon aman? Kenapa extension tertentu tidak jalan? Kenapa setting extension perlu restart?
  - Server: Server tidak terdeteksi? Auth yang didukung? Bisa akses dari luar rumah?
  - Reader: Mengganti arah baca? Progres tidak tersimpan?

### 6.5 Changelog dan News
- Changelog dibuat dari `CHANGELOG.md` repo app (format Keep a Changelog). Satu kartu per versi dengan label (Added/Fixed/Changed), anchor `/changelog#1.0.0`.
- News: artikel Markdown pendek per rilis besar atau pengumuman; daftar dengan gambar sampul; RSS.

### 6.6 Halaman lain
- **Privacy**: harus akurat terhadap kode. Sebelum menulis, audit dulu: data apa yang tersimpan di perangkat (library, riwayat, kredensial di secure storage), host apa saja yang dihubungi app (server Suwayomi pengguna, store yang ditambahkan, situs lewat extension, GitHub API untuk cek update), dan konfirmasi tidak ada analytics di app. Bagian website menjelaskan analytics yang dipakai (§11).
- **Legal**: disclaimer konten, lisensi, merek "Kuchie" & Kiri, kontak laporan.
- **Credits**: dari README → Credits, `NOTICE.md`, penerjemah dari `assets/licenses/`.
- **Translate**: platform terjemahan, daftar 24 bahasa dengan progres app dan website.
- **Contribute**: build, test, CI, panduan issue & PR, desain (`design/`).
- **Press**: logo SVG/PNG, ikon, pose Kiri, screenshot terbaru, deskripsi 1 kalimat & 1 paragraf, tombol unduh ZIP.
- **404**: Kiri pose "error"/"empty" beranimasi + pencarian + link ke Home.

## 7. Identitas visual

### Palet (dari `design/icons/kuchie-app-icon.svg`)

| Token | Nilai | Pemakaian |
| --- | --- | --- |
| `--ink-900` | `#101120` | latar dark (utama) |
| `--ink-800` | `#17182D` | permukaan dark |
| `--violet-800` | `#302458` | kartu, gradien hero |
| `--violet-500` | `#7966E5` | tombol utama, link |
| `--violet-300` | `#A69AFF` | hover, highlight, rim glass |
| `--violet-100` | `#E5DEFF` | teks aksen di latar gelap |
| `--lavender` | `#CBC1FF` | ilustrasi, badge |
| `--paper-50` | `#FFFDF5` | latar light ("kertas") |
| `--paper-100` | `#F4F0EA` | permukaan light |
| `--warm` | `#F7DEC0` | aksen hangat (dari ikon Cap Kertas), dipakai hemat |

Dark mode sebagai tampilan utama, light mode bernuansa kertas. Semua pasangan teks/latar dicek kontras WCAG AA. Gradien khas: `#302458 → #17182D → #101120` (latar), `#7966E5 → #A69AFF → #E5DEFF` (rim/aksen).

### Tipografi
- **Inter** (sudah ada di `assets/fonts/inter`) untuk huruf Latin, Kiril, Yunani, dan Vietnam.
- **Noto Sans** per aksara, dimuat **hanya** di halaman bahasa yang membutuhkannya: Arabic, JP, KR, SC, TC, Thai, Tamil. Self-host, subset, `font-display: swap`.
- Judul besar: Inter weight tinggi dengan tracking rapat; satu font display opsional untuk hero berbahasa Latin.

### Elemen khas
- **Glass**: header, kartu, dan tombol dengan `backdrop-filter: blur()` + rim gradien ungu, meniru Liquid Glass; fallback solid di browser yang tidak mendukung.
- **Bingkai panel manga**: sudut membulat + "kertas" miring dari ikon app sebagai pemisah section dan bingkai screenshot.
- **Garis kecepatan** (speed lines) SVG tipis sebagai aksen gerak di hero dan CTA.
- **Kiri (maskot)**: pose & animasi dari `assets/kuchie/character/` dan rig sumber `design/kiri/source/`. Untuk web, Kiri sebaiknya diekspor ulang sebagai **SVG berlapis** yang dianimasikan dengan CSS (lebih tajam dan jauh lebih kecil dari WebP); WebP yang sudah ada dipakai sebagai cadangan.
- **Mockup iPhone** dibuat sendiri dalam SVG/CSS (tanpa aset Apple berlisensi).

## 8. Bahasa

Website mengikuti **24 bahasa yang ada di app** (`lib/src/l10n/`):

| Kode URL | Bahasa | Catatan |
| --- | --- | --- |
| `/` | English | bahasa sumber |
| `/id/` | Bahasa Indonesia | ditulis penuh sejak awal |
| `/ar/` | العربية | **RTL** |
| `/ca/` | Català | |
| `/de/` | Deutsch | |
| `/es/` | Español | |
| `/fil/` | Filipino | |
| `/fr/` | Français | |
| `/it/` | Italiano | |
| `/ja/` | 日本語 | font Noto Sans JP |
| `/ko/` | 한국어 | font Noto Sans KR |
| `/nb/` | Norsk bokmål | |
| `/nl/` | Nederlands | |
| `/pt/` | Português | app punya `pt`, `pt_BR`, `pt_PT` |
| `/pt-br/` | Português (Brasil) | |
| `/pt-pt/` | Português (Portugal) | |
| `/ru/` | Русский | |
| `/ta/` | தமிழ் | font Noto Sans Tamil |
| `/th/` | ไทย | font Noto Sans Thai |
| `/tr/` | Türkçe | |
| `/uk/` | Українська | |
| `/vi/` | Tiếng Việt | |
| `/zh-hans/` | 简体中文 | font Noto Sans SC |
| `/zh-hant/` | 繁體中文 | font Noto Sans TC |

Catatan: `pt` vs `pt-br` vs `pt-pt` bisa disederhanakan menjadi `pt-br` + `pt-pt` saja (dengan `/pt/` dialihkan ke `/pt-br/`). Perlu keputusan (§16).

### Strategi terjemahan
- **Semua teks UI dan konten** disimpan sebagai file per bahasa (JSON untuk UI, Markdown untuk halaman). English adalah sumber.
- **Tahap launch**:
  - English dan Indonesia: semua halaman, ditulis manusia.
  - 22 bahasa lain: teks UI, Home, Features, Download, FAQ, Privacy, dan Legal diterjemahkan dengan bantuan mesin lalu ditandai *"perlu review"*. Guides yang belum diterjemahkan otomatis tampil dalam English dengan banner "Halaman ini belum diterjemahkan, bantu terjemahkan".
  - Privacy dan Legal versi non-English diberi catatan bahwa versi English yang berlaku.
- **Setelah launch**: penerjemah komunitas mengulas dan melengkapi lewat platform yang sama dengan app (Weblate/Crowdin, keduanya gratis untuk proyek open source).
- **Deteksi bahasa**: tanpa redirect otomatis (buruk untuk SEO dan membingungkan). Tampilkan banner kecil "Tersedia dalam Bahasa Indonesia" bila bahasa browser berbeda dengan halaman; pilihan disimpan di `localStorage`.
- **RTL (Arabic)**: seluruh CSS memakai *logical properties* (`margin-inline-start`, `inset-inline`, dll.) sehingga tata letak otomatis terbalik; animasi arah geser juga dibalik.
- SEO: `hreflang` untuk semua bahasa, `x-default` ke English, sitemap per bahasa.

## 9. Teknologi

Kriteria: ringan, bebas dikustom, statis (murah dan cepat), animasi kaya tanpa membebani.

### Rekomendasi

| Lapisan | Pilihan | Alasan |
| --- | --- | --- |
| Framework | **Astro** (output statis) | HTML statis, 0 KB JS secara default; JS hanya dimuat di komponen yang butuh ("islands"); i18n routing bawaan; bebas memakai komponen sendiri tanpa terikat framework UI |
| Docs (Guides/FAQ) | **Starlight** (tema docs Astro), dikustom penuh | sidebar, pencarian, i18n dengan fallback ke English, RTL, "Edit this page" sudah ada; komponen header/footer/warna bisa diganti agar menyatu dengan landing |
| Pencarian | **Pagefind** (bawaan Starlight) | index statis per bahasa, tanpa server atau layanan luar |
| Styling | **CSS murni** + custom properties + CSS nesting | tanpa framework CSS; token di §7; ukuran CSS kecil |
| Animasi dasar | **CSS scroll-driven animations** (`animation-timeline: view()/scroll()`) | berjalan di thread compositor, tanpa JS; reveal, parallax, progress |
| Animasi lanjut | **Motion** (versi vanilla JS, `animate` / `inView` / `scroll`) | untuk urutan rumit (hero, section sticky), fallback bila browser belum mendukung scroll-driven CSS; kecil dan *tree-shakeable* |
| Transisi halaman | **View Transitions API** (`@view-transition { navigation: auto; }`) | transisi antar-halaman tanpa JS, didukung Safari 18.2+ dan Chrome; browser lama berpindah biasa |
| Maskot | **SVG + CSS** (dari rig `design/kiri/source/`), WebP sebagai cadangan | tajam di semua layar, beberapa KB |
| Gambar | `astro:assets` → AVIF/WebP + `srcset` | otomatis ukuran yang pas |
| Kualitas | TypeScript, Prettier, Lighthouse CI, cek link rusak, Playwright untuk uji visual | |

**Tidak dipakai:** Three.js/WebGL (berat untuk iPhone lama), Lottie (runtime besar), GSAP (tidak perlu bila CSS + Motion cukup), smooth-scroll seperti Lenis (mengganggu scroll native iOS dan aksesibilitas), framework UI (React/Vue) kecuali kelak dibutuhkan satu komponen.

Alternatif yang dipertimbangkan: VitePress (dipakai Mihon; bagus untuk docs tetapi landing terbatas pada tema), Next.js (terlalu berat untuk situs statis), SvelteKit (bagus, tetapi Astro lebih sederhana untuk situs konten + multibahasa).

### Aturan performa animasi
- Hanya menganimasikan `transform`, `opacity`, dan `clip-path`; tidak menganimasikan ukuran/posisi layout.
- Animasi di luar layar dijeda (`IntersectionObserver` / `animation-play-state`).
- `prefers-reduced-motion: reduce` → semua gerakan diganti fade sederhana atau gambar diam; Kiri memakai pose statis (sama seperti app).
- Tidak ada scroll hijacking: scroll tetap native, section sticky memakai `position: sticky`.
- JS dimuat setelah konten terlihat (`client:visible` / `client:idle`).

### Anggaran ukuran (Home, mobile, setelah gzip)

| Item | Batas |
| --- | --- |
| HTML | ≤ 40 KB |
| CSS | ≤ 35 KB |
| JS total | ≤ 60 KB |
| Font (satu bahasa Latin) | ≤ 60 KB |
| Gambar di atas fold | ≤ 150 KB |
| LCP (4G) | < 2 detik |
| CLS | < 0,05 |
| INP | < 200 ms |

## 10. Repo, data, dan deploy

### Repo `kuchie-app/website`
```
website/                      (repo kuchie-app/website)
  PLAN.md                     ← dokumen ini
  astro.config.mjs
  package.json
  public/
    favicon.svg  apple-touch-icon.png
    kiri/                     ← SVG/WebP Kiri
    press/                    ← press kit
  scripts/
    fetch-release.mjs         ← rilis dari GitHub API → src/data/releases.json
    fetch-app-content.mjs     ← CHANGELOG.md + laporan kompatibilitas dari repo app
    i18n-check.mjs            ← laporan kunci terjemahan yang hilang
  src/
    components/
      layout/   Header, Footer, LangSwitcher, ThemeToggle, LangBanner
      home/     Hero, Stats, Collections, ReaderShowcase, FeatureGrid,
                DynamicIsland, ExtensionSafety, IconGallery, LanguageMarquee,
                OpenSource, FaqTeaser, FinalCta
      ui/       Button, GlassCard, PhoneMockup, Kiri, CodeCopy, Tabs, Accordion
    content/
      docs/<lang>/guides/*.md  docs/<lang>/faq/*.md
      news/<lang>/*.md
    i18n/<lang>.json
    data/releases.json        ← cache rilis terakhir (fallback bila API gagal)
    pages/
      [...lang]/index.astro  features.astro  download.astro  changelog.astro
      [...lang]/translate.astro  contribute.astro  press.astro  credits.astro
      [...lang]/privacy.md  legal.md
      altstore.json.ts  rss.xml.ts  404.astro
    styles/ tokens.css  base.css  motion.css
  .github/workflows/
    deploy.yml  pr-check.yml
```

### Pembagian docs antar repo
- **Repo website** memegang semua panduan pengguna (karena terjemahannya ada di sini). `docs/local-extensions.md` di repo app diubah menjadi ringkasan + link ke `kuchie.app/guides/extension-stores`.
- **Repo app** tetap memegang docs developer (build, runtime, QA), `CHANGELOG.md`, dan `docs/extension-compatibility.md`. Website mengambil keduanya dari **tag rilis terbaru** saat build, supaya isi changelog dan kompatibilitas cocok dengan versi yang bisa diunduh.

### Data rilis otomatis
- `fetch-release.mjs` membaca `https://api.github.com/repos/kuchie-app/Kuchie/releases` (endpoint yang sama dengan pengecekan update di app): versi, tanggal, URL IPA, ukuran, isi `.sha256`, catatan rilis.
- Dipakai di Home (tombol Download), Download, Changelog, News, dan **`/altstore.json`** (nama, bundle ID `app.kuchie.reader`, ikon, tint `#7966E5`, screenshot, daftar versi dengan `downloadURL`, `size`, `minOSVersion: "15.0"`, `localizedDescription`).
- Memakai `GITHUB_TOKEN` di CI untuk menghindari rate limit; bila API gagal, pakai `src/data/releases.json` yang terakhir di-commit.

### Deploy
- **Hosting: Cloudflare Pages** dengan domain `kuchie.app` (DNS di Cloudflare). `www.kuchie.app` dialihkan ke `kuchie.app`.
- `deploy.yml` di repo website berjalan saat:
  1. push ke `main`,
  2. `repository_dispatch` dari `release.yml` repo app (tambahkan satu langkah di akhir `release.yml` dengan token fine-grained yang hanya boleh memicu workflow repo website),
  3. jadwal harian (cadangan bila dispatch gagal).
- `pr-check.yml`: build, cek link rusak, `i18n-check`, Lighthouse CI dengan anggaran §9, dan deploy preview Cloudflare per PR.
- Header keamanan dan cache via `public/_headers` (CSP ketat, HSTS, cache panjang untuk aset berhash); redirect via `public/_redirects`.

## 11. SEO, analytics, aksesibilitas

**SEO**
- Title & meta description per halaman per bahasa, `hreflang`, canonical.
- Gambar Open Graph otomatis per halaman (logo + Kiri + judul dalam bahasa halaman) dibuat saat build.
- `sitemap.xml`, `robots.txt`, structured data `SoftwareApplication` (iOS, harga 0, versi) dan `FAQPage` di halaman FAQ.

**Analytics**: **Cloudflare Web Analytics** (gratis, tanpa cookie, tanpa banner persetujuan). Dijelaskan di `/privacy`.

**Aksesibilitas (target WCAG 2.2 AA)**
- Kontras lolos di kedua tema, fokus keyboard terlihat, skip-link, HTML semantik, `lang` dan `dir` benar per halaman.
- Semua animasi bisa dimatikan (reduced motion) dan tidak ada yang berkedip > 3 kali/detik.
- Gambar bermakna punya `alt` per bahasa; animasi dekoratif `aria-hidden`.
- Tombol salin, tab, accordion bisa dipakai dengan keyboard dan pembaca layar.

## 12. Aset yang perlu disiapkan

| Aset | Sumber | Catatan |
| --- | --- | --- |
| Logo & favicon | `design/icons/*.svg` | SVG + PNG 180/192/512 |
| Kiri | `design/kiri/source/`, `assets/kuchie/character/` | ekspor SVG berlapis untuk web + WebP cadangan |
| Ikon alternatif | `assets/icons/app-icon-*.png` | galeri & altstore.json |
| Ilustrasi panel manga | dibuat baru | untuk hero; gaya senada Kiri, bukan dari manga mana pun |
| Screenshot app | simulator + fixture QA | ~12 layar × light/dark; versi English & Indonesia (bahasa lain memakai English) |
| Rekaman layar pendek | simulator | webtoon scroll, Dynamic Island; dipakai sebagai referensi animasi, atau video MP4/WebM ≤ 500 KB |
| Mockup iPhone | SVG buatan sendiri | |
| Copywriting | ditulis baru | English & Indonesia dulu, lalu terjemahan |

Daftar screenshot: onboarding pilih koleksi, library grid, detail manga, reader webtoon, reader paged, slider Liquid Glass, updates, history, downloads + Dynamic Island, extension stores, layar connect server, pengaturan tampilan/ikon.

## 13. Perubahan di repo app

Kecil, setelah website live:
- `release.yml`: tambahkan `--dart-define=KUCHIE_PRIVACY_URL=https://kuchie.app/privacy` dan `KUCHIE_TRANSLATIONS_URL=https://kuchie.app/translate`, plus langkah `repository_dispatch` ke repo website.
- Tautan "Website" di layar More/About (opsional).
- README: link ke kuchie.app; `docs/local-extensions.md` diringkas dan diarahkan ke guide di website.

Catatan: **universal links tidak direkomendasikan**. File `apple-app-site-association` terikat ke Team ID, sedangkan setiap pengguna sideload menandatangani ulang IPA dengan tim mereka sendiri.

## 14. Tahapan kerja

| Fase | Isi | Perkiraan |
| --- | --- | --- |
| **0. Persiapan** | beli domain, buat repo `kuchie-app/website`, project Cloudflare Pages, keputusan §16 | 1 hari |
| **1. Fondasi** | setup Astro + Starlight, token warna & font, layout, header/footer, routing 24 bahasa + RTL, tema terang/gelap, deploy pertama ke kuchie.app | 3 hari |
| **2. Sistem animasi & komponen** | `motion.css`, utilitas reveal/parallax, PhoneMockup, GlassCard, Kiri SVG, aturan reduced motion | 3 hari |
| **3. Home** | 14 section + animasinya, diuji di iPhone sungguhan | 5 hari |
| **4. Download & Features** | wizard instal, kartu rilis, tabel Local vs Server | 3 hari |
| **5. Guides, FAQ, halaman lain** | tulis ~20 guide + FAQ (en & id), Changelog, News, Privacy (setelah audit kode), Legal, Credits, Translate, Contribute, Press, 404 | 5 hari |
| **6. Otomasi** | fetch-release, altstore.json, RSS, dispatch dari repo app, PR check & Lighthouse CI | 2 hari |
| **7. Terjemahan** | terjemahan bantuan mesin untuk 22 bahasa, setup platform terjemahan, `i18n-check` | 2–3 hari |
| **8. Aset & polish** | screenshot, gambar OG, SEO, audit aksesibilitas, uji Safari iOS/Chrome/Firefox, Android, layar kecil | 3 hari |
| **9. Launch** | update repo app & README, umumkan di News dan rilis berikutnya | 1 hari |

Total: kira-kira **4–6 minggu** kerja santai. Fase 4–5 bisa paralel setelah fase 2 selesai.

### Setelah launch (opsional)
- Halaman status kompatibilitas extension yang diperbarui otomatis dari laporan QA.
- Showcase tema/ikon komunitas.
- Halaman roadmap dari GitHub Projects.

## 15. Definisi selesai

- [ ] Semua halaman di §5 ada dalam English dan Bahasa Indonesia; 22 bahasa lain minimal Home, Features, Download, FAQ, Privacy, Legal, dan UI.
- [ ] Tata letak Arabic (RTL) benar di semua halaman.
- [ ] Tombol Download selalu menunjuk ke IPA terbaru dengan SHA-256 yang cocok.
- [ ] `/altstore.json` bisa ditambahkan di AltStore dan SideStore (diuji di perangkat).
- [ ] Tidak ada screenshot/teks yang menampilkan konten berhak cipta atau situs sumber tertentu.
- [ ] Lighthouse mobile ≥ 95 dan anggaran ukuran §9 terpenuhi di Home, Download, satu guide.
- [ ] Animasi 60 fps di iPhone 11; semua animasi mati dengan Reduce Motion.
- [ ] Tidak ada link rusak; 404 berfungsi.
- [ ] Rilis baru di repo app memperbarui website otomatis.
- [ ] `/privacy` sudah dicocokkan dengan perilaku app yang sebenarnya.

## 16. Keputusan yang masih perlu dari kamu

1. **Portugis**: tiga varian (`pt`, `pt-br`, `pt-pt`) seperti app, atau dua saja (`pt-br`, `pt-pt`)?
2. **Platform terjemahan**: Weblate atau Crowdin (keduanya gratis untuk open source), atau PR langsung ke file?
3. **Sosial/komunitas**: ada Discord, Reddit, atau X untuk ditautkan?
4. **Kontak**: pakai email `@kuchie.app` (diteruskan ke email kamu) atau GitHub Issues/Security Advisories saja?
5. **Ilustrasi hero**: dibuat dari aset Kiri yang sudah ada, atau perlu ilustrasi panel manga baru?

## 17. Perkiraan biaya

Harga per 18 November 2026, kurs perkiraan **Rp16.500/USD**. Dihitung ulang saat launch.

### Wajib

| Item | Pilihan | Biaya |
| --- | --- | --- |
| Domain `kuchie.app` | **Cloudflare Registrar** (harga modal, tanpa markup) | sekitar **US$14/tahun** (≈ Rp230.000). Tahun pertama bisa lebih murah bila ada promo registry |
| Hosting | **Cloudflare Pages Free** | **Rp0**: bandwidth statis tanpa batas, 500 build/bulan, preview per PR, SSL otomatis |
| **Total wajib** | | **≈ US$14/tahun ≈ Rp230.000/tahun** (≈ Rp19.000/bulan) |

Pengecekan RDAP registry hari ini tidak menemukan registrasi untuk `kuchie.app`, jadi domain kemungkinan masih tersedia. Pastikan lagi saat membeli.

Domain `.app` wajib HTTPS; Cloudflare Pages menyediakannya otomatis.

### Gratis (sudah termasuk)

| Item | Layanan |
| --- | --- |
| Repo & CI | GitHub (repo publik, Actions gratis) |
| Analytics | Cloudflare Web Analytics |
| Email `legal@` / `security@` | Cloudflare Email Routing (meneruskan ke email kamu) |
| Pencarian | Pagefind (statis) |
| Terjemahan | Hosted Weblate (paket Libre) atau Crowdin for Open Source |
| SSL, CDN, proteksi DDoS dasar | Cloudflare |

### Perbandingan registrar untuk `.app` (perpanjangan per tahun)

| Registrar | Tahun pertama | Perpanjangan | Catatan |
| --- | --- | --- | --- |
| Cloudflare | ~US$8–14 | ~US$14,20 | harga modal; wajib memakai DNS Cloudflare (cocok dengan hosting) |
| Porkbun | ~US$8–9 | ~US$15 | bebas memakai DNS mana pun |
| Namecheap | ~US$8–11 | ~US$23 | perpanjangan paling mahal |

### Opsional (hanya bila dibutuhkan)

| Item | Biaya |
| --- | --- |
| Plausible Analytics (pengganti Cloudflare Analytics) | ~€9/bulan |
| Cloudflare Pages Pro (bila > 500 build/bulan, sangat tidak mungkin) | US$20/bulan |
| Domain tambahan (mis. `kuchie.id`, `getkuchie.com`) untuk melindungi merek | ~US$10–40/tahun per domain |

Batas yang perlu diperhatikan di paket gratis Cloudflare Pages: maksimal 20.000 file per deploy. Dengan 24 bahasa, index Pagefind, dan gambar, situs diperkirakan beberapa ribu file, masih jauh di bawah batas. `i18n-check` di CI akan ikut melaporkan jumlah file.

Sumber harga: [costgoat](https://costgoat.com/compare/domains/app), [tldes](https://tldes.com/app), [tldprice](https://tldprice.org/tld/app), [hostingcompass](https://hostingcompass.com/en/domains/app), [badsky (Cloudflare)](https://badsky.net/domains/providers=cloudflare), [temps.sh (batas Cloudflare Pages)](https://temps.sh/blog/cloudflare-pages-free-tier-limits-2026), [hostfleet (perbandingan hosting)](https://hostfleet.pages.dev/cf-pages-vs-vercel-vs-netlify-2026/).

## 18. Risiko

| Risiko | Dampak | Mitigasi |
| --- | --- | --- |
| Website dianggap mempromosikan pembajakan | laporan ke hosting/registrar | aturan konten §4, disclaimer, tidak menautkan sumber |
| Animasi berat di perangkat lama | situs patah-patah, Lighthouse turun | aturan §9, anggaran ukuran di CI, uji di iPhone 11 dan Android menengah |
| Terjemahan mesin kurang tepat | kesan tidak profesional | label "perlu review", prioritaskan review komunitas untuk Home & Download |
| 24 bahasa memperlambat update konten | halaman bahasa lain usang | fallback ke English dengan banner, `i18n-check` melaporkan kunci yang hilang |
| GitHub API rate limit / gagal saat build | versi tidak ter-update | `GITHUB_TOKEN` + cache `releases.json` |
| Dispatch dari repo app gagal | website telat update setelah rilis | build terjadwal harian sebagai cadangan |
| Privacy policy tidak akurat | kehilangan kepercayaan | audit kode network sebelum menulis |
| Harga domain naik | biaya tahunan naik | Cloudflare tidak menambah markup; perpanjang beberapa tahun sekaligus bila perlu |
