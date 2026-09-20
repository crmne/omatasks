import QtQuick
import QtQuick.Controls as C
import QtQuick.Layouts
import qs.Commons
import "../Model.js" as Model
import "OrderModel.js" as Order
import "BulkModel.js" as Bulk

FocusScope {
    id: root
    required property var service
    property string view: "today"
    property bool settingsOpen: false
    property string composerKey: ""
    property string composerProject: ""
    property var heldRows: null
    property var selectedTask: null
    property var selectedIds: []
    property var dragRows: null
    property int dragIndex: -1
    property int dropIndex: -1
    property bool dropAfter: false
    property real dragX: 0
    property real dragY: 0
    property real dropY: 0
    readonly property bool dragging: dragIndex >= 0
    readonly property var options: service.viewOptions(view)
    readonly property var rows: dragRows || heldRows || Model.viewRows(service.tasks, service.projects, service.collaborators, options, view, service.user.id, service.now)
    readonly property bool setupVisible: !service.configured || settingsOpen
    readonly property real preferredHeight: Math.min(Style.space(service.panelHeight), setupVisible ? setup.implicitHeight + Style.space(68) : Math.max(display.opened || details.opened || taskMenu.visible ? Style.space(440) : Style.space(110), list.contentHeight + header.height + status.height + selectionBar.height + Style.space(8)))
    signal closeRequested()

    function updateListModel() {
        if (!list) return;
        var offset = list.contentY - list.originY;
        list.model = rows;
        list.forceLayout();
        list.contentY = list.originY + Math.max(0, Math.min(offset, list.contentHeight - list.height));
    }
    onRowsChanged: {
        updateListModel();
        var visible = Bulk.visibleIds(rows);
        selectedIds = selectedIds.filter(function(id) { return visible.indexOf(id) >= 0; });
    }
    Component.onCompleted: updateListModel()

    function addAt(key, projectId) {
        clearSelection();
        heldRows = rows;
        composerProject = projectId || "";
        composerKey = key;
        Qt.callLater(function() { var index = root.rows.findIndex(function(row) { return row.key === key; }); if (index >= 0) list.positionViewAtIndex(index, ListView.Contain); });
    }
    function clearSelection() { selectedIds = []; taskMenu.close(); }
    function toggleSelection(task) {
        if (dragging || service.saving) return;
        selectedIds = Bulk.toggle(selectedIds, task.id);
        forceActiveFocus();
    }
    function openTaskMenu(task, point) {
        if (dragging || service.saving || composerKey) return;
        if (selectedIds.indexOf(String(task.id)) < 0) selectedIds = [String(task.id)];
        taskMenu.tasks = service.tasks.filter(function(t) { return root.selectedIds.indexOf(String(t.id)) >= 0; });
        taskMenu.location = point;
        display.close();
        taskMenu.open();
    }
    function reset() { clearSelection(); view = "today"; settingsOpen = false; display.close(); details.close(); }
    function showTask(task) { clearSelection(); selectedTask = task; details.open(); }
    function startDrag(index, point) {
        if (service.saving || composerKey || setupVisible || selectedIds.length) return;
        dragRows = rows;
        dragIndex = index;
        // ListView keeps its current delegate alive outside the cache while the
        // user scrolls. The pressed MouseArea must survive a long drag.
        list.currentIndex = index;
        forceActiveFocus();
        moveDrag(point);
    }
    function moveDrag(point) {
        if (!dragging) return;
        dragX = point.x; dragY = point.y;
        locateDrop();
    }
    function locateDrop() {
        dropIndex = -1;
        var point = list.mapFromItem(root, dragX, dragY);
        if (point.x < 0 || point.x > list.width || point.y < 0 || point.y > list.height) return;
        var y = point.y + list.contentY;
        var index = list.indexAt(Math.min(Style.space(40), list.width / 2), y);
        if (index < 0) return;
        var row = list.itemAtIndex(index);
        if (!row) return;
        var after = y > row.y + row.height / 2;
        // A group's Add task row also accepts a drop after its last task.
        if (rows[index].kind === "add" && index > 0) { index--; row = list.itemAtIndex(index); after = true; }
        if (!row || !Order.changedOrder(rows, dragIndex, index, after, view)) return;
        dropIndex = index; dropAfter = after;
        dropY = list.y + row.y - list.contentY + (after ? row.height : 0);
    }
    function cancelDrag() { dragIndex = -1; dropIndex = -1; dragRows = null; }
    function finishDrag() {
        if (!dragging) return;
        var source = rows[dragIndex], target = dropIndex >= 0 ? rows[dropIndex] : null, after = dropAfter;
        if (target) service.reorderTasks(view, String(source.task.id), String(target.task.id), after, source.groupKey);
        cancelDrag();
    }
    Keys.onEscapePressed: { if (dragging) cancelDrag(); else if (taskMenu.visible) { if (!taskMenu.busy) taskMenu.close(); } else if (display.opened) display.close(); else if (details.opened && detailLoader.item) detailLoader.item.dismissEditor(); else if (composerKey) composerKey = ""; else if (selectedIds.length) clearSelection(); else if (settingsOpen) settingsOpen = false; else closeRequested(); }
    Keys.onPressed: function(event) {
        if (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_Tab) {
            var tabs = ["today", "inbox", "upcoming"];
            if (!dragging) view = tabs[(tabs.indexOf(view) + (event.modifiers & Qt.ShiftModifier ? 2 : 1)) % 3]; event.accepted = true;
        }
        if (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_A && !dragging && !composerKey && !details.visible && !display.visible && !taskMenu.visible && !setupVisible) {
            selectedIds = Bulk.visibleIds(rows); event.accepted = true;
        }
    }
    onViewChanged: { cancelDrag(); clearSelection(); composerKey = ""; list.positionViewAtBeginning(); }
    onSetupVisibleChanged: if (setupVisible) { cancelDrag(); clearSelection(); }
    onVisibleChanged: if (!visible) { cancelDrag(); clearSelection(); }
    onComposerKeyChanged: if (!composerKey) heldRows = null

    RowLayout {
        id: header
        anchors.top: parent.top; width: parent.width
        height: Style.space(28); spacing: Style.space(4)
        Repeater {
            model: [{id: "today", title: "Today"}, {id: "inbox", title: "Inbox"}, {id: "upcoming", title: "Upcoming"}]
            Action {
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                Layout.minimumWidth: 0
                text: modelData.title
                iconName: modelData.id
                iconDay: root.service.now.getDate()
                bold: true
                selected: root.view === modelData.id && !root.settingsOpen
                onClicked: { root.view = modelData.id; root.settingsOpen = false; }
            }
        }
        Action { id: displayButton; objectName: "displayButton"; iconName: "display"; iconSize: Style.space(17); tip: "Display"; selected: display.opened; enabled: root.service.configured; onClicked: display.opened ? display.close() : display.open() }
        Action { iconName: "settings"; iconSize: Style.space(17); tip: "Settings"; selected: root.settingsOpen; onClicked: root.settingsOpen = !root.settingsOpen }
    }
    ColumnLayout {
        id: status
        anchors.top: header.bottom; anchors.topMargin: visible ? Style.space(10) : 0
        width: parent.width
        height: visible ? implicitHeight + Style.space(8) : 0
        visible: statusText.text !== ""
        spacing: Style.space(4)
        Label {
            id: statusText
            Layout.fillWidth: true
            text: root.service.error || (!root.service.loaded && root.service.configured ? "Loading tasks…" : "")
            color: root.service.error ? Color.urgent : Color.popups.text
            wrapMode: Text.WordWrap; elide: Text.ElideNone
            font.pixelSize: Style.font.bodySmall
        }
        Action {
            objectName: "retrySync"
            visible: root.service.configured && root.service.error !== ""
            text: root.service.loading ? "Retrying…" : "Retry now"
            enabled: !root.service.loading && !root.service.saving && !root.service.connecting
            onClicked: root.service.refresh(true)
        }
    }
    RowLayout {
        id: selectionBar
        anchors.top: status.bottom
        width: parent.width
        height: visible ? Style.space(34) : 0
        visible: root.selectedIds.length > 0 && !root.setupVisible
        Label { Layout.fillWidth: true; text: root.selectedIds.length + " selected"; color: Color.accent; font.pixelSize: Style.font.bodySmall }
        Action {
            text: "Actions…"; objectName: "selectionActions"; enabled: !root.service.saving
            onClicked: {
                var task = root.service.tasks.find(function(t) { return String(t.id) === root.selectedIds[0]; });
                if (task) root.openTaskMenu(task, mapToItem(root, 0, height));
            }
        }
        Action { text: "Clear"; enabled: !root.service.saving; onClicked: root.clearSelection() }
    }
    C.ScrollView {
        visible: root.setupVisible
        anchors.top: status.bottom; anchors.topMargin: Style.space(18)
        anchors.bottom: parent.bottom
        width: parent.width; clip: true
        contentWidth: availableWidth
        Settings { id: setup; width: parent.width; service: root.service }
    }
    ListView {
        id: list
        objectName: "taskListView"
        visible: !root.setupVisible
        anchors.top: selectionBar.bottom; anchors.topMargin: Style.space(8)
        anchors.bottom: parent.bottom
        width: parent.width
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: !root.dragging
        model: []
        spacing: 0
        cacheBuffer: Style.space(1000)
        C.ScrollBar.vertical: C.ScrollBar { policy: list.contentHeight > list.height ? C.ScrollBar.AsNeeded : C.ScrollBar.AlwaysOff }
        header: Label {
            width: list.width
            height: visible ? Style.space(60) : 0
            visible: root.service.loaded && !root.rows.some(function(row) { return row.kind === "task"; })
            text: "No tasks in this view."
            verticalAlignment: Text.AlignVCenter
            opacity: 0.5
        }
        delegate: Loader {
            id: rowLoader
            required property var modelData
            required property int index
            width: list.width - Style.space(4)
            height: item ? item.implicitHeight : 0
            sourceComponent: modelData.kind === "group" ? groupComponent : modelData.kind === "task" ? taskComponent : addComponent
            Component {
                id: groupComponent
                Item {
                    implicitHeight: Style.space(40)
                    Label { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.bottomMargin: Style.space(9); text: rowLoader.modelData.title; font.bold: true; color: text === "Overdue" ? "#ef615b" : Color.popups.text }
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Color.popups.text; opacity: 0.12 }
                }
            }
            Component {
                id: taskComponent
                TaskRow {
                    task: rowLoader.modelData.task; service: root.service; view: root.view; grouping: root.options.grouping
                    reorderEnabled: !root.service.saving && !root.composerKey && !root.selectedIds.length
                    selected: root.selectedIds.indexOf(String(task.id)) >= 0
                    dragging: root.dragIndex === rowLoader.index
                    listDragging: root.dragging
                    opacity: dragging ? 0.3 : 1
                    onActivated: function(task) { root.showTask(task); }
                    onSelectionToggled: function(task) { root.toggleSelection(task); }
                    onContextRequested: function(task, x, y) { root.openTaskMenu(task, mapToItem(root, x, y)); }
                    onDragStarted: function(x, y) { root.startDrag(rowLoader.index, mapToItem(root, x, y)); }
                    onDragMoved: function(x, y) { root.moveDrag(mapToItem(root, x, y)); }
                    onDragEnded: root.finishDrag()
                    onDragCancelled: root.cancelDrag()
                }
            }
            Component {
                id: addComponent
                Item {
                    implicitHeight: root.composerKey === rowLoader.modelData.key ? composerLoader.implicitHeight + Style.space(20) : Style.space(40)
                    Action {
                        visible: root.composerKey !== rowLoader.modelData.key
                        y: Style.space(5)
                        text: "+   Add task"
                        foreground: Color.popups.text
                        onClicked: root.addAt(rowLoader.modelData.key, rowLoader.modelData.projectId)
                    }
                    Loader {
                        id: composerLoader
                        y: Style.space(10)
                        active: root.composerKey === rowLoader.modelData.key
                        width: parent.width
                        sourceComponent: Composer {
                            service: root.service
                            initialProjectId: root.composerProject
                            initialDue: root.view === "today" ? "today" : ""
                            onFinished: root.composerKey = ""
                            onCancelled: root.composerKey = ""
                            Component.onCompleted: Qt.callLater(focusInput)
                        }
                    }
                }
            }
        }
    }
    Timer {
        interval: 16; repeat: true; running: root.dragging
        onTriggered: {
            var y = root.dragY - list.y, edge = Style.space(36), speed = 0;
            if (root.dragX < 0 || root.dragX > list.width) return;
            if (y >= -edge && y < edge) speed = -Math.min(12, (edge - y) / 3);
            else if (y > list.height - edge && y <= list.height + edge) speed = Math.min(12, (y - list.height + edge) / 3);
            if (!speed) return;
            list.contentY = Math.max(list.originY, Math.min(list.originY + Math.max(0, list.contentHeight - list.height), list.contentY + speed));
            root.locateDrop();
        }
    }
    Rectangle {
        objectName: "taskDropMarker"
        visible: root.dragging && root.dropIndex >= 0
        x: Style.space(31); y: root.dropY - 1
        width: root.width - x; height: Style.space(2)
        color: Color.accent; z: 2
    }
    Rectangle {
        visible: root.dragging
        x: Style.space(24); y: Math.max(list.y, Math.min(root.height - height, root.dragY + Style.space(18)))
        width: root.width - x; height: dragLabel.implicitHeight + Style.space(16)
        color: Color.popups.background; border.color: Color.popups.border
        radius: Style.cornerRadius; opacity: 0.95; z: 3
        Label {
            id: dragLabel
            anchors.centerIn: parent; width: parent.width - Style.space(20)
            text: root.dragging ? Model.plain(root.rows[root.dragIndex].task.content) : ""
            maximumLineCount: 1
        }
    }
    TaskMenu {
        id: taskMenu
        service: root.service
        onCompleted: root.clearSelection()
        onEditRequested: function(task) { root.showTask(task); Qt.callLater(function() { if (detailLoader.item) detailLoader.item.startEditing(); }); }
    }
    C.Popup {
        id: display
        objectName: "displayPopup"
        parent: displayButton
        x: displayButton.width - width; y: displayButton.height + Style.space(8)
        width: Math.min(root.width, Style.space(340))
        height: Math.min(root.height - y, displayOptions.implicitHeight + padding * 2)
        padding: Style.space(16)
        focus: true
        closePolicy: C.Popup.CloseOnEscape | C.Popup.CloseOnPressOutsideParent
        background: Rectangle { color: Color.popups.background; border.width: 1; border.color: Color.popups.border; radius: Style.cornerRadius }
        contentItem: C.ScrollView {
            clip: true; contentWidth: availableWidth
            DisplayOptions { id: displayOptions; width: parent.width; service: root.service; view: root.view }
        }
    }
    C.Popup {
        id: details
        objectName: "taskDetailsPopup"
        x: 0; y: header.height + Style.space(8)
        width: root.width
        height: Math.min(root.height - y, (detailLoader.item ? detailLoader.item.implicitHeight : 0) + padding * 2)
        padding: Style.space(16); focus: true
        closePolicy: detailLoader.item && (detailLoader.item.editing || detailLoader.item.busy) ? C.Popup.NoAutoClose : C.Popup.CloseOnEscape | C.Popup.CloseOnPressOutside
        background: Rectangle { color: Color.popups.background; border.width: 1; border.color: Color.popups.border; radius: Style.cornerRadius }
        contentItem: Loader {
            id: detailLoader
            active: details.visible && root.selectedTask !== null
            sourceComponent: TaskDetails {
                service: root.service
                task: root.selectedTask
                onCloseRequested: details.close()
                onTaskRequested: function(task) { root.showTask(task); }
            }
        }
    }
    Connections {
        target: root.service
        function onTasksChanged() {
            if (!root.selectedTask) return;
            var current = root.service.tasks.find(function(t) { return String(t.id) === String(root.selectedTask.id); });
            if (current) root.selectedTask = current;
            else if (details.visible && !(detailLoader.item && detailLoader.item.busy)) details.close();
        }
    }
    Connections { target: root.service; function onConnected() { if (root.service.configured) root.settingsOpen = false; } }
}
