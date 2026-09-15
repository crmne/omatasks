import QtQuick
import QtQuick.Controls as C
import qs.Commons

C.AbstractButton {
    id: root
    property bool selected: false
    property color foreground: Color.popups.text
    property string tip: ""
    property bool bold: selected
    property bool bordered: false
    property string iconName: ""
    property int iconDay: new Date().getDate()
    property real iconSize: Style.space(16)
    property real maximumWidth: 10000
    property bool leftAligned: false
    padding: 0
    implicitHeight: Style.space(28)
    implicitWidth: Math.min(maximumWidth, text ? caption.implicitWidth + (iconName ? iconSize + Style.space(6) : 0) + Style.space(20) : implicitHeight)
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    Accessible.name: text || tip
    contentItem: Item {
        implicitWidth: contents.implicitWidth
        Row {
            id: contents
            anchors.verticalCenter: parent.verticalCenter
            anchors.horizontalCenter: root.leftAligned ? undefined : parent.horizontalCenter
            anchors.left: root.leftAligned ? parent.left : undefined
            anchors.leftMargin: Style.space(10)
            spacing: Style.space(6)
            opacity: root.enabled ? (root.selected || root.hovered ? 1 : 0.75) : 0.35
            ViewIcon { visible: root.iconName !== ""; name: root.iconName; day: root.iconDay; color: root.foreground; width: root.iconSize; height: width; anchors.verticalCenter: parent.verticalCenter }
            Label { id: caption; visible: text !== ""; width: Math.min(implicitWidth, Math.max(0, root.width - Style.space(20) - (root.iconName ? root.iconSize + contents.spacing : 0))); text: root.text; color: root.foreground; font.bold: root.bold; font.pixelSize: Style.font.bodySmall; anchors.verticalCenter: parent.verticalCenter }
        }
    }
    background: Rectangle {
        radius: Style.cornerRadius
        color: root.selected ? Style.selectedFillFor(root.foreground, Color.accent) : root.hovered || root.activeFocus ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent"
        border.width: root.selected || root.activeFocus || root.bordered ? 1 : 0
        border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, root.bordered ? 0.35 : 0.12)
    }
    Tip { visible: root.hovered && root.tip !== ""; text: root.tip }
}
