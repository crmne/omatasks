import QtQuick
import qs.Commons
import qs.Ui
import "ui" as Tasks
import "ui/BarModel.js" as Bar

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
    // The bar gives each section no limit, so a long task name would run into
    // the next section. `textRoom` is how wide the text may grow: its width now
    // plus the gap to that section, less a margin.
    property real textRoom: Infinity
    function measureRoom() {
        if (button.vertical || !root.service || root.service.barText === "") { textRoom = Infinity; return; }
        var top = root, region = "";
        for (var p = root; p; p = p.parent) {
            if (!region && typeof p.region === "string") region = p.region;
            top = p;
        }
        var boxes = [];
        function walk(item) {
            if (!item || !item.visible) return;
            // The bar's module lists and the centre anchor slot name their section.
            if (typeof item.region === "string" && item.region !== "" && (item.entries !== undefined || item.entry !== undefined)) {
                if (item.width > 0) {
                    var at = item.mapToItem(top, 0, 0);
                    boxes.push({region: item.region, left: at.x, right: at.x + item.width});
                }
                return;
            }
            for (var i = 0; i < item.children.length; i++) walk(item.children[i]);
        }
        walk(top);
        textRoom = Math.max(0, label.width + Bar.sectionGap(region, boxes) - Style.space(16));
    }
    Timer { interval: 2000; running: root.service !== null && root.service.barText !== "" && !button.vertical; repeat: true; triggeredOnStart: true; onTriggered: root.measureRoom() }
    onOpenedChanged: if (opened && service) { taskList.reset(); if (Date.now() - service.lastSync > 15000) service.refresh(); }

    WidgetButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        labelVisible: false
        hasVisualContent: true
        fixedWidth: vertical ? barSize : readout.implicitWidth + scaledHorizontalMargin * 2
        fixedHeight: vertical ? readout.implicitHeight + scaledVerticalPadding * 2 : barSize
        tooltipText: !root.service ? "" : root.service.error ? root.service.error
            : (root.service.barTasks.length ? Bar.tooltip(root.service.barTasks, root.service.now.getTime()) + "\n\n" : "") + "Todoist · Today\nRight-click: quick add"
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
            Row {
                id: label
                objectName: "barReadout"
                visible: root.service && root.service.loaded && root.service.barMode !== "icon"
                onWidthChanged: Qt.callLater(root.measureRoom)
                // A vertical bar has no room for a task name. When the name
                // does not fit, it is shortened, then dropped, then the count shows.
                readonly property string stage: {
                    if (!root.service || root.service.barText === "" || button.vertical) return "count";
                    var detail = detailMetrics.advanceWidth;
                    if (root.textRoom >= titleMetrics.advanceWidth + separatorMetrics.advanceWidth + detail) return "full";
                    if (root.textRoom >= shortMetrics.advanceWidth + separatorMetrics.advanceWidth + detail) return "short";
                    return root.textRoom >= detail ? "detail" : "count";
                }
                Text {
                    objectName: "barTitle"
                    visible: label.stage === "full" || label.stage === "short"
                    width: label.stage === "full" ? implicitWidth : Math.max(0, root.textRoom - separatorMetrics.advanceWidth - detailMetrics.advanceWidth)
                    text: root.service ? root.service.barTitle : ""
                    elide: Text.ElideRight
                    font.family: button.fontFamily; font.pixelSize: button.fontSize
                    color: button.foreground
                }
                Text {
                    objectName: "barDetail"
                    text: !root.service ? "" : label.stage === "count" ? root.service.todayCount
                        : (label.stage === "detail" ? "" : separatorMetrics.text) + root.service.barDetail
                    font.family: button.fontFamily; font.pixelSize: button.fontSize
                    color: button.foreground
                }
                TextMetrics { id: titleMetrics; font.family: button.fontFamily; font.pixelSize: button.fontSize; text: root.service ? root.service.barTitle : "" }
                TextMetrics { id: shortMetrics; font: titleMetrics.font; text: "Abc…" }
                TextMetrics { id: separatorMetrics; font: titleMetrics.font; text: " · " }
                TextMetrics { id: detailMetrics; font: titleMetrics.font; text: root.service ? root.service.barDetail : "" }
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
