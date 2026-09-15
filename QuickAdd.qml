import QtQuick
import QtQuick.Controls as C
import Quickshell
import Quickshell.Wayland
import qs.Commons
import "ui" as Tasks

Item {
    id: root
    property var shell: null
    property var manifest: null
    property bool opened: false
    property var service: shell ? shell.serviceFor("crmne.todoist") : null
    function open(payload) {
        if (!service) return;
        if (!service.configured) { opened = false; service.openPanel(); return; }
        if (service) service.closePanels();
        opened = true;
        Qt.callLater(function() { composer.focusInput(); });
    }
    function close() { opened = false; }
    function dismiss() { close(); if (shell) shell.hide("crmne.todoist"); }
    function toggle() { if (opened) dismiss(); else open("{}"); }

    PanelWindow {
        id: window
        visible: root.opened && root.service !== null
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.namespace: "omarchy-todoist-quick-add"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        MouseArea { anchors.fill: parent; onClicked: root.dismiss() }
        Rectangle {
            id: card
            anchors.centerIn: parent
            width: Math.min(Style.space(460), window.width - Style.space(32))
            height: Math.min(composer.implicitHeight + Style.space(36), window.height - Style.space(32))
            color: Color.popups.background
            border.color: Color.popups.border; border.width: 1; radius: Style.cornerRadius
            MouseArea { anchors.fill: parent }
            C.ScrollView {
                anchors.fill: parent
                anchors.margins: Style.space(18)
                contentWidth: availableWidth
                clip: true
                Tasks.Composer {
                    id: composer
                    width: parent.width
                    service: root.service
                    onFinished: root.dismiss()
                    onCancelled: root.dismiss()
                }
            }
        }
    }
}
