import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui as UI

ColumnLayout {
    id: root
    required property var service
    required property string view
    readonly property var options: service.viewOptions(view)
    spacing: Style.space(10)
    Label { text: "Sort"; font.bold: true }
    Repeater {
        model: [
            {key: "grouping", label: "Grouping", values: [{value: "none", label: "None"}, {value: "project", label: "Project"}, {value: "priority", label: "Priority"}, {value: "date", label: "Date"}, {value: "label", label: "Label"}]},
            {key: "sorting", label: "Sorting", values: [{value: "smart", label: "Smart"}, {value: "manual", label: "Manual"}, {value: "name", label: "Name"}, {value: "assignee", label: "Assignee"}, {value: "date", label: "Date"}, {value: "added", label: "Date added"}, {value: "deadline", label: "Deadline"}, {value: "priority", label: "Priority"}, {value: "project", label: "Project"}]}
        ]
        RowLayout {
            required property var modelData
            Layout.fillWidth: true
            Label { text: modelData.label; Layout.preferredWidth: Style.space(80) }
            UI.Dropdown { Layout.fillWidth: true; showLabel: false; fontFamily: Style.font.family; value: root.options[modelData.key]; options: modelData.values; onChanged: function(value) { root.service.setOption(root.view, modelData.key, value); } }
        }
    }
    Label { text: "Filter"; font.bold: true; Layout.topMargin: Style.space(6) }
    Repeater {
        model: [
            {key: "assignee", label: "Assignee", values: [{value: "mine", label: "Me and unassigned"}, {value: "all", label: "Everyone"}, {value: "me", label: "Me"}, {value: "unassigned", label: "Unassigned"}]},
            {key: "deadline", label: "Deadline", values: [{value: "all", label: "All"}, {value: "has", label: "Has a deadline"}, {value: "none", label: "No deadline"}, {value: "overdue", label: "Overdue"}]},
            {key: "priority", label: "Priority", values: [{value: "all", label: "All"}, {value: "4", label: "Priority 1"}, {value: "3", label: "Priority 2"}, {value: "2", label: "Priority 3"}, {value: "1", label: "Priority 4"}]},
            {key: "label", label: "Label", values: [{value: "all", label: "All"}].concat(root.service.labels.map(function(l) { return {value: l.name, label: l.name}; }))}
        ]
        RowLayout {
            required property var modelData
            Layout.fillWidth: true
            Label { text: modelData.label; Layout.preferredWidth: Style.space(80) }
            UI.Dropdown { Layout.fillWidth: true; showLabel: false; fontFamily: Style.font.family; value: root.options[modelData.key]; options: modelData.values; onChanged: function(value) { root.service.setOption(root.view, modelData.key, value); } }
        }
    }
    RowLayout {
        Action { text: "Reset view"; onClicked: root.service.resetView(root.view) }
        Item { Layout.fillWidth: true }
        Action { text: root.service.loading ? "Refreshing…" : "Refresh"; enabled: !root.service.loading; onClicked: root.service.refresh() }
    }
}
