// The next 24 hours: temperature as a filled curve, rain chance as bars under it, a label every 6 hours.
// Drawn once per data change on a Canvas (no animation), so it costs nothing between updates.
import QtQuick

Column {
    id: curve
    required property var shell
    readonly property var pts: shell.hours
    spacing: 4

    Canvas {
        id: canvas
        width: curve.width
        height: 64
        renderStrategy: Canvas.Cooperative

        readonly property color line: curve.shell.accent
        readonly property color rain: curve.shell.fg
        onLineChanged: requestPaint()
        onWidthChanged: requestPaint()
        Connections {
            target: curve
            function onPtsChanged() { canvas.requestPaint() }
        }

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const p = curve.pts;
            if (p.length < 2) return;
            const temps = p.map(o => o.temp);
            const lo = Math.min(...temps), hi = Math.max(...temps);
            const span = Math.max(hi - lo, 1);
            const top = 14, bottom = height - 4;   // room for the max label above
            const x = i => i * (width - 1) / (p.length - 1);
            const y = v => bottom - (v - lo) / span * (bottom - top - 10) - 6;

            // Rain chance: thin bars from the bottom, faint so the curve stays the subject
            ctx.fillStyle = Qt.alpha(rain, 0.18);
            for (let i = 0; i < p.length; i++) {
                const h = p[i].rain / 100 * (bottom - top);
                if (h > 0) ctx.fillRect(x(i) - 2, bottom - h, 4, h);
            }

            // Smooth path through the points (midpoint quadratic curves)
            const path = () => {
                ctx.moveTo(x(0), y(temps[0]));
                for (let i = 1; i < p.length - 1; i++)
                    ctx.quadraticCurveTo(x(i), y(temps[i]), (x(i) + x(i + 1)) / 2, (y(temps[i]) + y(temps[i + 1])) / 2);
                ctx.lineTo(x(p.length - 1), y(temps[p.length - 1]));
            };

            const grad = ctx.createLinearGradient(0, top, 0, bottom);
            grad.addColorStop(0, Qt.alpha(line, 0.35));
            grad.addColorStop(1, Qt.alpha(line, 0));
            ctx.beginPath();
            path();
            ctx.lineTo(width, bottom);
            ctx.lineTo(0, bottom);
            ctx.closePath();
            ctx.fillStyle = grad;
            ctx.fill();

            ctx.beginPath();
            path();
            ctx.strokeStyle = line;
            ctx.lineWidth = 2;
            ctx.stroke();

            // Mark the warmest and coolest hour
            ctx.font = "bold 10px '" + curve.shell.font + "'";
            ctx.textAlign = "center";
            for (const v of [hi, lo]) {
                const i = temps.indexOf(v);
                const px = Math.min(Math.max(x(i), 12), width - 12);
                ctx.fillStyle = line;
                ctx.beginPath();
                ctx.arc(x(i), y(v), 3, 0, 2 * Math.PI);
                ctx.fill();
                ctx.fillStyle = curve.shell.fg;
                ctx.fillText(Math.round(v) + "°", px, v === hi ? y(v) - 6 : Math.min(y(v) + 14, bottom));
            }
        }
    }

    // Hour labels under the curve: now, +6, +12, +18, +24
    Item {
        width: curve.width
        height: 12
        Repeater {
            model: 5
            Text {
                required property int index
                readonly property var pt: curve.pts[index * 6] ?? null
                x: Math.min(Math.max(index * 6 * (curve.width - 1) / Math.max(curve.pts.length - 1, 1) - width / 2, 0), curve.width - width)
                text: !pt ? "" : index === 0 ? "now" : curve.shell.hhmm(pt.t)
                color: curve.shell.dim
                font { family: curve.shell.font; pixelSize: 10 }
            }
        }
    }
}
