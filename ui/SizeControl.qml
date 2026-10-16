import QtQuick
import QtQuick.Controls as C
import qs.Commons
import qs.Commons as Commons

C.SpinBox {
    id: root
    implicitWidth: Style.space(148)
    implicitHeight: Style.space(36)
    stepSize: 20
    // Not the SpinBox's own editing, which needs a Qt text input. The
    // KeyField below takes digits and commits on Enter or focus loss.
    editable: false
    leftPadding: down.indicator.width + Style.space(4)
    rightPadding: up.indicator.width + Style.space(4)
    topPadding: 0
    bottomPadding: 0
    font.family: Qt.application.font.family
    font.pixelSize: Style.font.bodySmall

    function commit(value) {
        var number = parseInt(value, 10);
        if (!isNaN(number)) {
            number = Math.max(from, Math.min(to, number));
            if (number !== root.value) {
                // Step there, as the buttons do: assigning value would drop
                // the caller's binding to the saved size.
                var step = stepSize;
                stepSize = Math.abs(number - root.value);
                if (number > root.value) increase(); else decrease();
                stepSize = step;
                root.valueModified();
            }
        }
        field.text = Qt.binding(function() { return root.displayText; });
    }

    contentItem: KeyField {
        id: field
        objectName: "sizeField"
        framed: false
        text: root.displayText
        font: root.font
        foreground: Commons.Color.popups.text
        horizontalAlignment: Text.AlignHCenter
        maximumLength: 5
        validator: function(value) { return /^\d*$/.test(value); }
        onEditingFinished: root.commit(text)
    }
    background: Rectangle {
        color: "transparent"
        radius: Style.cornerRadius
        border.width: 1
        border.color: Qt.rgba(Commons.Color.popups.text.r, Commons.Color.popups.text.g, Commons.Color.popups.text.b, root.activeFocus ? 0.6 : 0.25)
    }
    down.indicator: Rectangle {
        width: Style.space(36); height: root.height
        radius: Style.cornerRadius
        color: root.down.pressed || root.down.hovered ? Style.hoverFillFor(Commons.Color.popups.text, Commons.Color.accent) : Qt.rgba(Commons.Color.popups.text.r, Commons.Color.popups.text.g, Commons.Color.popups.text.b, 0.05)
        Label { font.family: root.font.family; anchors.centerIn: parent; text: "−"; font.pixelSize: Style.space(20); opacity: root.value > root.from ? 1 : 0.3 }
    }
    up.indicator: Rectangle {
        x: root.width - width
        width: Style.space(36); height: root.height
        radius: Style.cornerRadius
        color: root.up.pressed || root.up.hovered ? Style.hoverFillFor(Commons.Color.popups.text, Commons.Color.accent) : Qt.rgba(Commons.Color.popups.text.r, Commons.Color.popups.text.g, Commons.Color.popups.text.b, 0.05)
        Label { font.family: root.font.family; anchors.centerIn: parent; text: "+"; font.pixelSize: Style.space(20); opacity: root.value < root.to ? 1 : 0.3 }
    }
}
