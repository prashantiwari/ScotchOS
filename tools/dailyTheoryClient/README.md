# Daily Theory

A window for a **dailyTheory** server, which serves short theories (350–500 words, in paragraphs) with linked sources, matched to interests you describe in your own words, up to a daily limit that resets at 00:00 UTC.

Open it from **rofi** (or any app launcher): type `theory` and pick **Daily Theory**. Or from a terminal: `scotchos theory` (toggles it). Esc closes it.

- **Sign up** (first run): describe your interests, or click suggestions from the server's catalog to add them, and pick how many theories per day you want (1–10). This takes 3–10 s while the server reads your interests.
- **Theory**: **Next theory** fetches a new one (4–12 s, up to ~25 s when the server has to retry). It shows the topic, title, originator, the theory, its key takeaway, sources, related ideas, further reading and the disclaimer. The sources are AI-claimed and unverified, so the disclaimer is always shown.
- **Links**: click a source or a book to search for it in your browser; the site it searches (Google Scholar for sources, Open Library for books) is shown on its right. The server builds these links from the citation, so they always open but can land on search results rather than the work itself. The last further-reading line, **Read more on Wikipedia**, opens the theory's Wikipedia article (or Wikipedia's search, when no article has that title).
- **History**: every theory you've had, newest first. Click one to read it again.
- **Save** (next to Next theory) keeps the theory on the **Saved** page; press it again (or × there) to remove it.
- **Highlights**: select text in a theory (Ctrl+C copies it) and press **Save highlight** under the selection, or Ctrl+S. Saved highlights are marked in the text and listed under the theory and on the **Saved** page, where a click opens the theory they're from. Highlights inside one paragraph are marked; one spanning paragraphs is marked per paragraph.
- **Saved**: saved theories and every highlight, newest first, and **Open folder**. They're Markdown notes in `~/Documents/DailyTheory/`, one per theory (see [Saved notes](#saved-notes)), so they still open after the theory drops out of the 50-theory history, after **Forget token**, or with the server down, and any Markdown app (Obsidian, a text editor) can read them.

### Saved notes

A theory gets a note, `~/Documents/DailyTheory/<title>.md` (e.g. `existence-precedes-essence.md`), when you save it or save a highlight in it. Removing the last highlight of a theory that isn't saved, or unsaving one with no highlights, deletes the note. The note is rewritten from the window's state on every change. A name already used by another note, or by a file of your own, gets the theory's id added (`<title>-th_….md`); files that aren't notes it wrote are never touched.

```markdown
---
id: "th_c1132fb4f1fb"
title: "Existence Precedes Essence"
originator: "Jean-Paul Sartre"
topic: "Philosophy"
subtopic: "Existentialism"
tags: ["dailytheory","philosophy","existentialism"]
saved: true                                   # false: kept only for its highlights
saved_at: "2026-10-23T08:52:15.989Z"
generated_at: "2026-10-23T07:39:44Z"
model: "gemini-3.5-flash-lite"
disclaimer: "AI-generated summary; verify sources before citing."
---

# Existence Precedes Essence

**Originator:** Jean-Paul Sartre
**Topic:** Philosophy › Existentialism

The theory, its paragraphs as they came…

> **Key takeaway:** …

## Highlights

> The highlighted text (a highlight across paragraphs keeps a `>` line between them)
>
> — saved 2026-10-23 14:22

## Sources

- [Title](<url>) — author · year · type

## Related

- An idea

## Further reading

- [Title](<url>) — author

---

*disclaimer · model · generated 2026-10-23 13:09*
```

