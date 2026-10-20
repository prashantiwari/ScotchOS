// common/conf.js: parse / set before-and-after cases, and bin/scotchos read against the same files.
// Run: node --test common/tests/   (or `scotchos test`)
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, writeFileSync, mkdtempSync, mkdirSync, rmSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const repo = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
// conf.js is a QML JavaScript library: without its `.pragma library` line it's plain JS.
const src = readFileSync(join(repo, "common/conf.js"), "utf8").replace(/^\.pragma library$/m, "");
const Conf = new Function(src + "\nreturn { parse, set, remove };")();

const lines = (...l) => l.join("\n");

// ---- parse ----

test("no [enabled] section is null (a read caught mid-save)", () => {
    assert.equal(Conf.parse(""), null);
    assert.equal(Conf.parse("[quote]\nurl = x\n"), null);
});

test("sections, keys and spacing", () => {
    const c = Conf.parse(lines("top = 1", "[enabled]", "  quote=yes", "clock   =   no  ", "[my-sec]", "empty =", ""));
    assert.deepEqual(c[""], { top: "1" });
    assert.deepEqual(c.enabled, { quote: "yes", clock: "no" });
    assert.deepEqual(c["my-sec"], { empty: "" });
});

test("a repeated section adds to the first; a repeated key keeps the last", () => {
    const c = Conf.parse(lines("[enabled]", "a = 1", "[x]", "k = 1", "[enabled]", "b = 2", "a = 3"));
    assert.deepEqual(c.enabled, { a: "3", b: "2" });
});

test("# is a comment at the start of a line or after a space only", () => {
    const c = Conf.parse(lines(
        "[enabled]",
        "# a = yes",
        "  # b = yes",
        "c = yes # comment",
        "d = yes\t# tab before it",
        "url = https://example.com/#top",
        "color = #ff0000",              // after a space: a comment, so empty
        "[s] # comment after a header",
    ));
    assert.deepEqual(c.enabled, { c: "yes", d: "yes", url: "https://example.com/#top", color: "" });
    assert.ok(c.s);
});

test("lines that aren't settings are ignored", () => {
    const c = Conf.parse(lines("[enabled]", "just words", "= no key", "bad key = 1", "[bad section!]", "k = 1"));
    assert.deepEqual(c.enabled, { k: "1" });
});

test("CRLF line endings", () => {
    assert.deepEqual(Conf.parse("[enabled]\r\na = yes  # c\r\n").enabled, { a: "yes" });
});

// ---- set: before -> after ----

const cases = [
    {
        name: "changes the value only",
        before: lines("[enabled]", "quote = yes", ""),
        args: ["enabled", "quote", "no"],
        after: lines("[enabled]", "quote = no", ""),
    },
    {
        name: "a shorter value keeps the comment's column",
        before: lines("[reader]", "font = 24     # size", "pages = 2     # 1 or 2"),
        args: ["reader", "font", "8"],
        after: lines("[reader]", "font = 8      # size", "pages = 2     # 1 or 2"),
    },
    {
        name: "a longer value keeps the comment's column while it fits",
        before: lines("[reader]", "font = 8      # size"),
        args: ["reader", "font", "1200"],
        after: lines("[reader]", "font = 1200   # size"),
    },
    {
        name: "a value longer than the gap leaves one space before the comment",
        before: lines("[q]", "url = a  # source"),
        args: ["q", "url", "https://example.com/quotes.json"],
        after: lines("[q]", "url = https://example.com/quotes.json # source"),
    },
    {
        name: "emptying a value keeps the comment in place",
        before: lines("[q]", "url = abc  # source"),
        args: ["q", "url", ""],
        after: lines("[q]", "url =      # source"),
    },
    {
        name: "filling an empty value with a comment",
        before: lines("[q]", "url =      # source"),
        args: ["q", "url", "abc"],
        after: lines("[q]", "url = abc  # source"),
    },
    {
        name: "filling an empty value without a comment",
        before: lines("[q]", "url ="),
        args: ["q", "url", "abc"],
        after: lines("[q]", "url = abc"),
    },
    {
        name: "a # inside the old value isn't taken for the comment",
        before: lines("[q]", "url = https://a/#x  # source"),
        args: ["q", "url", "https://b/#y"],
        after: lines("[q]", "url = https://b/#y  # source"),
    },
    {
        name: "indentation and spacing around = stay",
        before: lines("[enabled]", "  quote   =  yes"),
        args: ["enabled", "quote", "no"],
        after: lines("[enabled]", "  quote   =  no"),
    },
    {
        name: "the same key in another section isn't touched",
        before: lines("[enabled]", "a = 1", "[x]", "position = top", "[y]", "position = left"),
        args: ["y", "position", "right"],
        after: lines("[enabled]", "a = 1", "[x]", "position = top", "[y]", "position = right"),
    },
    {
        name: "a commented-out line isn't the setting",
        before: lines("[x]", "# font = 10", "font = 12"),
        args: ["x", "font", "14"],
        after: lines("[x]", "# font = 10", "font = 14"),
    },
    {
        name: "a missing key goes after the section's last setting, before blank lines and comments",
        before: lines("[enabled]", "a = yes", "[x]", "k = 1", "j = 2", "", "# next", "[y]", "z = 1"),
        args: ["x", "new", "v"],
        after: lines("[enabled]", "a = yes", "[x]", "k = 1", "j = 2", "new = v", "", "# next", "[y]", "z = 1"),
    },
    {
        name: "a missing key in an empty section goes right after its header",
        before: lines("[enabled]", "[x]", "# only a comment", "[y]"),
        args: ["x", "k", "1"],
        after: lines("[enabled]", "[x]", "k = 1", "# only a comment", "[y]"),
    },
    {
        name: "a missing section is added at the end",
        before: lines("[enabled]", "a = yes", ""),
        args: ["new-sec", "k", "1"],
        after: lines("[enabled]", "a = yes", "", "", "[new-sec]", "k = 1"),
    },
    {
        name: "a number is written as text",
        before: lines("[reader]", "font = 12"),
        args: ["reader", "font", 16],
        after: lines("[reader]", "font = 16"),
    },
];

