# Sync with Suwayomi

Kuchie keeps your library on your iPhone. If you run a [Suwayomi](https://github.com/Suwayomi/Suwayomi-Server) server, Sync keeps it and the iPhone alike: what you read on one shows up on the other, and on anything else that uses the server, such as its WebUI.

Your iPhone stays the source of truth. Kuchie works fully without the server; while it can't be reached, your changes wait and go out when it's back.

## Connect

1. Open **More → Sync** and tap **Connect sync** (or pick **Add a server** the first time you open Kuchie).
2. Enter the server's address, for example `http://192.168.1.10:4567`, or tap **Search my network**. Sign in if the server asks.
3. Kuchie compares both libraries without changing anything, then shows what it found:
   - **The iPhone is empty**: the first sync copies the server's library.
   - **The server is empty**: the first sync sends the iPhone's library.
   - **Both match**: they just sync.
   - **They differ**: choose **Merge** (keep everything from both), **Use the server library**, or **Use the iPhone library**.
4. Tap **Start sync**. The cloud next to the Library title shows how it's going.

## What syncs

| | |
|---|---|
| Library and categories | Yes |
| Read, unread, last page and history | Yes |
| Chapter bookmarks | Yes |
| Reader settings per series | Yes |
| Rating, tags and notes | Off at first; on by itself if the server already has ratings or tags |
| Extensions | Suggested, never installed for you |
| Downloads on the server | Shown on the iPhone; see below |

Turn any of these off in **Sync → Suwayomi server → Advanced**.

Some series stay on the iPhone only, because the server has no source for them: file imports, Kuchie repository sources and the built-in Shinigami source. **Sync → Suwayomi server → Needs attention** lists them with the reason.

### When both sides changed

Kuchie compares each side with what both agreed on after the last sync, so a change on one side simply wins. Only when both changed the same thing:

- **Reading wins**: a series removed on one side but read on the other since the last sync stays in the library.
- Read or unread: the newer change wins; if that's unclear, read wins.
- Last page: the side read more recently wins; otherwise the furthest page.
- Bookmarks: bookmarked wins. Categories: additions and removals from both sides all apply.

## When it syncs

- When you open Kuchie (at most every 5 minutes), when the network comes back, and about 10 seconds after you stop reading.
- When you pull down the Library, or tap **Sync now**.
- In the background, when iOS allows it. Opening Kuchie is the dependable way.

**Sync log** (Sync → Suwayomi server) lists the last 200 syncs.

## Downloads

One chapter, one place:

- While sync is on, **Download** saves a chapter **on the server**. Its disk is usually larger, and other apps on the server can read it too.
- **Save for offline** (in a chapter's menu) keeps a copy on the iPhone, for a flight or a trip. It takes the server's copy when there is one.
- Chapters show where they are: on the server, or on the iPhone and the server.

To read a chapter, Kuchie uses the copy on the iPhone, then the server, then the extension on the iPhone straight from the source. A chapter on the server is never locked behind it: away from home it still opens from the source, as long as there's internet.

### Move to server

**Storage → Move to server**, the chapter selection bar, or the card after connecting move chapters already saved on the iPhone to the server. By default the iPhone's copy is deleted, but only once the server reports it has every page; anything that fails keeps the iPhone's copy.

## Extensions

Installing an extension on the iPhone also installs it on the server while sync is on. The Sync page lists extensions that differ: installed only here, only on the server, or missing from the server's stores.

## Disconnect

**Sync → Suwayomi server → Disconnect**. Your library, progress and extensions stay on the iPhone; chapters on the server stay there. Kuchie offers to save them to the iPhone first.

## Troubleshooting

- **The cloud is grey, "Waiting for the server"**: the server can't be reached. That's normal away from home; changes go out when it's back. Add a backup address (for example a Tailscale one) in Sync → Suwayomi server → Advanced.
- **"Sign in again"**: the login expired or the password changed. Tap the button and sign in.
- **"Server changed"**: a different or reset server answers at the address. Kuchie stops and asks rather than mixing two libraries; disconnect and connect again.
- **A series won't sync**: check Needs attention. Installing its extension on the server, or the same store, usually fixes it.
- **Suwayomi versions**: tested with Stable v2.4.2366 and preview v2.4.2512.
