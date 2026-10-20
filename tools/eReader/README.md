# E-reader

A minimalist e-book reader in the theme's colors (wallbash, so it follows the wallpaper). It reads **EPUB, MOBI, AZW3 / AZW (no DRM), FB2 (and `.fb2.zip`), TXT and Markdown** from one folder, `~/Books` by default.

Open it from the **app launcher**: type `reader` (or `book`, `epub`) and pick **E-reader**. You can also run **Open E-reader** from the ScotchOS commands (`> reader`), or `scotchos reader` in a terminal. **Continue reading <title>** in the same commands (`> continue`, or `scotchos reader continue`) opens the book you opened last straight at your place.

- **Library**: a grid of covers (or the title on a tinted card when a book has none) with author and progress. The last opened book comes first. Type to filter, use the arrows to move, Enter or a click to open, and Esc to clear the filter or close.
- **Reading**: a centred column, with the book and the contents entry you're in on top, and the page, chapter and % of the book at the bottom. It reopens where you left off.
- **Pages** (default): page breaks fall between lines. → ← Space PgDn PgUp h l, the mouse wheel, or a click on the left or right third turn pages, and they carry into the next or previous chapter. **Scroll**: each chapter is one column. ↓ ↑ j k scroll, Space and PgDn scroll a screen, and at the end of a chapter Space (or the **Next chapter** link) moves on.
- **Links** in the book (footnotes, its own contents page) jump inside the reader. Web links open in the browser.
- **Bookmarks**: `B` marks the page you're on (a ribbon shows in the top-right corner; `B` again or a click on it removes it). `M` lists them with the start of the marked page, the chapter and the %, and Enter or a click jumps there. `E` in that list (or its export icon, top right) writes them to `~/Documents/Reader notes/<title>.md` (your XDG documents folder): the title, the author, each bookmark as its chapter and the start of its page, then each highlight as its chapter, its text and its note. The status line says where it went.
- **Highlights and notes**: drag the mouse over the text to select it (the ends snap to whole words; a click lets go of it). `H` keeps the selection as a highlight, a tint under the text; `N` adds or edits the note of the highlight under the selection (making it first if there's none), typed in the side panel: Enter keeps it, Esc doesn't. A highlight with a note is underlined. `Shift+H` lists them with their chapter and note: Enter or a click jumps there, Delete or the × removes one, `N` edits the note, and `E` exports them with the bookmarks. While nothing is selected, `H` and `N` keep their other meaning (previous page, search matches).
- **Search**: `/` opens a search box. Type words (any case; line breaks between them don't matter), Enter lists every match with its context and chapter, and Enter or a click on one jumps there with the match highlighted. Afterwards `n` and `N` go to the next and previous match.
- **Time left**: the status line ends with the time left in the chapter and in the book, at your reading speed. The speed is learned from your page turns (or scrolling): skims under 3 s and pauses over 10 min don't count, and until it has learned it assumes ~250 words a minute. Switch it off with `time_left = no`.
- **Text and layout**: `A` opens the **Aa** tab of the side panel. It lists the installed fonts, each in its own face (type to filter, Enter or a click switches the book to it, and the panel stays open to try another), with the size, spacing, justify, pages / scroll and page layout above. **Page layout** (`W` cycles): **Column**, a centred column at most `width` wide; **Full width**, the text across the whole window, less a margin on each side as wide as the gap between two pages; **Two pages**, side by side like an open book (pages mode only; scroll mode uses a column).
- **Back**: `Backspace` returns to where you were before a jump (a link, the contents, a bookmark or a search match), several jumps deep.

| Key (in a book) | Does |
|---|---|
| `T` | Contents (Enter or a click jumps; T or Esc closes; Tab switches to bookmarks) |
| `B` | Bookmark this page, or remove its bookmark |
| `M` | Bookmarks (Enter or a click jumps; Delete or the × removes one; `E` exports them to Markdown; Tab switches to contents) |
| drag | Select text (snaps to words; a click or Esc lets go) |
| `H` (text selected) | Highlight the selection |
| `N` (text selected) | Note on the highlight under the selection (Enter keeps it, Esc doesn't) |
| `Shift+H` | Highlights (Enter or a click jumps; Delete or the × removes one; `N` edits the note; `E` exports) |
| `/` | Search the book (type, Enter searches, ↑ ↓ and Enter jump) |
| `A` | Fonts and text (type to filter fonts, Enter picks one, + - size, ← → page layout) |
| `W` / `Shift+W` | Page layout: column → full width → two pages |
| `n` / `N` | Next / previous search match (nothing selected) |
| `Backspace` | Back to where the last jump left from |
| `F` / `F11` | Fullscreen ↔ floating window |
| `S` | Pages ↔ scroll |
| `+` / `-` | Font size |
| `]` / `[` | Column width (also each of two pages) |
| `.` / `,` | Line spacing |
| `Shift+J` | Justified ↔ ragged text |
| `Home` | Start of the chapter |
| `Esc` | Let go of the selection, else leave fullscreen, else back to the library |
| `Q` | Close |

The adjustments are saved to `scotchos.conf`, so they apply to every book. The place in the book is kept as a character offset, so it doesn't move when the size or width changes.

The design and its limits are in [`PRD.md`](PRD.md). Switch it off with `scotchos disable reader`: the window and its state are unloaded, and the launcher entry does nothing.

## Settings

In `[reader]` of `~/.config/scotchos/scotchos.conf` (defaults in [`scotchos.default.conf`](../../scotchos.default.conf)), or in the settings window (**E-reader**):

| Key | Default | What it does |
|---|---|---|
| `library_dir` | `~/Books` | Folder scanned, with its subfolders, for books |
| `layout` | `pages` | `pages` or `scroll` (`S` switches) |
| `font` | `serif` | Font family of the book text (`serif` lets fontconfig pick, e.g. DejaVu Serif). `A` lists the installed ones |
| `font_size` | `16` | px, 10–32 (`+` / `-`) |
| `width` | `720` | Max column width, px, 400–1600 (`]` / `[`) |
| `page_layout` | `column` | `column` (at most `width`), `full` (whole width, less a 56 px margin each side) or `two` (two pages side by side, each at most `width`; pages mode only) (`W`) |
| `line_height` | `150` | % of the font height, 100–220 (`.` / `,`) |
| `justify` | `no` | Justify paragraphs (`Shift+J`) |
| `time_left` | `yes` | Show the time left in the chapter and the book on the status line |

## Files in this folder

| File | What it does |
|---|---|
| `Reader.qml` | Loaded by `shell.qml` while `reader` is on (and reachable there as `reader`). The `reader` IPC target, the library list, the open book, positions, continue reading, the bookmark export, the `book.py` calls, and a loader for each window. |
| `ReaderWindow.qml` | The floating window (70 % × 85 % of the screen focused when it opened). Exists only while open. |
| `ReaderFullscreen.qml` | The fullscreen overlay layer (`scotchos-reader`, exclusive keyboard). Exists only while open in fullscreen. |
| `ReaderContent.qml` | What both windows show: library or book, the title and status lines, and every key. |
| `ReaderLibrary.qml` | The cover grid and the filter. Created only while the library is shown, so page turns (which update the positions it sorts by) don't touch it. |
| `ReaderBook.qml` | The chapter: rich text with a stylesheet made from the theme, pagination, the page layouts (and the second page), scrolling, links, selecting and the highlights. |
| `ReaderPanel.qml` | The side panel: contents, bookmarks, highlights and their notes (and the export), search, and fonts and text settings. |
| `book.py` | Lists the library (metadata and covers, cached), converts a book once into theme-free HTML chapters, searches a converted book, and exports its bookmarks and highlights to Markdown. |
| `tests/` | `test_book.py` and its fixtures: a small EPUB 3 and EPUB 2 (as folders, zipped by the test; the EPUB 2 one has unclosed `<p>`s), FB2, TXT and Markdown, plus the export. `scotchos test` runs it. |
| `reader.sh` | What the launcher entry runs: exits if `reader` is off, else `scotchos reader open`. |
| `scotchos-reader.desktop` | The app launcher entry; `install.sh` copies it to `~/.local/share/applications/` with the real path in `Exec`. |
| `PRD.md` | Requirements and design. |
| `README.md` | This file. |

## Requirements

| Requirement | Package (Arch/CachyOS) | Tested version | Used for |
|---|---|---|---|
| Quickshell | `quickshell` | 0.3.2 | The windows, `TextEdit` rich text, `qs ipc` |
| Hyprland | `hyprland` | 0.56.2 | Floats the window because it has a fixed size, focused monitor for fullscreen |
| Python 3 | `python` | 3.14.8 | `book.py` (standard library only) |
| mobi (only for MOBI / AZW3 / AZW) | `python-mobi` (AUR), or `pipx install mobi` | 0.4.1 (pipx) | Unpacking Kindle files. A pipx install works as long as its venv uses the same Python version as `python3`, because `book.py` adds that venv's `site-packages` to its path. Without it, the library still lists them (their headers are read directly), and opening one says to install it |
| A serif font | `ttf-dejavu`, `noto-fonts`… | DejaVu Serif 2.37 | Book text (`font = serif`) |
| JetBrainsMono Nerd Font | `ttf-jetbrains-mono-nerd`, or HyDE's bundled copy | — | Title, status, library and icons |

```bash
sudo pacman -S --needed quickshell python ttf-dejavu
yay -S python-mobi        # MOBI / AZW3 (or: pipx install mobi)
```

## Changes made to the system

- `~/.local/share/applications/scotchos-reader.desktop`: a copy of `scotchos-reader.desktop` with `@DIR@` replaced by this folder's full path. Made by `install.sh`. Until then, the reader opens with `scotchos reader` or the `> reader` command in the launcher.
- `~/.local/state/scotchos/reader-progress.json`: where you are in each book, when you last opened it, its bookmarks and highlights, and your reading speed (`_reading`). Created on the first open.
- `~/Documents/Reader notes/` (the XDG documents folder): one Markdown file per book whose notes you exported. Created on the first export; the reader never reads it back.
- `~/.cache/scotchos/reader/`: converted books, covers and the library index. Safe to delete: it's rebuilt as needed. Covers of books gone from the library are removed on the next scan, and their converted copies once they haven't been opened for 90 days.

No Hyprland config change and no keybind.

## Running it by hand

```bash
scotchos reader                       # toggle the window
scotchos reader open                  # or: tools/eReader/reader.sh
scotchos reader continue              # the book opened last, at its place (IPC: continueReading)
qs ipc -p ~/Projects/ScotchOS call reader close

# The converter on its own (prints JSON):
python3 tools/eReader/book.py scan ~/Books ~/.cache/scotchos/reader [~/.local/state/scotchos/reader-progress.json]
python3 tools/eReader/book.py open ~/Books/some.epub ~/.cache/scotchos/reader
python3 tools/eReader/book.py search ~/.cache/scotchos/reader/<id> "some words"
python3 tools/eReader/book.py export ~/.cache/scotchos/reader/<id> '{"bookmarks": [{"chapter": 0, "text": "…"}]}' /tmp/notes.md

# The converter's tests (temp dirs only, the real cache isn't touched):
python3 -m unittest discover -s tools/eReader/tests
```

QML changes hot-reload on save, which closes the window. Logs: `scotchos log 2>&1 | grep -E 'WARN|ERROR'`. `book.py` errors go to the log too (its stderr).

## Adapting

| What | Where | Current value |
|---|---|---|
| Formats picked up | `FORMATS` in `book.py` | epub, mobi, azw3, azw, fb2, fb2.zip, txt, md, markdown |
| Where chapters are split | `SPLIT` in `book.py` | 100 KB of HTML, between top-level blocks |
| Reading speed before it's learned, what counts as reading | `speed` and `learn()` in `Reader.qml` | 1200 characters a minute; moves of 3 s – 10 min at 150–6000 a minute |
| How long a converted book that left the library is kept | `KEEP_DAYS` in `book.py` | 90 days after its last open |
| Search results listed | `SEARCH_MAX` in `book.py` | 300 (the rest are counted) |
| Which tags survive | `TAGS` in `book.py` | Structure only: headings, paragraphs, emphasis, lists, quotes, tables, images, links |
| TXT chapter headings | `HEADING_TXT` in `book.py` | `Chapter …`, `Part …`, `I. TITLE` … |
| Text look (heading sizes, paragraph gap, link color) | `style` in `ReaderBook.qml` | Accent headings and links, 0.7 em paragraph gap |
| Fonts left out of the font list | `fonts` in `ReaderPanel.qml` | Nerd Fonts, icon, emoji, symbol, monospace and math fonts, Noto's per-script families |
| Gap between two pages (and the side margins in full width) | `gap` in `ReaderBook.qml` | 56 px |
| Window size | `ReaderWindow.qml` | 70 % × 85 % of the focused screen (at least 760 × 540) |
| Highlight tint, longest highlight | `Boxes` and `highlight()` in `ReaderBook.qml` | the accent at 25 %, 2000 characters |
| Ranges of the adjustment keys | `ReaderContent.qml` and `Reader.qml` | size 10–32, width 400–1600, spacing 100–220 |
| Positions file | `stateDir` in `Reader.qml` | `~/.local/state/scotchos/reader-progress.json` |
| Where exports go | `exportNotes()` in `Reader.qml` | `$(xdg-user-dir DOCUMENTS)/Reader notes/<title>.md` |
| Export format | `export()` in `book.py` | `# title`, `*author*`, `## Bookmarks`, then `### chapter · %` and a `>` quote each; `## Highlights` the same, with the note after the quote |

After changing `book.py`, run `scotchos test` (and add a case to `tests/test_book.py` for what you fixed). If its output changed, bump `VERSION` there, so that cached books are converted again.

## How it works

1. **Loading:** `shell.qml` loads `Reader` while `reader` is on. Idle, it's an `IpcHandler`, a few properties and a small `FileView` (positions). No processes or timers run. Each window is a `LazyLoader` that exists only while open. The state lives in `Reader`, so switching to fullscreen (a different window type) keeps the book and place.
2. **Library:** every open runs `book.py scan`. It walks `library_dir` and reads the metadata of new or changed files only (keyed by size and mtime in `library.json`): EPUB from the OPF, MOBI/AZW3 from the PDB / MOBI / EXTH headers, FB2 from `title-info`, Gutenberg TXT from its `Title:` line, Markdown from its first `# ` heading (else the file name). Covers are written to the cache, and the grid decodes them at display size. Symlinked folders are followed, each real folder once (so a link back up the tree doesn't loop). The scan then prunes the cache (see Changes made to the system), and finds moved or renamed books: positions are keyed by the path's hash, so a book with no position takes over the one of a book whose file is gone, with the same title and size (or, for positions saved before the size was, the same file name).
3. **Converting:** `book.py open` builds the book in a temp dir and renames it into `~/.cache/scotchos/reader/<id>/` (`id` is a hash of the path), so a failed conversion never leaves half a book. It's redone only when the file or `VERSION` changes. An `html.parser` walker keeps structural tags and drops every style, class, script and font, so the theme decides the look. Like a browser, it closes an open `<p>` when a block (another `<p>`, a `<div>`, a list, a heading…) starts inside it, unless a table cell lies between them, so sloppy books that never close their paragraphs don't nest them. Local images are extracted with their size, and remote ones are dropped (Markdown images only from the book's own folder). Each element `id` becomes an invisible U+2060 marker, and internal links become `scotchos:<chapter>:<anchor index>`. Chapters over 100 KB are split between blocks. The TOC comes from the EPUB 3 nav, the NCX, FB2 sections, or the headings when there's none. MOBI/AZW3 go through `mobi.extract()`, which gives an EPUB (KF8) or one HTML file (old MOBI, split at `mbp:pagebreak`, with contents from the `toc.ncx` beside it). DRM, from the MOBI encryption field or `META-INF/encryption.xml`, is reported and not read.
4. **Showing a chapter:** one chapter is in memory at a time, in a read-only `TextEdit` (rich text). Its `<style>` is built from the wallbash colors and the settings, so a wallpaper change or a `+` restyles it at once. Images are scaled to fit the column and page height. A resize recounts the pages (and refits the images, in a chapter that has any) once the size has stopped changing for 150 ms, not on every step of a drag.
5. **Pages:** the next page starts at the top of the line that the page's bottom edge cuts (`positionAt` → `positionToRectangle`). A line or image taller than the page is cut. Turning a page only moves the `Flickable`'s `contentY`, and a background-colored curtain hides the cut line below the page. There's no animation, so a page turn draws once.
6. **Position:** the character offset of the first visible line, and of the middle line (which contents entry is shown). After any relayout (size, font, width, mode), the page holding that character is shown again. Anchors are found as the n-th U+2060 in `getText()`. The positions file is written 2 s after the last move and when the window closes, atomically. The % of the book comes from the chapter text sizes in `book.json`. Each open also stamps the book's `opened` time: **Continue reading** (the launcher row, from `lastTitle()`, or the `continueReading` IPC call) opens the window, waits for its scan (which drops books whose file is gone and finds moved ones), then opens the most recently opened book still in the library. Opening it goes to its saved position as usual. The launcher calls `Reader` directly through `shell.qml`'s `reader` property, with no `qs ipc` process.
7. **Bookmarks:** stored with the book's position as (chapter, character offset), so like the position they survive font and width changes. A page "has" a bookmark when its offset falls between the page's first and last character (`positionAt` at the bottom-right corner of the page). The label is the first ~100 characters of the page, and the contents entry being read when it was made. **Export** saves the positions first, then runs `book.py export <book dir> <the book's entry as JSON> <file>` (the folder from `xdg-user-dir DOCUMENTS`, the title with slashes replaced). It reads the chapter titles from `book.json` and writes the file atomically, overwriting the last export. The format is one `## ` section per kind of note: bookmarks, then highlights.
8. **Search:** `book.py search` reads the converted chapters, turns them into plain text (block tags become spaces, entities are decoded) and matches the query's words with any whitespace between them, ignoring case. Each result says which chapter it's in and that it's the n-th match there, with ~45 characters of context on each side and the contents entry before it (counted from the anchor markers). Jumping loads the chapter and finds the n-th match again in the `TextEdit`'s own text (whose offsets differ: images, markers, paragraph separators), selects it, and shows its page. Jumps push the old (chapter, offset) on a 50-deep stack, which Backspace pops.
9. **Highlights:** stored with the bookmarks as `{ chapter, n, text, note, created, pos, percent, where }`. `text` (the selection, whitespace made single spaces) and `n` (which of its matches in the chapter it is, the one starting nearest the selection) find it again the way a search result is found, so it survives font, width and layout changes, and even a reconversion that moves the character offsets; `pos` only orders the list. They're **drawn** as rectangles under the text, one per line, from `positionToRectangle` of every character in the passage, rather than by wrapping the passage in a background-coloured `<span>`: changing the HTML would re-parse and lay out the whole chapter for each new highlight, and a place in the plain text can't be found in the HTML without parsing it again. The rectangles are worked out on each relayout (chapter, size, font) and when a highlight changes, never on a page turn, and the second page draws the same list. **Selecting** is done by the `MouseArea` over the text (the `TextEdit`s keep `selectByMouse: false`: that area takes every press for links and page turns, and the selection also shows search matches): a drag of more than 6 px selects from the character it started on, on both pages, kept inside the page's lines. A note is typed in the highlights panel; closing the panel any other way than Enter drops the edit.
10. **Page layouts and fonts:** the layout only sets the `TextEdit`'s width (the column, the whole view, or half of it less the gap). For **two pages** a second `TextEdit` (created only in that layout) gets the same text, width and font, so it lays out exactly like the first and the same page list fits it: the left shows page 2*k*, the right page 2*k*+1, each with its own curtain, and a page turn moves by two. The font list is `Qt.fontFamilies()`, filtered, built only while the **Aa** tab is open. Picking a font writes `font` to the conf, which restyles the text and repaginates, keeping the position.
11. **Time left:** each forward move inside a chapter is a sample of characters per minute (characters passed / time since the last move), kept if the move took 3 s to 10 min and the speed is 150–6000 a minute (so skimming and walking away don't count). The average gives the first samples more weight, then 10 % each, and is saved in the positions file as `_reading`. The time left is the remaining characters of the chapter (and of the following chapters, from `book.json`) divided by it.

## Uninstall

To only switch it off, `scotchos disable reader` is enough. To remove it:

1. Delete `~/.local/share/applications/scotchos-reader.desktop`, `~/.local/state/scotchos/reader-progress.json` and `~/.cache/scotchos/reader/`.
2. Remove `import "tools/eReader"` and the `LazyLoader` holding `Reader` from `shell.qml`, the `reader)` line and its usage line from `bin/scotchos`, the E-reader lines (and the python-mobi hint) from `install.sh`, the "Open E-reader" row from `tools/launcher/CommandsProvider.qml`, the `reader` item from `items` in `settings/SettingsWindow.qml`, and `reader` plus `[reader]` from `scotchos.default.conf` and `~/.config/scotchos/scotchos.conf`. Also remove its row from the root README.
3. Delete this folder. Optionally `yay -R python-mobi`.
