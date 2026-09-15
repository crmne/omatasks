// Synthetic tasks and intercepted requests: this test never contacts Todoist.
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
        stateDir: Quickshell.env("TODOIST_TEST_DIR") + "/state"
        property var captured: []
        function applyToken(value) {}
        function refresh() {}
        function completeTask(task) { throw new Error("Dragging must not complete a task"); }
        function request(method, path, body, credential, callback, requestId) {
            if (path !== "/sync" || !body.commands) throw new Error("Unexpected request");
            captured = captured.concat(body.commands);
            var statuses = {};
            body.commands.forEach(function(c) { statuses[c.uuid] = "ok"; });
            callback({sync_token: "fixture", sync_status: statuses}, "");
        }
    }
    FloatingWindow {
        id: window
        visible: true
        implicitWidth: 456; implicitHeight: 540
        color: Color.popups.background
        Tasks.TaskList { id: taskList; anchors.fill: parent; anchors.margins: 18; service: service }
    }
    TestCase {
        id: checks
        name: "TodoistDrag"
        when: window.visible
        function cleanupTestCase() { console.log("DRAG UI RESULTS", qtest_results.passCount, "passed", qtest_results.failCount, "failed"); Qt.callLater(Qt.quit); }
        function cleanup() { console.log("TEST", qtest_results.functionName, qtest_results.failed ? "FAILED" : "PASSED"); }
        function init() {
            service.token = "fixture"; service.loaded = true; service.error = "";
            service.now = new Date(2026, 8, 15, 12);
            service.user = {id: "me"}; service.preferences = {};
            service.projects = [{id: "inbox", name: "Inbox", inbox_project: true}];
            service.tasks = Array.from({length: 24}, function(_, i) { return {id: String(i), content: "Task " + (i + 1) + " with a useful description", description: "Description of the task to check dragging and layout.", priority: 1, project_id: "inbox", day_order: i, due: {date: "2026-09-15"}}; });
            service.captured = []; taskList.reset();
            var list = findChild(taskList, "taskListView"); list.positionViewAtBeginning();
            wait(150);
        }
        function test_drag_saves_order() {
            var source = findChild(taskList, "taskPointer_2"), target = findChild(taskList, "taskPointer_0");
            verify(source !== null); verify(target !== null);
            mousePress(source, 65, 12); mouseMove(source, 65, 35, 50);
            console.log("STARTED", taskList.dragging); verify(taskList.dragging);
            var point = source.mapFromItem(target, 65, 6);
            mouseMove(source, point.x, point.y, 50); wait(80);
            console.log("DROP", taskList.dropIndex, taskList.dropAfter); compare(taskList.dropIndex, 0); compare(taskList.dropAfter, false);

            mouseRelease(source, point.x, point.y); wait(100);
            compare(taskList.dragging, false); compare(service.captured.length, 1);
            compare(service.captured[0].type, "item_update_day_orders");
            compare(service.preferences.today.sorting, "manual");
            compare(taskList.rows[0].task.id, "2");
            verify(!findChild(taskList, "taskDetailsPopup").opened);
        }
        function test_escape_cancels() {
            var source = findChild(taskList, "taskPointer_1");
            mousePress(source, 65, 12); mouseMove(source, 65, 40, 50);
            verify(taskList.dragging); keyClick(Qt.Key_Escape); verify(!taskList.dragging);
            mouseRelease(source, 65, 40); wait(80);
            compare(service.captured.length, 0);
            verify(!findChild(taskList, "taskDetailsPopup").opened);
        }
        function test_edge_scroll_and_outside_cancel() {
            var source = findChild(taskList, "taskPointer_1"), list = findChild(taskList, "taskListView");
            mousePress(source, 65, 12); mouseMove(source, 65, 40, 50);
            var point = source.mapFromItem(list, 65, list.height - 5);
            mouseMove(source, point.x, point.y, 50); tryVerify(function() { return list.contentY > 1100; }, 4000); verify(taskList.dragging);
            point = source.mapFromItem(list, -30, list.height / 2);
            mouseMove(source, point.x, point.y, 50); compare(taskList.dropIndex, -1);
            mouseRelease(source, point.x, point.y); wait(80);
            compare(service.captured.length, 0); verify(!taskList.dragging);
        }
        function test_long_drag_keeps_scroll_position() {
            var source = findChild(taskList, "taskPointer_1"), list = findChild(taskList, "taskListView");
            mousePress(source, 65, 12); mouseMove(source, 65, 40, 50);
            var point = source.mapFromItem(list, 65, list.height - 5);
            mouseMove(source, point.x, point.y, 50); tryVerify(function() { return list.contentY > 1100; }, 4000); verify(taskList.dragging);
            point = source.mapFromItem(list, 65, list.height / 2);
            mouseMove(source, point.x, point.y, 50);
            verify(taskList.dropIndex > 10);
            var offset = list.contentY;
            mouseRelease(source, point.x, point.y); wait(150);
            console.log("SCROLL AFTER DROP", offset, list.contentY);
            verify(Math.abs(list.contentY - offset) < 50);
            compare(service.captured.length, 1);
        }
        function test_click_opens_details() {
            mouseClick(findChild(taskList, "taskPointer_0"), 65, 12); wait(80);
            verify(findChild(taskList, "taskDetailsPopup").opened);
            compare(service.captured.length, 0);
        }
    }
}
