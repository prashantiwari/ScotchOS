#!/usr/bin/env bash
# ScotchOS setup on a new machine: checks what's installed, installs the wallbash template and the
# `scotchos` command, and prints the Hyprland lines to add. Safe to run again; it never edits your Hyprland config.
set -u
root="$(dirname "$(readlink -f "$0")")"
ok()   { printf '  \e[32m✓\e[0m %s\n' "$*"; }
warn() { printf '  \e[33m!\e[0m %s\n' "$*"; }

echo "Dependencies"
missing=()
check() {   # check <command> <package> <what for>
    if command -v "$1" >/dev/null; then ok "$1"; else warn "$1 missing ($3)"; missing+=("$2"); fi
}
check qs       quickshell "every widget"
check python3  python     "system dashboard"
check cava     cava       "now playing visualizer (optional)"
check rofi     rofi       "app launcher entries (optional)"
check jq       jq         "launcher: YouTube search"
check curl     curl       "launcher: YouTube first video"
check brave    brave-bin  "launcher: YouTube search (AUR)"
python3 -c "import mobi" 2>/dev/null || echo "  optional: python-mobi (AUR) for MOBI / AZW3 books in the e-reader"
fc-list | grep -qi "JetBrainsMono Nerd" && ok "JetBrainsMono Nerd Font" ||
    { warn "JetBrainsMono Nerd Font missing"; missing+=(ttf-jetbrains-mono-nerd); }
if ((${#missing[@]})); then
    echo "  Install with:  sudo pacman -S --needed ${missing[*]/brave-bin/}"
    [[ " ${missing[*]} " == *" brave-bin "* ]] && echo "                 paru -S brave-bin"
fi

echo "Wallbash colors"
if [[ -d ~/.config/hyde/wallbash ]]; then
    mkdir -p ~/.config/hyde/wallbash/always
    cp "$root/wallbash/scotchos.dcol" ~/.config/hyde/wallbash/always/   # a copy: HyDE skips symlinked templates
    ok "template copied to ~/.config/hyde/wallbash/always/"
    if [[ -x ~/.local/lib/hyde/color.set.sh ]]; then
        ~/.local/lib/hyde/color.set.sh --single ~/.config/hyde/wallbash/always/scotchos.dcol >/dev/null 2>&1 &&
            ok "colors rendered" || warn "couldn't render now; they appear on the next wallpaper change"
    fi
else
    warn "HyDE not found: widgets use their built-in fallback colors"
fi

echo "Command"
chmod +x "$root/bin/scotchos" "$root/bin/scotchos-doctor" "$root"/tools/*/*.sh "$root"/widgets/*/*.py 2>/dev/null
mkdir -p ~/.local/bin
ln -sfn "$root/bin/scotchos" ~/.local/bin/scotchos && ok "~/.local/bin/scotchos -> bin/scotchos"
[[ ":$PATH:" == *":$HOME/.local/bin:"* ]] || warn "~/.local/bin isn't in PATH"

echo "App launcher entry"
mkdir -p ~/.local/share/applications
sed "s|@SCOTCHOS@|$root/bin/scotchos|" "$root/settings/scotchos-settings.desktop" \
    > ~/.local/share/applications/scotchos-settings.desktop && ok "ScotchOS Settings in rofi / app launchers"
sed "s|@DIR@|$root/tools/dailyTheoryClient|" "$root/tools/dailyTheoryClient/scotchos-dailytheory.desktop" \
    > ~/.local/share/applications/scotchos-dailytheory.desktop && ok "Daily Theory in rofi / app launchers"
sed "s|@DIR@|$root/tools/eReader|" "$root/tools/eReader/scotchos-reader.desktop" \
    > ~/.local/share/applications/scotchos-reader.desktop && ok "E-reader in rofi / app launchers"

cat <<EOF

Add to Hyprland
  Lua config (~/.config/hypr/hyprland.lua), inside hl.on("hyprland.start", function() … end):
      hl.exec_cmd("qs -n -d -p $root")
  and the launcher bind:
      hl.bind("SUPER + Y", hl.dsp.exec_cmd("$root/tools/launcher/launcher.sh"))

  Old-style config (hyprland.conf):
      exec-once = qs -n -d -p $root
      bind = SUPER, Y, exec, $root/tools/launcher/launcher.sh

Then start it now with:  scotchos start
EOF
