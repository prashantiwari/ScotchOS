// scotchos.conf as text: parsing it and changing one value. Pure functions (no file access), so
// common/tests/conf.test.mjs runs this same code under node; shell.qml does the reading and writing.
.pragma library

// A "#" only starts a comment at the start of a line or after a space, so values like URLs can hold one.
function stripComment(line) { return line.replace(/(^|\s)#.*/, "").trim() }

// Parsed into { section: { key: value } }, or null when there's no [enabled] section.
function parse(text) {
    const out = {};
    let section = out[""] = {};
    for (const line of text.split("\n")) {
        const l = stripComment(line);
        const s = l.match(/^\[([\w-]+)\]$/);
        if (s) { section = out[s[1]] = out[s[1]] ?? {}; continue; }
        const m = l.match(/^(\w+)\s*=\s*(.*)$/);
        if (m) section[m[1]] = m[2];
    }
    return out.enabled ? out : null;
}

// The text with `key = value` under [section], or null when it already holds that value. Only the value
// changes, so the line's alignment and comment stay; a missing key goes after the section's last setting.
function set(text, section, key, value) {
    value = String(value);
    const lines = text.split("\n");
    let cur = "", at = -1;
    for (let i = 0; i < lines.length; i++) {
        const l = stripComment(lines[i]);
        const s = l.match(/^\[([\w-]+)\]$/);
        if (s) { cur = s[1]; if (cur === section) at = i; continue; }
        if (cur !== section || !l) continue;
        // The lazy space after "=" leaves at least one space before the comment of an empty `key =  # …`.
        const m = lines[i].match(/^(\s*(\w+)\s*=[ \t]*?)(\S.*?)?(\s+#.*)?\s*$/);
        if (m && m[2] === key) {
            const old = m[3] ?? "";
            if (old === value) return null;
            // An empty `key =` has no space after the "=" to keep.
            const sep = /\s$/.test(m[1]) || value === "" ? "" : " ";
            // Pad or trim the gap before a comment so it stays in its column (the added space counts too).
            const gap = sep.length + value.length - old.length;
            let rest = m[4] ?? "";
            if (rest && gap < 0) rest = " ".repeat(-gap) + rest;
            else if (rest && gap > 0) rest = rest.replace(new RegExp("^ {0," + gap + "}( )"), "$1");
            lines[i] = m[1] + sep + value + rest;
            return lines.join("\n");
        }
        at = i;
    }
    if (at === -1) lines.push("", "[" + section + "]", key + " = " + value);
    else lines.splice(at + 1, 0, key + " = " + value);
    return lines.join("\n");
}
