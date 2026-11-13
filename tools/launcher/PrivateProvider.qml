// `private cats`: a private browser window on workspace 7, searching for what was typed; the work is in private-open.sh.
import Quickshell

Provider {
    id: p
    name: "Private"
    glyph: "\u{F05F9}"
    placeholder: "Search in a private window"
    keywords: ["private"]

    readonly property string script: Quickshell.shellDir + "/tools/launcher/private-open.sh"
    search: q => {
        const s = q.trim();
        return [{
            title: s ? "Search privately for “" + s + "”" : "Private window",
            subtitle: "Browser on workspace 7",
            glyph: glyph,
            run: () => Quickshell.execDetached(s ? [p.script, s] : [p.script]),
        }];
    }
}
