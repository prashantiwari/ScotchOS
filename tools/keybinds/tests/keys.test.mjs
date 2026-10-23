// tools/keybinds/keys.js: parsing and canonical combos, recorded key names, key cap labels.
// Run: node --test tools/keybinds/tests/   (or `scotchos test`)
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const repo = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
// keys.js is a QML JavaScript library: without its `.pragma library` line it's plain JS.
const src = readFileSync(join(repo, "tools/keybinds/keys.js"), "utf8").replace(/^\.pragma library$/m, "");
const K = new Function(src + "\nreturn { parse, format, canonical, keyName, modsOf, caps };")();

test("parse and format: aliases, order, spacing", () => {
    assert.deepEqual(K.parse("SUPER + CONTROL + left"), { mods: ["SUPER", "CTRL"], key: "left" });
    assert.deepEqual(K.parse("SUPER+ ALT  + F4"), { mods: ["SUPER", "ALT"], key: "F4" });
    assert.deepEqual(K.parse("F10"), { mods: [], key: "F10" });
    assert.equal(K.format(["SHIFT", "SUPER", "CTRL"], "T"), "SUPER + CTRL + SHIFT + T");
});

// The same cases as keybinds.py's canonical(), which the list's `canon` comes from: a clash is found by comparing them.
test("canonical matches keybinds.py", () => {
    assert.equal(K.canonical("SUPER + CONTROL + left"), "CTRL + SUPER + LEFT");
    assert.equal(K.canonical("CTRL+SUPER+Left"), "CTRL + SUPER + LEFT");
    assert.equal(K.canonical("SUPER+ ALT  + F4"), "ALT + SUPER + F4");
    assert.equal(K.canonical("F10"), "F10");
    assert.equal(K.canonical(""), "");
});

test("keyName: letters, digits, F keys, specials, unshifted punctuation, modifiers alone", () => {
    assert.equal(K.keyName(0x41, "a"), "A");
    assert.equal(K.keyName(0x37, "7"), "7");
    assert.equal(K.keyName(0x01000034, ""), "F5");
    assert.equal(K.keyName(0x01000004, "\r"), "Return");
    assert.equal(K.keyName(0x20, " "), "space");
    assert.equal(K.keyName(0x2f, "/"), "slash");
    assert.equal(K.keyName(0x3f, "?"), "slash");       // Shift + /
    assert.equal(K.keyName(0x01000002, ""), "Tab");     // Shift + Tab
    assert.equal(K.keyName(0x01000021, ""), "");        // Ctrl alone
    assert.equal(K.keyName(0x01000053, ""), "");        // Super alone
});

test("modsOf reads Qt's modifier bits", () => {
    assert.deepEqual(K.modsOf(0x04000000 | 0x02000000), ["CTRL", "SHIFT"]);
    assert.deepEqual(K.modsOf(0x10000000), ["SUPER"]);
    assert.deepEqual(K.modsOf(0), []);
});

test("caps: one label per key", () => {
    assert.deepEqual(K.caps("SUPER + CTRL + slash"), ["Super", "Ctrl", "/"]);
    assert.deepEqual(K.caps("SUPER + mouse:272"), ["Super", "Left click"]);
    assert.deepEqual(K.caps("XF86AudioRaiseVolume"), ["AudioRaiseVolume"]);
    assert.deepEqual(K.caps("SUPER + t"), ["Super", "T"]);
    assert.deepEqual(K.caps("SHIFT + RETURN"), ["Shift", "Enter"]);
});
