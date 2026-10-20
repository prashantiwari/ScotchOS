# ScotchOS feature phases

The features picked from `REVIEW.md` section 6 (launcher providers and now-playing controls were dropped), plus three small leftovers from the review. One phase per chat: start it with `/start-phase N`.

## Rules for every phase

- **Gate:** phase N starts only when phase N-1's status is `approved`. Claude sets `done`; only the user sets `approved` (by saying so, or by answering yes when `/start-phase N+1` asks).
- **Statuses:** `todo` → `in progress` → `done` (awaiting the user's approval) → `approved YYYY-MM-DD`.
- **Context:** read `CLAUDE.md` (already loaded), this file's "Rules" and your own phase only, then the files the phase lists under "Read first". Open other files only when a task needs them. No subagents unless the user asks.
- **Finish:** tick the tasks, run the phase's checks plus `scotchos doctor`, `scotchos test`, `scotchos restart` and a clean `scotchos log 2>&1 | grep -E 'WARN|ERROR'`. Update the touched READMEs, `scotchos.default.conf`, the settings window and the live conf for any new setting (CLAUDE.md's conventions). Write the "Handoff" lines (what the next phase should know, ≤ 5 lines), set the status to `done`, commit, and tell the user what to try before approving.
- **Resource rules** from CLAUDE.md apply to everything. For anything that runs while the desktop is shown, write down `scotchos status` and `top -p <pid>` before and after.
- Anything outside the repo (Hyprland config, `~/.local/share/…`): ask first, as CLAUDE.md says.

| Phase | What | Size | Model | Effort |
|---|---|---|---|---|
| 1 | Launcher: remembers picks, matches commands and initials | S | Sonnet 5.5 | medium |
| 2 | Dashboard: disk and battery | M | Sonnet 5.5 | medium |
| 3 | Claude usage notification; settings window reset and open buttons | M | Sonnet 5.5 | medium |
| 4 | E-reader: continue reading, bookmark export, converter leftovers | M | Opus 5.5 | medium |
| 5 | E-reader: highlights and notes | L | Opus 5.5 | high |
| 6 | `scotchos doctor --fix`; `enable`/`disable` keep the comment column | S | Sonnet 5.5 | medium |

**Model and effort:** pick them with `/model` before typing `/start-phase N`. Sonnet is enough where the work is clear and the code is small; Opus is for `book.py`'s HTML handling (4) and the highlight design in Qt rich text (5), where a wrong choice costs a redo. Haiku isn't recommended: every phase touches several files that must stay in step (conf, settings window, README, doctor). Low effort tends to skip the docs and checks at the end of a phase, so none of the phases use it. If a phase stalls on a hard bug, switch up a step (Sonnet → Opus, or medium → high) in the same chat rather than starting over.

---

## Phase 1: Launcher remembers what you pick

**Status:** approved 2026-10-21

**Model:** Sonnet 5.5, medium effort (small, clear task; the scoring is plain JS with tests).

**Goal:** apps you launch often rise in the list; typing part of the command (`code`) or the initials (`vsc` → Visual Studio Code) finds an app.

**Read first:** `tools/launcher/AppsProvider.qml` (32 lines), `tools/launcher/Provider.qml`, `tools/launcher/README.md`. `LauncherWindow.qml` (278) only if you need to know how `run` is called.

**Tasks:**
- [x] Move the scoring into a pure `tools/launcher/score.js` (`.pragma library`, like `common/conf.js`) so it can be tested: name prefix > name contains > initials > exec/genericName/keywords, plus a bonus from the launch count that reorders apps that match about equally well but never puts a bad match above a good one. Empty query: most launched first, then by name.
- [x] Match `e.execString` on the command's basename (without `env`, flags or `%U` field codes).
- [x] Initials: the first letter of each word of the name ("Visual Studio Code" → "vsc"). Also split camelCase ("LibreOffice" → "lo").
- [x] Launch counts in `Quickshell.cacheDir + "/launcher-counts.json"` (`{ desktop id: count }`), read with a `FileView`, written atomically only when something is launched. Forget ids that are no longer installed when the file is written.
- [x] `tools/launcher/tests/score.test.mjs` (node, loaded like `common/tests/conf.test.mjs`), and add the folder to `scotchos test` in `bin/scotchos`.
- [x] README: "How it works" and "Files in this folder".

**Done when:** `scotchos test` passes; with the launcher open, "vsc" and "code" find VS Code (or another app that has a fitting name/command); an app launched three times shows above its neighbours on an empty query and stays there after `scotchos restart`.

**Not in this phase:** new providers (dropped), fuzzy matching beyond initials.

