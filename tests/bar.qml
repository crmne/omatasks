// Synthetic tasks: this test never contacts Todoist. Every remote-sourced field
// holds an image tag pointing at a local server, and check-bar fails if anything
// but the deliberately unsafe control below asks that server for an image.
import QtQuick
import QtTest
import Quickshell
import qs.Commons as Commons
import qs.Ui as UI
import "plugin" as Plugin
import "plugin/ui" as Tasks

ShellRoot {
    id: root
    // Host 0 is this machine, and short enough for the bar's 28-character limit.
    readonly property string origin: "http://0:" + Quickshell.env("TODOIST_TEST_PORT")
    function tag(path) { return "<img src=\"" + origin + path + "\">"; }
    Plugin.Service {
        id: service
        enableShortcuts: false
        enableNotifications: false
        stateDir: Quickshell.env("TODOIST_TEST_DIR") + "/state"
        function refresh(manual) {}
    }
    QtObject {
        id: shell
        function serviceFor(name) { return service; }
        function summon(name, payload) {}
    }
    UI.PluginBarApi {
        id: barApi
        pluginId: "crmne.todoist"
        moduleName: "crmne.todoist"
        shell: shell
        barSize: 32
        barForeground: "white"
        foreground: "white"
        fontFamily: Qt.application.font.family
    }
    FloatingWindow {
        id: window
        visible: true
        implicitWidth: 700; implicitHeight: 560
        color: Commons.Color.popups.background
        Plugin.BarWidget { id: widget; x: 8; y: 8; bar: barApi }
        Tasks.TaskList { id: taskList; x: 8; y: 48; width: 456; height: 500; service: service }
        // The control: if Qt's default format stops fetching, or this test stops
        // being able to see a fetch, check-bar fails instead of passing quietly.
        Text { x: 480; y: 8; text: root.tag("/control") }
        TextMetrics { id: measured; font.family: barApi.fontFamily; font.pixelSize: Commons.Style.font.body }
    }
    TestCase {
        id: checks
        name: "TodoistBar"
        when: window.visible
        function cleanupTestCase() { console.log("BAR UI RESULTS", qtest_results.passCount, "passed", qtest_results.failCount, "failed"); Qt.callLater(Qt.quit); }
        function initTestCase() {
            var soon = new Date(Date.now() + 5 * 60000);
            function pad(n) { return String(n).padStart(2, "0"); }
            var due = soon.getFullYear() + "-" + pad(soon.getMonth() + 1) + "-" + pad(soon.getDate()) + "T" + pad(soon.getHours()) + ":" + pad(soon.getMinutes()) + ":00";
            service.token = "fixture"; service.user = {id: "me"}; service.preferences = {};
            service.sections = [{id: "section", project_id: "inbox", name: root.tag("/section")}];
            service.projects = [{id: "inbox", name: root.tag("/project"), inbox_project: true}];
            service.collaborators = [{id: "me", full_name: root.tag("/person"), name: root.tag("/person")}];
            service.tasks = [{id: "hostile", content: root.tag(""), description: root.tag("/description"), project_id: "inbox", section_id: "section", priority: 4, labels: [root.tag("/label")], responsible_uid: "me", deadline: {date: "2026-12-01"}, due: {date: due, string: root.tag("/due")}}];
            service.loaded = true;
            service.error = root.tag("/error");
            taskList.reset();
        }
        // At the name limit, so the tag reaches the bar whole.
        function test_bar_title_stays_literal() {
            compare(service.barTitle, root.tag(""));
            var title = findChild(widget, "barTitle");
            compare(title.text, root.tag(""));
            compare(title.textFormat, Text.PlainText);
            compare(findChild(widget, "barDetail").textFormat, Text.PlainText);
        }
        // The fit decision compares TextMetrics with this width; they must agree.
        function test_bar_title_is_as_wide_as_it_measures() {
            var title = findChild(widget, "barTitle");
            measured.font.pixelSize = title.font.pixelSize;
            measured.text = title.text;
            verify(Math.abs(title.implicitWidth - measured.advanceWidth) < 2, title.implicitWidth + " vs " + measured.advanceWidth);
        }
        function test_panel_and_details_show_tags_as_text() {
            var row = findChild(taskList, "taskPointer_hostile");
            verify(row);
            mouseClick(row, 65, 12);
            wait(300);
            verify(taskList.selectedTask && taskList.selectedTask.id === "hostile");
        }
        // Long enough for a fetch to reach the local server if one started.
        function test_z_wait_for_requests() { wait(1500); verify(true); }
    }
}
