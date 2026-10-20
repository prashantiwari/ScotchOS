// tools/launcher/score.js: matching, initials, and the launch-count bonus.
// Run: node --test tools/launcher/tests/   (or `scotchos test`)
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const repo = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
// score.js is a QML JavaScript library: without its `.pragma library` line it's plain JS.
const src = readFileSync(join(repo, "tools/launcher/score.js"), "utf8").replace(/^\.pragma library$/m, "");
const S = new Function(src + "\nreturn { execBasename, initials, score, rank };")();

const app = (id, name, exec = id, extra = {}) => ({ id, name, exec, genericName: "", keywords: [], ...extra });
const vscode = app("code", "Visual Studio Code", "/usr/bin/code --unity-launch %F");
const libre = app("libreoffice-writer", "LibreOffice Writer", "libreoffice --writer %U");
const firefox = app("firefox", "Firefox", "env MOZ_ENABLE_WAYLAND=1 firefox %u", { genericName: "Web Browser" });
const names = list => list.map(a => a.name);

test("execBasename drops env, VAR=value, flags, the path and field codes", () => {
    assert.equal(S.execBasename("/usr/bin/code --unity-launch %F"), "code");
    assert.equal(S.execBasename("env MOZ_ENABLE_WAYLAND=1 firefox %u"), "firefox");
    assert.equal(S.execBasename("env LANG=C /opt/App/Run"), "run");
    assert.equal(S.execBasename('"/opt/bin/tool" %U'), "tool");
    assert.equal(S.execBasename(""), "");
});

test("initials: words and camelCase", () => {
    assert.equal(S.initials("Visual Studio Code"), "vsc");
    assert.equal(S.initials("LibreOffice"), "lo");
    assert.equal(S.initials("GNU Image Manipulation Program"), "gimp");
    assert.equal(S.initials("qBittorrent"), "qb");
    assert.equal(S.initials("Files"), "f");
});

test("initials and command find an app", () => {
    assert.deepEqual(names(S.rank("vsc", [firefox, vscode, libre], {}, 8)), ["Visual Studio Code"]);
    assert.deepEqual(names(S.rank("lo", [firefox, vscode, libre], {}, 8)), ["LibreOffice Writer"]);
    assert.deepEqual(names(S.rank("code", [firefox, libre, vscode], {}, 8)), ["Visual Studio Code"]);
    assert.deepEqual(names(S.rank("browser", [vscode, firefox], {}, 8)), ["Firefox"]);
    assert.deepEqual(S.rank("zzz", [vscode, firefox], {}, 8), []);
});

test("name prefix > contains > initials > command > generic name", () => {
    const apps = [
        app("a", "Zed", "tools", { genericName: "Editor tools" }),   // generic only ("tools" is also its command)
        app("b", "Other", "stu"),                                      // command contains "stu"
        app("c", "Super Tool Unit"),                                   // initials "stu"
        app("d", "Mystuff"),                                           // name contains
        app("e", "Stuff"),                                             // name prefix
    ];
    assert.deepEqual(names(S.rank("stu", apps, {}, 8)), ["Stuff", "Mystuff", "Super Tool Unit", "Other"]);
});

test("a single letter is a prefix or substring, not initials", () => {
    assert.deepEqual(names(S.rank("v", [vscode, firefox], {}, 8)), ["Visual Studio Code"]);
});

test("launch counts reorder equal matches", () => {
    const a = app("a", "Editor One"), b = app("b", "Editor Two");
    assert.deepEqual(names(S.rank("edit", [a, b], {}, 8)), ["Editor One", "Editor Two"]);
    assert.deepEqual(names(S.rank("edit", [a, b], { b: 3 }, 8)), ["Editor Two", "Editor One"]);
});

test("a heavily launched bad match never beats a good one", () => {
    const good = app("good", "Terminal");
    const bad = app("bad", "Other", "x", { genericName: "A terminal emulator" });
    assert.deepEqual(names(S.rank("term", [bad, good], { bad: 100000 }, 8)), ["Terminal", "Other"]);
    const contains = app("c", "My Terminal");
    assert.deepEqual(names(S.rank("term", [contains, good], { c: 100000 }, 8)), ["Terminal", "My Terminal"]);
    const initial = app("i", "Tiny Editor Robot Machine");
    assert.deepEqual(names(S.rank("term", [initial, contains], { i: 100000 }, 8)).slice(0, 1), ["My Terminal"]);
});

test("empty query: most launched first, then by name", () => {
    const apps = [app("c", "Cat"), app("a", "Ant"), app("b", "Bee")];
    assert.deepEqual(names(S.rank("", apps, { b: 5, c: 5, a: 1 }, 8)), ["Bee", "Cat", "Ant"]);
    assert.deepEqual(names(S.rank("  ", apps, {}, 8)), ["Ant", "Bee", "Cat"]);
});

test("limit cuts the list", () => {
    const apps = [app("a", "Ant"), app("b", "Bee"), app("c", "Cat")];
    assert.equal(S.rank("", apps, {}, 2).length, 2);
});
