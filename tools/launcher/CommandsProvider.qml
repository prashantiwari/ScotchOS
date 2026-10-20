// ScotchOS commands: the settings window, the dailyTheory and e-reader windows, a restart, and a switch for every widget and tool.
import Quickshell

Provider {
    id: p
    name: "Commands"
    glyph: ""
    placeholder: "Run a ScotchOS command"
    keywords: [">", "sos"]
    inDefault: true

    readonly property string bin: Quickshell.shellDir + "/bin/scotchos"
    function isOn(key) { return core.isYes(core.conf.enabled?.[key] ?? "no") }

    // Rebuilt per search, so the switches always show the current state.
    function all() {
        const rows = [
            { title: "Open settings", run: () => { core.settingsOpen = true } },
            { title: "Restart ScotchOS", subtitle: "the widget shell", run: () => Quickshell.execDetached([bin, "restart"]) },
        ];
        if (isOn("dailytheory"))
            rows.push({ title: "Open Daily Theory", run: () => Quickshell.execDetached([bin, "theory", "open"]) });
        if (isOn("reader"))
            rows.push({ title: "Open E-reader", subtitle: "your books", run: () => Quickshell.execDetached([bin, "reader", "open"]) });
        if (isOn("claudeusage"))
            rows.push({ title: "Refresh Claude usage", run: () => core.action("claudeusage", "refresh") });
        // The launcher's own switch is left out: turning it off from here would end this very window.
        for (const key of Object.keys(core.conf.enabled ?? {})) {
            if (key === "launcher") continue;
            const on = isOn(key);
            rows.push({
                title: (on ? "Switch off " : "Switch on ") + key,
                subtitle: key + " is " + (on ? "on" : "off"),
                run: () => core.setConf("enabled", key, on ? "no" : "yes"),
            });
        }
        return rows.map(r => Object.assign({ glyph: glyph }, r));
    }

    search: q => {
        const s = q.trim().toLowerCase();
        return all().filter(r => !s || r.title.toLowerCase().includes(s));
    }
}
