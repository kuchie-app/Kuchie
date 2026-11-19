# Changelog

All notable changes to Kuchie are listed here. Versions follow [Semantic Versioning](https://semver.org).

## [1.1.0] - 2026-11-20

### Reader
- **Smooth scrolling in Webtoon and long strip**: a page that finished loading above the screen used to make the reader jump back to it, rebuild every page (a black flash with a spinner) and stop the fling. The strip now only shifts by the page's size change and keeps the fling going. One-finger drags use native iOS scrolling at 1x, and a tap no longer leaves the strip stuck mid-bounce.
- Local chapters read online fetch a few pages ahead, so fast flings land on loaded pages.
- **Swipe right from the left edge** closes the reader and returns to the manga.
- **Settings** are one short sheet, as in Tachimanga: reading mode, rotation, tap zones (shown as pictures, with invert and page animation), background, side padding, crop borders and auto scroll. Everything else is under **Advanced**.
- Server and Local readers share the same top bar, bottom bar, menus and tap zones.

### Manga details
- **Resume** opens the chapter you read most recently, at its page; once that chapter is finished, the next one after it.
- Both collections show the same actions: **Add to library**, **Tracking** and **Web View**. Downloading is on the server only; the save-to-device buttons are gone from server series (copies already on the device can still be removed).
- Under the tags: your **rating**, then **notes**, categories and your own tags.
- Chapters show whether they are read, bookmarked or saved, and how far you got (Page 12 of 40). List, grid and filter buttons share one style.
- Tap the title or author to copy it; press and hold to search it.

### Browse
- Sources show **settings** (when the extension has them), **pin** and **Latest** buttons.
- Installing or updating an extension starts right away. Only an APK signed with a key other than its store's still asks first.
- **Migrate** in the Local collection lists the sources of your library with a count; a source lists its series, each with Show entry and Migrate.
- A source's page keeps its covers visible behind the collapsed title and filters.

### History, Updates and tabs
- **History** opens the manga, shows time read and when, and has a delete button (Local). Covers of Local series are kept on the device.
- **Updates** in the Local collection list each new chapter with a save button, a summary banner and an updates summary.
- **Customize tabs** (Settings › General): choose the tabs, drag them into order and show or hide labels.
- Lists in Library, Updates, Browse and History no longer end under the tab bar.

### App
- Kuchie uses the iOS system font (SF Pro).
- Extension stores download faster, Hitomi, Doujindesu and Danbooru open and load their covers, and Local network permission problems are explained.


### App icon
- **Bookmark Scarf** is now the default icon. The others are named after what they show: **Kiri**, **Frame Peek** and **Paper Seal**. Open Frame was removed.
- The image upload under "Use your own image" is gone: iOS cannot set an app icon from a picture. The sheet now walks through making a Home Screen shortcut in the Shortcuts app.
- Icon, Live Activity and design asset files have English names. Saved Live Activity styles carry over.

### Both collections
- Connecting to a server: when a local address (192.168.x.x, 10.x, .local) cannot be reached on iPhone, Kuchie now says that Local Network permission is the likely cause and offers **Open Settings**; Safari has its own permission, so it can open the address while Kuchie cannot. Search my network shows the same hint when it finds nothing.
- Search my network scans the Wi-Fi subnet. It used to take the first private address, which on an iPhone can be the cellular (`pdp_ip`, often 10.x) or VPN interface.
- **More** lists the same rows in the same order in Local and Server: Incognito mode, General, Appearance, Library, Reader, (Sync, Tracking on Server), Extensions, Backup & Restore, Security and privacy, Reading Insights, Downloads, then Settings (Server), Share, Help and About. History is no longer repeated there (it is a tab).
- **Reading Insights**: total reading time and time per title, counted in both readers while they are open (not in Incognito mode). History rows show each title's reading time.
- **History** works the same in both: tapping a row opens the manga, Back from the reader lands on the manga page, and long-press opens the row's actions (including Continue reading).
- **Downloads**: the queue has a Pause/Resume button and Clear in the toolbar in both collections.
- **Security and privacy → Disable content sharing** blocks sharing manga links, pages and covers.

### Local collection
- **General** holds the app language, **Storage** (space used by downloads per title, extension cache and saved covers, each clearable) and **Advanced** (Clear cache; Network: Clear cookies, Bypass Cloudflare automatically, Clear Cloudflare pop-up mutes, User agent; Troubleshoot).
- **General** also has **Default tab** (or the last opened tab).
- **Library**: the filter button opens Filter (unread, downloaded), Sort (alphabetical, last read, unread, total chapters; tap again to reverse) and Display (grid or list, items per row, unread and downloaded badges). Covers show how many chapters are saved. The ⋯ menu can open a random title.
- **Library** settings: Edit categories, Show number of items, Display mode, Items per row, Unread and Downloaded badges. **Extensions** settings: extension stores, Source settings and 18+ extensions. **Downloads** settings (gear in Downloads): Delete after reading.
- **Backup & Restore** is a page of its own: create or restore a backup, automatic backups (frequency and how many to keep, run when Kuchie opens) and the backups kept on this iPhone (restore, save to Files, delete).
- History rows show when (time today, Yesterday, days ago) and have a delete button with confirmation; the toolbar has an Incognito button.
- **About** shows the version, update check, release notes and licenses.
- **Security and privacy** (both collections): App lock with Face ID, Touch ID or the passcode, a lock delay, and Secure screen to hide Kuchie in the app switcher.
- **Advanced → Network**: Bypass Cloudflare automatically (on/off), Clear Cloudflare pop-up mutes, User agent and Clear cookies. When a hidden Cloudflare check needs a tap, Kuchie asks you to verify, and you can mute the question per site.
- A source's browse page has a large title that collapses into the navigation bar, with Popular, Latest and Filter pinned under it.
- History shows covers for titles read online, including covers an extension served through the runtime. Reopening a chapter from History shows progress while the source loads.

### Browsing and reading
- **Source filters**: Filter on a source's page opens the extension's own filters (sort, status, type, genres and others) in the same sheet Server sources use, with Reset and Filter. The Filter button shows how many are set. Sources without filters still choose between Popular and Latest.
- Sources with settings have a settings button on their row in Browse.
- Extensions: the Extensions tab shows how many updates are waiting, and the updates section has **Update all**. An update that needs you to trust a new signer is left for a single update.
- Installing an extension confirms with a snack bar and an **Open** button, and shows a spinner while it works.
- Long-press a cover in a source to add it to or remove it from the library (with Undo). Titles already in the library carry an **In library** badge.
- Sources are grouped by language with your own language first, then alphabetically.
- **Save to device** offers the next 1, 5 or 10 chapters, all unread, or all chapters.
- History shows one row per series; a row's menu has **Remove from history**, and the toolbar has **Clear history**.
- In History, tapping a cover opens the manga; tapping the row continues the chapter, and Back from the reader returns to the manga instead of History.
- The manga page's **Resume** button also counts chapters read online, so it continues the chapter History shows.
- Downloads show covers in Queue, and **On device** lists one row per title (tap for its chapters, long-press to delete them all).
- Extension stores: a store's web page (such as yuzono.github.io/extensions) or a `mihon://` link can be added directly. A retired store that only lists "update/migrate" notices (the old Yūzōnō manga-repo) is refused with an explanation and an **Add Keiyoushi** button, and notice entries are hidden from other stores.
- **Updates** counts only chapters a source added since the last check, instead of every chapter of a newly added title, and shows covers.
- When a source or chapter fails, the message says why (the extension's own error, a site block with a WebView button, a slow source), instead of "Could not load manga" or "Something went wrong".
- Search fields no longer autocorrect titles (typing "Honeytoon" became "Honeymoon").
- App lock explains why it stayed off when the device cannot verify you.

### Performance
- Measured on an iPhone 15 (Profile build, 35 s of fast scrolling through the 1,700-entry extension list): median frame build 1.95 ms and raster 0.92 ms, 99th percentile 4.6 ms and 1.8 ms, and 2 of 2,411 frames over the 16.7 ms budget (the first frame of opening the list). Idle CPU about 3%, which is Flutter's profile-mode sampler; memory about 210–225 MB.
- A source's page, Server source lists and Server Updates no longer redraw 60 times a second while idle. The paging package kept its next-page shimmer built far below the screen whenever another page existed; it now shows only while a page is loading. Idle CPU on a source page in the Simulator went from about 24% (180 frames every 3 s) to about 1% (0 frames).
- Library, History, Downloads, Updates and the manga page no longer check the disk for each cover while they build or scroll; kept covers are listed once in the background.
- List covers decode at row size, and library sorting works out each title's keys once instead of on every comparison.

### Extension runtime
- Page images and covers from sources behind Cloudflare load again (Danbooru's image server answered 403; some Doujindesu covers stayed blank). The runtime's image proxy pinned image requests to HTTP/1.1, and Cloudflare refuses a browser user agent over HTTP/1.1; image requests now negotiate HTTP/2 like the extension's other requests. Checked on an iPhone 15 with Danbooru and Hitomi (Cursed Yūzōnō), and on the Mac with Doujindesu, Kiryuu, MangaPill and WestManga.
- The runtime applies Kuchie's user agent before it loads an extension, so the headers an extension builds once on load carry it instead of the runtime's desktop Firefox default. Page downloads also send it when the extension gives no user agent of its own.
- The default user agent is now this iPhone's own (Settings → General → Advanced → User agent). Danbooru shows a Cloudflare check to desktop browsers only, and it matches the browser Kuchie opens to pass a check.
- `prepare.sh` now makes Xcode recompile the runtime bridge. Running it after a first build used to give an app that embedded OpenJDK but reported "Extensions need the extension runtime, which this build does not include".
- **Simulator**: Debug builds start (or refresh) the extension runtime on the Mac during the Xcode build, and the app finds it on its own. Installing and opening extensions works from Xcode, `flutter run` or the Home Screen icon, with no environment variables.
- APKs translated to JVM classes are cached on the device, so reopening an extension after Kuchie restarts skips the slowest step.
- The runtime starts in the background when Browse opens or the Local collection starts, and loads the extensions behind recent History entries.
- After iOS suspends Kuchie, the runtime reopens its listener instead of failing with "runtime unavailable". A start that takes long now gets three minutes, and the message says to try again instead of claiming the build lacks the runtime.
- The JDK image is no longer re-verified on every start; extension classes are still verified.

## [1.0.0] - 2026-11-16

First public release.

### Collections
- Choose **Local** or **Server** at first launch and switch any time; each collection keeps its own library, history and downloads.
- **Server**: Suwayomi libraries, updates, history, download queue, trackers, migration and backups, with network discovery and no-auth, basic or UI-login servers.
- **Local**: import CBZ/ZIP archives and image folders, Kuchie extension repositories, and offline chapters saved on the iPhone.

### Mihon extension stores
- Add any store Mihon accepts: v2 indexes (`index.pb` protobuf or JSON, gzipped or not, with `extensionListUrl`), `repo.json` with `index_v2`, legacy `index.min.json`, and `mihon://` / `tachiyomi://add-repo` links. Tested with Keiyoushi, Suwayomi and Yūzōnō stores.
- Every APK's Signature Scheme v2/v3 signature is verified. APKs signed by their store's key install directly; others install only after you trust their signer, as in Mihon. Tampered APKs, plain-HTTP stores and stores that change their key are refused with a clear message.

### Reader and app
- Paged and continuous reading modes, chapter-to-chapter reading and page actions. Webtoon (continuous vertical) is the default.
- The page slider starts at page 1 on the left in every reading direction.
- Live Activities and Dynamic Island for downloads, Liquid Glass controls on iOS 26, themes, alternate app icons and 20+ languages.
- The in-app update check and project links point to github.com/kuchie-app/Kuchie by default.

### Fixed
- History showed the resume page one lower than the reader (for example 1/18 while reading page 2).
- Library category filters could notify listeners while a widget was building, which Riverpod forbids.
- Release logging, HTTP client leaks and startup crash handling.

### Extension runtime and compatibility
- The embedded runtime is M-Extension-Server v1.0.8.1, built for iOS with three Kuchie patches (extension user-agents, detached views, WebP and bitmap pixels). Release IPAs include it.
- Cloudflare challenges are solved in a hidden WebView, using Mangayomi's remote WebView bridge.
- **Source settings** for extensions that offer them (server addresses, logins, languages, mirrors).
- Untrusted APKs (not signed by their store's key, or from stores without a SHA-256 key) install after you trust their signer, as in Mihon. Anime extensions and unsupported extension-lib versions are left out, as in Mihon.
- Fixed: UTF-8 requests to the runtime, full chapter data for page lists, empty URLs, large catalogues, long APK loads, and the 32-store limit.
- Tested against 80 public stores and 211 extensions with Suwayomi-Server as a reference; see docs/extension-compatibility.md.

### Known limitations
- Some extensions apply a changed setting only after Kuchie restarts, as in Mihon.
- Extensions built for Mihon forks (Komikku, Kotatsu, novel readers) need APIs Mihon does not have.

[1.0.0]: https://github.com/kuchie-app/Kuchie/releases/tag/v1.0.0
