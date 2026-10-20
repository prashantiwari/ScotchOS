# Daily Theory

A window for a **dailyTheory** server, which serves short theories (≤ 500 words) with their sources, matched to interests you describe in your own words, up to a daily limit that resets at 00:00 UTC.

Open it from **rofi** (or any app launcher): type `theory` and pick **Daily Theory**. Or from a terminal: `scotchos theory` (toggles it). Esc closes it.

- **Sign up** (first run): describe your interests, or click suggestions from the server's catalog to add them, and pick how many theories per day you want (1–10). This takes 3–10 s while the server reads your interests.
- **Theory**: **Next theory** fetches a new one (3–10 s). It shows the topic, title, originator, the theory, its key takeaway, sources, related ideas, further reading and the disclaimer. The sources are AI-claimed and unverified, so the disclaimer is always shown.
- **History**: every theory you've had, newest first. Click one to read it again.
- **Interests**: change your interests or daily limit (changing interests keeps your history), see the profile the server derived from them, and **Forget token**, which is the "log out".
- The sidebar shows today's quota (`used / limit`) and when it resets, in local time. Once it's used up, Next is disabled and a countdown shows instead.
- Signup is limited by the server to 5 per hour per IP; over that, the banner says how many minutes to wait (from the `Retry-After` header).
- When something fails, a banner says what happened. **Retry** appears where trying again can help (the server or its AI provider failing, or the network), and it never retries on its own: each try can cost the server's shared free-tier LLM quota.

Switch it off with `scotchos disable dailytheory`: the window and its state are unloaded, and the launcher entry does nothing.

## Settings

In `[dailytheory]` of [`scotchos.conf`](../../scotchos.conf), or in the settings window (**Daily theory**):

| Key | Default | What it does |
|---|---|---|
| `server` | `http://localhost:8080` | Base URL of the dailyTheory API (no trailing `/` needed). |
| `registration_key` | empty | Sent as `X-Registration-Key` on signup, and only on signup. Needed only if the server sets `REGISTRATION_KEY`. |

## Files in this folder

| File | What it does |
|---|---|
| `DailyTheory.qml` | The client: API calls (`XMLHttpRequest`), error messages by code, the saved token, and the state the window shows (quota, history, current theory). Loaded while `dailytheory` is on. |
| `DailyTheoryWindow.qml` | The floating window: sidebar with the pages and quota; Sign up, Theory, History and Interests pages. Created only while open. |
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
| coreutils, sh | `coreutils` | 9.12 | Writing the token file (`umask 077`, `mkdir`, `cat`, `mv`) and deleting it (`rm`) |
| JetBrainsMono Nerd Font | `ttf-jetbrains-mono-nerd`, or HyDE's bundled copy | — | Font and icons |
| A dailyTheory server | — | API v1 (real server from the dailyTheory repo, 2026-10-20) | Everything shown |
| Go (only to run the server or the mock) | `go` | 1.27.1 | `go run ./cmd/server`, `go run ./cmd/mockserver` |

## Changes made to the system

- `~/.local/share/applications/scotchos-dailytheory.desktop`: a copy of `scotchos-dailytheory.desktop` with `@DIR@` replaced by this folder's full path (rofi may not have `~/.local/bin` in its PATH). Re-run `install.sh` (or the `sed` line in it) if you move the repo.
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
| Timeouts | `call()` in `DailyTheory.qml` | 65 s for signup, interest changes and Next (the server's own LLM timeout is 60 s); 10 s for the rest |
| History length | `refresh()` in `DailyTheory.qml` (`/v1/theories?limit=`) | 50 (the API allows 1–100) |
| Error wording | `fail()` in `DailyTheory.qml` | One line per API error code (`rate_limited` adds the wait from `Retry-After`) |
| Window size | `implicitWidth` / `implicitHeight` in `DailyTheoryWindow.qml` | 860 × 580 (fits the laptop's 1280 × 720) |
| Launcher name, icon | `scotchos-dailytheory.desktop`, then re-run `install.sh` | Daily Theory, `accessories-dictionary` |

## How it works

1. **Loading:** `shell.qml` loads `DailyTheory` while `dailytheory` is on. When idle it holds a few properties, a `FileView` with the token and an `IpcHandler`. It has no timers, and no processes run until a token is saved or deleted. The window is a `LazyLoader` inside it, created by `qs ipc call dailytheory open` and destroyed when closed. The state lives outside the window, so closing it during a signup doesn't lose the token, and the theory you were reading is still there when you reopen it.
2. **Opening:** the window calls `refresh()`. Signed in, that's `GET /v1/me` (profile and quota) and `GET /v1/theories?limit=50` (history; the newest becomes the current theory). Signed out, it's `GET /v1/topics` for the suggestion chips.
3. **Requests:** `call()` sends JSON with `XMLHttpRequest` in the shell process, so nothing is spawned. It sends only the documented fields, because the server rejects unknown ones. `Authorization: Bearer` goes on every call except signup, and `X-Registration-Key` only on signup. `PUT /v1/me` sends only the fields that changed. Next and Save are disabled while a request is in flight, so a double click can't send two.
4. **Errors:** every non-2xx answer is `{"error": {"code", "message"}}`, and `fail()` picks the message by `code` (never by HTTP status). `unauthorized` deletes the token and returns to signup. `quota_exceeded` marks the quota as used up until `resets_at`. A failed Next says it didn't use up quota, because the server doesn't count it.
5. **Quota:** it's updated from every Next response and from `/v1/me`. While it's used up, a 30 s timer refreshes the countdown, and after `resets_at` it calls `refresh()` once. The timer runs only while the window is open and the quota is used up.
6. **Token:** a `Process` runs `sh -c 'umask 077 && mkdir -p … && cat > tmp && mv tmp token'` and writes the token to its **stdin**, so it never appears in a command line that `ps` could show. The file is created `0600` and replaced atomically.

## Uninstall

To only switch it off, `scotchos disable dailytheory` is enough. To remove it:

1. Delete `~/.local/share/applications/scotchos-dailytheory.desktop` and `~/.local/state/scotchos/dailytheory-token`.
2. Remove `import "tools/dailyTheoryClient"` and the `LazyLoader` holding `DailyTheory` from `shell.qml`, the `theory)` line from `bin/scotchos`, the Daily Theory lines from `install.sh`, the `dailytheory` item from `items` in `settings/SettingsWindow.qml`, and `dailytheory` plus `[dailytheory]` from `scotchos.conf`. Also remove its row from the root README.
3. Delete this folder. `settings/Field.qml` can stay: the settings window uses it for any `text` setting.
