// tools/eReader/dict.js: the selected word, the forms tried in WordNet, and sdcv's output made into senses.
// Run: node --test tools/eReader/tests/   (or `scotchos test`). The sdcv text below is copied from
// `sdcv -n -j -e -u WordNet` (stardict-wordnet 2.4.2), cut short; sdcv itself isn't needed.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const repo = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
// dict.js is a QML JavaScript library: without its `.pragma library` line it's plain JS.
const src = readFileSync(join(repo, "tools/eReader/dict.js"), "utf8").replace(/^\.pragma library$/m, "");
const D = new Function(src + "\nreturn { wordOf, forms, parse, lookup };")();

const entry = (word, definition) => JSON.stringify([{ dict: "WordNet", word, definition }]);

const has = "\nhas\n     See {have}\n\nhave\n     v 1: have or possess, either in a concrete or an abstract sense;\n"
    + "          \"She has $1,000 in the bank\"; \"He has got two beautiful\n          daughters\"\n"
    + "          [syn: {have got}, {hold}]\n     2: have as a feature; \"This restaurant features the most famous\n"
    + "        chefs in France\" [syn: {feature}] [ant: {miss}]";
const running = "\nrun\n     n 1: a score in baseball made by a runner touching all four bases\n"
    + "          safely; \"the Yankees scored 3 runs\" [syn: {tally}]\n"
    + "     [also: {running}, {ran}]\n\nrunning\n     adj 1: moving quickly on foot; \"heard running footsteps\n"
    + "            behind him\"\n     2: (of fluids) moving or issuing in a stream\n\nrun\n"
    + "     v 1: move fast by using one's feet [syn: {running}, {scarper}]";
const well = "\nwell\n     adj 1: resulting favorably; \"all's well that ends well\" [syn: {good},\n"
    + "            {well(p)}]\n     [also: {better}, {best}]";
const thereby = "\nthereby\n     adv : by that means or because of that; \"He knocked over the red\n"
    + "           wine, thereby ruining the table cloth\"";

test("wordOf: one word, with curly or inner apostrophes and hyphens", () => {
    assert.equal(D.wordOf(" running "), "running");
    assert.equal(D.wordOf("Darcy’s"), "Darcy's");
    assert.equal(D.wordOf("dogs'"), "dogs'");
    assert.equal(D.wordOf("well-known"), "well-known");
    assert.equal(D.wordOf("o'clock"), "o'clock");
    assert.equal(D.wordOf("café"), "café");
    assert.equal(D.wordOf("run⁠"), "run");          // an anchor marker inside the selection
    assert.equal(D.wordOf("two words"), "");
    assert.equal(D.wordOf("1984"), "");
    assert.equal(D.wordOf("end."), "");
    assert.equal(D.wordOf("-ish"), "");
    assert.equal(D.wordOf(""), "");
    assert.equal(D.wordOf("a".repeat(41)), "");
});

test("forms: as written first, then lower-case, then endings off", () => {
    assert.deepEqual(D.forms("Darcy's"), ["Darcy's", "Darcy", "darcy's", "darcy"]);
    assert.deepEqual(D.forms("Happily"), ["Happily", "happily"]);
    assert.ok(D.forms("cats").includes("cat"));
    assert.ok(D.forms("studies").indexOf("study") < D.forms("studies").indexOf("studie"));
    assert.ok(D.forms("hoped").indexOf("hope") < D.forms("hoped").indexOf("hop"));
    assert.ok(D.forms("hopped").includes("hop"));        // the doubled consonant
    assert.ok(D.forms("bigger").includes("big"));
    assert.ok(D.forms("watches").includes("watch"));
    assert.ok(D.forms("is").every(f => f.length > 1));   // no one-letter stems
});

test("parse: senses, examples and synonyms; See sections and [also] left out", () => {
    const e = D.parse(has);
    assert.equal(e.length, 1);
    assert.equal(e[0].head, "have");
    assert.equal(e[0].pos, "verb");
    assert.deepEqual(e[0].senses[0], {
        gloss: "have or possess, either in a concrete or an abstract sense",
        examples: ["She has $1,000 in the bank", "He has got two beautiful daughters"],
        syns: ["have got", "hold"],
    });
    assert.deepEqual(e[0].senses[1].syns, ["feature"]);     // [ant: …] isn't a synonym

    const r = D.parse(running);
    assert.deepEqual(r.map(x => x.head + " " + x.pos), ["run noun", "running adjective", "run verb"]);
    assert.equal(r[0].senses.length, 1);                    // [also: …] didn't join the sense
    assert.equal(r[0].senses[0].gloss, "a score in baseball made by a runner touching all four bases safely");
    assert.equal(r[1].senses[1].gloss, "(of fluids) moving or issuing in a stream");
    assert.deepEqual(r[1].senses[1].examples, []);
});

test("parse: position marks off synonyms, the headword not among them, `adv :` with no number", () => {
    assert.deepEqual(D.parse(well)[0].senses[0].syns, ["good"]);
    const t = D.parse(thereby);
    assert.equal(t[0].pos, "adverb");
    assert.deepEqual(t[0].senses[0].examples, ["He knocked over the red wine, thereby ruining the table cloth"]);
});

test("lookup: the first form found wins, its own entries first", () => {
    const out = ["[]", entry("running", running), entry("run", running)].join("\n");
    const r = D.lookup("Running", out);
    assert.equal(r.word, "Running");
    assert.equal(r.head, "running");
    assert.deepEqual(r.entries.map(x => x.head + " " + x.pos), ["running adjective", "run noun", "run verb"]);

    const h = D.lookup("has", entry("has", has) + "\n[]\n");
    assert.equal(h.head, "have");                         // found as "has", shown as → have
});

test("lookup: nothing found, or output that isn't sdcv's", () => {
    assert.equal(D.lookup("xyzzy", "[]\n[]\n"), null);
    assert.equal(D.lookup("xyzzy", ""), null);
    assert.equal(D.lookup("xyzzy", "There are no words/phrases to translate.\n"), null);
    assert.equal(D.lookup("has", entry("has", "\nhas\n     See {have}")), null);
});
