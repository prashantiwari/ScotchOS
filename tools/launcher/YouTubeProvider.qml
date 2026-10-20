// YouTube search in a private Brave window; the work is in yt-open.sh (it needs hyprctl and curl).
import Quickshell

Provider {
    id: p
    name: "YouTube"
    glyph: ""
    placeholder: "Search YouTube"
    keywords: ["yt", "youtube"]

    readonly property string script: Quickshell.shellDir + "/tools/launcher/yt-open.sh"
    function row(q) {
        const s = q.trim();
        if (!s) return [];
        return [{
            title: "Search YouTube for “" + s + "”",
            subtitle: "Brave private window",
            glyph: glyph,
            altHint: "play the first video",
            run: () => Quickshell.execDetached([p.script, s, "results"]),
            alt: () => Quickshell.execDetached([p.script, s, "first"]),
        }];
    }
    search: q => row(q)
    fallback: q => row(q)
}
