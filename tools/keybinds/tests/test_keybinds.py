"""keybinds.py: combos, reading hl.bind calls out of Lua (aliases, _F tables, loops), the listing, the generated Lua.

Run: python3 -m unittest discover -s tools/keybinds/tests   (or `scotchos test`)
Nothing here calls hyprctl: the live binds are made up, and the Lua is written to a temp folder.
"""
import importlib.util
import os
import shutil
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("keybinds", os.path.join(HERE, "..", "keybinds.py"))
kb = importlib.util.module_from_spec(spec)
spec.loader.exec_module(kb)

# A small key_binds.lua in HyDE's style: locals, _F tables, a local function, two loops with one description.
HYDE = r'''
local _apps = hyde.config.app
local MOD = hyde.config.modifiers.main
local move_window = function(dir) return function() end end

_F = {description = "[Launcher|Apps] terminal emulator"}
hl.bind(MOD .. " + T", hl.dsp.exec_cmd(_apps.terminal), _F)
-- hl.bind(MOD .. " + K", hl.dsp.exec_cmd("commented out"), _F)
_F = {description = "[Hardware Controls|Audio] decrease volume", locked = true, repeating = true}
hl.bind("F11", hl.dsp.exec_cmd(hyde.sh.volumecontrol("-o", "d")), _F)
_F = {description = "[Window Management|Move active window] left", repeating = true}
hl.bind(MOD .. " + SHIFT + CONTROL + LEFT", move_window("l"), _F)
--[[ hl.bind("F1", hl.dsp.exec_cmd("block comment"), {}) ]]

for i = 1, 10 do
    _F = {description = "[Workspaces|Navigation] navigate to workspace " .. i}
    hl.bind(MOD .. " + " .. ((i == 10) and 0 or i), hl.dsp.focus({workspace = i}), _F)
end

for i = 1, 10 do
    for _, key in ipairs(kp[i]) do
        hl.bind(MOD .. " + " .. key, hl.dsp.focus({workspace = tostring(i + 10)}),
            {description = "[Workspaces|Navigation] navigate to workspace " .. (i + 10)})
    end
end
'''

USER = r'''
hl.bind("SUPER + SPACE", hl.dsp.exec_cmd(os.getenv("HOME") .. "/launcher.sh"), {
        description = "[Launcher|ScotchOS] launcher",
})
'''


def live(modmask, key, description, **flags):
    return dict({"modmask": modmask, "key": key, "keycode": 0, "description": description, "submap": ""}, **flags)


class Combos(unittest.TestCase):
    def test_canonical_is_a_set_of_modifiers_and_the_key(self):
        self.assertEqual(kb.canonical("SUPER + CONTROL + left"), "CTRL + SUPER + LEFT")
        self.assertEqual(kb.canonical("CTRL+SUPER+Left"), "CTRL + SUPER + LEFT")
        self.assertEqual(kb.canonical("SUPER+ ALT  + F4"), "ALT + SUPER + F4")
        self.assertEqual(kb.canonical("F10"), "F10")
        self.assertEqual(kb.canonical(""), "")

    def test_combo_of_reads_the_modmask(self):
        self.assertEqual(kb.combo_of(live(65, "slash", "")), "SUPER + SHIFT + slash")
        self.assertEqual(kb.combo_of(live(76, "F12", "")), "SUPER + CTRL + ALT + F12")
        self.assertEqual(kb.combo_of({"modmask": 0, "key": "", "keycode": 66}), "code:66")

    def test_split_description(self):
        self.assertEqual(kb.split_description("[Launcher|Apps] terminal"), ("Launcher|Apps", "terminal"))
        self.assertEqual(kb.split_description("no group"), ("", "no group"))


