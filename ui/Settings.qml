import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui as UI

ColumnLayout {
    id: root
    required property var service
    readonly property string fontFamily: service.fontFamily
    spacing: Style.space(20)
    ColumnLayout {
        visible: root.service.configured
        Layout.fillWidth: true
        spacing: Style.space(8)
        Label { font.family: root.fontFamily; text: "Panel size"; font.bold: true }
        RowLayout {
            Layout.fillWidth: true
            Label { font.family: root.fontFamily; Layout.fillWidth: true; text: "Width" }
            SizeControl { font.family: root.fontFamily; value: root.service.panelWidth; from: 360; to: 1000; Accessible.name: "Panel width"; onValueModified: root.service.setPanelSize("panelWidth", value) }
        }
        RowLayout {
            Layout.fillWidth: true
            Label { font.family: root.fontFamily; Layout.fillWidth: true; text: "Maximum height" }
            SizeControl { font.family: root.fontFamily; value: root.service.panelHeight; from: 280; to: 1200; Accessible.name: "Maximum panel height"; onValueModified: root.service.setPanelSize("panelHeight", value) }
        }
        Label { font.family: root.fontFamily; Layout.fillWidth: true; text: "Pixels. The panel shrinks to fit shorter lists."; font.pixelSize: Style.font.caption; opacity: 0.5; wrapMode: Text.WordWrap; elide: Text.ElideNone }
    }
    Rectangle { visible: root.service.configured; Layout.fillWidth: true; height: 1; color: Color.popups.text; opacity: 0.12 }
    Setup { Layout.fillWidth: true; service: root.service }
    Rectangle { Layout.fillWidth: true; height: 1; color: Color.popups.text; opacity: 0.12 }
    ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(8)
        Label { font.family: root.fontFamily; text: "Quick add shortcut"; font.bold: true }
        RowLayout {
            Layout.fillWidth: true
            UI.TextField { font.family: root.fontFamily;
                id: shortcutInput
                Layout.fillWidth: true
                text: root.service.shortcut.value
                placeholderText: "Disabled"
                enabled: !root.service.shortcut.busy
                onAccepted: root.service.shortcut.apply(text, true)
            }
            Action { fontFamily: root.fontFamily; text: "Apply"; bordered: true; enabled: !root.service.shortcut.busy; onClicked: root.service.shortcut.apply(shortcutInput.text, true) }
        }
        Label { font.family: root.fontFamily; Layout.fillWidth: true; text: "Super, Ctrl, Alt, Shift + a key. Leave empty to disable."; wrapMode: Text.WordWrap; elide: Text.ElideNone; opacity: 0.5; font.pixelSize: Style.font.caption }
        Label { font.family: root.fontFamily;
            Layout.fillWidth: true
            visible: text !== ""
            text: root.service.shortcut.message
            color: root.service.shortcut.successful ? Color.popups.text : Color.urgent
            opacity: 0.7; wrapMode: Text.WordWrap; elide: Text.ElideNone; font.pixelSize: Style.font.caption
        }
    }
}