**Handoff:**
- `score.js` ranks by tier (name prefix/contains, initials, command, other) + launch bonus ≤ 400; `AppsProvider.record()` writes `launcher-counts.json` in `Quickshell.cacheDir`.
- `scotchos test` now loops over suites (`common/tests`, `tools/launcher/tests`): add a folder to that `for` list for new node tests.
- Not checked live: launching an app and seeing it rise after `scotchos restart` (would open a window on the user's screen); the user should try it.

---

## Phase 2: Dashboard disk and battery

**Status:** todo

**Model:** Sonnet 5.5, medium effort (`/sys` reads and a card layout; the care is in measuring CPU before and after).

**Goal:** the system dashboard also shows root filesystem use, and on a laptop the battery level, charging state and power draw.

**Read first:** `widgets/systemDashboard/stats.py` (247), `widgets/systemDashboard/DashboardWidget.qml` (103), `widgets/systemDashboard/README.md`. `Dashboard.qml` (398) for the layout once you know what data you have.

**Tasks:**
- [ ] `stats.py`: disk from `os.statvfs("/")` (used / total, refreshed every 30 s, not every tick: it changes slowly). Battery from the first `/sys/class/power_supply/BAT*`: `capacity`, `status`, and watts from `power_now` or `current_now × voltage_now`. No battery (a desktop): the fields are absent and the card hides that row.
- [ ] The card: a disk row and a battery row that fit the existing style (rings or bars like the others; check `Ring.qml`/`Graph.qml` before adding a component). No history graph for these, and no animation on values that change every second.
- [ ] Settings: `show_disk` and `show_battery` (both `yes`) in `[dashboard]`, in `scotchos.default.conf`, the settings window and the live conf. `disk_path` (default `/`) only if it costs nothing.
- [ ] README: Settings table, "How it works".

**Done when:** the numbers match `df -h /` and `cat /sys/class/power_supply/BAT*/capacity`; unplugging the charger changes the state within a tick; CPU from `top -p <pid>` is no higher than before (write both numbers in the Handoff). `stats.py` changes need `scotchos restart`. Look at it on an empty workspace (tell the user first; it moves their view).

**Not in this phase:** per-disk lists, battery health, notifications.

**Handoff:**

---

## Phase 3: Claude usage notification; settings window buttons

**Status:** todo

**Model:** Sonnet 5.5, medium effort (two small features following existing patterns (`setConf`, `Process`)).

**Goal:** a desktop notification when a Claude usage limit crosses `warn` (the card is only seen on an empty workspace), and in the settings window a "Reset to default" button per setting and an "Open scotchos.conf" button.

**Read first:** `widgets/claudeUsage/ClaudeUsageWidget.qml` (167), `common/conf.js`, `settings/SettingsWindow.qml` (326). READMEs of `widgets/claudeUsage` and `settings` when updating them.

**Tasks:**
- [ ] Claude usage: `notify-send` once when a limit goes from below `warn` to at or above it, again only after that limit resets. Remember what was sent in `Quickshell.cacheDir`, so a restart doesn't repeat it. A `Process` that runs only when a notification is due. Setting `notify` (`yes`) in `[claudeusage]`, wired everywhere a setting goes. Add `libnotify` to the README's Requirements.
- [ ] `conf.js`: `remove(text, section, key)` (null when the key isn't there; leaves the section header even when it becomes empty), with before/after cases in `common/tests/conf.test.mjs`. `shell.qml`: `removeConf(section, key)` with the same "file changed on disk" guard as `setConf`.
- [ ] Settings window: a small reset button on each setting row, shown only when the conf has that key and its value differs from `def:`; it calls `removeConf`, so the widget's fallback (which doctor keeps equal to `def:`) applies. An "Open scotchos.conf" button in the header or footer (`xdg-open root.confPath` through a `Process`).
- [ ] READMEs: claudeUsage Settings table; settings README.

**Done when:** `scotchos test` passes; resetting a changed setting removes its line from the live conf and the widget shows the default; lowering `warn` below the current usage gives exactly one notification, also across `scotchos restart`; "Open scotchos.conf" opens the file.

**Not in this phase:** notifications for other widgets, a "reset everything" button.

**Handoff:**

---

## Phase 4: E-reader continue reading, bookmark export, converter leftovers

**Status:** todo

**Model:** Opus 5.5, medium effort (`book.py`'s sanitizer is easy to break in ways the fixtures only partly catch).

**Goal:** a launcher entry "Continue reading <title>" that opens the last book where you left off; bookmarks exported to Markdown; two converter fixes left over from the review.

**Read first:** `tools/eReader/Reader.qml` (405: progress, bookmarks, IPC), `tools/launcher/CommandsProvider.qml` (44), `tools/eReader/README.md`. `ReaderPanel.qml` (316) for the export button. `book.py` only around `Sanitizer.handle_starttag` and `file_meta`, plus `tests/test_book.py`.

**Tasks:**
- [ ] Progress gets an `opened` time per book when it's opened (if it isn't stored already). `reader` IPC: `continue()` opens the most recently opened book that still exists, at its position.
- [ ] Launcher: "Continue reading <title>" in `CommandsProvider` while `reader` is on and there's a last book; it calls the reader directly (both live in the shell), not through `qs ipc`.
- [ ] Export: a button (and key) in the bookmarks panel writes `<xdg-user-dir DOCUMENTS>/Reader notes/<title>.md`: title, author, and each bookmark as chapter title + the bookmark's text. Written by `book.py export <bookdir> <progress entry as JSON> <out>`, not in QML; the status line says where it went. Phase 5 adds highlights to the same file, so keep the format easy to extend.
- [ ] `book.py`: a block element starting inside an open `<p>` closes that `<p>` first (sloppy HTML made nested paragraphs; see the `Epub2.test_sloppy_html` fixture). A Markdown book's title is its first `# ` heading, else the file name. Bump `VERSION`.
- [ ] Tests in `tools/eReader/tests/test_book.py` for both fixes and for `export`; README: Files, "How it works", "Running it by hand".

**Done when:** `scotchos test` passes; opening a book, closing the reader, then "Continue reading" from the launcher reopens it at the same page; the exported file has every bookmark; the EPUB 2 fixture's output has no `<p>` inside a `<p>`.

**Not in this phase:** highlights (phase 5), syncing positions anywhere.

**Handoff:**

---

## Phase 5: E-reader highlights and notes

**Status:** todo

**Model:** Opus 5.5, high effort (the spike decides the design; selection, pagination and storage have to fit together).

**Goal:** select text in a book, keep it as a highlight with an optional note, see the highlights in the text and in a side panel list, and jump to them. They're stored next to bookmarks and exported with them.

**Read first:** phase 4's Handoff, `tools/eReader/ReaderBook.qml` (330: the read-only `TextEdit`, `selectByMouse: false`, pagination, how a search match is found again), `tools/eReader/Reader.qml` around the bookmarks (lines ~360–380). `ReaderPanel.qml` when adding the list.

**Tasks:**
- [ ] **Spike first (stop and report if it doesn't work):** how to show a highlight in Qt rich text without breaking pagination: wrapping the matched text in a `<span style="background-color:…">` when the chapter is loaded (located like search's n-th match), or drawing rectangles from `positionToRectangle`. Pick one, write why in a comment. If it needs more than this phase can hold, split into 5a (store, list, jump) and 5b (show in the text) here in PHASES.md and ask the user.
- [ ] Selection: mouse selection in the book (it's off today, check why first), `H` highlights the selection, `N` adds or edits the note of the highlight under the selection.
- [ ] Storage: `progress[bookId].highlights = [{ chapter, n, text, note, created }]`, where `n` locates the text in the chapter like search results do, so it survives re-layout and font changes.
- [ ] Side panel: a "Highlights" list (text, note, chapter title), Enter jumps, Delete removes. Export (phase 4) adds a Highlights section.
- [ ] README: keys, "How it works"; tests for any `book.py` change.

**Done when:** a highlight survives closing and reopening the book and a font size change; it shows in the text and in the list; export includes it; page turns are as fast as before (no rebuild of the library or the chapter's text on every page turn).

**Not in this phase:** highlight colours, sharing.

**Handoff:**

---

## Phase 6: `scotchos doctor --fix`; enable/disable keep the comment column

**Status:** todo

**Model:** Sonnet 5.5, medium effort (shell and awk, with tests to check against).

**Goal:** doctor fixes the mechanical gaps it finds itself; `scotchos enable/disable` keep a line's comment column like the settings window does.

**Read first:** `bin/scotchos-doctor` (175), `bin/scotchos` (`set_enabled`), `common/tests/conf.test.mjs` (the `enable/disable` test).

**Tasks:**
- [ ] `doctor --fix`: adds a missing `[enabled]` line (`key = no` with a comment from the widget README's first line) and a missing conf section (keys and values from the settings window's `def:`) to `scotchos.default.conf`, and the same lines to the live conf when they're missing there. Only conf files, never code or READMEs; atomic writes; prints each change; without `--fix` the output is as today, plus "run `scotchos doctor --fix`" when there's something it could fix.
- [ ] `set_enabled` keeps the comment's column (the same rule as `conf.js`'s `set`: pad or trim the gap, at least one space). Update the expected text in the `enable/disable` test.
- [ ] Root README: `doctor --fix`; CLAUDE.md's Testing line about doctor.

**Done when:** deleting a widget's `[enabled]` line and its section from a copy of the conf (`XDG_CONFIG_HOME` pointing at a temp dir) and running `doctor --fix` puts back what `scotchos.default.conf` has; `scotchos test` passes.

**Not in this phase:** fixing code wiring (imports, LazyLoaders, settings items).

**Handoff:**
