import QtQuick
import QtQuick.Controls as C
import qs.Commons
import "../Model.js" as Model

C.AbstractButton {
    id: root
    required property var task
    readonly property color priorityColor: ["#999999", "#999999", "#5297ff", "#eb9700", "#ef615b"][task.priority || 1]
    implicitWidth: Style.space(26)
    implicitHeight: Style.space(28)
    Accessible.name: "Complete " + Model.plain(task.content)
    focusPolicy: Qt.StrongFocus
    background: Item {}
    contentItem: Item {
        Rectangle {
            anchors.centerIn: parent
            width: Style.space(16); height: width; radius: width / 2
            border.width: Style.space(1.5); border.color: root.priorityColor
            color: root.hovered || root.activeFocus ? Qt.rgba(root.priorityColor.r, root.priorityColor.g, root.priorityColor.b, 0.15) : "transparent"
            Label { anchors.centerIn: parent; text: "✓"; visible: root.hovered || root.activeFocus; font.pixelSize: Style.font.caption; color: root.priorityColor }
        }
    }
}
