# ScotchOS review (2026-10-20)

A full read of the repo: `shell.qml`, `common/`, `settings/`, the four widgets, the three tools, `bin/`, `install.sh`, the READMEs and `CLAUDE.md`. Also run: `scotchos doctor` (everything wired in), `scotchos status` (running, **279 MB**) and `scotchos log` (only Qt text-input warnings, nothing from ScotchOS).

Overall the code is in good shape. The architecture holds up: one process, `LazyLoader` per widget, `DesktopWidget`/`DesktopPanel` bases, atomic conf writes, processes bound to visibility. Comments explain *why*, and the resource rules are followed almost everywhere. No crash-level bugs turned up. Most of what follows is small bugs, docs that have drifted, and robustness or portability gaps.

Each item has a tag: **[bug]** wrong behaviour, **[perf]** wasted work, **[robust]** fails badly in an edge case, **[docs]** docs that have drifted, **[port]** only works on this machine, **[idea]** a feature suggestion. "Verified" means I traced the code path; "likely" means I'm fairly sure but didn't reproduce it.

---

## Plan

Work through one phase per session. Start a fresh session with "do phase N of REVIEW.md", tick items off here as they're done, and commit each phase (or each fix) after `scotchos doctor`, `scotchos restart` and a clean `scotchos log`. The sections below the plan explain each item.

### Phase 1: quick wins (done 2026-10-21)
- [x] Commit the pending e-reader full-width margin change
- [x] Docs that drifted (section 2): Super+Y, `yt-open.sh`, `cava.conf`, README memory figure, conf comment alignment
- [x] 1.1 E-reader library only exists while shown (no rebuild on page turns)
- [x] 1.2 `scotchos restart` waits for the old shell to exit
- [x] 1.3 Claude usage retries right away when Claude Code saves a new token
- [x] 1.4 Dashboard collector: restart backoff, and no restart when it was stopped on purpose
- [x] 1.5 `scotchos enable/disable/toggle` reject names that aren't `[a-z][a-z0-9_]*`

### Phase 2: e-reader data (done 2026-10-21)
- [x] Prune the cache: converted books and covers whose id is gone from the library
- [x] Keep position and bookmarks when a book is moved or renamed
- [x] Guard `os.walk(followlinks=True)` against symlink cycles
- [x] Markdown images limited to the book's folder; `startswith(tmp + os.sep)` in `mobi_build`
- [x] Rescan when `library_dir` changes while the window is open
- [x] Re-layout on resize only rewrites image sizes when the chapter has images; debounce resizes

### Phase 3: small widget and tool fixes (done 2026-10-21)
- [x] Quote timer bound to `w.anyEmpty`
- [x] Dashboard: clear the histories when the collector starts again
- [x] Claude usage: show one limit when the other is missing
- [x] `setConf`: don't write when the file on disk differs from `confText` (lost hand edits)
- [x] Decide on `#` in values: only `#` at the start of a line or after a space is a comment
- [x] `yt-open.sh`: browser, window class and workspace from `[launcher]`; escape `prev_ws`
- [x] Launcher and reader windows: pick the screen once when they open
- [x] dailyTheory: warn about `http://` to a non-local server; limit the refresh after the quota reset; update `now` when the quota runs out

