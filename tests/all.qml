// Synthetic tasks: this test never contacts Todoist.
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
        function applyToken(value) {}
        function refresh() {}
        function request(method, path, body, credential, callback, requestId) { throw new Error("Unexpected request"); }
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
        name: "TodoistAllTab"
        when: window.visible
        function cleanupTestCase() { console.log("ALL UI RESULTS", qtest_results.passCount, "passed", qtest_results.failCount, "failed"); Qt.callLater(Qt.quit); }
        function cleanup() { console.log("TEST", qtest_results.functionName, qtest_results.failed ? "FAILED" : "PASSED"); }
        function init() {
            service.token = "fixture"; service.loaded = true; service.error = "";
            service.now = new Date(2026, 8, 15, 12);
            service.user = {id: "me"}; service.preferences = {};
            service.projects = [{id: "inbox", name: "Inbox", inbox_project: true}, {id: "pro", name: "Pro", child_order: 1}, {id: "perso", name: "Perso", child_order: 2}];
            service.tasks = [
                {id: "dated", content: "Dated", priority: 1, project_id: "pro", order_key: "a0", due: {date: "2026-09-20"}},
                {id: "undated", content: "Undated", priority: 1, project_id: "pro", order_key: "a1"},
                {id: "elsewhere", content: "Elsewhere", priority: 1, project_id: "perso", order_key: "a0"},
                {id: "done", content: "Done", priority: 1, project_id: "perso", order_key: "a1", checked: true}
            ];
            taskList.reset(); wait(100);
        }
        function tab(id) { return findChild(taskList, "viewTab_" + id); }
        function taskIds() { return taskList.rows.filter(function(r) { return r.kind === "task"; }).map(function(r) { return r.task.id; }); }
        function groupTitles() { return taskList.rows.filter(function(r) { return r.kind === "group"; }).map(function(r) { return r.title; }); }
        function test_all_is_a_fourth_tab_that_lists_undated_tasks_by_project() {
            verify(tab("all") !== null);
            compare(taskList.rows.filter(function(r) { return r.kind === "task"; }).length, 0);
            mouseClick(tab("all")); tryCompare(taskList, "view", "all");
            compare(JSON.stringify(taskIds()), JSON.stringify(["dated", "undated", "elsewhere"]));
            compare(JSON.stringify(groupTitles()), JSON.stringify(["Pro", "Perso"]));
        }
        function test_ctrl_tab_cycles_through_four_tabs_and_wraps() {
            taskList.forceActiveFocus();
            var seen = [];
            for (var i = 0; i < 4; i++) { keyClick(Qt.Key_Tab, Qt.ControlModifier); seen.push(taskList.view); }
            compare(JSON.stringify(seen), JSON.stringify(["inbox", "upcoming", "all", "today"]));
            keyClick(Qt.Key_Tab, Qt.ControlModifier | Qt.ShiftModifier);
            compare(taskList.view, "all");
        }
        function test_no_tab_label_is_truncated_at_the_default_and_minimum_panel_widths() {
            service.setPanelSize("panelWidth", 1);
            var widths = [460, service.panelWidth];
            for (var w = 0; w < widths.length; w++) {
                taskList.anchors.fill = null; taskList.height = 500; taskList.width = Style.space(widths[w]); wait(100);
                var total = 0;
                for (var i = 0; i < taskList.viewTabs.length; i++) { var t = tab(taskList.viewTabs[i]); total += t.implicitWidth; }
                for (var j = 0; j < taskList.viewTabs.length; j++) {  var b = tab(taskList.viewTabs[j]); verify(b.width >= b.implicitWidth, b.objectName + " is truncated at " + widths[w] + ": " + b.width + " < " + b.implicitWidth); }
            }
        }
        function test_the_bar_count_ignores_undated_tasks() {
            compare(service.todayCount, 0);
        }
    }
}