for (const c of cases) {
    test("set: " + c.name, () => {
        const out = Conf.set(c.before, ...c.args);
        assert.equal(out, c.after);
        // And the shell reads back what was set.
        const [section, key, value] = c.args;
        assert.equal(Conf.parse(out + "\n[enabled]")?.[section]?.[key], String(value));
    });
}

test("set: the same value is null (nothing to write)", () => {
    assert.equal(Conf.set(lines("[enabled]", "a = yes  # c"), "enabled", "a", "yes"), null);
    assert.equal(Conf.set(lines("[q]", "url ="), "q", "url", ""), null);
});

test("set there and back gives the original text", () => {
    const before = lines("[enabled]", "quote = yes   # hourly quote", "[q]", "url = abc  # source", "");
    let t = Conf.set(before, "enabled", "quote", "no");
    t = Conf.set(t, "q", "url", "");
    t = Conf.set(t, "q", "url", "abc");
    t = Conf.set(t, "enabled", "quote", "yes");
    assert.equal(t, before);
});

// ---- remove ----

test("remove: drops the key's line and keeps the rest", () => {
    const before = lines("[enabled]", "a = yes", "[q]", "url = x  # source", "n = 1", "[r]", "n = 2", "");
    assert.equal(Conf.remove(before, "q", "url"), lines("[enabled]", "a = yes", "[q]", "n = 1", "[r]", "n = 2", ""));
});

test("remove: the section header stays when it becomes empty", () => {
    assert.equal(Conf.remove(lines("[enabled]", "a = yes", "[q]", "url = x"), "q", "url"),
                 lines("[enabled]", "a = yes", "[q]"));
});

test("remove: a missing key or section is null", () => {
    const t = lines("[enabled]", "a = yes", "[q]", "url = x");
    assert.equal(Conf.remove(t, "q", "nope"), null);
    assert.equal(Conf.remove(t, "z", "url"), null);
    assert.equal(Conf.remove(t, "enabled", "url"), null);
});

test("remove: a commented-out line isn't the key; a repeated key goes entirely", () => {
    assert.equal(Conf.remove(lines("[q]", "# url = x"), "q", "url"), null);
    assert.equal(Conf.remove(lines("[q]", "url = 1", "[r]", "url = 2", "[q]", "url = 3"), "q", "url"),
                 lines("[q]", "[r]", "url = 2", "[q]"));
});

test("remove, then set, restores the value", () => {
    const t = Conf.remove(lines("[enabled]", "a = yes", "[q]", "n = 1"), "q", "n");
    assert.deepEqual(Conf.parse(Conf.set(t, "q", "n", 1)).q, { n: "1" });
});

// ---- bin/scotchos reads and writes the same file: it must agree with conf.js ----

function withConf(text, fn) {
    const home = mkdtempSync(join(tmpdir(), "scotchos-test-"));
    try {
        mkdirSync(join(home, "scotchos"));
        const file = join(home, "scotchos", "scotchos.conf");
        writeFileSync(file, text);
        // Throws when the command exits non-zero.
        const run = (...args) => execFileSync(join(repo, "bin/scotchos"), args,
            { env: { ...process.env, XDG_CONFIG_HOME: home }, encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] });
        fn(run, () => readFileSync(file, "utf8"));
    } finally {
        rmSync(home, { recursive: true, force: true });
    }
}

test("scotchos get agrees with parse on every setting of scotchos.default.conf", () => {
    const text = readFileSync(join(repo, "scotchos.default.conf"), "utf8");
    const c = Conf.parse(text);
    assert.ok(c, "scotchos.default.conf has an [enabled] section");
    withConf(text, run => {
        for (const [section, keys] of Object.entries(c)) {
            if (!section) continue;
            for (const [key, value] of Object.entries(keys))
                assert.equal(run("get", section, key, "MISSING"), (value || "MISSING") + "\n", `[${section}] ${key}`);
        }
    });
});

test("scotchos get handles comments like parse", () => {
    const text = lines("[enabled]", "a = yes", "[q]", "url = https://a/#x  # source", "color = #fff", "# k = 1", "");
    withConf(text, run => {
        assert.equal(run("get", "q", "url"), "https://a/#x\n");
        assert.equal(run("get", "q", "color", "def"), "def\n");
        assert.equal(run("get", "q", "k", "def"), "def\n");
    });
});

test("scotchos enable/disable change one value and keep the comment and its column", () => {
    const text = lines("[enabled]", "quote = yes   # hourly quote", "clock = no", "[quote]", "quote = keep", "");
    withConf(text, (run, read) => {
        run("disable", "quote");
        assert.equal(read(), lines("[enabled]", "quote = no    # hourly quote", "clock = no", "[quote]", "quote = keep", ""));
        assert.equal(Conf.parse(read()).enabled.quote, "no");
        run("enable", "quote");
        assert.equal(read(), lines("[enabled]", "quote = yes   # hourly quote", "clock = no", "[quote]", "quote = keep", ""));
        run("enable", "clock");
        assert.equal(Conf.parse(read()).enabled.clock, "yes");
        assert.throws(() => run("enable", "nosuch"), "an unknown name fails");
        assert.throws(() => run("enable", "clo.*"), "a pattern isn't a name");
        assert.equal(Conf.parse(read()).quote.quote, "keep");
    });
});
