#!/usr/bin/env python3
"""Hyprland keybinds for the ScotchOS keybinds window.

  keybinds.py list           the live binds (hyprctl binds -j), each with the hl.bind line it comes from, as JSON
  keybinds.py apply <json>   save the edits ({"binds": [...]}) to keybinds.json, regenerate scotchos-binds.lua,
                             reload Hyprland; rolled back if the reload reports new config errors

Your edits live in ~/.config/scotchos/keybinds.json; ~/.config/hypr/scotchos-binds.lua is generated from it
and loaded last by hyprland.lua, so it overrides HyDE's binds and your own.
"""
import json
import os
import re
import subprocess
import sys

HOME = os.path.expanduser("~")
CONFIG = os.environ.get("XDG_CONFIG_HOME") or os.path.join(HOME, ".config")
SHARE = os.environ.get("XDG_DATA_HOME") or os.path.join(HOME, ".local", "share")
EDITS = os.path.join(CONFIG, "scotchos", "keybinds.json")
GENERATED = os.path.join(CONFIG, "hypr", "scotchos-binds.lua")
USER_LUA = os.path.join(CONFIG, "hypr", "hyprland.lua")
HYDE_LUA = os.path.join(SHARE, "hypr", "lua", "key_binds.lua")
# The marker the loader lines in hyprland.lua carry; without them the edits would be written but never loaded.
LOADER = "scotchos-binds.lua"

def read(path):
    """A file's text, or None when it can't be read."""
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError:
        return None


# ---- Key combos ----
# hyprctl's modmask bits, in the order the window shows them.
MOD_BITS = [(64, "SUPER"), (4, "CTRL"), (8, "ALT"), (1, "SHIFT"), (2, "CAPS"), (16, "MOD2"), (32, "MOD3"), (128, "MOD5")]
# Spellings Hyprland treats as the same modifier (HyDE's binds.lua has the same table).
ALIASES = {"CONTROL": "CTRL", "WIN": "SUPER", "LOGO": "SUPER", "MOD1": "ALT", "MOD4": "SUPER"}
MOD_NAMES = {name for _, name in MOD_BITS}


def canonical(combo):
    """'SUPER + CONTROL + left' -> 'CTRL + SUPER + LEFT': what Hyprland matches on (as HyDE's canonicalize)."""
    parts = [p.strip() for p in combo.split("+")]
    parts = [p for p in parts if p]
    if not parts:
        return ""
    key = parts.pop().upper()
    mods = sorted({ALIASES.get(p.upper(), p.upper()) for p in parts})
    return " + ".join(mods + [key])


def combo_of(bind):
    """A hyprctl bind's modmask and key as 'SUPER + SHIFT + T'."""
    mods = [name for bit, name in MOD_BITS if bind.get("modmask", 0) & bit]
    key = bind.get("key") or ("code:%d" % bind["keycode"] if bind.get("keycode") else "")
    return " + ".join(mods + [key])


def split_description(text):
    """'[Launcher|Apps] terminal emulator' -> ('Launcher|Apps', 'terminal emulator')."""
    m = re.match(r"^\s*\[([^\]]*)\]\s*(.*)$", text or "")
    return (m.group(1).strip(), m.group(2).strip()) if m else ("", (text or "").strip())


# ---- Reading hl.bind calls out of Lua source ----
def strip_comments(src):
    """The source with comments blanked out (same length and lines, so offsets and line numbers still match)."""
    out, i, n = [], 0, len(src)
    while i < n:
        c = src[i]
        if c in "\"'":
            j = i + 1
            while j < n and src[j] != c and src[j] != "\n":
                j += 2 if src[j] == "\\" else 1
            out.append(src[i:j + 1])
            i = j + 1
        elif src.startswith("--", i):
            m = re.match(r"--\[(=*)\[", src[i:i + 64])
            close = "]" + m.group(1) + "]" if m else "\n"
            j = src.find(close, i)
            end = n if j < 0 else j + (len(close) if m else 0)
            out.append(re.sub(r"[^\n]", " ", src[i:end]))
            i = end
        else:
            out.append(c)
            i += 1
    return "".join(out)


