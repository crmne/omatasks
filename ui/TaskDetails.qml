import QtQuick
import QtQuick.Controls as C
import QtQuick.Layouts
import qs.Commons
import "../Model.js" as Model
import "EditModel.js" as Edit

Item {
    id: root
    required property var service
    required property var task
    property bool editing: false
    property bool completing: false
    property string message: ""
    readonly property bool busy: completing || (editor.item ? editor.item.submitting : false)
    readonly property var subtasks: service.tasks.filter(function(t) { return String(t.parent_id) === String(root.task.id); })
    readonly property var taskReminders: service.reminders.filter(function(r) { return String(r.item_id) === String(root.task.id); })
    readonly property var parentTask: service.tasks.find(function(t) { return String(t.id) === String(root.task.parent_id); }) || null
    readonly property var person: Model.byId(service.collaborators)[Model.assigned(task)]
    readonly property int completedChildren: {
        var record = service.completedInfo.find(function(x) { return String(x.item_id) === String(root.task.id); });
        return record ? Number(record.completed_items) || 0 : 0;
    }
    readonly property var information: [
        {name: "Project", value: Model.projectPath(task.project_id, service.projectMap, task.section_id, service.sectionMap)},
        {name: "Date", value: task.due ? Model.dueLabel(task, service.now, "details", "none") + (task.due.timezone ? " · " + task.due.timezone : "") : "No date"},
        {name: "Repeat", value: task.due && task.due.is_recurring ? task.due.string || "Recurring" : ""},
        {name: "Duration", value: task.duration ? task.duration.amount + " " + (task.duration.unit === "day" ? "days" : "minutes") : ""},
        {name: "Deadline", value: task.deadline ? task.deadline.date : ""},
        {name: "Priority", value: "P" + (5 - Number(task.priority || 1)), color: ["#999999", "#999999", "#5297ff", "#eb9700", "#ef615b"][task.priority || 1]},
        {name: "Labels", value: (task.labels || []).join(" · ") || "None"},
        {name: "Assignee", value: person ? person.full_name || person.name || person.email : Model.assigned(task) === String(service.user.id) ? "Me" : Model.assigned(task) ? "Assigned user" : "Unassigned"}
    ].filter(function(row) { return row.value; })
    implicitHeight: body.implicitHeight + footer.implicitHeight + Style.space(14)
    signal closeRequested()
    signal taskRequested(var task)

    function startEditing() { editing = true; message = ""; scroll.contentItem.contentY = 0; Qt.callLater(function() { if (editor.item) editor.item.focusInput(); }); }
    function complete() { message = ""; completing = service.completeTask(task); if (!completing) message = service.error || "Please wait for the current request to finish."; }
    function dismissEditor() { if (busy) return; if (editing) editing = false; else closeRequested(); }

    C.ScrollView {
        id: scroll
        objectName: "taskDetailScroll"
        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
        anchors.bottom: footer.top; anchors.bottomMargin: Style.space(12)
        clip: true
        contentWidth: availableWidth
        C.ScrollBar.horizontal.policy: C.ScrollBar.AlwaysOff
        ColumnLayout {
            id: body
            width: scroll.availableWidth
            spacing: Style.space(12)
            ColumnLayout {
                visible: !root.editing
                Layout.fillWidth: true; Layout.minimumWidth: 0
                spacing: Style.space(12)
                RowLayout {
                    Layout.fillWidth: true; Layout.minimumWidth: 0
                    spacing: Style.space(5)
                    TaskCheck { Layout.alignment: Qt.AlignTop; task: root.task; enabled: !root.service.saving; onClicked: root.complete() }
                    Label { Layout.fillWidth: true; Layout.minimumWidth: 0; Layout.alignment: Qt.AlignTop; Layout.topMargin: Style.space(5); text: Model.plain(root.task.content); wrapMode: Text.Wrap; elide: Text.ElideNone; font.bold: true }
                }
                Label { Layout.fillWidth: true; Layout.minimumWidth: 0; text: root.task.description || ""; visible: text !== ""; wrapMode: Text.Wrap; elide: Text.ElideNone; opacity: 0.7 }
                Rectangle { Layout.fillWidth: true; height: 1; color: Color.popups.text; opacity: 0.12 }
                Repeater {
                    model: root.information
                    RowLayout {
                        required property var modelData
                        Layout.fillWidth: true; Layout.minimumWidth: 0
                        spacing: Style.space(10)
                        Label { Layout.preferredWidth: Style.space(70); Layout.alignment: Qt.AlignTop; text: modelData.name; opacity: 0.5; font.pixelSize: Style.font.bodySmall }
                        Label { Layout.fillWidth: true; Layout.minimumWidth: 0; text: modelData.value; color: modelData.color || Color.popups.text; wrapMode: Text.Wrap; elide: Text.ElideNone; font.pixelSize: Style.font.bodySmall }
                    }
                }
                Repeater {
                    model: root.taskReminders
                    RowLayout {
                        required property var modelData
                        Layout.fillWidth: true; Layout.minimumWidth: 0
                        spacing: Style.space(10)
                        Label { Layout.preferredWidth: Style.space(70); Layout.alignment: Qt.AlignTop; text: "Reminder"; opacity: 0.5; font.pixelSize: Style.font.bodySmall }
                        Label { Layout.fillWidth: true; Layout.minimumWidth: 0; text: Edit.reminderText(modelData); wrapMode: Text.Wrap; elide: Text.ElideNone; font.pixelSize: Style.font.bodySmall }
                    }
                }
                Action { visible: root.parentTask !== null; text: "↑ " + Model.plain((root.parentTask || {}).content); maximumWidth: root.width; tip: "Parent task"; onClicked: root.taskRequested(root.parentTask) }
                Label { visible: root.subtasks.length + root.completedChildren > 0; text: "Subtasks · " + root.completedChildren + "/" + (root.completedChildren + root.subtasks.length); font.bold: true }
                Repeater {
                    model: root.subtasks
                    TaskRow { required property var modelData; Layout.fillWidth: true; Layout.minimumWidth: 0; task: modelData; service: root.service; view: "details"; onActivated: function(task) { root.taskRequested(task); } }
                }
                Action { visible: Number(root.task.note_count || root.task.comment_count || 0) > 0; text: (root.task.note_count || root.task.comment_count || 0) + " comments · Open in Todoist ↗"; maximumWidth: root.width; onClicked: Qt.openUrlExternally("https://app.todoist.com/app/task/" + encodeURIComponent(root.task.id)) }
                Label { visible: !!root.task.added_at; Layout.fillWidth: true; Layout.minimumWidth: 0; text: root.task.added_at ? "Added " + Qt.formatDateTime(new Date(root.task.added_at), "d MMM yyyy, HH:mm") : ""; opacity: 0.4; font.pixelSize: Style.font.caption; wrapMode: Text.Wrap; elide: Text.ElideNone }
            }
            Loader {
                id: editor
                active: root.editing
                Layout.fillWidth: true; Layout.minimumWidth: 0
                sourceComponent: Composer {
                    service: root.service
                    editingTask: root.task
                    onFinished: root.editing = false
                    onCancelled: root.editing = false
                }
            }
            Label { Layout.fillWidth: true; Layout.minimumWidth: 0; visible: text !== ""; text: root.message; wrapMode: Text.Wrap; elide: Text.ElideNone; color: Color.urgent }
        }
    }
    ColumnLayout {
        id: footer
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        spacing: Style.space(6)
        RowLayout {
            Layout.fillWidth: true
            Action { objectName: "editTaskButton"; visible: !root.editing; text: "Edit"; bordered: true; enabled: !root.service.saving; onClicked: root.startEditing() }
            Action { text: "Open in Todoist ↗"; onClicked: Qt.openUrlExternally("https://app.todoist.com/app/task/" + encodeURIComponent(root.task.id)) }
            Item { Layout.fillWidth: true }
            Action { visible: !root.editing; text: "Close"; enabled: !root.busy; onClicked: root.dismissEditor() }
        }
    }
    Connections {
        target: root.service
        function onTaskCompleted(taskId) { if (taskId === String(root.task.id)) { root.completing = false; root.closeRequested(); } }
        function onOperationFailed(message) { if (root.completing) { root.completing = false; root.message = message; } }
    }
}
