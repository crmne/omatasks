import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui as UI
import "../Model.js" as Model

ColumnLayout {
    id: root
    required property var service
    readonly property string fontFamily: service.fontFamily
    spacing: Style.space(14)
    function focusInput() { tokenInput.forceActiveFocus(); }
    Label { font.family: root.fontFamily; text: root.service.configured ? "Todoist account" : "Connect to Todoist"; font.bold: true; font.pixelSize: Style.font.heading }
    Label { font.family: root.fontFamily;
        Layout.fillWidth: true
        text: "Open Todoist → Settings → Integrations → Developer. Copy your API token and paste it below."
        wrapMode: Text.WordWrap
        elide: Text.ElideNone
        opacity: 0.7
    }
    Action { fontFamily: root.fontFamily; text: "Open Developer settings ↗"; bordered: true; onClicked: Qt.openUrlExternally(Model.TOKEN_URL) }
    UI.TextField {
        id: tokenInput
        Layout.fillWidth: true
        password: true
        font.family: root.fontFamily
        placeholderText: root.service.configured ? "Paste a replacement API token" : "Paste your API token"
        enabled: !root.service.connecting
        onAccepted: root.service.connectToken(text)
    }
    RowLayout {
        Action { fontFamily: root.fontFamily;
            text: root.service.connecting ? "Connecting…" : "Connect"
            selected: true
            enabled: tokenInput.text.trim().length > 0 && !root.service.connecting
            onClicked: root.service.connectToken(tokenInput.text)
        }
        Action { fontFamily: root.fontFamily; visible: root.service.configured; text: "Disconnect"; enabled: !root.service.connecting && !root.service.saving; onClicked: root.service.disconnect() }
    }
    Label { font.family: root.fontFamily; Layout.fillWidth: true; text: "Your token stays on this computer."; opacity: 0.45; font.pixelSize: Style.font.caption }
    Connections { target: root.service; function onConnected() { tokenInput.text = ""; } }
}