def balanced(src, start):
    """From the '(' or '{' at start, the index just past its match (strings skipped), or -1."""
    pairs = {"(": ")", "{": "}", "[": "]"}
    stack, i = [], start
    while i < len(src):
        c = src[i]
        if c in "\"'":
            j = i + 1
            while j < len(src) and src[j] != c:
                j += 2 if src[j] == "\\" else 1
            i = j + 1
            continue
        if c in pairs:
            stack.append(pairs[c])
        elif stack and c == stack[-1]:
            stack.pop()
            if not stack:
                return i + 1
        i += 1
    return -1


def split_args(text):
    """Top-level comma-separated parts of an argument list."""
    parts, depth, cur, i = [], 0, [], 0
    while i < len(text):
        c = text[i]
        if c in "\"'":
            j = i + 1
            while j < len(text) and text[j] != c:
                j += 2 if text[j] == "\\" else 1
            cur.append(text[i:j + 1])
            i = j + 1
            continue
        if c in "({[":
            depth += 1
        elif c in ")}]":
            depth -= 1
        if c == "," and depth == 0:
            parts.append("".join(cur).strip())
            cur = []
        else:
            cur.append(c)
        i += 1
    if "".join(cur).strip():
        parts.append("".join(cur).strip())
    return parts


STRING = r'"(?:[^"\\]|\\.)*"|\'(?:[^\'\\]|\\.)*\''


def unquote(s):
    return re.sub(r"\\(.)", r"\1", s[1:-1])


def concat(expr, names):
    """A Lua concatenation of strings and known names ('MOD .. " + T"'), or None when a part is unknown (a loop's i)."""
    out = []
    for part in re.split(r"\s*\.\.\s*", expr.strip()):
        if re.fullmatch(STRING, part):
            out.append(unquote(part))
        elif part in names and isinstance(names[part], str):
            out.append(names[part])
        else:
            return None
    return "".join(out)


def options(table, names):
    """'{description = "...", locked = true}' -> {'description': ..., 'locked': True}; None when it isn't a table."""
    table = table.strip()
    if not (table.startswith("{") and table.endswith("}")):
        return None
    out = {}
    for part in split_args(table[1:-1]):
        m = re.match(r"^(\w+)\s*=\s*(.+)$", part, re.S)
        if not m:
            continue
        k, v = m.group(1), m.group(2).strip()
        if v in ("true", "false"):
            out[k] = v == "true"
        elif re.fullmatch(r"-?\d+", v):
            out[k] = int(v)
        else:
            s = concat(v, names)
            # A description built from a loop variable: keep the fixed start, for matching by prefix.
            if s is None and k == "description":
                head = re.match(r"^(%s)\s*\.\.\s*(.+)$" % STRING, v, re.S)
                if head:
                    out["description_prefix"] = unquote(head.group(1))
                    out["description_tail"] = head.group(2).strip()
            elif s is not None:
                out[k] = s
    return out


# Names a bind's action may use and still mean the same thing when copied into scotchos-binds.lua.
GLOBALS = {"hl", "hyde", "os", "string", "tostring", "tonumber", "math", "true", "false", "nil", "and", "or", "not"}


def portable(expr, aliases):
    """The action with the file's local aliases (MOD, _apps) spelled out, or None if it uses other locals."""
    code = strip_comments(expr)
    out, i = [], 0
    for m in re.finditer(r"%s|[A-Za-z_]\w*" % STRING, code):
        tok = m.group(0)
        prev = code[:m.start()].rstrip()[-1:]
        after = code[m.end():].lstrip()[:1]
        if tok[0] in "\"'" or prev in (".", ":") or (after == "=" and code[m.end():].lstrip()[:2] != "=="):
            continue
        out.append(code[i:m.start()])
        if tok in aliases:
            out.append(aliases[tok])
        elif tok in GLOBALS:
            out.append(tok)
        else:
            return None
        i = m.end()
    out.append(code[i:])
    return "".join(out)


