# Wallbash template

`scotchos.dcol` is a HyDE wallbash template. It makes HyDE write the colors it applies (wallpaper or theme, after its dark/light handling) to `~/.cache/hyde/wallbash/scotchos.dcol`. The [system dashboard](../systemDashboard/README.md), [now playing](../nowPlaying/README.md) and [hourly quote](../hourlyQuote/README.md) cards read their colors from that file.

## Install

```bash
cp wallbash/scotchos.dcol ~/.config/hyde/wallbash/always/
```

Copy it rather than symlink it: HyDE skips symlinked templates. It takes effect on the next wallpaper or theme change. To render it right away:

```bash
~/.local/lib/hyde/color.set.sh --single ~/.config/hyde/wallbash/always/scotchos.dcol
```
