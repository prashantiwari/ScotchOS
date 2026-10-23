// Key combos for the keybinds window: pure functions (no Quickshell), so tools/keybinds/tests/keys.test.mjs
// runs this same code under node. A combo is Hyprland's Lua spelling, "SUPER + SHIFT + T".
.pragma library

// The order the window writes and shows modifiers in.
const MODS = ["SUPER", "CTRL", "ALT", "SHIFT"];
// Spellings Hyprland treats as the same modifier (as HyDE's binds.lua and keybinds.py).
const ALIASES = { CONTROL: "CTRL", WIN: "SUPER", LOGO: "SUPER", MOD1: "ALT", MOD4: "SUPER" };

// "SUPER + CONTROL + left" -> { mods: ["SUPER", "CTRL"], key: "left" }
function parse(combo) {
    const parts = (combo || "").split("+").map(p => p.trim()).filter(p => p);
    const key = parts.pop() || "";
    const mods = [];
    for (const p of parts) {
        const m = ALIASES[p.toUpperCase()] || p.toUpperCase();
        if (!mods.includes(m)) mods.push(m);
    }
    return { mods, key };
}

// { mods, key } back to a combo, modifiers in MODS order (others after them).
function format(mods, key) {
    const known = MODS.filter(m => mods.includes(m));
    return known.concat(mods.filter(m => !MODS.includes(m)), [key]).join(" + ");
}

// What Hyprland matches on: modifiers as a set, the key without case. "CTRL + SUPER + LEFT".
function canonical(combo) {
    const { mods, key } = parse(combo);
    if (!key) return "";
    return mods.slice().sort().concat([key.toUpperCase()]).join(" + ");
}

// ---- Recording a key press ----
// Qt key codes (Qt.Key_*) of keys that don't type a character, to xkb names.
const SPECIAL = {
    0x01000000: "Escape", 0x01000001: "Tab", 0x01000002: "Tab", 0x01000003: "BackSpace", 0x01000004: "Return",
    0x01000005: "KP_Enter", 0x01000006: "Insert", 0x01000007: "Delete", 0x01000008: "Pause", 0x01000009: "Print",
    0x01000010: "Home", 0x01000011: "End", 0x01000012: "Left", 0x01000013: "Up", 0x01000014: "Right",
    0x01000015: "Down", 0x01000016: "Prior", 0x01000017: "Next", 0x20: "space",
};
// Modifier keys on their own: not a key to bind.
const MODIFIER_KEYS = [0x01000020, 0x01000021, 0x01000022, 0x01000023, 0x01000024, 0x01000025, 0x01000053,
                       0x01000054, 0x01001103];
// Hyprland matches the key as it is without Shift, so Shift + / is SHIFT + slash, not "question" (US layout).
const UNSHIFTED = { "!": "1", "@": "2", "#": "3", "$": "4", "%": "5", "^": "6", "&": "7", "*": "8", "(": "9",
                    ")": "0", "_": "-", "+": "=", "{": "[", "}": "]", "|": "\\", ":": ";", "\"": "'", "<": ",",
                    ">": ".", "?": "/", "~": "`" };
const PUNCT = { "-": "minus", "=": "equal", "[": "bracketleft", "]": "bracketright", "\\": "backslash",
                ";": "semicolon", "'": "apostrophe", ",": "comma", ".": "period", "/": "slash", "`": "grave" };

// The xkb key name for a Qt key press, "" for a modifier alone or a key it doesn't know.
function keyName(qtKey, text) {
    if (MODIFIER_KEYS.includes(qtKey)) return "";
    if (SPECIAL[qtKey]) return SPECIAL[qtKey];
    if (qtKey >= 0x01000030 && qtKey <= 0x01000052) return "F" + (qtKey - 0x01000030 + 1);
    if ((qtKey >= 0x41 && qtKey <= 0x5a) || (qtKey >= 0x30 && qtKey <= 0x39)) return String.fromCharCode(qtKey);
    let ch = qtKey > 0x20 && qtKey < 0x7f ? String.fromCharCode(qtKey) : (text || "");
    ch = UNSHIFTED[ch] || ch;
    return PUNCT[ch] || "";
}

// Modifiers held in a Qt key event (event.modifiers), as names.
function modsOf(qtModifiers) {
    const out = [];
    if (qtModifiers & 0x10000000) out.push("SUPER");     // Qt.MetaModifier
    if (qtModifiers & 0x04000000) out.push("CTRL");
    if (qtModifiers & 0x08000000) out.push("ALT");
    if (qtModifiers & 0x02000000) out.push("SHIFT");
    return out;
}

// ---- Showing a combo ----
const LABELS = {
    SUPER: "Super", CTRL: "Ctrl", ALT: "Alt", SHIFT: "Shift", RETURN: "Enter", SPACE: "Space", ESCAPE: "Esc",
    TAB: "Tab", DELETE: "Del", BACKSPACE: "Backspace", PRIOR: "PgUp", NEXT: "PgDn", LEFT: "←", RIGHT: "→",
    UP: "↑", DOWN: "↓", "MOUSE:272": "Left click", "MOUSE:273": "Right click", "MOUSE:274": "Middle click",
    MOUSE_DOWN: "Wheel ↓", MOUSE_UP: "Wheel ↑", PRINT: "Print",
};
// "SLASH" -> "/" (built by hand: QML's JavaScript has no Object.fromEntries).
const PUNCT_LABEL = {};
for (const ch in PUNCT) PUNCT_LABEL[PUNCT[ch].toUpperCase()] = ch;

// One label per part, for the key caps: "SUPER + slash" -> ["Super", "/"].
function caps(combo) {
    const { mods, key } = parse(combo);
    const k = key.toUpperCase();
    const label = LABELS[k] || PUNCT_LABEL[k] || (k.startsWith("XF86") ? key.slice(4) : key.length === 1 ? k : key);
    return mods.map(m => LABELS[m] || m).concat(key ? [label] : []);
}