def scan(path, main_mod="SUPER"):
    """Every hl.bind(...) in a Lua file: combo, action text, options, line, and the action made portable (or None)."""
    src = read(path)
    if src is None:
        return []
    code = strip_comments(src)
    # `local MOD = hyde.config.modifiers.main` and the like: values for combos, and spellings for portable actions.
    names, aliases = {}, {}
    for m in re.finditer(r"^\s*local\s+(\w+)\s*=\s*([^\n]+?)\s*$", code, re.M):
        name, value = m.group(1), m.group(2)
        if re.fullmatch(STRING, value):
            names[name] = unquote(value)
        elif re.fullmatch(r"hyde(\.\w+)+", value):
            aliases[name] = value
            if value == "hyde.config.modifiers.main":
                names[name] = main_mod
    # Options tables assigned to a variable before the bind (key_binds.lua's `_F = {...}`), by position.
    tables = []
    for m in re.finditer(r"\b(\w+)\s*=\s*\{", code):
        end = balanced(code, m.end() - 1)
        if end > 0:
            tables.append((m.start(), m.group(1), code[m.end() - 1:end]))
    out = []
    for m in re.finditer(r"\bhl\.bind\s*\(", code):
        end = balanced(code, m.end() - 1)
        if end < 0:
            continue
        args = split_args(code[m.end():end - 1])
        if len(args) < 2:
            continue
        opts_text = args[2] if len(args) > 2 else "{}"
        if re.fullmatch(r"\w+", opts_text):
            last = [t for t in tables if t[1] == opts_text and t[0] < m.start()]
            opts_text = last[-1][2] if last else "{}"
        opts = options(opts_text, names) or {}
        combo = concat(args[0], names)
        # Inside `for i = 1, 10 do`: the loop, so one bind's `i` can be worked out from its description.
        loop = None
        head = [h for h in re.finditer(r"\bfor\s+(\w+)\s*=\s*(-?\d+)\s*,\s*(-?\d+)\s+do\b", code[:m.start()])]
        if head and "end" not in re.findall(r"\w+", code[head[-1].end():m.start()]):
            h = head[-1]
            loop = {"var": h.group(1), "from": int(h.group(2)), "to": int(h.group(3))}
        out.append({
            "combo": combo,
            "canon": canonical(combo) if combo else None,
            "action": args[1].strip(),
            "lua": portable(args[1], aliases),
            "aliases": aliases,
            "loop": loop,
            "opts": opts,
            "line": src.count("\n", 0, m.start()) + 1,
            "file": path,
        })
    return out


def substitute(expr, var, value):
    """expr with the name `var` (not a field or a table key) replaced by a number."""
    def rep(m):
        tok = m.group(0)
        if tok != var or expr[:m.start()].rstrip()[-1:] in (".", ":") or re.match(r"\s*=(?!=)", expr[m.end():]):
            return tok
        return str(value)
    return re.sub(r"%s|[A-Za-z_]\w*" % STRING, rep, expr)


def loop_instance(source, description):
    """For a bind made in a numeric loop: (i, the action with i filled in), from a description like
    '<prefix> .. i' or '<prefix> .. (i + 10)' and the live description's number. None if it doesn't fit."""
    opts, loop = source["opts"], source["loop"]
    prefix, tail = opts.get("description_prefix"), opts.get("description_tail", "")
    if not loop or prefix is None or not description.startswith(prefix):
        return None
    n = description[len(prefix):].strip()
    m = re.fullmatch(r"\(?\s*%s\s*(?:([+-])\s*(\d+))?\s*\)?" % re.escape(loop["var"]), tail)
    if not m or not re.fullmatch(r"-?\d+", n):
        return None
    i = int(n) - (int(m.group(2)) * (1 if m.group(1) == "+" else -1) if m.group(2) else 0)
    if not loop["from"] <= i <= loop["to"]:
        return None
    return i, substitute(source["action"], loop["var"], i)


# ---- Edits: keybinds.json -> scotchos-binds.lua ----
# Option names that are bind flags in Lua (hl.bind's table) and the window can switch.
FLAGS = ["locked", "repeating", "release", "long_press", "non_consuming", "transparent", "ignore_mods", "mouse"]
COMBO = re.compile(r"^[A-Za-z0-9_:]+( *\+ *[A-Za-z0-9_:]+)*$")


