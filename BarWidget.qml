import QtQuick
import qs.Commons
import qs.Ui
import "ui" as Tasks

Panel {
    id: root
    moduleName: "crmne.todoist"
    ipcTarget: ""
    readonly property var service: bar && bar.shell ? bar.shell.serviceFor(moduleName) : null
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight
    onServiceChanged: if (service) service.registerWidget(root)
    Component.onCompleted: if (service) service.registerWidget(root)
    Component.onDestruction: if (service) service.unregisterWidget(root)
    onOpenedChanged: if (opened && service) { taskList.reset(); if (Date.now() - service.lastSync > 15000) service.refresh(); }

    WidgetButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        labelVisible: false
        hasVisualContent: true
        fixedWidth: vertical ? barSize : readout.implicitWidth + scaledHorizontalMargin * 2
        fixedHeight: vertical ? readout.implicitHeight + scaledVerticalPadding * 2 : barSize
        tooltipText: root.service && root.service.error ? root.service.error : "Todoist · Today\nRight-click: quick add"
        onPressed: function(mouseButton) {
            if (mouseButton === Qt.RightButton && root.bar && root.bar.shell) { root.close(); root.bar.shell.summon(root.moduleName, "{}"); }
            else if (mouseButton === Qt.MiddleButton && root.service) root.service.refresh();
            else root.toggle();
        }
        Grid {
            id: readout
            anchors.centerIn: parent
            columns: button.vertical ? 1 : 2
            spacing: Style.space(5)
            Tasks.TodoistIcon { color: button.foreground; width: Style.space(14); height: width }
            Text {
                visible: root.service && root.service.loaded
                text: root.service ? root.service.todayCount : ""
                font.family: button.fontFamily; font.pixelSize: button.fontSize
                color: button.foreground
            }
        }
    }
    KeyboardPanel {
        id: panel
        anchorItem: root; owner: root; bar: root.bar
        open: root.opened && root.service !== null
        focusTarget: taskList
        contentWidth: fittedContentWidth(Style.space(root.service ? root.service.panelWidth : 420))
        contentHeight: fittedContentHeight(taskList.preferredHeight, Style.space(root.service ? root.service.panelHeight : 560))
        Tasks.TaskList {
            id: taskList
            anchors.fill: parent
            service: root.service
            onCloseRequested: root.close()
        }
    }
}
