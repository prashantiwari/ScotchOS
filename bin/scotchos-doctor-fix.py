#!/usr/bin/env python3
"""Conf part of `scotchos doctor --fix`: adds the [enabled] line and the [section] a widget or tool lacks.

Usage: scotchos-doctor-fix.py (--check | --fix) <repo> <live conf or ""> < "key=folder" lines
Only conf files are touched (the repo's scotchos.default.conf and the live one), never code or READMEs.
--check prints what --fix would add and changes nothing.
"""
import os
import re
import sys
from collections import Counter

mode, repo, live = sys.argv[1:4]
folders = dict(l.strip().split("=", 1) for l in sys.stdin if "=" in l)


def settings_window():
    """key -> (kind, [(setting key, default)]) from the items list of the settings window."""
    items, cur = {}, None
    for line in open(os.path.join(repo, "settings/SettingsWindow.qml")):
        m = re.search(r'\{ *key: "([^"]+)",[^}]*kind: "(widget|tool)"', line)
        if m:
            cur = m.group(1)
            items[cur] = (m.group(2), [])
            continue
        m = re.search(r'\{ *key: "([^"]+)",.*\bdef: ("(?:[^"\\]|\\.)*"|[\w.-]+)', line)
        if m and cur in items:
            d = m.group(2).strip('"')
            items[cur][1].append((m.group(1), {"true": "yes", "false": "no"}.get(d, d)))
    return items


def intro(folder):
    """The first sentence of the README's first paragraph, without markdown, as the line's comment."""
    text, para = open(os.path.join(repo, folder, "README.md")).read().split("\n"), []
    for line in text:
        if line.startswith("#"):
            continue
        if line.strip():
            para.append(line.strip())
        elif para:
            break
    s = " ".join(para)
    s = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", s)
    s = re.sub(r"[*`]", "", s)
    s = re.split(r"(?<=[.:;])\s", s)[0].rstrip(".:;")
    return s if len(s) <= 70 else s[:67].rstrip() + "..."


def sections(lines):
    cur, out = "", {}
    for i, l in enumerate(lines):
        m = re.match(r"^\[([\w-]+)\]\s*(#.*)?$", l)
        if m:
            cur = m.group(1)
            out.setdefault(cur, []).append(i)
        elif cur:
            out[cur].append(i)
    return out


def enabled_keys(lines, sec):
    keys = set()
    for i in sec.get("enabled", []):
        m = re.match(r"^\s*(\w+)\s*=", re.sub(r"(^|\s)#.*", "", lines[i]))
        if m:
            keys.add(m.group(1))
    return keys


def plan(path, items):
    """(new text or None, [messages]) for one conf file."""
    text = open(path).read()
    lines = text.split("\n")
    sec = sections(lines)
    if "enabled" not in sec:
        return None, []
    have = enabled_keys(lines, sec)
    msgs, add_enabled, add_sections = [], [], []
    for key in sorted(folders):
        if key not in have:
            add_enabled.append(key)
        if key not in sec and key in items and (items[key][0] == "widget" or items[key][1]):
            add_sections.append(key)
    if not add_enabled and not add_sections:
        return None, []

    # New [enabled] lines go after the last setting there, lined up with the existing ones.
    if add_enabled:
        last = max((i for i in sec["enabled"] if re.match(r"^\s*\w+\s*=", lines[i])), default=sec["enabled"][0])
        # The "=" and "#" columns most lines use (one long key doesn't set them).
        eqs, hashes = Counter(), Counter()
        for i in sec["enabled"]:
            m = re.match(r"^(\w+\s*)=\s*\S*(\s*)#", lines[i])
            if m:
                eqs[len(m.group(1))] += 1
                hashes[lines[i].index("#")] += 1
        width = eqs.most_common(1)[0][0] if eqs else 0
        col = hashes.most_common(1)[0][0] if hashes else 0
        new = []
        for key in add_enabled:
            head = "%-*s= no" % (max(width, len(key) + 1), key)
            new.append(head + " " * max(col - len(head), 1) + "# " + intro(folders[key]))
            msgs.append("[enabled] %s = no" % key)
        lines[last + 1:last + 1] = new
    for key in add_sections:
        body = ["%s = %s" % (k, d) if d != "" else "%s =" % k for k, d in items[key][1]]
        if lines and lines[-1] != "":
            lines.append("")
        lines += ["[%s]" % key] + body + [""]
        msgs.append("[%s] section with %d setting(s)" % (key, len(body)))
    return "\n".join(lines).rstrip("\n") + "\n", msgs


items = settings_window()
targets = [("scotchos.default.conf", os.path.join(repo, "scotchos.default.conf"))]
if live and os.path.exists(live):
    targets.append((live, os.path.realpath(live)))
for name, path in targets:
    new, msgs = plan(path, items)
    for m in msgs:
        print("  %s %s: %s" % ("would add to" if mode == "--check" else "added to", name, m))
    if new is not None and mode == "--fix":
        tmp = path + ".tmp"
        with open(tmp, "w") as f:
            f.write(new)
        os.replace(tmp, path)  # atomic, so the shell never reads a half-written file
