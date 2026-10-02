import QtQuick
import QtQuick.Controls as C
import QtQuick.Layouts
import qs.Commons
import qs.Ui as UI
import "../Model.js" as Model
import "ComposerModel.js" as Draft
import "EditModel.js" as Edit

ColumnLayout {
    id: root
    required property var service
    readonly property string fontFamily: service.fontFamily
    property var editingTask: null
    property var originalTask: null
    property var pendingCommands: []
    property var commandCache: ({})
    property var removedReminders: []
    property string replacingReminder: ""
    property string duration: "0"
    property string durationUnit: "minute"
    readonly property bool editing: editingTask !== null
    readonly property var existingReminders: editing ? service.reminders.filter(function(r) { return String(r.item_id) === String(editingTask.id) && removedReminders.indexOf(String(r.id)) < 0; }) : []
    property string initialProjectId: ""
    property string initialDue: ""
    property var project: service.projectMap[initialProjectId] || null
    property var section: null
    property var taskLabels: []
    property int priority: 0
    property string due: initialDue
    property string deadline: ""
    property string reminder: ""
    property var assignee: null
    property bool descriptionVisible: false
    property string requestId: ""
    property string sentText: ""
    property bool submitting: false
    property string message: ""
    property alias text: input.text
    property string pickerKind: ""
    property var activeToken: null
    property bool editingToken: false
    property int choiceIndex: 0
    property var highlightSpans: []
    readonly property var parsed: editing ? {tokens: [], labels: []} : Draft.parse(input.text, service, project)
    readonly property var shownProject: parsed.project || project
    readonly property var shownSection: parsed.section || section
    readonly property var shownAssignee: parsed.assignee || assignee
    readonly property int shownPriority: parsed.priority || priority
    readonly property string shownDeadline: parsed.deadline || deadline
    readonly property string shownReminder: parsed.reminder || reminder
    readonly property string shownDuration: parsed.duration || ""
    readonly property var shownLabels: taskLabels.concat(parsed.labels.filter(function(l) { return taskLabels.indexOf(l) < 0; }))
    readonly property var choices: Draft.choices(pickerKind, activeToken ? activeToken.query.replace(/\\(.)/g, "$1") : search.text, service, shownProject)
    readonly property var inbox: service.projects.find(function(p) { return p.inbox_project; }) || null
    readonly property string projectName: shownProject ? shownProject.name : "Inbox"
    readonly property var typedDate: parsed.tokens.filter(function(t) { return t.kind === "due"; }).slice(-1)[0] || null
    readonly property string shownDate: typedDate ? /^no (?:due )?date$/i.test(typedDate.value) ? "" : typedDate.value : due
    readonly property bool dark: Color.popups.background.r * 0.299 + Color.popups.background.g * 0.587 + Color.popups.background.b * 0.114 < 0.5
    onParsedChanged: Qt.callLater(updateHighlights)
    signal finished()
    signal cancelled()
    spacing: Style.space(10)
    Component.onCompleted: if (editing) loadTask()

    function loadTask() {
        originalTask = JSON.parse(JSON.stringify(editingTask));
        var data = Edit.snapshot(originalTask);
        input.text = data.text; description.text = data.description; descriptionVisible = true;
        project = service.projectMap[data.projectId] || {id: data.projectId, name: "Project"};
        section = service.sectionMap[data.sectionId] || null;
        taskLabels = data.labels; priority = data.priority; due = data.due; deadline = data.deadline;
        duration = String(data.duration); durationUnit = data.durationUnit;
        var person = Model.byId(service.collaborators)[data.assigneeId];
        assignee = data.assigneeId ? {id: data.assigneeId, name: person ? person.full_name || person.name : "Assigned user"} : null;
    }
    function submitEdit() {
        var change;
        try {
            change = Edit.changes(originalTask, {text: input.text, description: description.text, projectId: String((project || {}).id || ""), sectionId: String((section || {}).id || ""), labels: taskLabels, priority: priority || 4, due: due, deadline: deadline, assigneeId: String((assignee || {}).id || ""), duration: duration, durationUnit: durationUnit}, service.now);
        } catch (e) { message = e.message; return; }
        var specs = [], id = String(originalTask.id);
        if (change.move) specs.push({type: "item_move", args: Object.assign({id: id}, change.move)});
        if (Object.keys(change.update).length) specs.push({type: "item_update", args: Object.assign({id: id}, change.update)});
        removedReminders.forEach(function(r) { specs.push({type: "reminder_delete", args: {id: r}}); });
        if (reminder) specs.push({type: "reminder_add", args: Edit.reminderArgs(reminder, id)});
        if (!specs.length) { finished(); return; }
        var signature = JSON.stringify(specs);
        pendingCommands = specs.map(function(spec) {
            var key = JSON.stringify(spec);
            if (!root.commandCache[key]) {
                var command = Object.assign({uuid: Model.uuid()}, spec);
                if (spec.type === "reminder_add") command.temp_id = Model.uuid();
                root.commandCache[key] = command;
            }
            return root.commandCache[key];
        });
        sentText = signature; message = "";
        submitting = service.updateTask(id, pendingCommands);
        if (!submitting) message = service.error || "Please wait for the current request to finish.";
    }

    function focusInput() { input.forceActiveFocus(); }
    function reset() {
        input.text = ""; description.text = ""; descriptionVisible = false;
        project = service.projectMap[initialProjectId] || null; section = null; taskLabels = [];
        priority = 0; due = initialDue; deadline = ""; reminder = ""; assignee = null;
        pickerKind = ""; activeToken = null; requestId = ""; message = "";
    }
    function closePicker() { pickerKind = ""; activeToken = null; }
    function openPicker(kind) {
        if (pickerKind === kind && !activeToken) { closePicker(); focusInput(); return; }
        activeToken = null; search.text = ""; pickerKind = kind; choiceIndex = 0;
        Qt.callLater(function() { search.forceActiveFocus(); });
    }
    function updateToken() {
        if (editing || editingToken || input.inputMethodComposing || !input.activeFocus) return;
        var token = Draft.tokenAt(input.text, input.cursorPosition);
        // A complete shortcut is already reflected in the chips. Keep it in
        // the title, with a highlight, and stop offering autocomplete for it.
        if (token && (token.kind !== "label" || /\s$/.test(token.query)) && parsed.tokens.some(function(t) { return t.start === token.start && t.end <= input.cursorPosition; })) token = null;
        if (token) { activeToken = token; pickerKind = token.kind; choiceIndex = 0; }
        else if (activeToken) closePicker();
    }
    function removeTyped(kind, value) {
        var tokens = parsed.tokens.filter(function(t) { return t.kind === kind && (value === undefined || t.value === value); });
        editingToken = true;
        tokens.slice().reverse().forEach(function(t) { input.remove(t.start, t.end); });
        editingToken = false;
        closePicker();
    }
    function clearProperty(kind, value) {
        removeTyped(kind, value);
        if (kind === "priority") priority = 0;
        if (kind === "deadline") deadline = "";
        if (kind === "reminder") reminder = "";
        if (kind === "section") section = null;
        if (kind === "assignee") assignee = null;
        if (kind === "label") taskLabels = taskLabels.filter(function(l) { return l !== value; });
    }
    function priorityColor(value) { return value > 0 && value < 4 ? (dark ? ["#ff5c50", "#ff9a00", "#438eff"] : ["#d1453b", "#eb8909", "#246fe0"])[value - 1] : Color.popups.text; }
    function dateColor(value) {
        if (!value) return Color.popups.text;
        var offset = Draft.dateOffset(value, service.now, service.user);
        if (offset === null || offset > 7) return Color.popups.text;
        if (offset < 0) return priorityColor(1);
        if (offset === 0) return dark ? "#25b84c" : "#058527";
        if (offset === 1) return dark ? "#ff9a00" : "#ad6200";
        return dark ? "#b38ded" : "#692fc2";
    }
    function highlightColor(token) {
        if (token.kind === "due" || token.kind === "deadline" || token.kind === "priority" && token.value === 1) return dark ? "#722724" : "#ffe3e3";
        if (token.kind === "priority" && token.value === 2) return dark ? "#714b20" : "#fff0d1";
        if (token.kind === "priority" && token.value === 3) return dark ? "#244771" : "#e1edff";
        return dark ? "#414141" : "#eeeeee";
    }
    function highlightRects() {
        // Observe text layout changes, including font changes and wrapping.
        input.cursorRectangle; input.width; input.contentHeight; input.font;
        var rects = [];
        parsed.tokens.forEach(function(token) {
            if (token.kind === "due" && token !== root.typedDate) return;
            if (token.end > input.length) return;
            var segment = null;
            for (var i = token.start; i < token.end; i++) {
                var first = input.positionToRectangle(i), last = input.positionToRectangle(i + 1);
                if (!segment || segment.y !== first.y) {
                    segment = {kind: token.kind, value: token.value, x: first.x - 2, y: first.y, width: 0, height: first.height};
                    rects.push(segment);
                }
                segment.width = Math.max(segment.width, (last.y === first.y ? last.x : first.x + metrics.advanceWidth(input.text[i])) - segment.x + 2);
            }
        });
        return rects;
    }
    function updateHighlights() { highlightSpans = highlightRects(); }
    function setDate(value) {
        removeTyped("due");
        due = value;
    }
    function choose(row) {
        if (!row) return;
        var kind = pickerKind, token = activeToken;
        if (!editing && token) {
            editingToken = true;
            input.remove(token.start, token.end);
            var spelling = row.value ? Draft.spelling(kind, row.value) + " " : "";
            input.insert(token.start, spelling);
            input.cursorPosition = token.start + spelling.length;
            closePicker(); focusInput(); editingToken = false;
            return;
        }
        if (!editing) {
            if (kind === "project") { removeTyped("section"); removeTyped("assignee"); }
            if (kind !== "label") removeTyped(kind);
        }
        if (kind === "project") { project = row.value; section = null; assignee = null; }
        if (kind === "section") section = row.value;
        if (kind === "label" && taskLabels.indexOf(row.value) < 0) taskLabels = taskLabels.concat([row.value]);
        if (kind === "priority") priority = row.value;
        if (kind === "due") setDate(row.value);
        if (kind === "deadline") deadline = row.value;
        if (kind === "reminder") {
            if (replacingReminder && removedReminders.indexOf(replacingReminder) < 0) removedReminders = removedReminders.concat([replacingReminder]);
            replacingReminder = ""; reminder = row.value;
        }
        if (kind === "assignee") assignee = row.value;
        editingToken = true;
        if (token) { input.remove(token.start, token.end); input.cursorPosition = token.start; }
        closePicker(); focusInput(); editingToken = false;
    }
    function moveChoice(step) {
        if (!choices.length) return;
        choiceIndex = (choiceIndex + step + choices.length) % choices.length;
        suggestions.positionViewAtIndex(choiceIndex, ListView.Contain);
    }
    function handleKey(event) {
        if (pickerKind) {
            if (event.key === Qt.Key_Escape) { closePicker(); focusInput(); event.accepted = true; }
            else if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) { moveChoice(event.key === Qt.Key_Down ? 1 : -1); event.accepted = true; }
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Tab) { choose(choices[choiceIndex]); event.accepted = true; }
        } else if (event.key === Qt.Key_Escape) { cancelled(); event.accepted = true; }
        else if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) { submit(); event.accepted = true; }
        else if (event.key === Qt.Key_Down && input.activeFocus) { descriptionVisible = true; description.forceActiveFocus(); event.accepted = true; }
    }
    function submit() {
        if (!input.text.trim() || submitting) return;
        if (editing) { submitEdit(); return; }
        var text = Draft.quickText({text: input.text, description: description.text, project: project,
            section: section, labels: taskLabels, priority: priority, due: due,
            deadline: deadline, reminder: reminder, assignee: assignee, parsed: parsed});
        if (sentText !== text || !requestId) requestId = Model.uuid();
        sentText = text; message = "";
        submitting = service.addTask(text, requestId);
        if (!submitting) message = service.error || "Please wait for the current request to finish.";
    }

    FontMetrics { id: metrics; font: input.font }
    C.TextArea {
        id: input
        objectName: "taskName"
        Layout.fillWidth: true
        implicitHeight: Math.max(Style.space(30), contentHeight)
        wrapMode: TextEdit.Wrap
        textFormat: TextEdit.PlainText
        padding: 0; color: Color.popups.text
        font.family: root.fontFamily; font.pixelSize: Style.font.body; font.bold: true
        placeholderText: "Task name"; placeholderTextColor: Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.4)
        selectionColor: Color.accent; selectedTextColor: Color.popups.background
        // Keep a plain TextArea for cursor movement, selection, undo, paste
        // and input methods. Only the recognized spans' backgrounds are drawn.
        background: Item {
            clip: true
            Repeater {
                model: root.highlightSpans
                Rectangle {
                    required property var modelData
                    objectName: "highlight_" + modelData.kind
                    x: modelData.x; y: modelData.y
                    width: modelData.width; height: modelData.height
                    radius: 2
                    color: root.highlightColor(modelData)
                }
            }
        }
        enabled: !root.submitting
        onTextChanged: { root.updateToken(); Qt.callLater(root.updateHighlights); }
        onCursorPositionChanged: root.updateToken()
        onContentHeightChanged: Qt.callLater(root.updateHighlights)
        onWidthChanged: Qt.callLater(root.updateHighlights)
        onFontChanged: Qt.callLater(root.updateHighlights)
        Keys.onPressed: function(event) {
            root.handleKey(event);
            if (!event.accepted && !(event.modifiers & Qt.ShiftModifier) && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) { root.submit(); event.accepted = true; }
        }
    }
    C.ScrollView {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(Style.space(90), Math.max(Style.space(28), description.implicitHeight))
        visible: root.descriptionVisible || description.text !== ""
        clip: true
        contentWidth: availableWidth
        C.ScrollBar.horizontal.policy: C.ScrollBar.AlwaysOff
        C.TextArea {
            id: description
            width: parent.width
            objectName: "taskDescription"
            padding: 0; wrapMode: TextEdit.Wrap
            color: Color.popups.text
            font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall
            placeholderText: "Description"; placeholderTextColor: Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.4)
            background: Item {}
            enabled: !root.submitting
            Keys.onPressed: function(event) {
                root.handleKey(event);
                if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) { root.submit(); event.accepted = true; }
            }
        }
    }
    Action { fontFamily: root.fontFamily; visible: !root.descriptionVisible; text: "Description"; implicitHeight: Style.space(22); onClicked: { root.descriptionVisible = true; description.forceActiveFocus(); } }

    Flow {
        Layout.fillWidth: true
        spacing: Style.space(6)
        enabled: !root.submitting
        Chip { fontFamily: root.fontFamily; objectName: "dateChip"; foreground: root.dateColor(root.shownDate); text: root.shownDate || "Date"; iconName: "today"; removable: root.shownDate !== ""; maximumWidth: Math.min(root.width, Style.space(230)); onClicked: root.openPicker("due"); onRemoved: root.setDate("") }
        Chip { fontFamily: root.fontFamily; objectName: "priorityChip"; text: root.shownPriority ? "P" + root.shownPriority : "Priority"; iconName: "flag"; foreground: root.priorityColor(root.shownPriority); removable: root.shownPriority > 0; onClicked: root.openPicker("priority"); onRemoved: root.clearProperty("priority") }
        Chip { fontFamily: root.fontFamily; visible: root.shownDeadline !== ""; text: root.shownDeadline; iconName: "upcoming"; removable: true; onClicked: root.openPicker("deadline"); onRemoved: root.clearProperty("deadline") }
        Chip { fontFamily: root.fontFamily; visible: root.shownReminder !== ""; text: root.shownReminder; iconName: "bell"; removable: true; onClicked: root.openPicker("reminder"); onRemoved: root.clearProperty("reminder") }
        Chip { fontFamily: root.fontFamily; visible: root.shownDuration !== ""; text: root.shownDuration.replace(/^for /, ""); removable: true; onRemoved: root.removeTyped("duration") }
        Chip { fontFamily: root.fontFamily; visible: root.shownSection !== null; text: root.shownSection ? "/ " + root.shownSection.name : ""; removable: true; maximumWidth: root.width; onClicked: root.openPicker("section"); onRemoved: root.clearProperty("section") }
        Chip { fontFamily: root.fontFamily; visible: root.shownAssignee !== null; text: root.shownAssignee ? "+ " + root.shownAssignee.name : ""; removable: true; maximumWidth: root.width; onClicked: root.openPicker("assignee"); onRemoved: root.clearProperty("assignee") }
        Repeater {
            model: root.shownLabels
            Chip { fontFamily: root.fontFamily; required property string modelData; text: modelData; iconName: "label"; removable: true; maximumWidth: root.width; onClicked: root.openPicker("label"); onRemoved: root.clearProperty("label", modelData) }
        }
        Action { fontFamily: root.fontFamily; iconName: "label"; tip: "Labels (@)"; onClicked: root.openPicker("label") }
        Action { fontFamily: root.fontFamily; iconName: "more"; tip: "More task options"; selected: more.visible; onClicked: more.visible = !more.visible }
    }
    Flow {
        id: more
        visible: false
        Layout.fillWidth: true; spacing: Style.space(6)
        Action { fontFamily: root.fontFamily; text: "Reminder"; iconName: "bell"; onClicked: { more.visible = false; root.replacingReminder = ""; root.openPicker("reminder"); } }
        Action { fontFamily: root.fontFamily; text: "Deadline"; iconName: "upcoming"; onClicked: { more.visible = false; root.openPicker("deadline"); } }
        Action { fontFamily: root.fontFamily; text: "Section"; enabled: root.shownProject !== null; onClicked: { more.visible = false; root.openPicker("section"); } }
        Action { fontFamily: root.fontFamily; text: "Assignee"; enabled: root.shownProject !== null && root.shownProject.is_shared === true; onClicked: { more.visible = false; root.openPicker("assignee"); } }
    }
    ColumnLayout {
        visible: root.editing
        Layout.fillWidth: true
        spacing: Style.space(8)
        RowLayout {
            Layout.fillWidth: true
            Label { font.family: root.fontFamily; text: "Duration"; Layout.fillWidth: true }
            UI.TextField { font.family: root.fontFamily; objectName: "taskDuration"; Layout.preferredWidth: Style.space(60); text: root.duration; validator: IntValidator { bottom: 0; top: 100000 } onTextEdited: root.duration = text; enabled: !root.submitting }
            UI.Dropdown { fontFamily: root.fontFamily; Layout.preferredWidth: Style.space(95); showLabel: false; value: root.durationUnit; options: [{value: "minute", label: "Minutes"}, {value: "day", label: "Days"}]; onChanged: function(value) { root.durationUnit = value; } enabled: !root.submitting }
        }
        Label { font.family: root.fontFamily; text: "0 = no duration"; opacity: 0.45; font.pixelSize: Style.font.caption }
        Repeater {
            model: root.existingReminders
            Chip { fontFamily: root.fontFamily; required property var modelData; text: Edit.reminderText(modelData); iconName: "bell"; maximumWidth: root.width; removable: !modelData.notify_uid || String(modelData.notify_uid) === String(root.service.user.id); enabled: !root.submitting; onClicked: if (removable) { root.replacingReminder = String(modelData.id); root.openPicker("reminder"); } onRemoved: root.removedReminders = root.removedReminders.concat([String(modelData.id)]) }
        }
    }

    Rectangle {
        id: picker
        visible: root.pickerKind !== ""
        Layout.fillWidth: true
        implicitHeight: pickerBody.implicitHeight + Style.space(16)
        radius: Style.cornerRadius; color: Color.popups.background; border.color: Color.popups.border; border.width: 1
        ColumnLayout {
            id: pickerBody
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: Style.space(8)
            spacing: Style.space(6)
            RowLayout {
                Layout.fillWidth: true
                Label { font.family: root.fontFamily; Layout.fillWidth: true; text: ({project: "Project", label: "Labels", section: "Section", priority: "Priority", due: "Date", deadline: "Deadline", reminder: "Reminder", assignee: "Assignee"})[root.pickerKind] || ""; font.bold: true; font.pixelSize: Style.font.bodySmall }
                Action { fontFamily: root.fontFamily; iconName: "close"; iconSize: Style.space(12); tip: "Close picker"; onClicked: { root.closePicker(); root.focusInput(); } }
            }
            UI.TextField { font.family: root.fontFamily;
                id: search
                objectName: "pickerSearch"
                visible: !root.activeToken
                Layout.fillWidth: true
                placeholderText: root.editing && root.pickerKind === "deadline" ? "YYYY-MM-DD" : ["due", "deadline", "reminder"].indexOf(root.pickerKind) >= 0 ? "e.g. tomorrow at 4pm" : "Search…"
                onTextEdited: root.choiceIndex = 0
                Keys.onPressed: event => root.handleKey(event)
            }
            ListView {
                id: suggestions
                objectName: "suggestions"
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(Style.space(160), contentHeight)
                clip: true; boundsBehavior: Flickable.StopAtBounds
                model: root.choices
                C.ScrollBar.vertical: C.ScrollBar {}
                delegate: C.AbstractButton {
                    id: option
                    required property var modelData
                    required property int index
                    width: suggestions.width; height: Style.space(32)
                    hoverEnabled: true
                    padding: Style.space(6)
                    contentItem: RowLayout {
                        spacing: Style.space(8)
                        ViewIcon { visible: !!option.modelData.icon; name: option.modelData.icon || ""; color: root.pickerKind === "priority" ? root.priorityColor(option.modelData.value) : option.modelData.color || Color.popups.text }
                        Label { font.family: root.fontFamily; visible: !!option.modelData.prefix; text: option.modelData.prefix || ""; opacity: 0.6 }
                        Label { font.family: root.fontFamily; Layout.fillWidth: true; text: option.modelData.label; font.pixelSize: Style.font.bodySmall }
                        Label { font.family: root.fontFamily; Layout.maximumWidth: parent.width * 0.35; text: option.modelData.detail || ""; opacity: 0.4; font.pixelSize: Style.font.caption }
                    }
                    background: Rectangle { radius: Style.cornerRadius; color: option.hovered || root.choiceIndex === option.index ? Style.hoverFillFor(Color.popups.text, Color.accent) : "transparent" }
                    onClicked: root.choose(modelData)
                }
            }
            Label { font.family: root.fontFamily; visible: root.choices.length === 0; Layout.fillWidth: true; text: root.pickerKind === "section" && !root.shownProject ? "Choose a project first." : root.pickerKind === "assignee" && (!root.shownProject || !root.shownProject.is_shared) ? "Choose a shared project first." : "No matches"; opacity: 0.5; wrapMode: Text.WordWrap }
            Label { font.family: root.fontFamily; visible: root.pickerKind === "reminder"; Layout.fillWidth: true; text: "Before-task reminders need a task time. Availability follows your Todoist plan."; font.pixelSize: Style.font.caption; opacity: 0.5; wrapMode: Text.WordWrap; elide: Text.ElideNone }
        }
    }
    Rectangle { Layout.fillWidth: true; height: 1; color: Color.popups.text; opacity: 0.12 }
    RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(4)
        Action { fontFamily: root.fontFamily; Layout.fillWidth: true; Layout.minimumWidth: 0; maximumWidth: root.width; leftAligned: true; text: (root.shownProject && !root.shownProject.inbox_project ? "# " : "") + root.projectName + " ▾"; iconName: !root.shownProject || root.shownProject.inbox_project ? "inbox" : ""; tip: "Project (#)"; enabled: !root.submitting; onClicked: root.openPicker("project") }
        Action { fontFamily: root.fontFamily; text: "Cancel"; enabled: !root.submitting; onClicked: { root.reset(); root.cancelled(); } }
        Action { fontFamily: root.fontFamily; text: root.submitting ? (root.editing ? "Saving…" : "Adding…") : root.editing ? "Save" : "Add task"; selected: true; enabled: !root.service.saving && input.text.trim().length > 0; onClicked: root.submit() }
    }
    Label { font.family: root.fontFamily; Layout.fillWidth: true; visible: text !== ""; text: root.message; wrapMode: Text.WordWrap; elide: Text.ElideNone; color: Color.urgent }
    Connections {
        target: root.service
        function onTaskAdded() { if (root.submitting) { root.submitting = false; root.reset(); root.finished(); } }
        function onTaskUpdated(taskId) { if (root.editing && root.submitting && String(root.editingTask.id) === taskId) { root.submitting = false; root.finished(); } }
        function onOperationFailed(message) { if (root.submitting) { root.submitting = false; root.message = message; root.focusInput(); } }
    }
}
