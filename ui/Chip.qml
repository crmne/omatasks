import QtQuick
import qs.Commons

Item {
    id: root
    property string text: ""
    property string iconName: ""
    property color foreground: Color.popups.text
    property bool removable: false
    property real maximumWidth: Style.space(220)
    signal clicked()
    signal removed()
    implicitHeight: Style.space(26)
    implicitWidth: Math.min(maximumWidth, main.implicitWidth + (removable ? remove.width : 0))
    Rectangle { anchors.fill: parent; color: "transparent"; border.width: 1; border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.22); radius: Style.cornerRadius }
    Action { id: main; width: parent.width - (root.removable ? remove.width : 0); height: parent.height; text: root.text; iconName: root.iconName; iconSize: Style.space(14); foreground: root.foreground; tip: root.text; onClicked: root.clicked() }
    Action { id: remove; anchors.right: parent.right; visible: root.removable; width: Style.space(22); height: parent.height; iconName: "close"; iconSize: Style.space(12); tip: "Remove " + root.text; onClicked: root.removed() }
}