Highlights are listed in the order they appear in the theory. You can edit a note elsewhere (the window re-reads the folder each time it opens), as long as the front matter's `id`, the `## ` headings and the list and quote shapes stay; delete a note to drop it. Don't edit while the window is open: its next save rewrites the note from what it read.
- **Interests**: change your interests or daily limit (changing interests keeps your history), see the profile the server derived from them, and **Forget token**, which is the "log out".
- The sidebar shows today's quota (`used / limit`) and when it resets, in local time. Once it's used up, Next is disabled and a countdown shows instead.
- Signup is limited by the server to 5 per hour per IP; over that, the banner says how many minutes to wait (from the `Retry-After` header).
- When something fails, a banner says what happened. **Retry** appears where trying again can help (the server or its AI provider failing, or the network), and it never retries on its own: each try can cost the server's shared free-tier LLM quota.

Switch it off with `scotchos disable dailytheory`: the window and its state are unloaded, and the launcher entry does nothing.

## Settings

In `[dailytheory]` of `~/.config/scotchos/scotchos.conf` (defaults in [`scotchos.default.conf`](../../scotchos.default.conf)), or in the settings window (**Daily theory**):

| Key | Default | What it does |
|---|---|---|
| `server` | `http://localhost:8080` | Base URL of the dailyTheory API (no trailing `/` needed). Use `https://` for anything but this machine: over plain `http://` the token and registration key aren't encrypted, and the window and log say so. |
| `registration_key` | empty | Sent as `X-Registration-Key` on signup, and only on signup. Needed only if the server sets `REGISTRATION_KEY`. |

## Files in this folder

| File | What it does |
|---|---|
| `DailyTheory.qml` | The client: API calls (`XMLHttpRequest`), error messages by code, the saved token, saved theories and highlights, and the state the window shows (quota, history, current theory). Loaded while `dailytheory` is on. |
| `notes.js` | A theory with its highlights to a Markdown note and back (pure JS; `tests/notes.test.mjs` runs it under node). |
| `tests/notes.test.mjs` | Round-trip tests for `notes.js`, run by `scotchos test`. |
| `DailyTheoryWindow.qml` | The floating window: sidebar with the pages and quota; Sign up, Theory, History, Saved and Interests pages. Created only while open. |
| `daily-theory.sh` | What the launcher entry runs: exits if `dailytheory` is off, else `scotchos theory open`. |
| `scotchos-dailytheory.desktop` | The app launcher entry; `install.sh` copies it to `~/.local/share/applications/` with the real path in `Exec`. |
| `API.md` | The server's HTTP API v1 contract (copied from the dailyTheory repo, `docs/API.md`). |
| `CLIENT_GUIDE.md` | The server's guide for client developers (copied from `docs/CLIENT_GUIDE.md`). |
| `README.md` | This file. |

It also uses `Stepper.qml` from [`settings/`](../../settings/README.md) for the daily limit, and adds `Field.qml` there (a text setting) for the two settings above.

## Requirements

| Requirement | Package (Arch/CachyOS) | Tested version | Used for |
|---|---|---|---|
| Quickshell | `quickshell` | 0.3.2 | The window, `qs ipc` to open it, HTTP with QML's built-in `XMLHttpRequest` (no curl) |
| Qt 6 | `qt6-base` | 6.12.0 | `XMLHttpRequest.timeout` |
| Hyprland | `hyprland` | 0.56.2 | Floats the window because it has a fixed size (min = max), no window rule needed |
| xdg-utils | `xdg-utils` | 1.2.1 | Opening source and reading links in the default browser (`Qt.openUrlExternally` runs `xdg-open`) |
| coreutils, sh | `coreutils` | 9.12 | Writing the token file (`umask 077`, `mkdir`, `cat`, `mv`) and deleting it (`rm`) |
| JetBrainsMono Nerd Font | `ttf-jetbrains-mono-nerd`, or HyDE's bundled copy | — | Font and icons |
| A dailyTheory server | — | API v1 (real server from the dailyTheory repo, 2026-10-20) | Everything shown |
| Node.js (only for `scotchos test`) | `nodejs` | 26.11.1 | `tests/notes.test.mjs` |
| Go (only to run the server or the mock) | `go` | 1.27.1 | `go run ./cmd/server`, `go run ./cmd/mockserver` |

