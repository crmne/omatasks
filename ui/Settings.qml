import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
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
        Label { font.family: root.fontFamily; text: "Panel and bar"; font.bold: true }
        RowLayout {
            Layout.fillWidth: true
            Label { font.family: root.fontFamily; Layout.fillWidth: true; text: "Width" }
            SizeControl { font.family: root.fontFamily; value: root.service.panelWidth; from: 440; to: 1000; Accessible.name: "Panel width"; onValueModified: root.service.setPanelSize("panelWidth", value) }
        }
        RowLayout {
            Layout.fillWidth: true
            Label { font.family: root.fontFamily; Layout.fillWidth: true; text: "Maximum height" }
            SizeControl { font.family: root.fontFamily; value: root.service.panelHeight; from: 280; to: 1200; Accessible.name: "Maximum panel height"; onValueModified: root.service.setPanelSize("panelHeight", value) }
        }
        Label { font.family: root.fontFamily; Layout.fillWidth: true; text: "Pixels. The panel shrinks to fit shorter lists."; font.pixelSize: Style.font.bodySmall; opacity: 0.5; wrapMode: Text.WordWrap; elide: Text.ElideNone }
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Style.space(6)
            Label { font.family: root.fontFamily; Layout.fillWidth: true; text: "In the bar" }
            UI.Dropdown {
                objectName: "barMode"
                Layout.preferredWidth: Style.space(190)
                showLabel: false; fontFamily: root.fontFamily
                value: root.service.barMode
                options: [{value: "task", label: "Next task"}, {value: "count", label: "Today’s count"}, {value: "icon", label: "Icon only"}]
                onChanged: function(value) { root.service.setBarMode(value); }
            }
        }
        Label { font.family: root.fontFamily; Layout.fillWidth: true; text: "Today’s next timed task: one due now first, then one you are late on. Today’s count once none is left."; font.pixelSize: Style.font.bodySmall; opacity: 0.5; wrapMode: Text.WordWrap; elide: Text.ElideNone; visible: root.service.barMode === "task" }
    }
    Rectangle { visible: root.service.configured; Layout.fillWidth: true; height: 1; color: Commons.Color.popups.text; opacity: 0.12 }
    ColumnLayout {
        id: notifications
        visible: root.service.configured
        Layout.fillWidth: true
        spacing: Style.space(8)
        readonly property var options: root.service.notifySettings
        Label { font.family: root.fontFamily; text: "Notifications"; font.bold: true }
        Repeater {
            model: [
                {key: "enabled", label: "Show notifications", detail: "Your Todoist reminders, with Complete and Snooze buttons."},
                {key: "atDueTime", label: "At each task’s time", detail: "Even when the task has no reminder."},
                {key: "deadlines", label: "Deadline warnings", detail: "The day before a deadline and on the day, at recap time."},
                {key: "recap", label: "Morning recap", detail: "Today’s tasks and the next 3 days’ deadlines, once you are at the computer."}
            ]
            RowLayout {
                required property var modelData
                Layout.fillWidth: true
                enabled: modelData.key === "enabled" || notifications.options.enabled
                opacity: enabled ? 1 : 0.4
                spacing: Style.space(10)
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(2)
                    Label { font.family: root.fontFamily; Layout.fillWidth: true; text: modelData.label }
                    Label { font.family: root.fontFamily; Layout.fillWidth: true; text: modelData.detail; opacity: 0.5; wrapMode: Text.WordWrap; elide: Text.ElideNone; font.pixelSize: Style.font.bodySmall }
                }
                UI.ToggleSwitch {
                    Layout.alignment: Qt.AlignVCenter
                    objectName: "notify-" + modelData.key
                    checked: notifications.options[modelData.key]
                    foreground: Commons.Color.popups.text
                    Accessible.name: modelData.label
                    onToggled: root.service.setNotification(modelData.key, !checked)
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            enabled: notifications.options.enabled && notifications.options.recap
            opacity: enabled ? 1 : 0.4
            Label { font.family: root.fontFamily; Layout.fillWidth: true; text: "Recap time" }
            KeyField { font.family: root.fontFamily;
                id: recapInput
                Layout.preferredWidth: Style.space(70)
                text: notifications.options.recapTime
                placeholderText: "08:00"
                onAccepted: recapApply.apply()
                Connections { target: root.service; function onPreferencesChanged() { recapInput.text = root.service.notifySettings.recapTime; } }
            }
            Action { fontFamily: root.fontFamily;
                id: recapApply
                property string message: ""
                text: "Apply"; bordered: true
                function apply() { message = root.service.setNotification("recapTime", recapInput.text) ? "" : "Use a 24-hour time, such as 08:00."; }
                onClicked: apply()
            }
        }
        Label { font.family: root.fontFamily; Layout.fillWidth: true; visible: text !== ""; text: recapApply.message; color: Commons.Color.urgent; wrapMode: Text.WordWrap; elide: Text.ElideNone; font.pixelSize: Style.font.bodySmall }
        RowLayout {
            Layout.fillWidth: true
            enabled: notifications.options.enabled
            opacity: enabled ? 1 : 0.4
            Label { font.family: root.fontFamily; Layout.fillWidth: true; text: "Repeat overdue tasks" }
            UI.Dropdown {
                Layout.preferredWidth: Style.space(150)
                showLabel: false; fontFamily: root.fontFamily
                value: String(notifications.options.overdueHours)
                options: [{value: "0", label: "Never"}, {value: "1", label: "Every hour"}, {value: "2", label: "Every 2 hours"}, {value: "4", label: "Every 4 hours"}]
                onChanged: function(value) { root.service.setNotification("overdueHours", Number(value)); }
            }
        }
        Label { font.family: root.fontFamily; Layout.fillWidth: true; text: "Reminds you again about timed tasks still open on the day they were due."; opacity: 0.5; wrapMode: Text.WordWrap; elide: Text.ElideNone; font.pixelSize: Style.font.bodySmall; visible: notifications.options.enabled }
        Action { fontFamily: root.fontFamily;
            text: "Show the recap now"; leftAligned: true
            enabled: notifications.options.enabled && root.service.loaded
            onClicked: root.service.notifyRecap(true)
        }
    }
    Rectangle { visible: root.service.configured; Layout.fillWidth: true; height: 1; color: Commons.Color.popups.text; opacity: 0.12 }
    Setup { Layout.fillWidth: true; service: root.service }
    Rectangle { Layout.fillWidth: true; height: 1; color: Commons.Color.popups.text; opacity: 0.12 }
    ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(8)
        Label { font.family: root.fontFamily; text: "Quick add shortcut"; font.bold: true }
        RowLayout {
            Layout.fillWidth: true
            KeyField { font.family: root.fontFamily;
                id: shortcutInput
                Layout.fillWidth: true
                text: root.service.shortcut.value
                placeholderText: "Disabled"
                enabled: !root.service.shortcut.busy
                onAccepted: root.service.shortcut.apply(text, true)
                // Typing drops the binding; show a saved or reset shortcut again.
                Connections { target: root.service.shortcut; function onValueChanged() { shortcutInput.text = root.service.shortcut.value; } }
            }
            Action { fontFamily: root.fontFamily; text: "Apply"; bordered: true; enabled: !root.service.shortcut.busy; onClicked: root.service.shortcut.apply(shortcutInput.text, true) }
        }
        Label { font.family: root.fontFamily; Layout.fillWidth: true; text: "Super, Ctrl, Alt, Shift + a key. Leave empty to disable."; wrapMode: Text.WordWrap; elide: Text.ElideNone; opacity: 0.5; font.pixelSize: Style.font.bodySmall }
        Label { font.family: root.fontFamily;
            Layout.fillWidth: true
            visible: text !== ""
            text: root.service.shortcut.message
            color: root.service.shortcut.successful ? Commons.Color.popups.text : Commons.Color.urgent
            opacity: 0.7; wrapMode: Text.WordWrap; elide: Text.ElideNone; font.pixelSize: Style.font.bodySmall
        }
    }
}
