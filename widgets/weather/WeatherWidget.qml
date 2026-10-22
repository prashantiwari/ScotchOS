// ScotchOS Weather: current conditions, the next 24 hours and the coming days from Open-Meteo,
// on the desktop layer of every screen.
import QtQuick
import Quickshell
import Quickshell.Io
import "../../common"
import "../../common/http.js" as Http

DesktopWidget {
    id: w
    section: "weather"

    // ---- Settings ----
    readonly property string place: placeSetting("top")
    // auto (from your IP), a city name ("Pune"), or "lat,lon"
    readonly property string location: (str("location", "auto") || "auto").trim()
    readonly property string units: str("units", "metric", ["metric", "imperial"])
    readonly property bool imperial: units === "imperial"
    readonly property int intervalMin: Math.max(10, num("interval", 30))
    readonly property int days: Math.min(7, Math.max(3, num("days", 5)))
    readonly property bool showHourly: flag("show_hourly", true)

    // ---- State ----
    // `data` is the trimmed Open-Meteo reply; kept in weather.json in the cache with the place and settings
    // it was fetched for, so a restart shows it right away and a changed location fetches again.
    property var data: null
    property string city: ""
    property string fetchedFor: ""   // location + units of `data`
    property real fetchedAt: 0       // ms since epoch, 0 = never
    property real lastTry: 0
    property string lastTryFor: ""
    property bool loading: false
    property bool cacheRead: false
    property string error: ""
    property real now: Date.now()    // moved on by the minute timer, so the 24 h curve starts at the current hour
    readonly property int retryMs: 5 * 60 * 1000
    readonly property string wanted: location + "|" + units

    onWantedChanged: if (cacheRead && anyEmpty) tick()

    // ---- Locating ----
    // done({ lat, lon, city }) or done(null). IP lookups try two services; a VPN moves you to its exit.
    function locate(done) {
        const m = location.match(/^\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*$/);
        if (m) return done({ lat: +m[1], lon: +m[2], city: "" });
        if (location !== "auto") {
            Http.get("https://geocoding-api.open-meteo.com/v1/search?count=1&name=" + encodeURIComponent(location), {}, r => {
                const g = r.ok && r.data && r.data.results ? r.data.results[0] : null;
                done(g ? { lat: g.latitude, lon: g.longitude, city: g.name } : null);
            });
            return;
        }
        Http.get("https://ipinfo.io/json", {}, r => {
            const loc = r.ok && r.data?.loc ? r.data.loc.split(",") : null;
            if (loc) return done({ lat: +loc[0], lon: +loc[1], city: r.data.city ?? "" });
            Http.get("http://ip-api.com/json?fields=status,city,lat,lon", {}, r2 => {
                done(r2.ok && r2.data?.status === "success" ? { lat: r2.data.lat, lon: r2.data.lon, city: r2.data.city } : null);
            });
        });
    }

    // ---- Fetching ----
    function fetchWeather() {
        const forWhat = wanted;
        lastTry = Date.now();
        lastTryFor = forWhat;
        loading = true;
        locate(p => {
            if (!p) return fail("couldn't find the location \"" + w.location + "\"");
            // unixtime keeps the hours comparable with the clock here, whatever the location's time zone
            const url = "https://api.open-meteo.com/v1/forecast?latitude=" + p.lat + "&longitude=" + p.lon
                + "&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,is_day"
                + "&hourly=temperature_2m,precipitation_probability,weather_code,is_day"
                + "&daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,precipitation_probability_max"
                + "&timezone=auto&timeformat=unixtime&forecast_days=8&forecast_hours=48"
                + (w.imperial ? "&temperature_unit=fahrenheit&wind_speed_unit=mph" : "");
            Http.get(url, {}, r => {
                if (!r.ok || !r.data?.current) return fail("Open-Meteo: HTTP " + r.status);
                const d = r.data;
                w.data = { offset: d.utc_offset_seconds, current: d.current, hourly: d.hourly, daily: d.daily };
                w.city = p.city;
                w.fetchedFor = forWhat;
                w.fetchedAt = Date.now();
                w.error = "";
                w.loading = false;
                cache.setText(JSON.stringify({ data: w.data, city: w.city, fetchedFor: w.fetchedFor, fetchedAt: w.fetchedAt }));
            });
        });
    }

    function fail(msg) {
        console.warn("weather:", msg, "- retrying in", retryMs / 60000, "min");
        error = msg;
        loading = false;
    }

    function tick() {
        now = Date.now();
        const stale = fetchedFor !== wanted || now - fetchedAt >= intervalMin * 60000;
        if (cacheRead && !loading && stale && (lastTryFor !== wanted || now - lastTry >= retryMs))
            fetchWeather();
    }

    FileView {
        id: cache
        path: Quickshell.cacheDir + "/weather.json"
        onLoaded: {
            try {
                const c = JSON.parse(text());
                w.data = c.data;
                w.city = c.city;
                w.fetchedFor = c.fetchedFor;
                w.fetchedAt = c.fetchedAt;
            } catch (e) {}
            w.cacheRead = true;
            if (w.anyEmpty) w.tick();
        }
        onLoadFailed: { w.cacheRead = true; if (w.anyEmpty) w.tick(); }
    }

    // Once a minute instead of one long timer, so it catches up right after a suspend. Only while shown.
    Timer {
        interval: 60000
        repeat: true
        running: w.anyEmpty
        triggeredOnStart: true
        onTriggered: w.tick()
    }

    // ---- Derived values for the card ----
    // WMO weather code -> [label, day icon, night icon] (Material Design weather glyphs in the Nerd Font)
    function describe(code) {
        if (code === 0) return ["Clear", "\u{F0599}", "\u{F0594}"];
        if (code <= 2) return [code === 1 ? "Mostly clear" : "Partly cloudy", "\u{F0595}", "\u{F0F31}"];
        if (code === 3) return ["Overcast", "\u{F0590}", "\u{F0590}"];
        if (code <= 48) return ["Fog", "\u{F0591}", "\u{F0591}"];
        if (code <= 57) return ["Drizzle", "\u{F0597}", "\u{F0597}"];
        if (code <= 67) return [code >= 65 ? "Heavy rain" : "Rain", code >= 65 ? "\u{F0596}" : "\u{F0597}", code >= 65 ? "\u{F0596}" : "\u{F0597}"];
        if (code <= 77) return ["Snow", "\u{F0598}", "\u{F0598}"];
        if (code <= 82) return [code === 82 ? "Heavy showers" : "Showers", "\u{F0596}", "\u{F0596}"];
        if (code <= 86) return ["Snow showers", "\u{F0F36}", "\u{F0F36}"];
        return [code >= 96 ? "Storm, hail" : "Thunderstorm", "\u{F067E}", "\u{F067E}"];
    }
    function icon(code, isDay) { const d = describe(code); return isDay ? d[1] : d[2] }
    readonly property string deg: "°"
    readonly property string windUnit: imperial ? "mph" : "km/h"

    // A unix time as a Date whose UTC fields read as the location's wall clock
    function local(t) { return new Date((t + (data?.offset ?? 0)) * 1000) }
    function hhmm(t) {
        const d = local(t);
        return String(d.getUTCHours()).padStart(2, "0") + ":" + String(d.getUTCMinutes()).padStart(2, "0");
    }

    // The next 25 hourly points from the current hour: [{ t, temp, rain }]
    readonly property var hours: {
        const h = data?.hourly;
        if (!h) return [];
        const start = Math.floor(now / 3600000) * 3600;
        const i0 = Math.max(0, h.time.findIndex(t => t >= start));
        const out = [];
        for (let i = i0; i < Math.min(h.time.length, i0 + 25); i++)
            out.push({ t: h.time[i], temp: h.temperature_2m[i], rain: h.precipitation_probability[i] ?? 0,
                       code: h.weather_code[i], isDay: h.is_day[i] });
        return out;
    }

    // Today (index of the current local day) and the following ones, `days` in all
    readonly property int todayIndex: {
        const t = data?.daily?.time;
        if (!t) return 0;
        let i = 0;
        while (i + 1 < t.length && t[i + 1] <= now / 1000) i++;
        return i;
    }
    function day(n) {
        const d = data?.daily;
        const i = todayIndex + n;
        if (!d || i >= d.time.length) return null;
        return { t: d.time[i], code: d.weather_code[i], max: d.temperature_2m_max[i], min: d.temperature_2m_min[i],
                 rain: d.precipitation_probability_max[i] ?? 0, sunrise: d.sunrise[i], sunset: d.sunset[i] };
    }

    // ---- One panel per screen, only where the workspace is empty ----
    Variants {
        model: Quickshell.screens

        DesktopPanel {
            layerName: "scotchos-weather"
            visible: w.workspaceEmpty(modelData)
            place: w.place
            marginX: w.marginX
            marginY: w.marginY
            implicitWidth: card.width
            implicitHeight: card.height

            WeatherCard {
                id: card
                shell: w
            }
        }
    }
}
