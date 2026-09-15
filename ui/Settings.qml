import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui as UI

ColumnLayout {
    id: root
    required property var service
    spacing: Style.space(20)
    ColumnLayout {
        visible: root.service.configured
        Layout.fillWidth: true
        spacing: Style.space(8)
        Label { text: "Panel size"; font.bold: true }
        RowLayout {
            Layout.fillWidth: true
            Label { Layout.fillWidth: true; text: "Width" }
            SizeControl { value: root.service.panelWidth; from: 360; to: 1000; Accessible.name: "Panel width"; onValueModified: root.service.setPanelSize("panelWidth", value) }
        }
        RowLayout {
            Layout.fillWidth: true
            Label { Layout.fillWidth: true; text: "Maximum height" }
            SizeControl { value: root.service.panelHeight; from: 280; to: 1200; Accessible.name: "Maximum panel height"; onValueModified: root.service.setPanelSize("panelHeight", value) }
        }
        Label { Layout.fillWidth: true; text: "Pixels. The panel shrinks to fit shorter lists."; font.pixelSize: Style.font.caption; opacity: 0.5; wrapMode: Text.WordWrap; elide: Text.ElideNone }
    }
    Rectangle { visible: root.service.configured; Layout.fillWidth: true; height: 1; color: Color.popups.text; opacity: 0.12 }
    Setup { Layout.fillWidth: true; service: root.service }
    Rectangle { Layout.fillWidth: true; height: 1; color: Color.popups.text; opacity: 0.12 }
    ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(8)
        Label { text: "Quick add shortcut"; font.bold: true }
        RowLayout {
            Layout.fillWidth: true
            UI.TextField {
                id: shortcutInput
                Layout.fillWidth: true
                text: root.service.shortcut.value
                placeholderText: "Disabled"
                enabled: !root.service.shortcut.busy
                onAccepted: root.service.shortcut.apply(text, true)
            }
            Action { text: "Apply"; bordered: true; enabled: !root.service.shortcut.busy; onClicked: root.service.shortcut.apply(shortcutInput.text, true) }
        }
        Label { Layout.fillWidth: true; text: "Super, Ctrl, Alt, Shift + a key. Leave empty to disable."; wrapMode: Text.WordWrap; elide: Text.ElideNone; opacity: 0.5; font.pixelSize: Style.font.caption }
        Label {
            Layout.fillWidth: true
            visible: text !== ""
            text: root.service.shortcut.message
            color: root.service.shortcut.successful ? Color.popups.text : Color.urgent
            opacity: 0.7; wrapMode: Text.WordWrap; elide: Text.ElideNone; font.pixelSize: Style.font.caption
        }
    }
}
