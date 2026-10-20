// dailyTheory client: the API calls, the saved token and what the window shows. Loaded while `dailytheory`
// is on; it runs nothing until the window opens, and outlives the window so a signup in flight isn't lost.
import QtQuick
import Quickshell
import Quickshell.Io
import "../../common/http.js" as Http

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
    Component.onCompleted: insecureChanged()

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
    // "Log out": v1 has no logout endpoint, so the token is just deleted here.
    function forget() {
        token = ""; me = null; quota = null; history = []; current = null; view = "theory";
        removeToken.running = true;
        loadTopics();
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
