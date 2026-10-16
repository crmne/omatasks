// Synthetic tasks, isolated settings and intercepted HTTP: no account access.
import QtQuick
import QtQuick.Controls as C
import QtTest
import Quickshell
import qs.Commons
import qs.Commons as Commons
import "plugin" as Plugin
import "plugin/ui" as Tasks

ShellRoot {
    QtObject { id: fontBar; property string fontFamily: Style.font.family }
    QtObject { id: fontWidget; property var bar: fontBar }
    Tasks.Label { id: nativeLabel; visible: false }
    TextMetrics { id: narrowGlyphs; font.family: service.fontFamily; font.pixelSize: 14; text: "iiiiiiii" }
    TextMetrics { id: wideGlyphs; font: narrowGlyphs.font; text: "WWWWWWWW" }
    Plugin.Service {
        id: service
        enableShortcuts: false
        stateDir: Quickshell.env("TODOIST_TEST_DIR") + "/state"
        property var captured: []
        function applyToken(value) {}
        function refresh() {}
        function addTask(text, requestId) { captured = captured.concat([{text: text, id: requestId}]); return true; }
        function request() { throw new Error("Composer tests must not access the network"); }
        Component.onCompleted: {
            token = "fixture"; loaded = true; now = new Date(2026, 9, 2, 9);
            projects = [{id: "inbox", name: "Inbox", inbox_project: true}, {id: "studio", name: "Studio", is_shared: true}, {id: "personal", name: "Personal"}];
            sections = [{id: "website", project_id: "studio", name: "Website"}];
            labels = [{id: "next", name: "next"}, {id: "email", name: "email"}];
            collaborators = [{id: "alex", full_name: "Alex Smith", project_id: "studio"}];
        }
    }
    FloatingWindow {
        id: window
        visible: true
        implicitWidth: 560; implicitHeight: 740
        color: Commons.Color.popups.background
        Rectangle {
            id: card
            width: parent.width
            height: (settings.visible ? settings.implicitHeight : composer.implicitHeight) + 36
            color: Commons.Color.popups.background
            border.color: Commons.Color.popups.border; border.width: 1; radius: Style.cornerRadius
            Tasks.Composer { id: composer; x: 18; y: 18; width: parent.width - 36; service: service }
            Tasks.Settings { id: settings; visible: false; x: 18; y: 18; width: parent.width - 36; service: service }
        }
        Tasks.TaskList { id: inlineList; visible: false; anchors.fill: parent; anchors.margins: 18; service: service }
        Column {
            visible: false
            x: 18; y: 18; width: 300; spacing: 8
            Tasks.KeyField { id: plainField; width: parent.width; property int acceptedCount: 0; onAccepted: acceptedCount++ }
            Tasks.KeyField { id: secretField; width: parent.width; password: true }
            Tasks.SizeControl { id: sizeControl; property int saved: 400; property int modified: 0; value: saved; from: 360; to: 1000; onValueModified: { modified++; saved = value; } }
        }
    }
    TestCase {
        id: checks
        name: "TodoistComposer"
        when: window.visible && Quickshell.env("TODOIST_CAPTURE_ONLY") !== "1"
        function cleanupTestCase() { console.log("COMPOSER UI RESULTS", qtest_results.passCount, "passed", qtest_results.failCount, "failed"); Qt.callLater(Qt.quit); }
        function cleanup() { console.log("TEST", qtest_results.functionName, qtest_results.failed ? "FAILED" : "PASSED"); }
        function init() { service.widgets = [fontWidget]; fontBar.fontFamily = Style.font.family; composer.reset(); composer.editingTask = null; composer.submitting = false; composer.visible = true; inlineList.visible = false; inlineList.composerKey = ""; service.captured = []; composer.focusInput(); wait(30); }
        function enter(text) {
            var input = findChild(composer, "taskName");
            input.text = text; input.cursorPosition = text.length; composer.focusInput(); composer.updateToken(); wait(20);
            return input;
        }
        function test_dates_priority_and_pasted_metadata() {
            var text = "Review tomorrow at 4pm !!1 #Studio /Website @next !30m {Friday}";
            enter(text);
            compare(composer.shownDate, "tomorrow at 4pm"); compare(composer.shownPriority, 1);
            compare(composer.shownProject.id, "studio"); compare(composer.shownSection.id, "website");
            compare(composer.shownLabels[0], "next"); compare(composer.shownReminder, "30m"); compare(composer.shownDeadline, "Friday");
            verify(findChild(composer, "highlight_due") !== null); verify(findChild(composer, "highlight_priority") !== null);
            composer.closePicker(); keyClick(Qt.Key_Return);
            compare(service.captured.length, 1); compare(service.captured[0].text, text);
        }
        function test_priority_without_trailing_space() {
            enter("Review p1"); compare(composer.shownPriority, 1); compare(composer.pickerKind, "");
            keyClick(Qt.Key_Backspace); compare(composer.shownPriority, 0);
            compare(composer.pickerKind, "priority");
            keyClick(Qt.Key_Down); keyClick(Qt.Key_Return);
            compare(composer.shownPriority, 2); verify(composer.text.indexOf("p2") >= 0);
            compare(service.captured.length, 0, "Accepting a suggestion does not submit");
        }
        function test_project_picker_keyboard_and_scoped_sections() {
            enter("Review #Stu"); compare(composer.pickerKind, "project"); compare(composer.choices.length, 1);
            keyClick(Qt.Key_Tab); compare(composer.shownProject.id, "studio"); compare(composer.pickerKind, "");
            var input = findChild(composer, "taskName"); input.insert(input.length, "/Web"); input.cursorPosition = input.length; composer.updateToken();
            compare(composer.pickerKind, "section"); keyClick(Qt.Key_Return); compare(composer.shownSection.id, "website");
            compare(service.captured.length, 0);
            input.insert(input.length, "+Alex"); input.cursorPosition = input.length; composer.updateToken();
            keyClick(Qt.Key_Return); compare(composer.shownAssignee.id, "alex");
        }
        function test_label_autocomplete_remains_open_while_typing() {
            enter("Review @ne"); compare(composer.pickerKind, "label");
            compare(composer.choices[0].value, "next"); keyClick(Qt.Key_Return);
            compare(composer.shownLabels.length, 1); compare(composer.shownLabels[0], "next"); compare(composer.pickerKind, "");
            compare(composer.text.trim(), "Review @next");
        }
        function test_chip_changes_replace_typed_values() {
            enter("Review tomorrow p1 #Studio @next");
            composer.setDate("today"); compare(composer.shownDate, "today"); verify(composer.text.indexOf("tomorrow") < 0);
            composer.openPicker("priority"); wait(20); composer.choose(composer.choices[2]);
            compare(composer.shownPriority, 3); verify(composer.text.indexOf("p1") < 0);
            composer.clearProperty("label", "next"); compare(composer.shownLabels.length, 0); verify(composer.text.indexOf("@next") < 0);
            composer.submit(); compare(service.captured.length, 1);
            verify(service.captured[0].text.indexOf("today") >= 0); verify(service.captured[0].text.indexOf("p3") >= 0);
        }
        function test_today_default_does_not_override_typed_project_or_date() {
            composer.project = service.projectMap.inbox; composer.due = "today";
            enter("Review tomorrow #Studio"); composer.closePicker(); composer.submit();
            compare(service.captured[0].text, "Review tomorrow #Studio");
        }
        function test_no_date_overrides_today_default() {
            composer.due = "today"; enter("Review no date"); compare(composer.shownDate, "");
            composer.submit(); compare(service.captured[0].text, "Review no date");
        }
        function test_manual_date_replaces_all_prior_typed_dates() {
            enter("Review today tomorrow"); compare(composer.shownDate, "tomorrow");
            composer.setDate("next week"); compare(composer.shownDate, "next week"); compare(composer.text.trim(), "Review");
        }
        function test_adding_a_label_keeps_existing_typed_labels() {
            enter("Review @next"); composer.closePicker(); composer.openPicker("label"); wait(20);
            composer.choose(composer.choices.filter(function(row) { return row.value === "email"; })[0]);
            compare(composer.shownLabels.length, 2); verify(composer.shownLabels.indexOf("next") >= 0); verify(composer.shownLabels.indexOf("email") >= 0);
        }
        function test_inline_new_task_uses_the_same_parser_and_colors() {
            composer.visible = false; inlineList.visible = true; inlineList.reset();
            var row = inlineList.rows.filter(function(r) { return r.kind === "add"; })[0]; verify(row !== undefined);
            inlineList.addAt(row.key, row.projectId); wait(80);
            var input = findChild(inlineList, "taskName"); verify(input !== null);
            compare(input.font.family, Qt.application.font.family);
            input.text = "Review tomorrow !!1 #Studio @next"; input.cursorPosition = input.length; wait(30);
            compare(findChild(inlineList, "dateChip").text, "tomorrow"); compare(findChild(inlineList, "priorityChip").text, "P1");
            verify(findChild(inlineList, "highlight_due") !== null);
            keyClick(Qt.Key_Escape); keyClick(Qt.Key_Return); compare(service.captured.length, 1); compare(service.captured[0].text, "Review tomorrow !!1 #Studio @next");
        }
        function test_title_wraps_and_highlight_positions_follow_font_size() {
            card.width = 360;
            enter("A long task name that wraps to another line tomorrow at 4pm p1 #Studio /Website @next");
            var input = findChild(composer, "taskName"); verify(input.contentHeight > input.font.pixelSize * 2);
            input.font.pixelSize = Style.font.body + 2; wait(30);
            verify(composer.highlightSpans.some(function(rect) { return rect.kind === "due" && rect.y > 0; }));
            verify(composer.highlightSpans.every(function(rect) { return rect.width > 0 && rect.x + rect.width <= input.width + 3; }));
            input.font.pixelSize = Qt.binding(function() { return Style.font.body; });
            card.width = 560;
        }
        function test_desktop_ui_font_is_used_even_with_a_monospace_bar() {
            service.preferences = {fontFamily: "monospace"}; fontBar.fontFamily = "monospace";
            var family = Qt.application.font.family;
            compare(composer.fontFamily, family); compare(findChild(composer, "taskName").font.family, family);
            compare(settings.fontFamily, family); compare(inlineList.fontFamily, family); compare(nativeLabel.font.family, family);
            verify(wideGlyphs.advanceWidth > narrowGlyphs.advanceWidth * 2, "UI glyph widths must be proportional");
            verify(findChild(settings, "fontPicker") === null);
            fontBar.fontFamily = "Inter"; compare(composer.fontFamily, family); compare(settings.fontFamily, family);
            service.widgets = []; compare(composer.fontFamily, family); compare(settings.fontFamily, family);
        }
        function test_light_and_dark_highlight_colors() {
            var original = Commons.Color.popups.background;
            Commons.Color.popups.background = "#ffffff"; compare(composer.dark, false);
            compare(composer.highlightColor({kind: "due"}), "#ffe3e3"); compare(composer.priorityColor(1), "#d1453b");
            compare(composer.dateColor("tomorrow"), "#ad6200");
            Commons.Color.popups.background = "#282828"; compare(composer.dark, true);
            compare(composer.highlightColor({kind: "due"}), "#722724"); compare(composer.priorityColor(1), "#ff5c50");
            compare(composer.dateColor("tomorrow"), "#ff9a00");
            Commons.Color.popups.background = original;
        }
        function test_description_keeps_shortcuts_literal_and_ctrl_enter_submits() {
            enter("Review"); keyClick(Qt.Key_Down);
            var description = findChild(composer, "taskDescription"); verify(description.activeFocus);
            description.text = "tomorrow p1 #Studio"; keyClick(Qt.Key_Return, Qt.ControlModifier);
            compare(service.captured.length, 1); compare(service.captured[0].text, "Review // tomorrow p1 #Studio");
        }
        function test_escape_dismisses_picker_before_cancelling() {
            enter("Review #Stu"); keyClick(Qt.Key_Escape); compare(composer.pickerKind, ""); compare(composer.text, "Review #Stu");
        }
        function type(text) { for (var i = 0; i < text.length; i++) keyClick(text[i]); }
        function test_key_field_edits_from_keys() {
            plainField.text = ""; plainField.acceptedCount = 0; plainField.parent.visible = true; plainField.forceActiveFocus();
            type("hello world"); compare(plainField.text, "hello world"); compare(plainField.cursorPosition, 11);
            for (var i = 0; i < 5; i++) keyClick(Qt.Key_Left);
            type("big "); compare(plainField.text, "hello big world");
            keyClick(Qt.Key_Backspace, Qt.ControlModifier); compare(plainField.text, "hello world"); compare(plainField.cursorPosition, 6);
            keyClick(Qt.Key_Home); compare(plainField.cursorPosition, 0); keyClick(Qt.Key_Delete); compare(plainField.text, "ello world");
            keyClick(Qt.Key_End); keyClick(Qt.Key_Backspace); compare(plainField.text, "ello worl");
            keyClick(Qt.Key_Z, Qt.ControlModifier); compare(plainField.text, "ello world");
            keyClick(Qt.Key_A, Qt.ControlModifier); compare(plainField.selectedText, "ello world"); type("x"); compare(plainField.text, "x");
            keyClick(Qt.Key_U, Qt.ControlModifier); compare(plainField.text, "");
            keyClick(Qt.Key_Return); compare(plainField.acceptedCount, 1);
            keyClick(Qt.Key_V); compare(plainField.text, "v", "Plain V types a letter");
            plainField.parent.visible = false;
        }
        function test_password_field_draws_bullets() {
            secretField.text = "secret"; compare(secretField.shown, "\u2022\u2022\u2022\u2022\u2022\u2022");
            compare(secretField.text, "secret");
        }
        function test_paste_reads_clipboard_only_on_request_bounded_and_clean() {
            // check-composer puts a fake wl-paste first in PATH: it prints a
            // line with control characters and 6000 more bytes, then hangs.
            plainField.text = "A "; plainField.parent.visible = true; plainField.forceActiveFocus();
            verify(!plainField.pasting);
            var started = Date.now();
            keyClick(Qt.Key_V, Qt.ControlModifier); verify(plainField.pasting);
            tryVerify(function() { return !plainField.pasting; }, 6000);
            verify(Date.now() - started < 4000, "the read stops at its deadline");
            verify(plainField.text.indexOf("A Line one line two") === 0, plainField.text.slice(0, 40));
            verify(plainField.text.length <= 2 + 4096); verify(!/[\u0000-\u001f]/.test(plainField.text));
            plainField.parent.visible = false;
        }
        function test_task_name_keeps_shift_enter_newline_and_enter_submits() {
            enter("Review"); keyClick(Qt.Key_Return, Qt.ShiftModifier);
            compare(composer.text, "Review\n"); compare(service.captured.length, 0);
            type("notes"); keyClick(Qt.Key_Return); compare(service.captured.length, 1); compare(service.captured[0].text, "Review\nnotes");
        }
        function test_size_control_commits_typed_value_and_keeps_binding() {
            sizeControl.parent.visible = true; sizeControl.saved = 400; sizeControl.modified = 0;
            var field = findChild(sizeControl, "sizeField"); field.forceActiveFocus();
            keyClick(Qt.Key_A, Qt.ControlModifier); type("5x00"); compare(field.text, "500");
            keyClick(Qt.Key_Return); compare(sizeControl.value, 500); compare(sizeControl.modified, 1); compare(field.text, "500");
            sizeControl.saved = 700; compare(sizeControl.value, 700, "value still follows the saved size"); compare(field.text, "700");
            keyClick(Qt.Key_A, Qt.ControlModifier); type("5000"); keyClick(Qt.Key_Return); compare(sizeControl.value, 1000);
            sizeControl.parent.visible = false;
        }
        function test_no_qt_text_input_is_instantiated() {
            var found = [];
            function walk(item) {
                var name = String(item);
                if (/^(QQuickTextInput|QQuickTextEdit|QQuickTextField|QQuickTextArea|TextField|TextArea)/.test(name)) found.push(name);
                for (var i = 0; i < item.children.length; i++) walk(item.children[i]);
            }
            walk(window.contentItem);
            compare(found.length, 0, found.join(", "));
        }
        function test_existing_task_title_is_not_reinterpreted() {
            composer.editingTask = {id: "task", content: "Discuss tomorrow p1", project_id: "inbox", priority: 1, labels: []};
            composer.loadTask(); compare(composer.parsed.tokens.length, 0); compare(composer.shownPriority, 4);
            compare(composer.text, "Discuss tomorrow p1"); composer.editingTask = null;
        }
    }
    Timer {
        id: captures
        interval: 250; repeat: true
        running: Quickshell.env("TODOIST_CAPTURE_ONLY") === "1"
        property int phase: 0
        property var scenes: [
            {theme: "dark", width: 360, settings: false}, {theme: "light", width: 360, settings: false},
            {theme: "dark", width: 560, settings: false}, {theme: "light", width: 560, settings: false},
            {theme: "dark", width: 420, settings: true}, {theme: "light", width: 420, settings: true},
            {theme: "dark", width: 420, settings: true, token: true}, {theme: "light", width: 420, settings: true, token: true}
        ]
        function named(item, name) {
            if (item.objectName === name) return item;
            for (var i = 0; i < item.children.length; i++) { var found = named(item.children[i], name); if (found) return found; }
            return null;
        }
        onTriggered: {
            var scene = scenes[Math.floor(phase / 2)];
            if (!scene) { Qt.quit(); return; }
            if (phase % 2 === 0) {
                Commons.Color.popups.background = scene.theme === "light" ? "#ffffff" : "#282828";
                Commons.Color.popups.text = scene.theme === "light" ? "#202020" : "#eeeeee";
                Commons.Color.popups.border = scene.theme === "light" ? "#cccccc" : "#555555";
                Commons.Color.foreground = Commons.Color.popups.text; Commons.Color.background = Commons.Color.popups.background;
                Commons.Color.accent = scene.theme === "light" ? "#d1453b" : "#ff5c50";
                // Use the real bar default; a fake proportional bar font hides regressions.
                service.widgets = [fontWidget]; fontBar.fontFamily = Style.font.family;
                service.preferences = {};
                card.width = scene.width;
                composer.reset(); composer.visible = !scene.settings; settings.visible = scene.settings;
                composer.text = "Review tomorrow at 4pm !!1 #Studio /Website @next !30m {Friday}";
                composer.focusInput();
                if (scene.token) { var token = named(settings, "tokenInput"); token.text = "0123456789abcdef0123"; token.forceActiveFocus(); }
            } else {
                var path = Quickshell.env("TODOIST_CAPTURE_DIR") + "/" + Quickshell.env("TODOIST_CAPTURE_STAGE") + "-" + (scene.token ? "token" : scene.settings ? "settings" : "composer") + "-" + scene.width + "-" + scene.theme + ".png";
                card.grabToImage(function(result) { result.saveToFile(path); });
            }
            phase++;
        }
    }
}
