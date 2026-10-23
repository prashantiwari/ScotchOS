// dailyTheory client: the API calls, the saved token and what the window shows. Loaded while `dailytheory`
// is on; it runs nothing until the window opens, and outlives the window so a signup in flight isn't lost.
import QtQuick
import Quickshell
import Quickshell.Io
import "../../common/http.js" as Http
import "notes.js" as Notes

Scope {
    id: t
    required property var core

    // ---- Settings ([dailytheory] in scotchos.conf) ----
    readonly property string server: String(core.conf.dailytheory?.server || "http://localhost:8080").replace(/\/+$/, "")
    readonly property string regKey: core.conf.dailytheory?.registration_key ?? ""
    // Plain http to another machine sends the token and registration key unencrypted.
    readonly property bool insecure: /^http:\/\//i.test(server)
                                     && !/^http:\/\/(localhost|127\.\d+\.\d+\.\d+|\[::1\])(:\d+)?(\/|$)/i.test(server)
    onInsecureChanged: if (insecure) console.warn("dailytheory:", server, "is plain http to another host: the token crosses the network unencrypted")
    Component.onCompleted: { insecureChanged(); loadNotes(); }

    // ---- State ----
    property bool open: false
    property string token: ""
    property bool tokenRead: false
    property var me: null           // GET /v1/me without its quota
    property var quota: null        // { used, limit, resets_at }
    property var history: []        // newest first
    property var current: null      // the theory on the Theory page
    property var topics: []         // catalog, for the interest suggestions
    property string busy: ""        // "next" / "signup" / "save" while one is in flight
    property var error: null        // { text, retry: function | undefined }
    property string view: "theory"
    readonly property bool signedIn: token !== ""
    readonly property bool outOfQuota: !!quota && quota.used >= quota.limit

    IpcHandler {
        target: "dailytheory"
        function open(): void { t.open = true }
        function close(): void { t.open = false }
        function toggle(): void { t.open = !t.open }
    }

    LazyLoader {
        active: t.open
        DailyTheoryWindow { client: t }
    }

    // ---- Token: ~/.local/state/scotchos/dailytheory-token, mode 0600 ----
    // The server shows it once and can't recover it, so it's kept outside the repo and the cache.
    readonly property string tokenPath: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state")
                                        + "/scotchos/dailytheory-token"
    FileView {
        path: t.tokenPath
        printErrors: false
        onLoaded: { t.token = text().trim(); t.tokenRead = true; if (t.open) t.refresh(); }
        onLoadFailed: { t.tokenRead = true; if (t.open) t.refresh(); }
    }
    // Written through stdin (never argv, which `ps` shows), with umask 077, to a temp file then renamed.
    Process {
        id: saveToken
        property string value
        command: ["sh", "-c", 'umask 077 && mkdir -p "${1%/*}" && cat > "$1.tmp" && mv -f "$1.tmp" "$1"', "sh", t.tokenPath]
        stdinEnabled: true
        onStarted: { write(value); stdinEnabled = false; }
        onExited: code => { if (code !== 0) console.warn("dailytheory: couldn't save the token to", t.tokenPath) }
    }
    Process {
        id: removeToken
        command: ["rm", "-f", t.tokenPath]
    }

    function storeToken(v) {
        token = v;
        saveToken.value = v;
        saveToken.stdinEnabled = true;
        saveToken.running = true;
    }
    // "Log out": v1 has no logout endpoint, so the token is just deleted here. Saved theories and highlights stay.
    function forget() {
        token = ""; me = null; quota = null; history = []; current = null; view = "theory";
        removeToken.running = true;
        loadTopics();
    }

    // ---- Saved theories and highlights: one Markdown note per theory in ~/Documents/DailyTheory ----
    // API v1 has no bookmarks, so they're kept here, as notes you can read and edit anywhere (notes.js writes and parses
    // them). Each holds the whole theory, so it still opens once it's out of the 50-theory history.
    readonly property string notesDir: (Quickshell.env("XDG_DOCUMENTS_DIR") || Quickshell.env("HOME") + "/Documents") + "/DailyTheory"
    property var savedTheories: ({})    // id → theory, from the notes
    property var files: ({})            // id → its file name in notesDir
    property var otherFiles: []         // .md files there that aren't saved theories: never written over
    property var saved: []              // { id, saved_at }, newest first
    property var highlights: []         // { id, theory_id, text, saved_at }, newest first
    property bool savedLoaded: false
    property int hlSeq: 0

    // Read when the shell starts and each time the window opens, so notes edited or deleted elsewhere show up.
    // Each file is printed after a \036 (record separator) line holding its name.
    Process {
        id: readNotes
        command: ["sh", "-c", 'cd "$1" 2>/dev/null || exit 0; for f in *.md; do [ -f "$f" ] && printf "\\036%s\\n" "$f" && cat "$f"; done',
                  "sh", t.notesDir]
        stdout: StdioCollector { onStreamFinished: t.parseNotes(text) }
    }
    property bool readAfterWrites: false
    function loadNotes() {
        // A read racing a write could bring back the old file: read once the writes are done.
        if (writer.running || writeQueue.length) readAfterWrites = true;
        else if (!readNotes.running) readNotes.running = true;
    }
    function parseNotes(out) {
        if (writer.running || writeQueue.length) return loadNotes();
        const theories = {}, names = {}, others = [], marks = [];
        let keep = [];
        for (const chunk of out.split(String.fromCharCode(30)).slice(1)) {
            const nl = chunk.indexOf("\n");
            const name = chunk.slice(0, nl), n = Notes.fromMarkdown(chunk.slice(nl + 1));
            if (!n || theories[n.theory.id]) { others.push(name); continue; }
            theories[n.theory.id] = n.theory;
            names[n.theory.id] = name;
            if (n.note.saved) keep.push({ id: n.theory.id, saved_at: n.note.saved_at });
            for (const h of n.note.highlights)
                marks.push({ id: "hl_" + (++hlSeq), theory_id: n.theory.id, text: h.text, saved_at: h.saved_at });
        }
        const newest = (a, b) => a.saved_at < b.saved_at ? 1 : a.saved_at > b.saved_at ? -1 : 0;
        savedTheories = theories; files = names; otherFiles = others;
        saved = keep.sort(newest); highlights = marks.sort(newest);
        savedLoaded = true;
    }

    // Writes go one at a time, each to a temp file then renamed, so a note is never half-written.
    property var writeQueue: []         // { name, text }; an empty text deletes the file
    Process {
        id: writer
        property string text
        onStarted: { if (text) write(text); stdinEnabled = false; }
        onExited: code => {
            if (code !== 0) console.warn("dailytheory: couldn't write", command[command.length - 1]);
            Qt.callLater(t.nextWrite);
        }
    }
    function nextWrite() {
        if (writer.running) return;
        if (!writeQueue.length) {
            if (readAfterWrites) { readAfterWrites = false; loadNotes(); }
            return;
        }
        const job = writeQueue[0];
        writeQueue = writeQueue.slice(1);
        const path = notesDir + "/" + job.name;
        writer.text = job.text;
        writer.command = job.text ? ["sh", "-c", 'mkdir -p "${1%/*}" && cat > "$1.tmp" && mv -f "$1.tmp" "$1"', "sh", path]
                                  : ["rm", "-f", path];
        writer.stdinEnabled = !!job.text;
        writer.running = true;
    }
    // Rewrites a theory's note from the state here, or deletes it once it's neither saved nor highlighted.
    function writeNote(id) {
        const th = savedTheories[id];
        if (!th) return;
        const note = { saved: isSaved(id), saved_at: saved.find(s => s.id === id)?.saved_at,
                       highlights: highlights.filter(h => h.theory_id === id) };
        let name = files[id];
        if (!note.saved && !note.highlights.length) {
            const all = Object.assign({}, savedTheories), names = Object.assign({}, files);
            delete all[id]; delete names[id];
            savedTheories = all; files = names;
            if (name) writeQueue = writeQueue.concat([{ name: name, text: "" }]);
        } else {
            if (!name) {
                name = Notes.fileName(th, Object.values(files).concat(otherFiles));
                const names = Object.assign({}, files);
                names[id] = name;
                files = names;
            }
            writeQueue = writeQueue.concat([{ name: name, text: Notes.toMarkdown(th, note) }]);
        }
        nextWrite();
    }
    function keepCopy(th) {
        const all = Object.assign({}, savedTheories);
        all[th.id] = th;
        savedTheories = all;
    }
    function isSaved(id) { return saved.some(s => s.id === id) }
    function toggleSaved(th) {
        if (!th?.id || !savedLoaded) return;
        if (isSaved(th.id)) saved = saved.filter(s => s.id !== th.id);
        else { keepCopy(th); saved = [{ id: th.id, saved_at: new Date().toISOString() }].concat(saved); }
        writeNote(th.id);
    }
    function addHighlight(th, text) {
        text = String(text ?? "").split(String.fromCharCode(0x2029)).join("\n\n").replace(/[ \t]+\n/g, "\n").trim();
        if (!th?.id || !text || !savedLoaded) return;
        if (highlights.some(h => h.theory_id === th.id && h.text === text)) return;
        keepCopy(th);
        highlights = [{ id: "hl_" + (++hlSeq), theory_id: th.id, text: text, saved_at: new Date().toISOString() }]
                     .concat(highlights);
        writeNote(th.id);
    }
    function removeHighlight(id) {
        const h = highlights.find(x => x.id === id);
        if (!h) return;
        highlights = highlights.filter(x => x.id !== id);
        writeNote(h.theory_id);
    }
    function openNotes() { Qt.openUrlExternally("file://" + notesDir) }
    // The server's copy when it's in history (it may have gained fields), else the one saved here.
    function theoryById(id) { return history.find(h => h.id === id) ?? savedTheories[id] ?? null }
    function show(id) {
        const th = theoryById(id);
        if (!th) return;
        current = th; view = "theory"; error = null;
    }

    // ---- HTTP ----
    // slow: the LLM-backed calls (signup, interest change, next) take 3-12 s, ~25 s when the server retries; it gives
    // up at 75 s with 503 upstream_unavailable, so wait past that to get its answer instead of a timeout.
    function call(method, path, body, slow, done) {
        const headers = { "Accept": "application/json" };
        if (token && path !== "/v1/users") headers["Authorization"] = "Bearer " + token;
        if (path === "/v1/users" && regKey) headers["X-Registration-Key"] = regKey;
        Http.request(method, server + path, { headers: headers, body: body, timeout: slow ? 85000 : 10000 }, r => {
            if (r.ok && r.data) return done(r.data, null);
            const err = r.data?.error ?? (r.status === 0
                ? { code: "network", message: "Couldn't reach " + t.server + " (offline, or it timed out)." }
                : { code: "internal", message: "HTTP " + r.status });
            // rate_limited carries Retry-After (seconds), which fail() turns into minutes.
            if (err.code === "rate_limited") err.retry_after = parseInt(r.header("Retry-After")) || 0;
            if (err.code === "unauthorized" && t.token) t.forget();
            done(null, err);
        });
    }

    // What to tell the user, by error code (never by status or message text).
    function fail(err, retry) {
        const n = quota?.limit ?? me?.daily_limit;
        const text = ({
            invalid_request: err.message,
            no_topics: "Couldn't find topics in that, try being more specific (or pick some suggestions).",
            unauthorized: "The server didn't accept the saved token, so it was removed. Sign up again.",
            forbidden: "The server needs a registration key: set it in ScotchOS settings › Daily theory.",
            quota_exceeded: "You've had all " + (n ?? "your") + " for today.",
            rate_limited: "Too many signups from here, try again in "
                          + (err.retry_after ? Math.max(1, Math.ceil(err.retry_after / 60)) + " min." : "a while."),
            generation_failed: "The server couldn't generate that right now.",
            upstream_unavailable: "The server's AI provider is busy or down.",
        })[err.code] ?? (err.code === "network" ? err.message : "Something went wrong (" + err.code + ").");
        // These mean this client sent a wrong path, method or a body over 16 KiB: a bug to find in `scotchos log`.
        if (["not_found", "method_not_allowed", "payload_too_large"].includes(err.code))
            console.warn("dailytheory:", err.code, err.message);
        // Only offer Retry where trying again can help; it's always a click, never automatic (each try costs LLM quota).
        const retryable = ["generation_failed", "upstream_unavailable", "internal", "network"].includes(err.code);
        // A failed /next isn't counted, so say so: otherwise Retry looks like it spends one of today's.
        const free = retry === next && ["generation_failed", "upstream_unavailable"].includes(err.code);
        error = { text: text + (free ? " That didn't use up your quota." : ""), retry: retryable ? retry : undefined };
    }

    function setMe(data) {
        const user = Object.assign({}, data);
        delete user.quota;
        delete user.token;
        me = user;
        if (data.quota) quota = data.quota;
    }

    // ---- Calls ----
    // On every window open: profile, quota and history if signed in, else the catalog for signup.
    function refresh() {
        if (!tokenRead) return;     // the FileView calls back once it has read the token
        error = null;
        loadNotes();
        if (!signedIn) return loadTopics();
        call("GET", "/v1/me", null, false, (data, err) => {
            if (err) return fail(err, refresh);
            setMe(data);
        });
        call("GET", "/v1/theories?limit=50", null, false, (data, err) => {
            if (err) return fail(err, refresh);
            history = data.theories ?? [];
            // Swap in the server's copy of the theory being read: it may have gained fields since (links, 2026-10-20).
            const fresh = current && history.find(h => h.id === current.id);
            if (fresh) current = fresh;
            else if (!current && history.length) current = history[0];
        });
    }

    // Source and reading links come from the server: open web links only, never file: or other schemes.
    function openLink(url) {
        if (/^https?:\/\//i.test(url ?? "")) Qt.openUrlExternally(url);
        else console.warn("dailytheory: not opening", url);
    }

    function loadTopics() {
        if (topics.length) return;
        call("GET", "/v1/topics", null, false, (data, err) => {
            if (!err) topics = data.topics ?? [];
        });
    }

    function next() {
        if (busy) return;
        busy = "next"; error = null;
        call("POST", "/v1/theories/next", null, true, (data, err) => {
            busy = "";
            if (err) {
                if (err.code === "quota_exceeded" && quota) quota = Object.assign({}, quota, { used: quota.limit, resets_at: err.resets_at ?? quota.resets_at });
                return fail(err, next);
            }
            quota = data.quota;
            current = data.theory;
            history = [data.theory].concat(history.filter(h => h.id !== data.theory.id));
            view = "theory";
        });
    }

    function signup(interests, limit) {
        if (busy) return;
        busy = "signup"; error = null;
        call("POST", "/v1/users", { interests: interests, daily_limit: limit }, true, (data, err) => {
            busy = "";
            if (err) return fail(err, () => signup(interests, limit));
            storeToken(data.token);
            setMe(data);
            history = []; current = null; view = "theory";
            refresh();
        });
    }

    // PUT /v1/me with only the fields that changed (the server wants at least one).
    function save(interests, limit) {
        if (busy || !me) return;
        const body = {};
        if (interests !== me.interests) body.interests = interests;
        if (limit !== me.daily_limit) body.daily_limit = limit;
        if (!Object.keys(body).length) return;
        busy = "save"; error = null;
        call("PUT", "/v1/me", body, "interests" in body, (data, err) => {
            busy = "";
            if (err) return fail(err, () => save(interests, limit));
            setMe(data);
        });
    }
}
