import QtQuick
import qs.Commons

// Small, theme-colored list-view icons, drawn at their native size.
Item {
    id: root
    property string name: "today"
    property color color: Color.popups.text
    property int day: new Date().getDate()
    implicitWidth: Style.space(16)
    implicitHeight: Style.space(16)
    Canvas {
        id: canvas
        anchors.fill: parent
        onPaint: {
            var c = getContext("2d"), s = width / 24;
            c.reset(); c.scale(s, s); c.strokeStyle = root.color; c.fillStyle = root.color;
            c.lineWidth = 1.6; c.lineJoin = "round"; c.lineCap = "round";
            if (root.name === "inbox") {
                c.beginPath(); c.moveTo(5, 3); c.lineTo(19, 3); c.lineTo(22, 18); c.lineTo(21, 21); c.lineTo(3, 21); c.lineTo(2, 18); c.closePath(); c.stroke();
                c.beginPath(); c.moveTo(3, 14); c.lineTo(8, 14); c.lineTo(10, 17); c.lineTo(14, 17); c.lineTo(16, 14); c.lineTo(21, 14); c.stroke();
            } else if (root.name === "display") {
                c.strokeRect(4, 3, 16, 18);
                for (var row = 7; row <= 17; row += 5) { c.beginPath(); c.moveTo(8, row); c.lineTo(16, row); c.stroke(); }
            } else if (root.name === "settings") {
                c.beginPath();
                for (var i = 0; i < 48; i++) { var a = i * Math.PI / 24, r = (i % 6 === 0 || i % 6 === 5) ? 7.5 : 10; var px = 12 + Math.cos(a) * r, py = 12 + Math.sin(a) * r; if (!i) c.moveTo(px, py); else c.lineTo(px, py); }
                c.closePath(); c.stroke(); c.beginPath(); c.arc(12, 12, 3.5, 0, Math.PI * 2); c.stroke();
            } else if (root.name === "flag") {
                c.beginPath(); c.moveTo(5, 22); c.lineTo(5, 3); c.lineTo(19, 3); c.lineTo(16, 8); c.lineTo(19, 13); c.lineTo(5, 13); c.stroke();
            } else if (root.name === "label") {
                c.beginPath(); c.moveTo(3, 4); c.lineTo(12, 4); c.lineTo(22, 14); c.lineTo(14, 22); c.lineTo(3, 11); c.closePath(); c.stroke(); c.beginPath(); c.arc(8, 8, 1, 0, Math.PI * 2); c.fill();
            } else if (root.name === "bell") {
                c.beginPath(); c.moveTo(4, 18); c.lineTo(6, 15); c.lineTo(6, 9); c.bezierCurveTo(6, 1, 18, 1, 18, 9); c.lineTo(18, 15); c.lineTo(20, 18); c.closePath(); c.stroke(); c.beginPath(); c.arc(12, 20, 2, 0, Math.PI); c.stroke();
            } else if (root.name === "close") {
                c.beginPath(); c.moveTo(6, 6); c.lineTo(18, 18); c.moveTo(18, 6); c.lineTo(6, 18); c.stroke();
            } else if (root.name === "more") {
                for (var dot = 5; dot <= 19; dot += 7) { c.beginPath(); c.arc(dot, 12, 1, 0, Math.PI * 2); c.fill(); }
            } else {
                c.strokeRect(3, 3, 18, 18);
                if (root.name === "today") { c.beginPath(); c.moveTo(3, 8); c.lineTo(21, 8); c.stroke(); }
                else for (var y = 8; y <= 16; y += 4) for (var x = 7; x <= 17; x += 5) { c.beginPath(); c.arc(x, y, 1, 0, Math.PI * 2); c.fill(); }
            }
        }
        Connections { target: root; function onColorChanged() { canvas.requestPaint(); } function onNameChanged() { canvas.requestPaint(); } }
    }
    Text {
        visible: root.name === "today"
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 0.39
        text: root.day
        color: root.color
        font.family: Style.font.family
        font.pixelSize: root.height * 0.43
        font.bold: true
    }
}
