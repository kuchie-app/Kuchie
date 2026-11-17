# Mihon extension compatibility

This report describes how Kuchie 1.0.0 was tested against public Mihon extension stores and how each failure was attributed.

## Method

1. **Stores.** 149 candidate store URLs were collected from community repo lists and a GitHub code search for Mihon `repo.json` files. 88 were live manga stores; the rest were dead links, anime-only (Aniyomi) stores, or other apps' formats. The harness added 80 distinct stores, including Keiyoushi, Yūzōnō, Cursed Yūzōnō, Suwayomi, Kavita and many personal stores.
2. **Extensions.** From each store the harness picked random extensions (30 from Keiyoushi, up to 3 from each other store): 211 in total. Each was installed through Kuchie's real code (store parsing, APK signature check, embedded runtime) and walked through popular list → manga details → chapter list → pages of the oldest chapter. APKs not signed by their store's key were trusted, as a Mihon user would tap **Trust**.
3. **Reference.** Every failure was run again through [Suwayomi-Server](https://github.com/Suwayomi/Suwayomi-Server), a separate JVM implementation of the Tachiyomi extension API, installing the same package from the same store. A failure that also happens there belongs to the extension, its site or its store. A failure that happens only in Kuchie was treated as a Kuchie bug and fixed.

The harness has no WebView, so sites behind Cloudflare fail in it even though the app solves them (see below).

## Result

| Outcome | Extensions |
| --- | --- |
| Works end to end (list, details, chapters, pages) | 91 |
| Cloudflare or bot check; solved in the app by its WebView | 21 |
| Site or extension error that Suwayomi shows too | 32 |
| Site page or APK gone (404) | 26 |
| Corrupt APK (fails the JVM verifier in Suwayomi too) | 12 |
| Needs an account or settings first (now in **Source settings**) | 6 |
| Domain no longer exists | 6 |
| Built against a Mihon fork's API (Komikku, Kotatsu, novel apps) | 5 |
| Site timeout or rate limit | 3 |
| Site certificate chain broken | 3 |
| Not a Mihon extension | 3 |
| Store entry points to the wrong package | 3 |

No failure remained that happened only in Kuchie. Cloudflare-protected sources were checked in the app on the simulator: Komikzoid, which returns 403 to any plain HTTP client, listed manga and chapters after the WebView solved its challenge.

## Kuchie and runtime bugs found and fixed

| Symptom | Cause | Fix |
| --- | --- | --- |
| No current extension could list manga | The runtime translated constructors of R8-optimised classes into code the JVM rejects | Runtime upgraded to M-Extension-Server v1.0.8.1 |
| MangaDex and others: HTTP 403 | The runtime replaced every extension's own user-agent | `patches/0001-keep-extension-user-agent.patch` |
| Turnstile solvers crashed | `View.getParent()` threw instead of returning `null` | `patches/0002-detached-view-has-no-parent.patch` |
| Descrambled pages (AchyManga) did not load | The native WebP reader cannot load on iOS, and `Bitmap.setPixels` was missing | `patches/0003-bitmap-webp-and-pixel-access.patch` |
| Chinese, Japanese and Thai sources: 404 on details | Requests to the runtime had no UTF-8 charset, so non-Latin URLs were garbled | Requests declare `charset=utf-8` |
| Guya-based sources: no pages | Page requests sent only the chapter URL; Mihon sends the whole chapter (scanlator, number, date) | The chapter travels with its fields |
| Single-series sources (webcomics) failed | An empty manga or chapter URL was rejected; Mihon allows it | Empty URLs accepted |
| Large catalogues (1,797 titles on one page) failed | Lists were capped at 1,000 items | Caps raised to 20,000 |
| Large APKs timed out | The runtime call timed out after 45 seconds | 90 seconds per call, 3 minutes to load an APK |
| Only 32 stores could be added | A local limit Mihon does not have | 256 stores |
| Stores with an MD5, SHA-1 or missing signing key were refused | Kuchie required a SHA-256 key | Accepted as in Mihon; their APKs need the reader's trust |
| Aniyomi stores broke the whole index | A reused protobuf field number | Unknown field types are skipped |
