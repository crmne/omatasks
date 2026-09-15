// Render the real UI with sample data. No account access or network requests.
import QtQuick
import QtTest
import Quickshell
import qs.Commons
import "plugin" as Plugin
import "plugin/ui" as Tasks

ShellRoot {
    Plugin.Service {
        id: service
        enableShortcuts: false
        stateDir: Quickshell.env("TODOIST_PREVIEW_DIR") + "/state"
        function applyToken(value) {}
        function refresh() {}
        function request(method, path, body, credential, callback, requestId) { throw new Error("Preview must not access the network"); }
        Component.onCompleted: {
            token = "sample-data"; loaded = true; now = new Date(2026, 8, 15, 9);
            user = {id: "me"};
            projects = [{id: "inbox", name: "Inbox", inbox_project: true}, {id: "studio", name: "Studio"}, {id: "personal", name: "Personal"}];
            sections = [{id: "website", project_id: "studio", name: "Website"}];
            labels = [{id: "next", name: "next"}, {id: "design", name: "design"}, {id: "email", name: "email"}];
            tasks = [
                {id: "1", content: "Review the homepage designs", description: "Leave feedback on typography and the mobile layout.", project_id: "studio", section_id: "website", priority: 4, due: {date: "2026-09-15T10:00:00"}, duration: {amount: 30, unit: "minute"}, labels: ["design", "next"]},
                {id: "2", content: "Send the first beta invites", description: "Start with the early testers and include the setup guide.", project_id: "studio", priority: 3, due: {date: "2026-09-15T14:00:00"}, labels: ["email"]},
                {id: "3", content: "Polish the launch demo", description: "Keep it short: capture a task, plan the day, then get back to work.", project_id: "studio", priority: 4, due: {date: "2026-09-15"}, labels: ["next"]},
                {id: "4", content: "Write the release notes", description: "A clear introduction, a few examples, and a good screenshot.", project_id: "studio", priority: 3, due: {date: "2026-09-15"}, labels: ["next"]},
                {id: "5", content: "Book a table for Friday", project_id: "personal", priority: 2, due: {date: "2026-09-15"}, labels: []},
                {id: "6", content: "Pick up coffee beans", description: "Try the new roaster around the corner.", project_id: "personal", priority: 1, due: {date: "2026-09-15"}, labels: []},
                {id: "7", content: "Read a chapter", project_id: "personal", priority: 1, due: {date: "2026-09-15", is_recurring: true}, labels: []}
            ];
        }
    }
    FloatingWindow {
        id: window
        visible: true
        implicitWidth: 1600; implicitHeight: 900
        color: "#100c0b"
        Item {
        id: artwork
        anchors.fill: parent
        Canvas {
            anchors.fill: parent
            onPaint: {
                var c = getContext("2d"), g = c.createRadialGradient(0, height, 0, 0, height, 1050);
                g.addColorStop(0, "#48291e"); g.addColorStop(0.48, "#1c1210"); g.addColorStop(1, "#100c0b");
                c.fillStyle = g; c.fillRect(0, 0, width, height);
            }
        }
        Text { x: 80; y: 87; text: "OMATASKS / CRMNE"; color: "#ff936f"; font.family: Style.font.family; font.pixelSize: 18; font.letterSpacing: 4 }
        Text { x: 76; y: 164; text: "Todoist,\nright in your bar."; color: "#eee7e5"; font.family: "Inter"; font.weight: Font.Bold; font.pixelSize: 72; lineHeight: 1.08 }
        Text { x: 80; y: 372; text: "Your day at a glance.\nYour next task, a shortcut away."; color: "#b4a6a1"; font.family: Style.font.family; font.pixelSize: 21; lineHeight: 1.5 }
        Column {
            x: 80; y: 508; spacing: 27
            Repeater {
                model: ["Today, Inbox and Upcoming", "Complete, edit and drag to reorder", "Projects, priorities, labels and reminders", "Quick Add with Alt + Space", "Your Omarchy theme, down to the details"]
                Row {
                    required property string modelData
                    spacing: 14
                    Text { text: "•"; color: "#ff936f"; font.pixelSize: 22 }
                    Text { text: modelData; color: "#d0c4bf"; font.family: Style.font.family; font.pixelSize: 18 }
                }
            }
        }
        Rectangle { x: 80; y: 808; width: 850; height: 1; color: "#544038" }
        Text { x: 80; y: 833; text: "OmaTasks for Todoist. Native to Omarchy."; color: "#947f75"; font.family: Style.font.family; font.pixelSize: 17 }
        Item {
            id: panelScene
            x: 1016; y: 52; width: 456; height: 700
            scale: 1.1; transformOrigin: Item.TopLeft
            Row {
                anchors.right: parent.right; anchors.rightMargin: 22
                spacing: 7
                Tasks.TodoistIcon { width: 16; height: 16; color: Color.foreground }
                Tasks.Label { text: String(service.todayCount); font.pixelSize: 13 }
            }
            Rectangle {
                id: panel
                y: 34; width: parent.width; height: 620
                color: Color.popups.background; radius: Style.cornerRadius
                border.color: Color.popups.border; border.width: 2
                Tasks.TaskList { id: taskList; anchors.fill: parent; anchors.margins: 18; service: service }
            }
            Text { anchors.horizontalCenter: parent.horizontalCenter; y: panel.y + panel.height + 20; text: "Today, without leaving your desktop."; color: "#947f75"; font.family: Style.font.family; font.pixelSize: 12 }
        }
        Rectangle {
            id: quickCard
            visible: false
            width: 460; height: composer.implicitHeight + 36
            color: Color.popups.background; radius: Style.cornerRadius
            border.color: Color.popups.border; border.width: 1
            Tasks.Composer {
                id: composer
                x: 18; y: 18; width: parent.width - 36
                service: service
                text: "Review the launch plan"
                initialProjectId: "studio"
                due: "tomorrow at 10am"
                priority: 2
                taskLabels: ["next"]
            }
        }
        }
    }
    TestCase { id: capture; when: false }
    Timer {
        interval: 400; running: true; repeat: true
        property int phase: 0
        onTriggered: {
            phase++;
            var dir = Quickshell.env("TODOIST_PREVIEW_OUT");
            if (phase === 1) {
                artwork.grabToImage(function(result) { result.saveToFile(dir + "/preview.png"); });
                panel.grabToImage(function(result) { result.saveToFile(dir + "/screenshots/today.png"); });
            }
            if (phase === 2) quickCard.visible = true;
            if (phase === 3) quickCard.grabToImage(function(result) { result.saveToFile(dir + "/screenshots/quick-add.png"); });
            if (phase === 4) composer.openPicker("project");
            if (phase === 5) quickCard.grabToImage(function(result) { result.saveToFile(dir + "/screenshots/quick-add-picker.png"); });
            if (phase === 6) {
                quickCard.visible = false;
                taskList.showTask(service.tasks[0]);
            }
            if (phase === 7) {
                var popup = capture.findChild(taskList, "taskDetailsPopup");
                popup.contentItem.parent.grabToImage(function(result) { result.saveToFile(dir + "/screenshots/task-details.png"); });
            }
            if (phase === 8) {
                capture.findChild(taskList, "taskDetailsPopup").close();
                capture.findChild(taskList, "displayPopup").open();
            }
            if (phase === 9) {
                var menu = capture.findChild(taskList, "displayPopup");
                menu.contentItem.parent.grabToImage(function(result) { result.saveToFile(dir + "/screenshots/display.png"); });
            }
            if (phase === 10) Qt.quit();
        }
    }
}
