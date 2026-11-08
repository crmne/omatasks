// Synthetic projects: this test never contacts Todoist.
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
        implicitWidth: 360; implicitHeight: 360
        color: Color.popups.background
        Tasks.FolderFilter { id: filter; anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 18; service: service; view: "today" }
    }
    TestCase {
        id: checks
        name: "TodoistFolderFilter"
        when: window.visible
        function cleanupTestCase() { console.log("FOLDER UI RESULTS", qtest_results.passCount, "passed", qtest_results.failCount, "failed"); Qt.callLater(Qt.quit); }
        function cleanup() { console.log("TEST", qtest_results.functionName, qtest_results.failed ? "FAILED" : "PASSED"); }
        function init() {
            service.token = "fixture"; service.loaded = true; service.user = {id: "me"}; service.preferences = {};
            service.projects = [
                {id: "perso", name: "Perso", child_order: 1}, {id: "errands", name: "Errands", parent_id: "perso", child_order: 1},
                {id: "pro", name: "Pro", child_order: 2}, {id: "planning", name: "Planning", parent_id: "pro", child_order: 1}, {id: "training", name: "Training", parent_id: "pro", child_order: 2}
            ];
            filter.close(); wait(50);
        }
        function row(id) { tryVerify(function() { return findChild(filter.rows, "folderRow_" + id) !== null; }); return findChild(filter.rows, "folderRow_" + id); }
        function click(id) { var item = row(id); mouseClick(item, item.width / 2, item.height / 2); wait(30); }
        function trigger() { return findChild(filter, "folderTrigger"); }
        function folder() { return service.viewOptions("today").folder; }
        function summary() { var t = trigger(); for (var i = 0; i < t.children.length; i++) if (t.children[i].text !== undefined && t.children[i].elide !== undefined) return t.children[i].text; return ""; }
        function test_shows_all_and_lists_every_folder_when_opened() {
            compare(summary(), "All");
            filter.open(); tryCompare(filter, "popupOpen", true);
            compare(filter.nodes.length, 5);
            verify(!row("pro").checked);
        }
        function test_checking_a_folder_checks_its_subfolders_and_keeps_the_menu_open() {
            filter.open(); tryCompare(filter, "popupOpen", true);
            click("pro");
            compare(JSON.stringify(folder()), JSON.stringify({include: ["pro"], exclude: []}));
            verify(row("pro").checked); verify(row("planning").checked); verify(row("training").checked); verify(!row("errands").checked);
            compare(summary(), "Pro");
            verify(filter.popupOpen);
        }
        function test_unchecking_a_subfolder_keeps_the_parent_and_siblings() {
            filter.open(); tryCompare(filter, "popupOpen", true);
            click("pro"); click("planning");
            compare(JSON.stringify(folder()), JSON.stringify({include: ["pro"], exclude: ["planning"]}));
            verify(!row("pro").checked); verify(row("pro").partial); verify(!row("planning").checked); verify(row("training").checked);
            compare(summary(), "Pro (2/3)");
        }
        function test_checking_only_a_subfolder_marks_its_parent_partial() {
            filter.open(); tryCompare(filter, "popupOpen", true);
            click("training");
            verify(row("training").checked); verify(row("pro").partial); verify(!row("planning").checked);
            click("pro");
            verify(row("pro").checked); verify(row("planning").checked);
        }
        function test_siblings_can_be_selected_and_cleared() {
            filter.open(); tryCompare(filter, "popupOpen", true);
            click("errands"); click("training");
            compare(summary(), "Errands, Training");
            click("errands"); click("training");
            compare(summary(), "All");
        }
    }
}
