# E-reader: product requirements

A minimalist e-book reader that lives in the ScotchOS shell. It looks like the rest of ScotchOS: wallbash colors (so it follows the wallpaper and HyDE theme), JetBrainsMono Nerd Font for its chrome, no decoration beyond a thin title line and a progress line.

Status: v1, 2026-10-20.

## Goals

- Open a **library window** of the books in one folder (`~/Books` by default), with covers, authors and how far you've read, and read any of them in a couple of keystrokes.
- Read **EPUB, MOBI / AZW3 / AZW (no DRM), FB2 (and `.fb2.zip`), TXT and Markdown**.
- Text in the theme's colors, with the font, size, column width and line spacing adjustable live and remembered.
- **Pages** (Kindle-style) or **continuous scroll**, a setting that a key also toggles.
- A **table of contents** to jump around.
- **Floating window** by default, **F** for a distraction-free fullscreen.
- Remember the position in every book, and reopen where you left off.
- Cost nothing while closed: no processes, no timers.

## Non-goals (v1)

- DRM-protected books (detected and reported, never decrypted).
- PDF, CBZ/CBR comics, DjVu: they are page images, not reflowable text, and would need a different renderer.
- Bookmarks, highlights, notes, search in the book, dictionary lookup, text-to-speech.
- The book's own CSS: fonts, colors and layout are replaced by the theme. Structure (headings, emphasis, lists, quotes, tables, images, links) is kept.
- Syncing, a store, metadata editing, several library folders.

## Users and entry points

One user, on this machine. The reader is opened from:

| Entry | How |
|---|---|
| App launcher (Super+Space, or rofi) | **E-reader**: the `scotchos-reader.desktop` entry (installed by `install.sh`) |
| ScotchOS commands in the launcher | `> reader` → **Open E-reader** |
| Terminal | `scotchos reader [open\|close\|toggle]` |

There's no keybind of its own (no change to `hyprland.lua`).

## Experience

### Library

- A grid of books: cover (or, without one, a card with the title in the accent color), title, author, a thin progress bar with the percentage.
- Sorted by last opened, then by title. Books never opened come after the ones you've started.
- Typing filters by title or author. Arrows move the selection, Enter opens it, a click opens it.
- Esc clears the filter, or closes the window when the filter is empty.
- Empty folder: a line saying where to put books and which formats work.
- The folder is scanned each time the window opens. Metadata and covers are cached, so a rescan only reads new or changed files.

### Reading

