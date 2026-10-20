// History graph: a filled line of `values`, scaled between `min` and `max`.
// Optionally a second line (`values2`), and `autoMax` to scale to the largest sample.
// Axis labels (top, middle, bottom) sit in a gutter on the left, formatted by `label`.
import QtQuick

Canvas {
    id: graph
    property var values: []
    property real min: 0
    property real max: 100
    property int capacity: 60
    property bool autoMax: false
    property var values2: []
    property color color: "white"
    property color color2: "white"
    property color gridColor: "#22ffffff"
    property color labelColor: "#99ffffff"
    property string fontFamily: "monospace"
    property var label: v => Math.round(v)
    property real gutter: 34

    // The scale actually used: `max`, or with autoMax the largest sample rounded up to a
    // power of two (never below `max`), so the axis labels stay round numbers.
    readonly property real scaleMax: {
        const m = autoMax ? Math.max(max, ...values, ...values2) : max;
        return autoMax ? Math.pow(2, Math.ceil(Math.log2(m))) : m;
    }

    onValuesChanged: requestPaint()
    onValues2Changed: requestPaint()
    onColorChanged: requestPaint()
    onColor2Changed: requestPaint()
    onLabelColorChanged: requestPaint()

    onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        const w = width - gutter;  // plot area, right of the labels
        const pad = 5;             // keeps the top and bottom labels inside the canvas
        const h = height - 2 * pad;

        // Guide lines at 0 / 25 / 50 / 75 / 100 %, labelled at 0 and 100 %.
        ctx.lineWidth = 1;
        ctx.font = "9px '" + fontFamily + "'";
        ctx.textAlign = "right";
        ctx.textBaseline = "middle";
        for (let i = 0; i <= 4; i++) {
            const gy = Math.round(pad + h * i / 4) + 0.5;
            ctx.strokeStyle = gridColor;
            ctx.beginPath(); ctx.moveTo(gutter, gy); ctx.lineTo(width, gy); ctx.stroke();
            if (i === 0 || i === 4) {
                ctx.fillStyle = labelColor;
                ctx.fillText(label(scaleMax - (scaleMax - min) * i / 4), gutter - 5, gy);
            }
        }

        const step = w / (capacity - 1);
        const y = v => pad + h - h * Math.max(0, Math.min(1, (v - min) / (scaleMax - min)));

        function series(vals, col) {
            if (vals.length < 2)
                return;
            const x0 = width - (vals.length - 1) * step;  // newest sample on the right
            ctx.beginPath();
            ctx.moveTo(x0, y(vals[0]));
            for (let i = 1; i < vals.length; i++)
                ctx.lineTo(x0 + i * step, y(vals[i]));
            ctx.strokeStyle = col;
            ctx.lineWidth = 2;
            ctx.lineJoin = "round";
            ctx.stroke();

            ctx.lineTo(width, pad + h);
            ctx.lineTo(x0, pad + h);
            ctx.closePath();
            const fill = ctx.createLinearGradient(0, pad, 0, pad + h);
            fill.addColorStop(0, Qt.alpha(col, 0.35));
            fill.addColorStop(1, Qt.alpha(col, 0.0));
            ctx.fillStyle = fill;
            ctx.fill();
        }
        series(values, color);
        series(values2, color2);
    }
}
