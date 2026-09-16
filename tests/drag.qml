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
        property var completions: []
        property bool failNext: false
        function applyToken(value) {}
        function refresh() {}
        function completeTask(task) { completions = completions.concat([String(task.id)]); }
        function request(method, path, body, credential, callback, requestId) {
            if (path !== "/sync" || !body.commands) throw new Error("Unexpected request");
            captured = captured.concat(body.commands);
            if (failNext) { failNext = false; callback(null, "Connection lost"); return; }
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
            service.token = "fixture"; service.loaded = true; service.error = ""; service.bulkRetry = null;
            service.now = new Date(2026, 8, 15, 12);
            service.user = {id: "me"}; service.preferences = {};
            service.projects = [{id: "inbox", name: "Inbox", inbox_project: true}];
            service.tasks = Array.from({length: 24}, function(_, i) { return {id: String(i), content: "Task " + (i + 1) + " with a useful description", description: "Description of the task to check dragging and layout.", priority: 1, project_id: "inbox", day_order: i, due: {date: "2026-09-15"}}; });
            service.captured = []; service.completions = []; service.failNext = false; taskList.reset(); taskList.anchors.bottomMargin = 18;
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
        function test_ctrl_click_selects_and_toggles() {
            mouseClick(findChild(taskList, "taskPointer_0"), 65, 12, Qt.LeftButton, Qt.ControlModifier);
            mouseClick(findChild(taskList, "taskPointer_1"), 65, 12, Qt.LeftButton, Qt.ControlModifier);
            compare(taskList.selectedIds.join(","), "0,1");
            verify(!findChild(taskList, "taskDetailsPopup").opened);
            mouseClick(findChild(taskList, "taskPointer_0"), 65, 12, Qt.LeftButton, Qt.ControlModifier);
            compare(taskList.selectedIds.join(","), "1");
            compare(service.captured.length, 0);
            keyClick(Qt.Key_Escape); compare(taskList.selectedIds.length, 0);
        }
        function test_ctrl_click_circle_selects_without_completing() {
            mouseClick(findChild(taskList, "taskPointer_0"), 13, 18, Qt.LeftButton, Qt.ControlModifier);
            compare(taskList.selectedIds.join(","), "0");
            compare(service.completions.length, 0);
            verify(!findChild(taskList, "taskDetailsPopup").opened);
        }
        function test_plain_click_circle_still_completes() {
            mouseClick(findChild(taskList, "taskPointer_0"), 13, 18);
            compare(service.completions.join(","), "0");
            verify(!findChild(taskList, "taskDetailsPopup").opened);
        }
        function test_context_priority_applies_to_entire_selection() {
            mouseClick(findChild(taskList, "taskPointer_0"), 65, 12, Qt.LeftButton, Qt.ControlModifier);
            mouseClick(findChild(taskList, "taskPointer_1"), 65, 12, Qt.LeftButton, Qt.ControlModifier);
            mouseClick(findChild(taskList, "taskPointer_0"), 65, 12, Qt.RightButton);
            var menu = findChild(taskList, "taskContextMenu");
            tryCompare(menu, "opened", true); wait(50);
            compare(menu.taskIds.join(","), "0,1");
            verify(menu.x >= 0 && menu.y >= 0 && menu.x + menu.width <= taskList.width && menu.y + menu.height <= taskList.height);
            var priority = findChild(menu.contentItem, "bulkPriority_4");
            if (Quickshell.env("TODOIST_SELECTION_SCREENSHOT")) grabImage(window.contentItem).save(Quickshell.env("TODOIST_SELECTION_SCREENSHOT"));
            mouseClick(priority, priority.width / 2, priority.height / 2); wait(50);
            compare(service.captured.length, 2);
            compare(service.captured[0].args.priority, 4); compare(service.captured[1].args.priority, 4);
            compare(taskList.selectedIds.length, 0); verify(!menu.opened);
        }
        function test_right_click_unselected_task_replaces_selection() {
            mouseClick(findChild(taskList, "taskPointer_0"), 65, 12, Qt.LeftButton, Qt.ControlModifier);
            mouseClick(findChild(taskList, "taskPointer_1"), 65, 12, Qt.RightButton);
            var menu = findChild(taskList, "taskContextMenu"); tryCompare(menu, "opened", true);
            compare(taskList.selectedIds.join(","), "1"); compare(menu.taskIds.join(","), "1");
            keyClick(Qt.Key_Escape); tryCompare(menu, "opened", false);
            compare(service.captured.length, 0);
        }
        function test_selection_prevents_accidental_drag_and_clears_on_tab_change() {
            mouseClick(findChild(taskList, "taskPointer_0"), 65, 12, Qt.LeftButton, Qt.ControlModifier);
            var source = findChild(taskList, "taskPointer_0");
            mousePress(source, 65, 12, Qt.LeftButton, Qt.ControlModifier); mouseMove(source, 65, 40, 50);
            verify(!taskList.dragging);
            mouseRelease(source, 65, 40, Qt.LeftButton, Qt.ControlModifier);
            taskList.view = "inbox"; compare(taskList.selectedIds.length, 0);
        }
        function test_select_all_deduplicates_label_groups_and_prunes_hidden_tasks() {
            service.tasks = service.tasks.slice(0, 2).map(function(t) { return Object.assign({}, t, {labels: ["work", "next"]}); });
            service.setOption("today", "grouping", "label");
            taskList.forceActiveFocus(); keyClick(Qt.Key_A, Qt.ControlModifier);
            compare(taskList.selectedIds.length, 2);
            service.tasks = service.tasks.slice(1); wait(30);
            compare(taskList.selectedIds.join(","), "1");
        }
        function test_bulk_delete_requires_confirmation() {
            mouseClick(findChild(taskList, "taskPointer_0"), 65, 12, Qt.RightButton);
            var menu = findChild(taskList, "taskContextMenu"); tryCompare(menu, "opened", true);
            // The final action can be below the fold on a short panel.
            menu.showPage("delete"); wait(30);
            compare(service.captured.length, 0);
            var confirm = findChild(menu, "bulkConfirmDelete"); mouseClick(confirm, confirm.width / 2, confirm.height / 2);
            compare(service.captured.length, 1); compare(service.captured[0].type, "item_delete");
        }
        function test_bulk_custom_date_and_deadline_validation() {
            mouseClick(findChild(taskList, "taskPointer_0"), 65, 12, Qt.RightButton);
            var menu = findChild(taskList, "taskContextMenu"); tryCompare(menu, "opened", true);
            menu.showPage("deadline"); wait(30);
            var input = findChild(menu, "bulkDateInput"); input.text = "2026-02-30";
            var apply = findChild(menu, "bulkApplyInput"); mouseClick(apply, apply.width / 2, apply.height / 2);
            verify(menu.message.indexOf("YYYY-MM-DD") >= 0); compare(service.captured.length, 0);
            menu.showPage("customDate"); input.text = "every Monday at 10am"; wait(30);
            mouseClick(apply, apply.width / 2, apply.height / 2);
            compare(service.captured.length, 1); compare(service.captured[0].args.due.string, "every Monday at 10am");
        }
        function test_menu_fits_short_panel_and_resets_after_subpage() {
            taskList.anchors.bottomMargin = window.height - 262; wait(30);
            compare(taskList.height, 244);
            mouseClick(findChild(taskList, "taskPointer_0"), 65, 12, Qt.RightButton);
            var menu = findChild(taskList, "taskContextMenu"); tryCompare(menu, "opened", true); wait(30);
            verify(menu.height <= taskList.height); verify(menu.y >= 0);
            menu.showPage("move"); wait(30); menu.close();
            mouseClick(findChild(taskList, "taskPointer_0"), 65, 12, Qt.RightButton);
            tryCompare(menu, "opened", true); compare(menu.page, "main");
            menu.close(); taskList.anchors.bottomMargin = 18;
        }
        function test_bulk_failure_preserves_menu_and_retry() {
            mouseClick(findChild(taskList, "taskPointer_0"), 65, 12, Qt.LeftButton, Qt.ControlModifier);
            mouseClick(findChild(taskList, "taskPointer_1"), 65, 12, Qt.LeftButton, Qt.ControlModifier);
            mouseClick(findChild(taskList, "taskPointer_0"), 65, 12, Qt.RightButton);
            var menu = findChild(taskList, "taskContextMenu"); tryCompare(menu, "opened", true); wait(30);
            service.failNext = true;
            var priority = findChild(menu.contentItem, "bulkPriority_4"); mouseClick(priority, priority.width / 2, priority.height / 2);
            verify(menu.opened); verify(menu.canRetry); verify(!menu.pending); compare(taskList.selectedIds.length, 2);
            verify(menu.message.indexOf("Connection lost") >= 0);
            var firstId = service.captured[0].uuid;
            menu.pending = true; verify(service.retryTaskAction());
            compare(service.captured[2].uuid, firstId); verify(!menu.opened); compare(taskList.selectedIds.length, 0);
        }
    }
}