## Changes made to the system

- `~/.local/share/applications/scotchos-dailytheory.desktop`: a copy of `scotchos-dailytheory.desktop` with `@DIR@` replaced by this folder's full path (rofi may not have `~/.local/bin` in its PATH). Re-run `install.sh` (or the `sed` line in it) if you move the repo.
- `~/Documents/DailyTheory/`: created on the first save, with one Markdown note per saved or highlighted theory. Deleting the folder clears them.
- `~/.local/state/scotchos/dailytheory-token` (or under `$XDG_STATE_HOME`): the bearer token, mode `0600`, written when you sign up and deleted by **Forget token** or when the server rejects it. The server returns it only once and can't recover it: if the file is lost, you have to sign up again (as a new user, with a new history).

No keybind and no change to `hyprland.lua`. To add one later:

```lua
hl.bind("SUPER + ALT + T", hl.dsp.exec_cmd(os.getenv("HOME") .. "/Projects/ScotchOS/tools/dailyTheoryClient/daily-theory.sh toggle"))
```

## Running it by hand

```bash
scotchos theory                                    # toggle the window
scotchos theory open                               # or: tools/dailyTheoryClient/daily-theory.sh
qs ipc -p ~/Projects/ScotchOS call dailytheory close
```

The server (needs a Gemini key in its `.env`, see the dailyTheory README), from the dailyTheory repo:

```bash
cd ~/Projects/dailyTheory
go run ./cmd/server                                # :8080
```

For offline UI work there is also a mock (in-memory, so restarting it forgets every user and the client goes back to signup; stop it before starting the server, both use :8080):

```bash
cd ~/Projects/dailyTheory
go run ./cmd/mockserver                            # :8080, 3 s simulated LLM latency
go run ./cmd/mockserver -latency 1s -fail-rate 0.3 # 30 % of LLM calls fail with 503: shows the Retry banner
go run ./cmd/mockserver -registration-key secret   # signup needs registration_key = secret
```

QML changes hot-reload on save, which closes the window. Logs: `scotchos log 2>&1 | grep -E 'WARN|ERROR'`

## Adapting

