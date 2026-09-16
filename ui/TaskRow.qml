import QtQuick
import qs.Commons
import "../Model.js" as Model

Item {
    id: root
    required property var task
    required property var service
    property string view: "today"
    property string grouping: "none"
    property bool reorderEnabled: false
    property bool dragging: false
    property bool listDragging: false
    property bool selected: false
    signal activated(var task)
    signal selectionToggled(var task)
    signal contextRequested(var task, real x, real y)
    signal dragStarted(real x, real y)
    signal dragMoved(real x, real y)
    signal dragEnded()
    signal dragCancelled()
    readonly property string dueText: Model.dueLabel(task, service.now, view, grouping)
    readonly property string projectText: Model.projectPath(task.project_id, service.projectMap, task.section_id, service.sectionMap)
    readonly property int childCount: service.tasks.filter(function(t) { return String(t.parent_id) === String(root.task.id); }).length
    readonly property int completedChildren: {
        var info = service.completedInfo.filter(function(x) { return String(x.item_id) === String(root.task.id); })[0];
        return info ? Number(info.completed_items) || 0 : 0;
    }
    readonly property bool hasReminder: service.reminders.some(function(r) { return String(r.item_id) === String(root.task.id); })
    readonly property var person: Model.byId(service.collaborators)[Model.assigned(task)]
    readonly property var metadata: {
        var parts = [];
        if (childCount + completedChildren) parts.push({text: "⑂ " + completedChildren + "/" + (childCount + completedChildren), color: Color.popups.text});
        if (dueText) parts.push({text: "▣ " + dueText, color: Model.overdue(task, service.now) ? "#ef615b" : "#4baf63"});
        if ((task.due || {}).is_recurring) parts.push({text: "↻", color: "#4baf63"});
        if (hasReminder) parts.push({text: "◷", color: Color.popups.text});
        if (task.deadline) parts.push({text: "⚑ " + Model.dayLabel(task.deadline.date, Model.dateKey(service.now)), color: "#b58ce8"});
        (task.labels || []).forEach(function(label) { parts.push({text: "♢ " + label, color: "#5297ff"}); });
        if (person) parts.push({text: person.full_name || person.name, color: Color.popups.text});
        return parts;
    }
    implicitHeight: content.implicitHeight + Style.space(18)

    Rectangle { anchors.fill: parent; color: root.selected ? Style.selectedFillFor(Color.popups.text, Color.accent) : Style.hoverFillFor(Color.popups.text, Color.accent); visible: root.selected || hover.hovered; opacity: root.selected ? 1 : 0.5; radius: Style.cornerRadius }
    Rectangle { anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom; width: Style.space(2); color: Color.accent; visible: root.selected }
    HoverHandler { id: hover }
    MouseArea {
        id: pointer
        objectName: "taskPointer_" + root.task.id
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        preventStealing: root.reorderEnabled
        cursorShape: root.listDragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
        property real pressX: 0
        property real pressY: 0
        property bool moved: false
        property bool canDrag: false
        onPressed: function(mouse) { pressX = mouse.x; pressY = mouse.y; moved = false; canDrag = mouse.button === Qt.LeftButton && !(mouse.modifiers & Qt.ControlModifier); }
        onPositionChanged: function(mouse) {
            if (!pressed || !canDrag || !root.reorderEnabled) return;
            if (!moved && Math.hypot(mouse.x - pressX, mouse.y - pressY) >= Qt.styleHints.startDragDistance) {
                moved = true; root.dragStarted(mouse.x, mouse.y);
            }
            if (moved) root.dragMoved(mouse.x, mouse.y);
        }
        onReleased: { if (moved) root.dragEnded(); }
        onCanceled: { if (moved) root.dragCancelled(); }
        onClicked: function(mouse) {
            if (moved) return;
            if (mouse.button === Qt.RightButton) root.contextRequested(root.task, mouse.x, mouse.y);
            else if (mouse.modifiers & Qt.ControlModifier) root.selectionToggled(root.task);
            else root.activated(root.task);
        }
    }
    TaskCheck {
        x: 0; y: Style.space(5)
        task: root.task
        enabled: !root.service.saving && !root.listDragging
        onClicked: root.service.completeTask(root.task)
    }
    MouseArea {
        // Modified clicks on the completion circle select instead of completing.
        x: 0; y: Style.space(5); width: Style.space(26); height: Style.space(28)
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: function(mouse) { if (mouse.button === Qt.LeftButton && !(mouse.modifiers & Qt.ControlModifier)) mouse.accepted = false; }
        onClicked: function(mouse) {
            if (mouse.button === Qt.RightButton) root.contextRequested(root.task, x + mouse.x, y + mouse.y);
            else root.selectionToggled(root.task);
        }
    }
    Column {
        id: content
        anchors.left: parent.left; anchors.leftMargin: Style.space(31)
        anchors.right: parent.right; anchors.rightMargin: Style.space(3)
        y: Style.space(9)
        spacing: Style.space(4)
        Label {
            width: parent.width
            text: Model.plain(root.task.content)
            wrapMode: Text.WordWrap
            maximumLineCount: 2
        }
        Label {
            visible: text !== ""
            width: parent.width
            text: Model.plain(root.task.description)
            font.pixelSize: Style.font.bodySmall
            opacity: 0.6
        }
        Item {
            width: parent.width
            height: Style.space(16)
            Row {
                anchors.left: parent.left
                anchors.right: project.left
                anchors.rightMargin: Style.space(8)
                height: parent.height
                spacing: Style.space(6)
                clip: true
                Repeater {
                    model: root.metadata
                    Label { required property var modelData; text: modelData.text; color: modelData.color; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
                }
            }
            Label {
                id: project
                anchors.right: parent.right
                width: Math.min(implicitWidth, parent.width * (root.metadata.length ? 0.4 : 0.85))
                text: root.projectText + "  #"
                horizontalAlignment: Text.AlignRight
                font.pixelSize: Style.font.caption
                opacity: 0.55
            }
        }
    }
    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Color.popups.text; opacity: 0.09 }
    Tip { visible: hover.hovered && !root.listDragging && !root.selected; text: root.projectText + (root.task.description ? "\n" + Model.plain(root.task.description) : ""); delay: 1200 }
}
