---
name: check-shell
description: Check that the ScotchOS widget shell is healthy after a change - restart it, read the log for warnings, confirm each enabled widget's layer appears on an empty workspace, take a screenshot, and measure memory/CPU. Use after editing QML, scotchos.conf or a widget helper, or when a widget isn't showing.
---

# Check the ScotchOS shell

0. `scotchos doctor`: fix anything it lists first.
1. `scotchos restart` (only needed for non-QML changes; QML hot-reloads), wait ~2 s.
2. `scotchos log 2>&1 | grep -E 'WARN|ERROR'`. A missing `quote.json` right after a fresh start is expected; anything else needs fixing.
3. `scotchos status`: running, memory, and the on/off list. Compare the memory with the baseline taken before the change (the `new-widget` / `new-tool` skills note one); a small card adding more than ~30 MB needs explaining. With no baseline, report the number as is.
4. Visual check (**tell the user first: it switches their workspace for a few seconds**):

   ```bash
   prev=$(hyprctl activeworkspace -j | jq -r .id); mon=$(hyprctl activeworkspace -j | jq -r .monitor)
   hyprctl dispatch 'hl.dsp.focus({workspace = "9"})' >/dev/null; sleep 2
   hyprctl layers -j | jq -r '.. | objects | select((.namespace? // "") | startswith("scotchos")) | "\(.namespace) \(.w)x\(.h) @\(.x),\(.y)"'
   grim -o "$mon" <scratchpad>/shot.png
   hyprctl dispatch "hl.dsp.focus({workspace = \"$prev\"})" >/dev/null
   ```

   Then read the screenshot. Every enabled widget should have a `scotchos-<key>` layer (now playing only while a player has a track), and the cards shouldn't overlap.
5. CPU while visible: `top -b -n 3 -d 2 -p <qs pid>`; idle widgets should stay around 1–3 % of one core.
6. Report what you checked and what you saw, including anything that failed.