| What | Where | Current value |
|---|---|---|
| Server URL, registration key | `[dailytheory]` in `scotchos.conf` | `http://localhost:8080`, none |
| Token location | `tokenPath` in `DailyTheory.qml` | `~/.local/state/scotchos/dailytheory-token` |
| Notes folder | `notesDir` in `DailyTheory.qml` | `$XDG_DOCUMENTS_DIR/DailyTheory`, else `~/Documents/DailyTheory` |
| Note layout | `toMarkdown()` / `fromMarkdown()` in `notes.js` (change both, then `scotchos test`) | as in [Saved notes](#saved-notes) |
| Highlight colour | `markColor` in `DailyTheoryWindow.qml` | the wallbash accent at 35 % over the background |
| Timeouts | `call()` in `DailyTheory.qml` | 85 s for signup, interest changes and Next (the server gives up at 75 s with `upstream_unavailable`); 10 s for the rest |
| Which links open | `openLink()` in `DailyTheory.qml` | `http://` and `https://` only |
| Site names next to links | `site()` in `DailyTheoryWindow.qml` | Google Scholar, Open Library, Wikipedia; any other site shows its host |
| History length | `refresh()` in `DailyTheory.qml` (`/v1/theories?limit=`) | 50 (the API allows 1–100) |
| Error wording | `fail()` in `DailyTheory.qml` | One line per API error code (`rate_limited` adds the wait from `Retry-After`) |
| Window size | `implicitWidth` / `implicitHeight` in `DailyTheoryWindow.qml` | 860 × 580 (fits the laptop's 1280 × 720) |
| Launcher name, icon | `scotchos-dailytheory.desktop`, then re-run `install.sh` | Daily Theory, `accessories-dictionary` |

## How it works

1. **Loading:** `shell.qml` loads `DailyTheory` while `dailytheory` is on. When idle it holds a few properties, a `FileView` with the token and an `IpcHandler`. It has no timers, and no processes run until a token is saved or deleted. The window is a `LazyLoader` inside it, created by `qs ipc call dailytheory open` and destroyed when closed. The state lives outside the window, so closing it during a signup doesn't lose the token, and the theory you were reading is still there when you reopen it.
2. **Opening:** the window calls `refresh()`. Signed in, that's `GET /v1/me` (profile and quota) and `GET /v1/theories?limit=50` (history; the newest becomes the current theory, or the one you were reading is replaced by the server's fresh copy, which picks up fields added since, such as links). Signed out, it's `GET /v1/topics` for the suggestion chips.
3. **Requests:** `call()` sends JSON with `XMLHttpRequest` in the shell process, so nothing is spawned. It sends only the documented fields, because the server rejects unknown ones. `Authorization: Bearer` goes on every call except signup, and `X-Registration-Key` only on signup. `PUT /v1/me` sends only the fields that changed. Next and the Interests page's Save are disabled while a request is in flight, so a double click can't send two.
4. **Errors:** every non-2xx answer is `{"error": {"code", "message"}}`, and `fail()` picks the message by `code` (never by HTTP status). `not_found`, `method_not_allowed` and `payload_too_large` mean the client sent something wrong, so they also go to the log as a warning. `unauthorized` deletes the token and returns to signup. `quota_exceeded` marks the quota as used up until `resets_at`. A failed Next says it didn't use up quota, because the server doesn't count it.
5. **Quota:** it's updated from every Next response and from `/v1/me`. While it's used up, a 30 s timer refreshes the countdown, and after `resets_at` it calls `refresh()`; if the server still reports it used up, each further try waits twice as long (up to 8 min). The timer runs only while the window is open and the quota is used up.
6. **Text and links:** server text is shown as plain text, so a `<` in it can't turn into rich text; the theory's blank lines (`\n\n`) are its paragraph breaks. The theory itself is a read-only `TextEdit` so it can be selected; it's rich text built by `marked()`, which escapes `& < >` first and only then adds the paragraphs and the `<span>` behind each saved highlight (found by exact text, first match). A source or reading line is clickable when it has a `url`; `openLink()` passes it to `Qt.openUrlExternally` only if it starts with `http://` or `https://`.
7. **Token:** a `Process` runs `sh -c 'umask 077 && mkdir -p … && cat > tmp && mv tmp token'` and writes the token to its **stdin**, so it never appears in a command line that `ps` could show. The file is created `0600` and replaced atomically.
8. **Saved:** when the shell starts and each time the window opens, one `sh` prints every `*.md` in the notes folder, each after a `\036` line with its name, and `notes.js` parses them (`fromMarkdown()`; files without front matter holding an `id` are left alone). Each change rewrites that theory's note with `toMarkdown()` through a `Process` that writes stdin to a temp file and renames it (or `rm` when it's no longer kept), one write at a time; a read asked for meanwhile waits for the writes. Nothing runs between changes.

## Uninstall

To only switch it off, `scotchos disable dailytheory` is enough. To remove it:

1. Delete `~/.local/share/applications/scotchos-dailytheory.desktop`, `~/.local/state/scotchos/dailytheory-token` (and `~/Documents/DailyTheory/` if you don't want the notes).
2. Remove `import "tools/dailyTheoryClient"` and the `LazyLoader` holding `DailyTheory` from `shell.qml`, the `theory)` line from `bin/scotchos`, the Daily Theory lines from `install.sh`, the `dailytheory` item from `items` in `settings/SettingsWindow.qml`, and `dailytheory` plus `[dailytheory]` from `scotchos.default.conf` and `~/.config/scotchos/scotchos.conf`. Also remove its row from the root README.
3. Delete this folder. `settings/Field.qml` can stay: the settings window uses it for any `text` setting.
