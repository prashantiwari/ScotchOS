// E-reader: the library, the open book, reading positions and the book.py calls. Loaded while `reader` is on;
// it runs nothing until the window opens, and keeps the open book while the window switches to fullscreen and back.
import QtQuick
import Quickshell
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
    readonly property bool justify: core.isYes(setting("justify", "no"))
    // Live adjustments (keys in the book view) go to the conf, so they apply to every book and survive restarts.
    function set(key, value) { core.setConf("reader", key, String(value)) }
    function step(key, fallback, min, max, by) { set(key, Math.max(min, Math.min(max, clamped(key, fallback, min, max) + by))) }

    // ---- Paths ----
    readonly property string helper: Quickshell.shellDir + "/tools/eReader/book.py"
    readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || home + "/.cache") + "/scotchos/reader"
    // Outside the Quickshell cache dir, whose name depends on the repo path: moving the repo keeps the positions.
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/scotchos"

    // ---- State ----
    property bool open: false
    property bool fullscreen: false
    property string view: "library"     // library / book
    property string panel: ""           // the side panel shown: "" (none), contents, bookmarks
    property var books: []
    property bool scanning: false
    property string error: ""
    property string bookId: ""
    property var book: null             // book.json, plus `dir`
    property int chapter: 0
    property int pos: 0                 // character offset of the first visible line in the chapter
    property int posEnd: 0              // and of the last visible character
    property int anchor: -1             // jump to this anchor (the n-th U+2060) once the chapter is laid out
    property bool atEnd: false          // open the chapter on its last page (paging backwards)
    property bool loading: false
    property string chapterHtml: ""
    property var marks: []              // character offset of each anchor in the chapter (set by the book view)
    property int probe: 0               // character at the middle of the view: which contents entry is being read
    property var progress: ({})         // id -> { path, title, chapter, pos, percent, opened }
    signal jumped()

    IpcHandler {
        target: "reader"
        function open(): void { r.open = true }
        function close(): void { r.open = false }
        function toggle(): void { r.open = !r.open }
    }

    LazyLoader {
        active: r.open && !r.fullscreen
        ReaderWindow { reader: r }
    }
    LazyLoader {
        active: r.open && r.fullscreen
        ReaderFullscreen { reader: r }
    }

    onOpenChanged: {
        if (open) {
            scan();
        } else {
            saveProgress();
            fullscreen = false;
        }
    }

    // ---- Library ----
    // Rescanned on every open; book.py caches metadata and covers, so only new or changed files are read.
    function scan() {
        if (scanProc.running) return;
        scanning = true;
        scanProc.running = true;
    }
    Process {
        id: scanProc
        // mkdir: the state dir must exist before the first position is saved.
        command: ["sh", "-c", 'mkdir -p "$1" && exec python3 "$2" scan "$3" "$4"', "sh",
                  r.stateDir, r.helper, r.libraryDir, r.cacheDir]
        stdout: SplitParser {
            onRead: line => {
                try {
                    const d = JSON.parse(line);
                    if (d.error) r.error = d.error;
                    else r.books = d.books ?? [];
                } catch (e) {
                    r.error = "Couldn't read the library.";
                }
            }
        }
        onExited: r.scanning = false
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
        chapterHtml = "";
        bookId = b.id;
        openProc.path = b.path;
        openProc.running = true;
    }
    Process {
        id: openProc
        property string path
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
    // Links in the text: scotchos:<chapter>:<anchor> inside the book, web links in the browser, nothing else.
    function follow(link) {
        const m = String(link).match(/^scotchos:(-?\d+):(-?\d+)$/);
        if (m) { if (+m[1] >= 0) goTo(+m[1], +m[2], 0); return; }
        if (/^https?:\/\//i.test(link)) Qt.openUrlExternally(link);
    }
    FileView {
        id: chapterFile
        printErrors: false
        onLoaded: r.chapterHtml = text()
        onLoadFailed: r.error = "Couldn't read this chapter."
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
        progress[bookId] = Object.assign({}, old, { path: openProc.path, title: book.title, opened: Date.now() });
        progressChanged();
        saveTimer.restart();
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