class Scan(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.hyde = os.path.join(self.dir, "key_binds.lua")
        self.user = os.path.join(self.dir, "hyprland.lua")
        for path, text in ((self.hyde, HYDE), (self.user, USER)):
            with open(path, "w") as f:
                f.write(text)
        self.found = kb.scan(self.hyde, "SUPER")

    def tearDown(self):
        shutil.rmtree(self.dir)

    def test_comments_are_skipped(self):
        actions = " ".join(s["action"] for s in self.found)
        self.assertNotIn("commented out", actions)
        self.assertNotIn("block comment", actions)
        self.assertEqual(len(self.found), 5)

    def test_aliases_and_option_tables(self):
        t = self.found[0]
        self.assertEqual(t["combo"], "SUPER + T")
        self.assertEqual(t["lua"], "hl.dsp.exec_cmd(hyde.config.app.terminal)")
        self.assertEqual(t["opts"]["description"], "[Launcher|Apps] terminal emulator")
        self.assertEqual(t["line"], 7)
        vol = self.found[1]
        self.assertEqual(vol["opts"], {"description": "[Hardware Controls|Audio] decrease volume",
                                       "locked": True, "repeating": True})

    def test_local_functions_are_not_portable(self):
        self.assertIsNone(self.found[2]["lua"])

    def test_loop_binds_resolve_from_the_description(self):
        first, kp = self.found[3], self.found[4]
        self.assertIsNone(first["combo"])
        self.assertEqual(first["loop"], {"var": "i", "from": 1, "to": 10})
        self.assertEqual(kb.loop_instance(first, "[Workspaces|Navigation] navigate to workspace 3"),
                         (3, "hl.dsp.focus({workspace = 3})"))
        # 13 is outside the first loop (i = 13) and inside the second (i = 3).
        self.assertIsNone(kb.loop_instance(first, "[Workspaces|Navigation] navigate to workspace 13"))
        self.assertEqual(kb.loop_instance(kp, "[Workspaces|Navigation] navigate to workspace 13"),
                         (3, "hl.dsp.focus({workspace = tostring(3 + 10)})"))

    def test_listing_matches_live_binds_to_their_source(self):
        binds = [live(64, "T", "[Launcher|Apps] terminal emulator"),
                 live(0, "F11", "[Hardware Controls|Audio] decrease volume", locked=True, repeat=True),
                 live(64, "3", "[Workspaces|Navigation] navigate to workspace 3"),
                 live(64, "KP_3", "[Workspaces|Navigation] navigate to workspace 13"),
                 live(64, "SPACE", "[Launcher|ScotchOS] launcher")]
        old = kb.USER_LUA
        kb.USER_LUA = self.user
        try:
            rows = kb.listing(binds, self.found + kb.scan(self.user, "SUPER"), [])
        finally:
            kb.USER_LUA = old
        self.assertEqual([r["origin"] for r in rows], ["hyde", "hyde", "hyde", "hyde", "user"])
        self.assertEqual(rows[1]["flags"]["repeating"], True)
        self.assertEqual(rows[2]["lua"], "hl.dsp.focus({workspace = 3})")
        self.assertEqual(rows[3]["lua"], "hl.dsp.focus({workspace = tostring(3 + 10)})")
        self.assertEqual(rows[4]["lua"], 'hl.dsp.exec_cmd(os.getenv("HOME") .. "/launcher.sh")')

    def test_listing_marks_edits_and_switched_off_binds(self):
        edits = [{"was": "SUPER + T", "combo": "SUPER + ALT + T", "exec": "kitty", "description": "[Launcher|Apps] kitty"},
                 {"was": "F11", "combo": "F11", "off": True, "description": "[Hardware Controls|Audio] decrease volume",
                  "action": "volume down"}]
        binds = [live(72, "T", "[Launcher|Apps] kitty")]
        rows = kb.listing(binds, self.found, edits)
        self.assertEqual([(r["origin"], r["edit"]) for r in rows], [("scotchos", 0), ("off", 1)])
        self.assertEqual(rows[0]["action"], "kitty")
        self.assertEqual(rows[1]["combo"], "F11")


class Generate(unittest.TestCase):
    def test_every_unbind_comes_before_every_bind(self):
        # Moving SUPER + B to SUPER + O, and SUPER + O's own bind to SUPER + B: a swap.
        lua = kb.generate([
            {"was": "SUPER + B", "combo": "SUPER + O", "lua": "hl.dsp.exec_cmd(hyde.config.app.browser)", "description": "b"},
            {"was": "SUPER + O", "combo": "SUPER + B", "exec": "obsidian", "description": "o"},
        ])
        body = lua[lua.index("end\n\n"):]
        self.assertLess(body.rindex("unbind("), body.index("hl.bind("))
        self.assertEqual(body.count('unbind("SUPER + B")'), 1)
        self.assertIn('hl.bind("SUPER + O", hl.dsp.exec_cmd(hyde.config.app.browser), { description = "b" })', lua)
        self.assertIn('hl.bind("SUPER + B", hl.dsp.exec_cmd("obsidian"), { description = "o" })', lua)

    def test_switched_off_binds_are_only_unbound(self):
        lua = kb.generate([{"was": "SUPER + C", "combo": "SUPER + C", "off": True}])
        self.assertIn('unbind("SUPER + C")', lua)
        self.assertNotIn("hl.bind(", lua)

    def test_strings_are_escaped_and_flags_written(self):
        lua = kb.generate([{"was": "", "combo": "SUPER + N", "exec": 'notify-send "hi \\ there"',
                            "description": "[Custom] say \"hi\"", "flags": {"locked": True, "release": False, "bogus": True}}])
        self.assertIn(r'hl.dsp.exec_cmd("notify-send \"hi \\ there\"")', lua)
        self.assertIn(r'{ description = "[Custom] say \"hi\"", locked = true }', lua)

    def test_check_refuses_what_would_break_the_config(self):
        self.assertIsNone(kb.check({"combo": "SUPER + N", "exec": "x"}))
        self.assertIsNone(kb.check({"combo": "SUPER + C", "off": True}))
        self.assertIn("isn't a key combo", kb.check({"combo": 'SUPER + "x', "exec": "x"}))
        self.assertIn("no key besides", kb.check({"combo": "SUPER + SHIFT", "exec": "x"}))
        self.assertIn("no command", kb.check({"combo": "SUPER + N", "exec": " "}))


if __name__ == "__main__":
    unittest.main()
