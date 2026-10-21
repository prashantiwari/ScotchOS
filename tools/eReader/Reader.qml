// E-reader: the library, the open book, reading positions and the book.py calls. Loaded while `reader` is on;
// it runs nothing until the window opens, and keeps the open book while the window switches to fullscreen and back.
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

Scope {
    id: r
    required property var core

    // ---- Settings ([reader] in scotchos.conf) ----
    readonly property var section: core.conf.reader ?? ({})
    function setting(key, fallback) { const v = section[key]; return v === undefined || v === "" ? fallback : v }
    function clamped(key, fallback, min, max) {
        const n = parseInt(setting(key, fallback));
        return Math.max(min, Math.min(max, isNaN(n) ? fallback : n));
    }
    readonly property string home: Quickshell.env("HOME")
    readonly property string libraryDir: String(setting("library_dir", "~/Books")).replace(/^~(?=\/|$)/, home)
    readonly property string layout: setting("layout", "pages") === "scroll" ? "scroll" : "pages"
    readonly property string bookFont: setting("font", "serif")
    readonly property int fontSize: clamped("font_size", 16, 10, 32)
    readonly property int lineHeight: clamped("line_height", 150, 100, 220)
    readonly property int columnWidth: clamped("width", 720, 400, 1600)
    // column: one column at most `width` wide / full: the whole width / two: two pages side by side (pages only)
    readonly property var pageLayouts: ["column", "full", "two"]
    readonly property string pageLayout: pageLayouts.includes(setting("page_layout", "column")) ? setting("page_layout", "column") : "column"
    readonly property bool justify: core.isYes(setting("justify", "no"))
    readonly property bool timeLeft: core.isYes(setting("time_left", "yes"))
    // Live adjustments (keys in the book view) go to the conf, so they apply to every book and survive restarts.
    function set(key, value) { core.setConf("reader", key, String(value)) }
    function step(key, fallback, min, max, by) { set(key, Math.max(min, Math.min(max, clamped(key, fallback, min, max) + by))) }
    function cyclePageLayout(by) { set("page_layout", pageLayouts[(pageLayouts.indexOf(pageLayout) + by + 3) % 3]) }

    // ---- Paths ----
    readonly property string helper: Quickshell.shellDir + "/tools/eReader/book.py"
    readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || home + "/.cache") + "/scotchos/reader"
    // Outside the Quickshell cache dir, whose name depends on the repo path: moving the repo keeps the positions.
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/scotchos"

    // ---- State ----
    property bool open: false
    property bool fullscreen: false
    // The screen the window goes on, picked when it opens and when fullscreen switches (so F covers the monitor the
    // window is on), not bound: a binding to the focused monitor would move it when focus follows the mouse.
    // `shown` follows `open` but only after `screen` is set, so the window never starts on the old one.
    property var screen: null
    property bool shown: false
    function setFullscreen(on) {
        if (!on) toEmptyWorkspace();
        screen = core.focusedScreen();
        fullscreen = on;
    }
    // The window opens on the focused workspace: when that one has windows, go to the next empty one on the same
    // monitor first, so the reader gets a workspace of its own instead of squeezing in with them.
    function toEmptyWorkspace() {
        if ((Hyprland.focusedWorkspace?.toplevels.values.length ?? 0) > 0)
            Hyprland.dispatch('hl.dsp.focus({workspace = "emptynm"})');
    }
    property string view: "library"     // library / book
    property string panel: ""           // the side panel shown: "" (none), contents, bookmarks, highlights, search, text
    property var books: []
    property bool scanning: false
    property string error: ""
    property string bookId: ""
    property var book: null             // book.json, plus `dir`
    property int chapter: 0
    property int pos: 0                 // character offset of the first visible line in the chapter
    property int posEnd: 0              // and of the last visible character
    property int anchor: -1             // jump to this anchor (the n-th U+2060) once the chapter is laid out
    property var find: null             // or to this search match, { query, n }: the n-th match in the chapter
    property bool atEnd: false          // open the chapter on its last page (paging backwards)
    property bool loading: false
    property string chapterHtml: ""
    property var marks: []              // character offset of each anchor in the chapter (set by the book view)
    property int probe: 0               // character at the middle of the view: which contents entry is being read
    property var progress: ({})         // id -> { path, title, chapter, pos, percent, opened, bookmarks, highlights }
    signal jumped()

    IpcHandler {
        target: "reader"
        function open(): void { r.open = true }
        function close(): void { r.open = false }
        function toggle(): void { r.open = !r.open }
        // `continue` is a reserved word, so the call is `continueReading`.
        function continueReading(): void { r.continueReading() }
    }

    LazyLoader {
        active: r.shown && !r.fullscreen
        ReaderWindow { reader: r }
    }
    LazyLoader {
        active: r.shown && r.fullscreen
        ReaderFullscreen { reader: r }
    }

    onOpenChanged: {
        if (open) {
            toEmptyWorkspace();
            screen = core.focusedScreen();
            shown = true;
            scan();
        } else {
            saveProgress();
            shown = false;
            fullscreen = false;
        }
    }

    // ---- Library ----
    // Rescanned on every open; book.py caches metadata and covers, so only new or changed files are read.
    function scan() {
        if (scanProc.running) { rescan = true; return; }
        scanning = true;
        scanProc.running = true;
    }
    property bool rescan: false         // asked for while a scan was running (library_dir changed): run again after
    onLibraryDirChanged: if (open) scan()
    Process {
        id: scanProc
        // mkdir: the state dir must exist before the first position is saved.
        command: ["sh", "-c", 'mkdir -p "$1" && exec python3 "$2" scan "$3" "$4" "$5"', "sh",
                  r.stateDir, r.helper, r.libraryDir, r.cacheDir, progressFile.path]
        stdout: SplitParser {
            onRead: line => {
                try {
                    const d = JSON.parse(line);
                    if (d.error) r.error = d.error;
                    else { r.books = d.books ?? []; r.adoptMoved(d.moved ?? {}); }
                } catch (e) {
                    r.error = "Couldn't read the library.";
                }
            }
        }
        onExited: {
            r.scanning = false;
            if (r.rescan) { r.rescan = false; r.scan(); }
            else if (r.resuming) r.resume();
        }
    }
    // A moved or renamed book gets a new id; book.py found the position it had under the old one.
    function adoptMoved(moved) {
        if (!progressLoaded) return;
        let changed = false;
        for (const [id, old] of Object.entries(moved)) {
            if (progress[id] || !progress[old]) continue;
            progress[id] = Object.assign({}, progress[old], { path: books.find(b => b.id === id)?.path ?? progress[old].path });
            delete progress[old];
            changed = true;
        }
        if (changed) { progressChanged(); saveProgress(); }
    }

    // ---- Continue reading: the book opened last (`opened` in its position) that's still in the library ----
    // Ids of the books with a position, the last opened first; only the ones the last scan found, once there was one.
    function recent() {
        return Object.keys(progress).filter(id => progress[id]?.opened && (!books.length || books.some(b => b.id === id)))
            .sort((a, b) => progress[b].opened - progress[a].opened);
    }
    function lastTitle() { const id = recent()[0]; return id ? progress[id].title ?? "" : "" }
    // Opens the window and waits for its scan, which drops books whose file is gone and adopts moved ones.
    property bool resuming: false
    function continueReading() {
        resuming = true;
        if (open) scan(); else open = true;
    }
    function resume() {
        resuming = false;
        const id = recent()[0];
        const b = id && books.find(x => x.id === id);
        if (b) openBook(b);
        else error = "No book to continue.";
    }

    // ---- Opening a book: book.py converts it once into the cache, then book.json and one chapter are read ----
    function openBook(b) {
        if (loading) return;
        error = "";
        panel = "";
        if (b.id === bookId && book) { view = "book"; return; }
        saveProgress();
        loading = true;
        view = "book";
        book = null;
        history = [];
        clearSearch();
        chapterHtml = "";
        bookId = b.id;
        openProc.path = b.path;
        openProc.size = b.size ?? 0;
        openProc.running = true;
    }
    Process {
        id: openProc
        property string path
        property real size                  // saved with the position, to know the book again once it's moved
        command: ["python3", r.helper, "open", path, r.cacheDir]
        stdout: SplitParser {
            onRead: line => {
                try {
                    const d = JSON.parse(line);
                    if (d.error) { r.fail(d.error); return; }
                    bookFile.path = d.dir + "/book.json";
                    bookFile.reload();
                } catch (e) {
                    r.fail("Couldn't open this book.");
                }
            }
        }
        onExited: code => { if (code !== 0) r.fail("book.py failed (see scotchos log).") }
    }
    function fail(text) {
        error = text;
        loading = false;
        bookId = "";
        book = null;
        view = "library";
    }
    FileView {
        id: bookFile
        printErrors: false
        onLoaded: {
            let b;
            try { b = JSON.parse(text()); } catch (e) { return r.fail("Couldn't read the converted book."); }
            b.dir = path.slice(0, path.lastIndexOf("/"));
            const saved = r.progress[r.bookId];
            r.book = b;
            r.goTo(saved ? Math.min(saved.chapter, b.chapters.length - 1) : 0, -1, saved?.pos ?? 0);
            r.loading = false;
            r.touch();
        }
        onLoadFailed: r.fail("Couldn't read the converted book.")
    }

    // ---- Moving around ----
    // chapter, anchor index (-1 = none), character offset; the book view applies them after laying the chapter out.
    function goTo(c, a, p) {
        if (!book) return;
        c = Math.max(0, Math.min(book.chapters.length - 1, c));
        atEnd = false;
        find = null;
        lastTurn = null;            // a jump isn't reading
        anchor = a ?? -1;
        pos = p ?? 0;
        if (c !== chapter || !chapterHtml) {
            chapter = c;
            chapterHtml = "";
            chapterFile.path = book.dir + "/" + book.chapters[c].file;
            chapterFile.reload();
        } else {
            jumped();           // same chapter: the view applies anchor / pos now
        }
    }
    function nextChapter() { if (book && chapter < book.chapters.length - 1) goTo(chapter + 1, -1, 0) }
    function prevChapter() {
        if (!book || chapter === 0) return;
        goTo(chapter - 1, -1, 0);
        atEnd = true;
    }
    // Jumps (links, contents, bookmarks, search) remember where they left from: Backspace goes back.
    property var history: []
    function jump(c, a, p) {
        history = history.concat([{ chapter: chapter, pos: pos }]).slice(-50);
        goTo(c, a, p);
    }
    function back() {
        const h = history[history.length - 1];
        if (!h) return;
        history = history.slice(0, -1);
        goTo(h.chapter, -1, h.pos);
    }
    // Links in the text: scotchos:<chapter>:<anchor> inside the book, web links in the browser, nothing else.
    function follow(link) {
        const m = String(link).match(/^scotchos:(-?\d+):(-?\d+)$/);
        if (m) { if (+m[1] >= 0) jump(+m[1], +m[2], 0); return; }
        if (/^https?:\/\//i.test(link)) Qt.openUrlExternally(link);
    }
    FileView {
        id: chapterFile
        printErrors: false
        onLoaded: r.chapterHtml = text()
        onLoadFailed: r.error = "Couldn't read this chapter."
    }

    // ---- Search: book.py finds the matches in the converted chapters; the book view finds the n-th one again ----
    property string query: ""           // being typed in the search panel
    property string searched: ""        // the query the results are for
    property var results: []            // { chapter, n, where, before, match, after }
    property int total: 0               // matches, also past the listed ones
    property int result: -1             // the result last jumped to (n / N go on from there)
    readonly property bool searching: searchProc.running
    function search() {
        const q = query.trim();
        if (!book || !q || searchProc.running) return;
        searchProc.command = ["python3", helper, "search", book.dir, q];
        searchProc.q = q;
        searchProc.running = true;
        results = [];
    }
    function clearSearch() { query = ""; searched = ""; results = []; total = 0; result = -1; }
    // n / N: the next or previous match after the last one shown.
    function nextResult(by) {
        if (results.length) showResult(result < 0 ? (by > 0 ? 0 : results.length - 1) : (result + by + results.length) % results.length);
    }
    function showResult(i) {
        const m = results[i];
        if (!m) return;
        result = i;
        jump(m.chapter, -1, 0);
        find = { query: searched, n: m.n };     // read by the view's relayout, which goTo only queued
    }
    Process {
        id: searchProc
        property string q
        stdout: SplitParser {
            onRead: data => {
                try {
                    const d = JSON.parse(data);
                    r.results = d.results ?? [];
                    r.total = d.total ?? 0;
                    r.searched = searchProc.q;
                    r.result = -1;
                } catch (e) {
                    r.results = [];
                }
            }
        }
    }

    // The contents entry being read: the last one starting before the middle of the view.
    readonly property int tocIndex: {
        let n = -1;
        (book?.toc ?? []).forEach((e, i) => {
            if (e.chapter < chapter || (e.chapter === chapter && (e.anchor < 0 || (marks[e.anchor] ?? 0) <= probe))) n = i;
        });
        return n;
    }

    // ---- Positions: ~/.local/state/scotchos/reader-progress.json ----
    // The share of the book read: chapter sizes (characters of text) weighted by the place in the chapter.
    function percentAt(c, frac) {
        if (!book) return 0;
        let before = 0, total = 0;
        book.chapters.forEach((ch, i) => { total += ch.size; if (i < c) before += ch.size; });
        return Math.round(1000 * (before + book.chapters[c].size * frac) / total) / 10;
    }
    // Called by the book view after every page turn or scroll (frac: 0..1 within the chapter).
    function report(p, frac, mid) {
        learn(p);
        pos = p;
        probe = mid ?? p;
        const old = progress[bookId] ?? {};
        progress[bookId] = Object.assign({}, old, { path: openProc.path || old.path, title: book.title, chapter: chapter, pos: p,
                                                    percent: percentAt(chapter, frac), opened: old.opened ?? Date.now() });
        progressChanged();
        saveTimer.restart();
    }
    function touch() {
        const old = progress[bookId] ?? { chapter: 0, pos: 0, percent: 0 };
        progress[bookId] = Object.assign({}, old, { path: openProc.path, size: openProc.size, title: book.title, opened: Date.now() });
        progressChanged();
        saveTimer.restart();
    }
    // ---- Reading speed (characters per minute) and the time left ----
    // Learned from moving forward in a chapter: the characters passed over the time it took. Moves under 3 s
    // (skimming) or over 10 min (away) are left out, and each one counts for a tenth of the average.
    readonly property real speed: progress._reading?.cpm ?? 1200      // ~250 words a minute until it's learned
    property var lastTurn: null         // { chapter, pos, at } of the last report
    function learn(p) {
        const now = Date.now(), last = lastTurn;
        lastTurn = { chapter: chapter, pos: p, at: now };
        if (!last || last.chapter !== chapter || p <= last.pos || p - last.pos > 8000) return;
        const dt = now - last.at;
        if (dt < 3000 || dt > 600000) return;
        const cpm = (p - last.pos) / dt * 60000;
        if (cpm < 150 || cpm > 6000) return;
        const old = progress._reading ?? { cpm: 1200, samples: 0 };
        // The first moves replace the guess faster than later ones change the average.
        const w = Math.max(0.1, 1 / (old.samples + 2));
        progress._reading = { cpm: Math.round(old.cpm * (1 - w) + cpm * w), samples: old.samples + 1 };
    }
    // Minutes to read the rest of the chapter (frac: how far into it), and of the book.
    function minutesLeft(frac, wholeBook) {
        if (!book) return 0;
        let chars = book.chapters[chapter].size * (1 - frac);
        if (wholeBook) book.chapters.forEach((ch, i) => { if (i > chapter) chars += ch.size; });
        return chars / speed;
    }
    function duration(min) {
        if (min < 1) return "<1 min";
        if (min < 60) return Math.round(min) + " min";
        const h = Math.floor(min / 60), m = Math.round(min % 60);
        return h + " h " + (m < 10 ? "0" : "") + m;
    }

    // ---- Bookmarks: kept with the position, { chapter, pos, percent, text, where, at }, in reading order ----
    readonly property var bookmarks: progress[bookId]?.bookmarks ?? []
    // The bookmark on the page (or screen) being shown, -1 if none.
    readonly property int markHere: bookmarks.findIndex(b => b.chapter === chapter && b.pos >= pos && b.pos <= posEnd)
    // B: removes the bookmark on this page, or adds one at its first line (text: the start of that line).
    function toggleBookmark(text) {
        if (!book) return;
        const list = bookmarks.slice();
        if (markHere >= 0) list.splice(markHere, 1);
        else list.push({ chapter: chapter, pos: pos, percent: progress[bookId]?.percent ?? 0, text: text,
                         where: book.toc[tocIndex]?.title ?? book.chapters[chapter].title ?? "", at: Date.now() });
        setBookmarks(list.sort((a, b) => a.chapter - b.chapter || a.pos - b.pos));
    }
    function removeBookmark(i) { const list = bookmarks.slice(); list.splice(i, 1); setBookmarks(list); }
    function setBookmarks(list) {
        progress[bookId] = Object.assign({}, progress[bookId] ?? { chapter: chapter, pos: pos, percent: 0 }, { bookmarks: list });
        progressChanged();
        saveTimer.restart();
    }

    // ---- Highlights: kept with the position, { chapter, n, text, note, created, pos, percent, where }, in reading order ----
    // `text` and `n` find the passage again (the n-th match of the text in its chapter, as search results do), so a
    // highlight doesn't depend on the layout or on book.py's offsets; `pos` (where it started) only orders the list.
    readonly property var highlights: progress[bookId]?.highlights ?? []
    signal highlightsEdited()           // the book view draws them again (progressChanged fires on every page turn)
    // The highlight on the page (or screen) being shown, -1 if none.
    readonly property int highlightHere: highlights.findIndex(h => h.chapter === chapter && h.pos >= pos && h.pos <= posEnd)
    // sel: { text, n, pos } from the book view's selection; returns the new highlight's index.
    function addHighlight(sel) {
        const h = { chapter: chapter, n: sel.n, text: sel.text, note: "", created: Date.now(), pos: sel.pos,
                    percent: progress[bookId]?.percent ?? 0, where: book.toc[tocIndex]?.title ?? book.chapters[chapter].title ?? "" };
        const list = highlights.concat([h]).sort((a, b) => a.chapter - b.chapter || a.pos - b.pos);
        setHighlights(list);
        return list.indexOf(h);
    }
    function removeHighlight(i) { const list = highlights.slice(); list.splice(i, 1); setHighlights(list); }
    function setHighlights(list) {
        progress[bookId] = Object.assign({}, progress[bookId] ?? { chapter: chapter, pos: pos, percent: 0 }, { highlights: list });
        progressChanged();
        highlightsEdited();
        saveTimer.restart();
    }
    // Jumps like a search result: the view finds the n-th match again, or falls back to `pos`.
    function showHighlight(i) {
        const h = highlights[i];
        if (!h) return;
        jump(h.chapter, -1, h.pos);
        find = { query: h.text, n: h.n };
    }
    // ---- Notes: typed in the highlights panel (N), Enter keeps it, Esc leaves it as it was ----
    property int noting: -1             // the highlight whose note is being typed
    property string note: ""
    property bool notingFromBook: false // N was pressed in the book: the panel closes again after
    onPanelChanged: if (panel !== "highlights") noting = -1      // closed some other way (a click outside): dropped
    function editNote(i, fromBook) {
        if (!highlights[i]) return;
        noting = i;
        note = highlights[i].note ?? "";
        notingFromBook = fromBook;
        panel = "highlights";
    }
    function endNote(keep) {
        if (keep && highlights[noting]) {
            const list = highlights.slice();
            list[noting] = Object.assign({}, list[noting], { note: note.trim() });
            setHighlights(list);
        }
        noting = -1;
        if (notingFromBook) panel = "";
    }

    // ---- Export: book.py writes the bookmarks and highlights to <Documents>/Reader notes/<title>.md ----
    property string notice: ""          // shown on the status line for a few seconds
    function exportNotes() {
        if (!book || exportProc.running) return;
        saveProgress();
        // A title is a file name here: no slashes, and no leading dot (that would hide it).
        const name = String(book.title || "Untitled").replace(/[\/\0]/g, "-").replace(/^\.+/, "").slice(0, 120);
        exportProc.command = ["sh", "-c", 'exec python3 "$1" export "$2" "$3" "$(xdg-user-dir DOCUMENTS 2>/dev/null || echo "$HOME/Documents")/Reader notes/$4.md"',
                              "sh", helper, book.dir, JSON.stringify(progress[bookId] ?? {}), name];
        exportProc.running = true;
    }
    function say(text) { notice = text; noticeTimer.restart(); }
    Process {
        id: exportProc
        stdout: SplitParser {
            onRead: line => {
                try {
                    const d = JSON.parse(line);
                    r.say(d.error ? d.error : "Notes saved to " + String(d.path).replace(r.home + "/", "~/"));
                } catch (e) {
                    r.say("Couldn't export the notes.");
                }
            }
        }
    }
    Timer {
        id: noticeTimer
        interval: 6000
        onTriggered: r.notice = ""
    }

    // A moment after the last page turn, so holding → doesn't write the file on every page.
    Timer {
        id: saveTimer
        interval: 2000
        onTriggered: r.saveProgress()
    }
    function saveProgress() {
        if (!progressLoaded) return;
        saveTimer.stop();
        progressFile.setText(JSON.stringify(progress));
    }
    property bool progressLoaded: false
    FileView {
        id: progressFile
        path: r.stateDir + "/reader-progress.json"
        atomicWrites: true
        printErrors: false
        onLoaded: {
            try { r.progress = JSON.parse(text()) ?? {}; } catch (e) { r.progress = {}; }
            r.progressLoaded = true;
        }
        onLoadFailed: r.progressLoaded = true
    }
}