- A centred text column (max `width` px), a title line on top (book · chapter, dim) and a status line at the bottom (page *n / m* of the chapter, or the scroll position, chapter *i / N*, % of the book).
- **Pages mode**: page breaks fall between lines, never through one. → / ← / Space / Shift+Space / PgDn / PgUp / l / h / mouse wheel / click on the right or left third of the window turn pages. They carry over into the next or previous chapter.
- **Scroll mode**: the chapter is one scrolling column. ↓ / ↑ / j / k scroll, Space / PgDn / PgUp scroll a screen, and at the end of a chapter Space (or a **Next chapter** link) moves on.
- **Links**: links inside the book (footnotes, the book's own contents page) jump in the reader. Web links open in the browser. Other schemes are ignored.
- **Images** are scaled to fit the column and page.
- **T** opens the table of contents: the book's own TOC (EPUB nav or NCX, FB2 sections), or the headings when there's none. The current chapter is highlighted. Click or Enter jumps.
- **Esc** goes back to the library (or closes the TOC). **Q** closes the window.

### Adjusting (live, saved to `scotchos.conf`, so they apply to every book)

| Key | Change |
|---|---|
| `+` / `-` | Font size (10–32 px) |
| `]` / `[` | Column width (400–1600 px, 40 px steps) |
| `.` / `,` | Line spacing (100–220 %, 10 % steps) |
| `S` | Pages ↔ scroll |
| `J` | Justified ↔ ragged-right text |
| `F` | Floating ↔ fullscreen |

The position in the book survives all of these: it's stored as a character offset, not a page number.

### Theme

- Background `bg`, text `fg`, headings and links `accent`, secondary text `dim`, borders `Qt.alpha(accent, 0.35)`: the same wallbash colors as every widget, updated live when the wallpaper changes.
- Book text uses the `font` setting (default `serif`, i.e. whatever fontconfig picks), and the chrome uses JetBrainsMono Nerd Font.

## Settings (`[reader]` in `scotchos.conf`, and the settings window)

| Key | Default | Meaning |
|---|---|---|
| `library_dir` | `~/Books` | Folder scanned (recursively) for books |
| `layout` | `pages` | `pages` or `scroll` |
| `font` | `serif` | Font family for book text |
| `font_size` | `16` | px |
| `line_height` | `150` | % of the font height |
| `width` | `720` | Max column width, px |
| `justify` | `no` | Justify paragraphs |

## Technical design

### Pieces

| Piece | Role |
|---|---|
| `book.py` (Python 3, stdlib only, plus `mobi` for MOBI text) | `scan`: library metadata and covers, cached. `open`: converts a book once into cleaned, theme-free HTML chapters plus a `book.json` (title, author, chapters, TOC, anchors) in the cache. |
| `Reader.qml` (Scope) | Loaded while `reader` is on. Holds the `reader` IPC target, the library list, the open book, the reading positions, and runs `book.py`. The window is a `LazyLoader` inside it. |
| `ReaderWindow.qml` / `ReaderFullscreen.qml` | The floating `FloatingWindow` and the fullscreen overlay `PanelWindow` (exclusive keyboard focus). Both hold the same `ReaderContent`. |
| `ReaderContent.qml` | Keys, and switching between library, book and TOC. |
| `ReaderLibrary.qml`, `ReaderBook.qml`, `ReaderToc.qml` | The three views. |

### Conversion (book.py)

- **EPUB**: `META-INF/container.xml` → OPF → spine order, metadata, cover (`properties="cover-image"`, `<meta name="cover">`, or a manifest item named cover). TOC from the EPUB 3 nav document, else `toc.ncx`. `META-INF/encryption.xml` encrypting anything but fonts means DRM.
- **MOBI / AZW3 / AZW**: metadata and cover come from the PDB/MOBI/EXTH headers (stdlib, no `mobi` needed, so the library always shows them). A non-zero encryption field means DRM. Text goes through `mobi.extract()`: KF8 gives an EPUB that takes the EPUB path, and old MOBI gives one HTML file, split at `mbp:pagebreak` with headings as its TOC.
- **FB2**: XML. Top-level `<section>`s become chapters, `<title>` becomes a heading, `epigraph` / `cite` become blockquotes, `poem` lines become paragraphs, `<binary>` images are decoded to files, and the notes body becomes a final "Notes" chapter.
- **TXT**: UTF-8 (falling back to cp1252). Blank lines separate paragraphs, and short lines like `Chapter 12` / `Part Two` become headings and chapter breaks.
- **Markdown**: a small converter (headings, paragraphs, emphasis, code, lists, quotes, links, images, rules). `#` / `##` headings start chapters.
- **Sanitizing**: an `html.parser` walker keeps a whitelist of structural tags and drops every `style`, `class`, `<style>`, `<script>`, font and color. Local images are extracted with their pixel size (read from the PNG/JPEG/GIF header). Remote images are dropped. Each element `id` becomes an invisible U+2060 marker, so that QML can find anchors in the plain text. Internal links become `scotchos:<chapter>:<anchor>`.
- **Splitting**: a chapter over ~100 KB of HTML is split between top-level blocks, so that one `TextEdit` never lays out a whole book.
- **Cache**: `~/.cache/scotchos/reader/<id>/`, where id = hash of the real path. It's rebuilt when the file's size or mtime, or the converter version, changes.

### Rendering (QML)

- A read-only `TextEdit` with `textFormat: RichText` and a generated `<style>` (colors, line height, paragraph spacing, justification). `TextEdit` rather than `Text` because it has `positionAt` / `positionToRectangle` / `getText` / `linkAt`.
- **Pagination**: starting at y = 0, the next page starts at the top of the line that the bottom edge cuts (`positionAt(x, bottom)` → `positionToRectangle`). Each page is a clipped viewport onto the same `TextEdit`, so the chapter is laid out once and turning a page only moves it. It's recomputed when the size, font or text changes.
- **Position**: (chapter, character offset of the first visible line). The page or scroll offset is derived from it after every relayout.
- **Anchors**: the n-th U+2060 in `getText(0, length)` is the chapter's n-th anchor.
- **Progress %**: the chapter sizes from `book.json`, weighted by the offset within the chapter.

### State

- Positions: `~/.local/state/scotchos/reader-progress.json`, `{ id: { path, chapter, pos, percent, opened } }`, written atomically a moment after the last page turn and when the window closes. It's outside the Quickshell cache dir, so that moving the repo doesn't reset it.
- Converted books and covers: `~/.cache/scotchos/reader/` (safe to delete).

### Resource rules

- While closed: one `IpcHandler` and a few properties. No processes or timers. `book.py` runs only on open (scan) and on opening a book.
- No animations on page turns: a page turn redraws once.
- One chapter in memory at a time. Covers are decoded at their display size (`sourceSize`), and the library grid reuses its delegates.

## Dependencies

| Package | Why | Required |
|---|---|---|
| `quickshell` | The windows | yes |
| `python` (3.x) | `book.py` | yes |
| `python-mobi` (AUR) | MOBI / AZW3 text | only for those formats. Without it, opening one shows `yay -S python-mobi` |
| A serif font (`ttf-dejavu`, `noto-fonts`…) | Book text | recommended |

## Acceptance criteria

1. With `reader = no`, nothing is loaded, `scotchos reader` does nothing, and `reader.sh` exits at once.
2. `scotchos doctor` passes.
3. The library lists every supported file in `library_dir`, with title and author, and covers where the book has one.
4. EPUB 2, EPUB 3, KF8 AZW3, old MOBI (with `python-mobi`), FB2, TXT and MD files open, show the right chapters in the TOC, and turn pages without cutting lines.
5. Changing the font size, width or spacing keeps the same text at the top of the page.
6. Closing and reopening (or restarting the shell) returns to the same place in the book.
7. The colors follow a wallpaper change while the reader is open.
8. Fullscreen covers the focused monitor, and F or Esc gets back.
9. Shell memory with the window closed is unchanged (`scotchos status`) compared with before the reader existed.