def lua_string(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def check(edit):
    """Why an edit can't be written, or None."""
    if not COMBO.match(edit.get("combo", "").strip()):
        return "'%s' isn't a key combo (like SUPER + SHIFT + T)" % edit.get("combo", "")
    if edit.get("was") and not COMBO.match(edit["was"].strip()):
        return "'%s' isn't a key combo" % edit["was"]
    if canonical(edit["combo"]).split(" + ")[-1] in MOD_NAMES:
        return "%s has no key besides the modifiers" % edit["combo"]
    if not edit.get("off") and not (edit.get("exec") or "").strip() and not (edit.get("lua") or "").strip():
        return "%s: no command or action" % edit["combo"]
    return None


def generate(edits):
    """The Lua for scotchos-binds.lua. Every unbind comes before every bind, so a bind moved onto a combo that
    another edit frees isn't removed again by that edit."""
    lines = [
        "-- Written by the ScotchOS keybinds window (Super + Ctrl + /) from ~/.config/scotchos/keybinds.json.",
        "-- Saving there rewrites this file: change the binds in the window, or in keybinds.json.",
        "-- hyprland.lua loads it last, so it overrides HyDE's binds and the ones in hyprland.lua.",
        "",
        "-- HyDE's bind wrapper keeps the exact string each live bind was registered with, and hl.unbind",
        "-- matches that string, so look it up by the canonical combo (every flag variant goes).",
        "local function unbind(combo)",
        "\tlocal active = hyde and hyde.binds and hyde.binds._active",
        "\tif not active then",
        "\t\thl.unbind(combo)",
        "\t\treturn",
        "\tend",
        "\tlocal id = hyde.binds.canonicalize(combo)",
        "\tfor key, registered in pairs(active) do",
        "\t\tif key == id or key:sub(1, #id + 1) == id .. \"|\" then",
        "\t\t\thl.unbind(registered)",
        "\t\t\tactive[key] = nil",
        "\t\tend",
        "\tend",
        "end",
        "",
    ]
    freed = []
    for e in edits:
        for c in (e.get("was"), e["combo"]):
            if c and canonical(c) not in [canonical(f) for f in freed]:
                freed.append(c.strip())
    if freed:
        lines.append("-- Free every combo an edit touches: the old place of a moved or switched-off bind, and the new one.")
        lines += ["unbind(%s)" % lua_string(c) for c in freed]
        lines.append("")
    for e in edits:
        if e.get("off"):
            continue
        action = e["lua"].strip() if (e.get("lua") or "").strip() else "hl.dsp.exec_cmd(%s)" % lua_string(e["exec"].strip())
        opts = ["description = %s" % lua_string(e.get("description", "").strip())]
        opts += ["%s = %s" % (f, "true" if v else "false") for f, v in sorted((e.get("flags") or {}).items())
                 if f in FLAGS and v]
        lines.append("hl.bind(%s, %s, { %s })" % (lua_string(e["combo"].strip()), action, ", ".join(opts)))
    return "\n".join(lines).rstrip() + "\n"


def read_edits():
    try:
        with open(EDITS, encoding="utf-8") as f:
            data = json.load(f)
        return data.get("binds", []) if isinstance(data, dict) else []
    except (OSError, ValueError):
        return []


def write(path, text):
    """Atomic: a reload in the middle of a save never sees half a file."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path + ".tmp", "w", encoding="utf-8") as f:
        f.write(text)
    os.replace(path + ".tmp", path)


def hyprctl(*args):
    try:
        return subprocess.run(["hyprctl", *args], capture_output=True, text=True, timeout=10).stdout
    except (OSError, subprocess.TimeoutExpired):
        return ""


def config_errors():
    try:
        return [e for e in json.loads(hyprctl("configerrors", "-j") or "[]") if e.strip()]
    except ValueError:
        return []


def wired():
    return LOADER in (read(USER_LUA) or "")


def apply(edits):
    """Saves the edits and reloads; on new config errors puts both files back and reloads again."""
    for e in edits:
        why = check(e)
        if why:
            return {"ok": False, "error": why}
    if not wired():
        return {"ok": False, "error": "hyprland.lua doesn't load %s (see tools/keybinds/README.md)" % LOADER}
    old = {p: read(p) for p in (EDITS, GENERATED)}
    before = set(config_errors())
    write(EDITS, json.dumps({"binds": edits}, indent=2) + "\n")
    write(GENERATED, generate(edits))
    hyprctl("reload")
    new = [e for e in config_errors() if e not in before]
    if new:
        for p, text in old.items():
            if text is None:
                os.remove(p)
            else:
                write(p, text)
        hyprctl("reload")
        return {"ok": False, "error": "Hyprland didn't take it, nothing changed:\n" + "\n".join(new)}
    return {"ok": True}


# ---- The list the window shows ----
def main_modifier():
    m = re.search(r'modifiers\.main\s*=\s*"(\w+)"', read(os.path.join(SHARE, "hypr", "lua", "variables.lua")) or "")
    return m.group(1) if m else "SUPER"


def listing(live, sources, edits):
    """The window's rows: every live bind with its source, then the switched-off ones (from the edits)."""
    by_canon = {}
    prefixed = []
    # Later files win, like the binds themselves: hyprland.lua over key_binds.lua.
    for s in sources:
        if s["canon"]:
            by_canon.setdefault(s["canon"], []).append(s)
        elif s["opts"].get("description_prefix"):
            prefixed.append(s)
    edit_at = {canonical(e["combo"]): i for i, e in enumerate(edits) if not e.get("off")}
    rows = []
    for b in live:
        combo = combo_of(b)
        canon = canonical(combo)
        group, text = split_description(b.get("description", ""))
        row = {
            "combo": combo, "canon": canon, "group": group, "text": text,
            "description": b.get("description", ""), "submap": b.get("submap", ""), "mouse": b.get("mouse", False),
            "flags": {"locked": b.get("locked", False), "repeating": b.get("repeat", False),
                      "release": b.get("release", False), "long_press": b.get("longPress", False),
                      "non_consuming": b.get("non_consuming", False), "mouse": b.get("mouse", False)},
            "origin": "", "file": "", "line": 0, "action": "", "lua": None, "edit": -1,
        }
        if canon in edit_at:
            e = edits[edit_at[canon]]
            row.update(origin="scotchos", file=GENERATED, edit=edit_at[canon],
                       action=e.get("lua") or e.get("exec", ""), lua=e.get("lua") or None)
            row["flags"].update(e.get("flags") or {})
        else:
            cands = [s for s in by_canon.get(canon, [])]
            match = [s for s in cands if s["opts"].get("description", "") == b.get("description", "")] or cands[-1:]
            action, lua = None, None
            if not match:
                # Made in a loop: the loop whose range fits the description's number (SUPER + 3 vs SUPER + KP_3).
                for s in prefixed:
                    inst = loop_instance(s, b.get("description", ""))
                    if inst:
                        match, action = [s], inst[1]
                        lua = portable(action, s["aliases"])
            if match:
                s = match[-1]
                if action is None:
                    action, lua = s["action"], s["lua"] if s["canon"] else None
                row.update(origin="user" if s["file"] == USER_LUA else "hyde", file=s["file"], line=s["line"],
                           action=action, lua=lua)
                # transparent and a few more aren't in hyprctl's output; the source has them.
                row["flags"].update({k: v for k, v in s["opts"].items() if k in FLAGS})
        rows.append(row)
    for i, e in enumerate(edits):
        if not e.get("off"):
            continue
        group, text = split_description(e.get("description", ""))
        rows.append({
            "combo": e["combo"], "canon": canonical(e["combo"]), "group": group, "text": text,
            "description": e.get("description", ""), "submap": "", "mouse": False, "flags": e.get("flags") or {},
            "origin": "off", "file": GENERATED, "line": 0, "action": e.get("action", ""), "lua": None, "edit": i,
        })
    return rows


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "list":
        try:
            live = json.loads(hyprctl("binds", "-j") or "[]")
        except ValueError:
            live = []
        mod = main_modifier()
        sources = scan(HYDE_LUA, mod) + scan(USER_LUA, mod)
        edits = read_edits()
        print(json.dumps({"binds": listing(live, sources, edits), "edits": edits, "wired": wired(),
                          "errors": config_errors(), "generated": GENERATED, "editsPath": EDITS}))
    elif cmd == "apply" and len(sys.argv) > 2:
        try:
            edits = json.loads(sys.argv[2]).get("binds", [])
        except (ValueError, AttributeError):
            print(json.dumps({"ok": False, "error": "not JSON"}))
            return 1
        print(json.dumps(apply(edits)))
    else:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
