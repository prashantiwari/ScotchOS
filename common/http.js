// HTTP for widgets and tools, with QML's built-in XMLHttpRequest (in the shell process, nothing spawned).
// One place for the timeout, the readyState check and the JSON parse, so every caller handles errors the same way.
.pragma library

// request(method, url, { headers, body, timeout }, done): `body` is sent as JSON. done gets
// { status, ok, data, header(name) }: status 0 means offline or timed out, data is null when the reply isn't JSON.
function request(method, url, opts, done) {
    const xhr = new XMLHttpRequest();
    xhr.timeout = opts.timeout ?? 15000;
    xhr.onreadystatechange = () => {
        if (xhr.readyState !== XMLHttpRequest.DONE) return;
        let data = null;
        try { data = JSON.parse(xhr.responseText); } catch (e) {}
        done({ status: xhr.status, ok: xhr.status >= 200 && xhr.status < 300, data: data,
               header: name => xhr.getResponseHeader(name) });
    };
    xhr.open(method, url);
    for (const name in opts.headers ?? {}) xhr.setRequestHeader(name, opts.headers[name]);
    if (opts.body === undefined || opts.body === null) {
        xhr.send();
    } else {
        xhr.setRequestHeader("Content-Type", "application/json");
        xhr.send(JSON.stringify(opts.body));
    }
}

function get(url, opts, done) { request("GET", url, opts, done) }