### Phase 4: structure (done 2026-10-21)
- [x] Live conf at `${XDG_CONFIG_HOME:-~/.config}/scotchos/scotchos.conf`. The repo keeps the defaults as `scotchos.default.conf` (reset to the settings window's `def:` values; today's tracked file holds personal values such as font 24 / two pages). `scotchos start` and `install.sh` copy the default when the live file is missing; move this machine's current conf there once (record it under "Changes made to the system"). `bin/scotchos start` passes the resolved path to the shell as `SCOTCHOS_CONF`, and `shell.qml` reads and writes that path, so a symlinked conf (dotfiles) is written through instead of being replaced by the atomic write. `doctor` checks the default file; docs, skills and `CLAUDE.md` name the new path
- [x] `doctor`: include `tools/` in the duplicate-name check, run shellcheck and `py_compile`, compare settings `def:` with the widgets' fallbacks
- [x] Portability (section 4): CPU sensor list, skip NVML while the GPU is suspended (not testable here: Runtime D3 is off), `install.sh` dependencies and the workspace rule. AMD/Intel GPUs are still not shown
- [x] `common/http.js` (a JS library rather than a QML type: it's stateless) shared by the quote, Claude usage and dailyTheory (5.4)

### Phase 5: tests
- [ ] `tools/eReader/tests/` with small EPUB 2/3, FB2, TXT and Markdown fixtures (5.3)
- [ ] `parseConf` / `setConf` before/after cases

### Phase 6: features (section 6), one session each, picked as wanted

---

## 1. Fix soon

### 1.1 [perf] The e-reader library is rebuilt on every page turn (verified)
`tools/eReader/ReaderLibrary.qml:10-18`: `shown` depends on `reader.progress`, and `Reader.report()` (`Reader.qml:286-295`) calls `progressChanged()` on every page turn and scroll. So each page turn:
- re-filters and re-sorts the whole book list,
- gives the `GridView` a new model array, which destroys and recreates every cover delegate (the library is only `visible: false` while reading, not unloaded),
- resets `grid.currentIndex` to 0 (`onShownChanged`).

**Fix:** sort by a separate `property var opened: ({})` (id → timestamp) that only `touch()` changes. Or wrap the library in a `Loader { active: reader.view === "library" }`. Either one also stops `cell.saved` bindings from re-running on every page turn.

### 1.2 [bug] `scotchos restart` can leave nothing running (likely)
`bin/scotchos:60`: `qs kill …; sleep 0.5; qs -n -d -p "$root"`. `-n` refuses to start while another instance is up. If the old process takes longer than 0.5 s to exit (a big e-reader chapter or a slow NVML call can do it), the new one exits and nothing is left running. **Fix:** wait for the old process to go away:
```bash
restart) qs kill -p "$root" >/dev/null 2>&1
         for _ in {1..50}; do pgrep -f "qs -n -d -p $root\$" >/dev/null || break; sleep 0.1; done
         qs -n -d -p "$root" ;;
```

### 1.3 [robust] The Claude usage card stays on "token expired" for up to 10 minutes after re-login (verified)
`widgets/claudeUsage/ClaudeUsageWidget.qml:108-120`: when `~/.claude/.credentials.json` changes (Claude Code refreshed the token), only `creds` is updated. If the last fetch failed with "token expired" or "not logged in", `tick()` waits out `retryMs` (10 min) before trying again. **Fix:** in `onLoaded`, after start-up, call `w.refresh()` when `w.error` is set. `refresh()` already applies the 30 s cooldown.

### 1.4 [robust] The dashboard collector restarts forever with no backoff (verified)
`widgets/systemDashboard/DashboardWidget.qml:64-66`: if `stats.py` dies at start (python3 missing, a syntax error after an edit), it is restarted every 2 s forever, and each crash goes to the log. Also, `onExited` fires when the panel hides normally (`running` goes false), which needlessly drops `collectorAlive` for 2 s, so the dashboard comes back up to 2 s late when you return to an empty workspace. **Fix:** only restart when `running` was still wanted, and double the delay after each quick failure (2 s, 4 s, 8 s … capped at about a minute). Reset the delay after a run that lasted more than a minute.

### 1.5 [robust] `scotchos enable/disable/toggle` treat the name as a regex (verified)
`bin/scotchos:42-55, 80-82`: the name goes straight into `grep -E` and awk `~`. `scotchos enable 'dash.*'` switches `dashboard` on and prints `dash.*: on`. **Fix:** at the top of `set_enabled`, add `[[ $1 =~ ^[a-z][a-z0-9_]*$ ]] || { echo "scotchos: bad name '$1'" >&2; exit 1; }`.

---

## 2. Docs that have drifted

| Where | What it says | What's true |
|---|---|---|
| `scotchos.conf:10` | "**Super+Space** launcher" | The bind is `SUPER + Y` (`hyprland.lua:62`, README, launcher README) |
| `tools/eReader/PRD.md:32` | "App launcher (Super+Space, or rofi)" | Same |
| `CLAUDE.md:36` | "Don't run `yt-search.sh`" | The script is `tools/launcher/yt-open.sh` (it opens Brave and moves focus to workspace 1) |
| `widgets/nowPlaying/cava.conf:1,5` | "`shell.qml` reads the raw output", "Must match `barCount` in shell.qml" | It's `NowPlayingWidget.qml` |
| `README.md:98` | "One Quickshell process for all **three** widgets uses about **205 MB**" | There are four widgets plus three tools, and `scotchos status` shows 279 MB today. Re-measure and update. |
| `scotchos.conf:11` | `dailytheory = yes     #` | Comment column out of line with the other rows (cosmetic) |

Also uncommitted: the e-reader "full width keeps a 56 px margin" change (`ReaderBook.qml`, README) is ready to commit. The `scotchos.conf` diff is just your own settings (font 24, two pages); see 5.1.

---

## 3. Smaller bugs and rough edges

### Core / settings
- **[robust] `setConf` can overwrite hand edits with stale text.** `shell.qml:82-110` builds the new file from `confText`, the last *valid* read. Suppose the conf on disk has no `[enabled]` (an editor's half-save, or an edit in progress). A click in the settings window then writes the old text plus the change, and your edit is lost. It's rare, but a cheap fix is to skip the write (and warn) when `confFile.text()` differs from `confText`.
- **[robust] `#` can't appear in any value.** `parseConf` (`shell.qml:59`) and `bin/scotchos get` strip from the first `#`. `Field.qml` blocks typing it, but a URL with a fragment or a hand-written key containing `#` gets cut. Either document it in the conf header, or treat only ` #` (whitespace before it) as a comment.
- **[robust] Symlinked conf.** `bin/scotchos:4` carefully resolves a symlinked conf, but `FileView { atomicWrites: true }` in `shell.qml` writes to `shellDir + "/scotchos.conf"`. Depending on how Quickshell does atomic writes, that may replace the symlink with a plain file. This only matters if you adopt 5.1. Check it first, or point the FileView at the resolved path. **Checked (Phase 4):** Quickshell 0.3.2 writes through the symlink (QSaveFile follows it), and the shell now gets the resolved path anyway.

### Widgets
- **[perf] The quote timer runs while hidden.** `QuoteWidget.qml:81-86` has `running: true`. Every other widget follows the rule "bind `Timer.running` to `w.anyEmpty`". It's once a minute, so cheap, but it also fetches a quote when nobody can see it. Use `running: w.anyEmpty` with `triggeredOnStart: true`, like `ClaudeUsageWidget`.
- **[bug] Dashboard graphs join across gaps.** When the dashboard hides and `stats.py` stops, `cpuHistory`/`tempHistory`/`rxHistory` keep their old samples. When it shows again, new samples are appended right after them, so the "60 s" graph mixes data from minutes apart. Clear the histories in the collector's `onStarted` (or store a timestamp per sample).
- **[robust] Claude usage needs both limits.** `limit()` throws when `five_hour` or `seven_day` is missing or null, which drops the whole reading. If a plan ever returns only one, show the one you have (`null` → row hidden; the cards already handle `l === null`).
- Tiny: `ClaudeUsageCard.qml:18` computes `m` before the `if (!t)` check. Harmless, but reads oddly.

### Launcher
- **[robust] `yt-open.sh` hard-codes Brave, class `brave-browser` and workspace 1** (`yt-open.sh:19,29,30`). Put them in `[launcher]` in the conf (`browser`, `browser_class`, `workspace`) so the tool works on another machine. `install.sh` already treats Brave as optional.
- **[robust] `prev_ws` goes into a Lua string unescaped** (`yt-open.sh:37`). A workspace name containing `"` breaks the dispatch. Escape `"` and `\` first.
- **[robust] The window follows monitor focus while open** (`LauncherWindow.qml:15`, also `ReaderWindow.qml:9`, `ReaderFullscreen.qml:7`). `screen:` is a live binding to `Hyprland.focusedMonitor`, so a focus change while it's open (moving the mouse to the other screen with focus-follows-mouse) can move or resize the window. Capture the screen once in `Component.onCompleted` (likely, not reproduced).

### dailyTheory
- **[robust] Over HTTP, the token goes in plain text.** `server` defaults to `http://localhost:8080`, which is fine locally. Pointed at a remote `http://` server, the bearer token and registration key cross the network unencrypted. A one-line warning in the window or log when the host isn't `localhost`/`127.0.0.1` and the scheme is `http` would help.
- **[robust] Refresh loop after midnight.** `DailyTheoryWindow.qml:25-33`: once `now >= resets_at`, it calls `refresh()` every 30 s until the server reports a fresh quota. If the server's clock or reset runs late, that's two requests every 30 s. Give up after a few tries, or step the timer up.
- `DailyTheoryWindow.qml:24`: `now` only moves while out of quota, so right after the quota runs out "resets in …" can show a time up to the window's age too long. Set `win.now = Date.now()` when `outOfQuota` turns true.

### E-reader
- **[robust] The cache is never pruned.** `~/.cache/scotchos/reader` already holds 29 MB for 4 books. Converted books of deleted or moved files stay forever, and so do their covers: `scan()` (`book.py:992-998`) only replaces covers of re-stamped entries, while `library.json` drops them. In `scan()`, delete `covers/<id>*` and `<id>/` dirs whose id isn't in `fresh` and wasn't opened in, say, 90 days.
- **[bug] Moving or renaming a book loses its position and bookmarks.** `book_id()` (`book.py:37`) hashes the real path, and `reader-progress.json` is keyed by it. Fallback: when an unknown id has the same `(size, title)` as a progress entry whose `path` no longer exists, move that entry to the new id (in `scan`, or on open).
- **[robust] `os.walk(followlinks=True)`** (`book.py:973`) loops if `~/Books` contains a symlink cycle. Track `(st_dev, st_ino)` of visited dirs.
- **[robust] Markdown images can copy any readable file into the cache.** `md_build`'s `img()` (`book.py:909-917`) accepts absolute and `../` paths, and `Builder.image` writes whatever bytes it gets. `![](../../.ssh/id_rsa)` would copy that file into the cache. It's your own machine, so the risk is low, but restrict it to the book's folder like `mobi_build` does. While there, use `p.startswith(tmp + os.sep)` in `mobi_build` (`book.py:617`), not a bare prefix.
- **[perf] Re-layout on resize.** `ReaderBook.qml:45-53`: `html` depends on `te.width` and `flick.height` through `fitImages()`, even for chapters with no images. Every width or height change re-parses the whole chapter's rich text (up to 100 KB) and paginates again. Two-page mode does it twice (a second `TextEdit`). Only rewrite image sizes when the chapter has `<img`, and debounce resizes.
- `Reader.qml:99-100`: the scan command binds `libraryDir`, but changing `library_dir` while the window is open doesn't rescan until it's reopened. Add `onLibraryDirChanged: if (open) scan()`.

---

## 4. Portability: works here, not on another machine

These are fine for this laptop, but `install.sh` and the README present ScotchOS as installable elsewhere:

- **CPU temperature only reads `coretemp`** (`stats.py:11`). AMD machines use `k10temp` (`Tctl`), some ARM boards `cpu_thermal`. Try a list in order.
- **NVML is polled every 2 s** (`stats.py:119-134`). The comment rightly says runtime D3 is off here. On a normal Optimus laptop this keeps the dGPU awake and costs battery. Before querying, check `/sys/bus/pci/devices/<gpu>/power/runtime_status` and skip (show "asleep") when it's `suspended`.
- **The dashboard only shows GPU 0**, and only NVIDIA. AMD and Intel could come from `/sys/class/drm/card*/device/gpu_busy_percent` and hwmon.
- **`install.sh`** doesn't mention `python3` for the e-reader (only "system dashboard"), or `hyprctl` and `jq` for the reader and launcher scripts. It also prints only the Lua lines plus an old-style `hyprland.conf` variant, not the `hl.workspace_rule` the launcher README says is needed.

---

## 5. Structure and tooling suggestions

### 5.1 Keep your personal settings out of git
**Decision (2026-10-21):** the second option, `~/.config/scotchos/scotchos.conf`, with the repo's copy renamed to `scotchos.default.conf`. It survives a re-clone or a moved repo, fits XDG, and leaves `git status` clean; the details are in the Phase 4 item above.

`scotchos.conf` is tracked, and the settings window rewrites it all the time, so `git status` almost always shows it changed (as it does now). Options:
- Track `scotchos.conf.default` and gitignore `scotchos.conf`; `install.sh` copies the default when the conf is missing. `scotchos doctor` would then check the default file.
- Or move the live conf to `~/.config/scotchos/scotchos.conf`. It survives a re-clone and fits XDG. `bin/scotchos` and `shell.qml` each need one path change (`bin/scotchos` already supports a symlink).

### 5.2 Gaps in `scotchos doctor`
- The duplicate-file-name check (`bin/scotchos-doctor:102`) only looks in `widgets/` and `settings/`. `shell.qml` imports the `tools/*` folders too, so a future `tools/x/Graph.qml` would clash with the dashboard's `Graph.qml` without a warning. Add `tools` to the `find`.
- Run `shellcheck` (if installed) on `bin/*`, `install.sh` and `tools/*/*.sh`, and `python3 -m py_compile` on the `.py` helpers. Neither linter is installed right now (`pacman -S shellcheck python-pyflakes`).
- Check that the defaults in `settings/SettingsWindow.qml` (`def:`) match each widget's `str/num/flag` fallbacks. They match today, but nothing keeps them in sync.

### 5.3 Tests where they're cheap
`book.py` is the most complex code in the repo (1,100 lines of format parsing) and the one most likely to regress. A `tools/eReader/tests/` folder would catch converter regressions before a `VERSION` bump rebuilds every cached book. It would need tiny fixtures (a 2-chapter EPUB 3 with a nav, an EPUB 2 with an NCX, an FB2 with notes, a Gutenberg-style TXT, a Markdown file) and a `python3 -m unittest` that checks chapter count, TOC entries, anchors, links and `search()` hits. `parseConf`/`setConf` could get the same treatment: copy the two functions into a small `node` test, or keep a table of before/after conf snippets.

### 5.4 One HTTP helper
`QuoteWidget`, `ClaudeUsageWidget` and `DailyTheory` each write the same XHR boilerplate (timeout, `readyState`, status check, JSON parse). A `common/Http.qml` with `get(url, headers, timeout, done)` / `send(method, …)` would remove about 40 lines and make error handling consistent.

---

## 6. Feature ideas

Roughly in order of usefulness against effort:

1. **Launcher: remember what you pick.** Store a launch count per app in `Quickshell.cacheDir` and add it to the score in `AppsProvider`, so frequent apps rise. Also match on `e.execString`, and allow simple fuzzy matching (initials: "vsc" → Visual Studio Code).
2. **Launcher: more providers.** The `Provider` design makes these easy: a calculator (`=2*pi`), a web search fallback, open e-reader books (`book dune`), clipboard history (`cliphist`).
3. **Now playing: controls.** The card is click-through by design. A launcher provider ("Pause", "Next track") or `scotchos media next` over IPC would give control without changing that.
4. **E-reader: highlights and notes**, stored next to bookmarks. **Export** bookmarks to Markdown. A **"continue reading"** command in the launcher that opens the last book where you left off.
5. **Dashboard: disk and battery.** Root filesystem use from `os.statvfs("/")`, battery and power draw from `/sys/class/power_supply/BAT*`. Both are cheap reads that fit `stats.py`.
6. **Claude usage: notify** (`notify-send`) once when a limit crosses `warn`, since the card is only visible on an empty workspace.
7. **Settings window: a "Reset to default" button** per setting (removes the key, so the widget's fallback applies), and an "Open scotchos.conf" button.
8. **`scotchos doctor --fix`** for the mechanical parts (missing `[enabled]` line or conf section), since it already knows exactly what's missing.

