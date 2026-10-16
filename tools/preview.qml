// Render the real UI with sample data. No account access or network requests.
import QtQuick
import QtQuick.Effects
import QtTest
import Quickshell
import qs.Commons
import qs.Commons as Commons
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
        clip: true
        // Omarchy's ristretto wallpaper, blurred and dimmed under real panels.
        Image {
            id: wallpaper
            // Larger than the canvas, so the blur has no dark edges.
            anchors.fill: parent; anchors.margins: -120
            source: "file://" + Quickshell.env("TODOIST_PREVIEW_WALLPAPER")
            fillMode: Image.PreserveAspectCrop
            visible: false
        }
        MultiEffect { anchors.fill: wallpaper; source: wallpaper; blurEnabled: true; blur: 1.0; blurMax: 48; brightness: -0.12 }
        Rectangle { anchors.fill: parent; color: "#100c0b"; opacity: 0.55 }
        Item {
            id: panelScene
            x: 330; y: 70; width: 456; height: 654
            scale: 1.15; transformOrigin: Item.TopLeft
            Row {
                anchors.right: parent.right; anchors.rightMargin: 22
                spacing: 7
                Tasks.TodoistIcon { width: 16; height: 16; color: Commons.Color.foreground }
                Tasks.Label { text: String(service.todayCount); font.pixelSize: 13 }
            }
            Rectangle {
                id: panel
                y: 34; width: parent.width; height: 620
                color: Commons.Color.popups.background; radius: Style.cornerRadius
                border.color: Commons.Color.popups.border; border.width: 2
                Tasks.TaskList { id: taskList; anchors.fill: parent; anchors.margins: 18; service: service }
            }
        }
        Rectangle {
            id: previewCard
            x: 790; y: 330
            width: 460; height: previewComposer.implicitHeight + 36
            scale: 1.2; transformOrigin: Item.TopLeft
            color: Commons.Color.popups.background; radius: Style.cornerRadius
            border.color: Commons.Color.popups.border; border.width: 2
            Tasks.Composer {
                id: previewComposer
                x: 18; y: 18; width: parent.width - 36
                service: service
                text: "Plan the launch tomorrow at 10am p2 #Studio @next"
            }
        }
        Rectangle {
            id: quickCard
            visible: false
            width: 460; height: composer.implicitHeight + 36
            color: Commons.Color.popups.background; radius: Style.cornerRadius
            border.color: Commons.Color.popups.border; border.width: 1
            Tasks.Composer {
                id: composer
                x: 18; y: 18; width: parent.width - 36
                service: service
                text: "Review the launch plan tomorrow at 10am p2 #Studio @next"
            }
        }
        }
    }
    FloatingWindow {
        id: selectionWindow
        visible: false
        implicitWidth: 456; implicitHeight: 620
        color: Commons.Color.popups.background
        Rectangle {
            id: selectionCanvas
            anchors.fill: parent; color: Commons.Color.popups.background
            Tasks.TaskList { id: selectionList; anchors.fill: parent; anchors.margins: 18; service: service }
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
                previewComposer.closePicker();
                artwork.grabToImage(function(result) { result.saveToFile(dir + "/preview.png"); });
                panel.grabToImage(function(result) { result.saveToFile(dir + "/screenshots/today.png"); });
            }
            if (phase === 2) { quickCard.visible = true; composer.closePicker(); }
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
            if (phase === 10) {
                capture.findChild(taskList, "displayPopup").close();
                selectionWindow.visible = true;
            }
            if (phase === 11) {
                selectionList.selectedIds = ["1", "2"];
                selectionList.openTaskMenu(service.tasks[0], Qt.point(85, 80));
            }
            if (phase === 12) {
                // Include the popup in this sample canvas for a full-resolution capture.
                capture.findChild(selectionList, "taskContextMenu").contentItem.parent.parent = selectionCanvas;
            }
            if (phase === 13) selectionCanvas.grabToImage(function(result) { result.saveToFile(dir + "/screenshots/multi-selection.png"); });
            if (phase === 14) Qt.quit();
        }
    }
}
