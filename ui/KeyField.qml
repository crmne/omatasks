import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui as UI
import "KeyEdit.js" as KeyEdit

// A text field built from key events instead of Qt's text input.
//
// Every editable Qt TextInput or TextEdit asks the clipboard for its contents
// whenever another application changes it, focused or not, with no size
// limit or deadline. This field never does. It takes key events, keeps the
// text, caret and selection itself (KeyEdit.js), and draws them with plain
// Text items. The clipboard is read only when the user pastes with Ctrl+V or
// Shift+Insert, by wl-paste in a separate process, capped at two seconds and
// 4096 bytes. Copying writes the clipboard and never reads it.
//
// It looks like the kit's TextField when framed, and offers the parts of the
// TextField and TextArea API the plugin uses: text, placeholderText,
// cursorPosition, length, insert, remove, positionToRectangle, accepted,
// editingFinished and textEdited. keyPressed runs before the field's own
// keys, so a caller can take Enter, Escape or arrows first.
Item {
    id: root

    property string text: ""
    property string placeholderText: ""
    property bool password: false
    property bool multiline: false
    property bool framed: true
    property int maximumLength: 32767
    // Optional function(text) -> bool. An edit that fails it is ignored.
    property var validator: null
    property int horizontalAlignment: Text.AlignLeft
    property color foreground: Commons.Color.foreground
    property color accent: Commons.Color.accent
    property color placeholderTextColor: Qt.darker(foreground, 1.6)
    property color selectionColor: Style.selectionFillFor(foreground, accent)
    property real horizontalPadding: framed ? Style.spacing.controlPaddingX : 0
    property real verticalPadding: framed ? Style.spacing.inputPaddingY : 0
    property alias font: metrics.font
    property int cursorPosition: 0
    property int anchorPosition: 0
    readonly property int length: text.length
    readonly property int selectionStart: Math.min(anchorPosition, cursorPosition)
    readonly property int selectionEnd: Math.max(anchorPosition, cursorPosition)
    readonly property string selectedText: text.slice(selectionStart, selectionEnd)
    readonly property real lineHeight: Math.ceil(metrics.height)
    readonly property real contentHeight: lines.length * lineHeight
    readonly property rect cursorRectangle: { lines; cursorPosition; inner.width; return positionToRectangle(cursorPosition); }
    property bool pasting: false

    signal accepted()
    signal editingFinished()
    signal textEdited()
    signal keyPressed(var event)

    readonly property string shown: password ? "•".repeat(text.length) : text
    readonly property var lines: { metrics.font; return KeyEdit.lines(shown, multiline ? inner.width : -1, measure, multiline); }
    readonly property bool hot: mouse.containsMouse
    readonly property var borderSpec: Border.controlSpec(activeFocus ? "focus" : (hot ? "hover-cursor" : "normal"), foreground, accent)

    property bool internal: false
    property var history: []

    function measure(value) { return metrics.advanceWidth(value); }
    function current() { return {text: text, cursor: cursorPosition, anchor: anchorPosition}; }
    function apply(next) {
        internal = true;
        if (text !== next.text) text = next.text;
        cursorPosition = next.cursor; anchorPosition = next.anchor;
        internal = false;
    }
    // A user edit: checked, remembered for undo, and reported.
    function edit(next) {
        if (next.text === text) { apply(next); return true; }
        if (validator && !validator(next.text)) return false;
        history.push(current());
        if (history.length > 100) history.shift();
        apply(next);
        textEdited();
        return true;
    }
    function insert(position, value) {
        position = KeyEdit.clamp(position, 0, text.length);
        var cursor = cursorPosition >= position ? cursorPosition + value.length : cursorPosition;
        apply({text: text.slice(0, position) + value + text.slice(position), cursor: cursor, anchor: cursor});
    }
    function remove(start, end) {
        start = KeyEdit.clamp(start, 0, text.length); end = KeyEdit.clamp(end, start, text.length);
        var cursor = cursorPosition > end ? cursorPosition - (end - start) : Math.min(cursorPosition, start);
        apply({text: text.slice(0, start) + text.slice(end), cursor: cursor, anchor: cursor});
    }
    function selectAll() { apply(KeyEdit.selectAll(current())); }
    function deselect() { anchorPosition = cursorPosition; }
    function undo() { if (history.length) { apply(history.pop()); textEdited(); } }
    function pasteText(value) { edit(KeyEdit.insert(current(), KeyEdit.clean(value, multiline).slice(0, KeyEdit.PASTE_LIMIT), maximumLength)); }
    function startPaste() { if (pasting) return; pasting = true; paste.running = true; pasteDeadline.restart(); }

    function lineX(index) {
        var line = lines[index], width = measure(shown.slice(line.start, line.end));
        if (multiline) return 0;
        if (width + caret.width > inner.width) return Math.min(0, inner.width - caret.width - measure(shown.slice(0, cursorPosition)));
        if (horizontalAlignment === Text.AlignHCenter) return (inner.width - width) / 2;
        if (horizontalAlignment === Text.AlignRight) return inner.width - width - caret.width;
        return 0;
    }
    function positionToRectangle(position) {
        position = KeyEdit.clamp(position, 0, text.length);
        var index = KeyEdit.lineOf(lines, position), line = lines[index];
        return Qt.rect(inner.x + lineX(index) + measure(shown.slice(line.start, position)), inner.y + index * lineHeight, caret.width, lineHeight);
    }
    function positionAt(x, y) {
        var index = KeyEdit.clamp(Math.floor((y - inner.y) / lineHeight), 0, lines.length - 1);
        return KeyEdit.positionInLine(shown, lines[index], x - inner.x - lineX(index), measure);
    }
    // Move between display lines at the caret's x. Returns false at the edge.
    function verticalMove(step, extend) {
        var index = KeyEdit.lineOf(lines, cursorPosition) + step;
        if (index < 0 || index >= lines.length) return false;
        var line = lines[KeyEdit.lineOf(lines, cursorPosition)];
        var x = measure(shown.slice(line.start, cursorPosition));
        apply(KeyEdit.moveTo(current(), KeyEdit.positionInLine(shown, lines[index], x, measure), extend));
        return true;
    }

    // Typed text from a key event, or "" for anything that is not plain input.
    function typed(event) {
        if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return "";
        var value = String(event.text || "");
        return KeyEdit.clean(value, false) === value ? value : "";
    }
    function handle(event) {
        var ctrl = (event.modifiers & Qt.ControlModifier) !== 0, shift = (event.modifiers & Qt.ShiftModifier) !== 0;
        var s = current(), line = lines[KeyEdit.lineOf(lines, cursorPosition)];
        switch (event.key) {
        case Qt.Key_V: if (!ctrl) break; startPaste(); return true;
        case Qt.Key_Insert: if (!shift) break; startPaste(); return true;
        case Qt.Key_A: if (!ctrl) break; selectAll(); return true;
        case Qt.Key_U: if (!ctrl) break; edit(KeyEdit.clear()); return true;
        case Qt.Key_Z: if (!ctrl) break; undo(); return true;
        // Copying writes the clipboard; it never reads it.
        case Qt.Key_C: if (!ctrl) break; if (!password && selectedText) Quickshell.clipboardText = selectedText; return true;
        case Qt.Key_X: if (!ctrl) break; if (!password && selectedText) { Quickshell.clipboardText = selectedText; edit(KeyEdit.backspace(s, false)); } return true;
        case Qt.Key_Backspace: edit(KeyEdit.backspace(s, ctrl)); return true;
        case Qt.Key_Delete: edit(KeyEdit.forwardDelete(s, ctrl)); return true;
        case Qt.Key_Left: apply(KeyEdit.left(s, ctrl, shift)); return true;
        case Qt.Key_Right: apply(KeyEdit.right(s, ctrl, shift)); return true;
        case Qt.Key_Home: apply(KeyEdit.moveTo(s, ctrl || !multiline ? 0 : line.start, shift)); return true;
        case Qt.Key_End: apply(KeyEdit.moveTo(s, ctrl || !multiline ? text.length : line.hard ? line.end : KeyEdit.previous(text, line.end), shift)); return true;
        case Qt.Key_Up: return multiline && verticalMove(-1, shift);
        case Qt.Key_Down: return multiline && verticalMove(1, shift);
        case Qt.Key_Return:
        case Qt.Key_Enter:
            if (multiline && !ctrl) { edit(KeyEdit.insert(s, "\n", maximumLength)); return true; }
            accepted(); editingFinished();
            return true;
        }
        var value = typed(event);
        if (value === "") return false;
        edit(KeyEdit.insert(s, value, maximumLength));
        return true;
    }

    activeFocusOnTab: true
    implicitWidth: framed ? Style.space(160) : Style.space(40)
    implicitHeight: Math.max(1, lines.length) * lineHeight + 2 * verticalPadding + (framed ? Border.top(borderSpec) + Border.bottom(borderSpec) : 0)

    onTextChanged: if (!internal) { history = []; cursorPosition = text.length; anchorPosition = cursorPosition; }
    onCursorPositionChanged: if (!internal && (cursorPosition < 0 || cursorPosition > text.length)) cursorPosition = KeyEdit.clamp(cursorPosition, 0, text.length)
    onActiveFocusChanged: if (!activeFocus) { deselect(); editingFinished(); }
    Keys.onPressed: function(event) {
        root.keyPressed(event);
        if (event.accepted) return;
        if (root.handle(event)) { event.accepted = true; blink.on = true; blink.restart(); }
    }

    FontMetrics { id: metrics; font.family: Style.font.family; font.pixelSize: Style.font.body }

    UI.BorderSurface {
        visible: root.framed
        anchors.fill: parent
        color: Style.controlFill(root.activeFocus, root.hot, root.foreground, root.accent)
        borderSpec: root.borderSpec
        radius: Style.cornerRadius
    }

    Item {
        id: inner
        x: root.horizontalPadding + (root.framed ? Border.left(root.borderSpec) : 0)
        y: root.multiline ? root.verticalPadding + (root.framed ? Border.top(root.borderSpec) : 0) : (root.height - height) / 2
        width: Math.max(0, root.width - x - root.horizontalPadding - (root.framed ? Border.right(root.borderSpec) : 0))
        height: Math.max(1, root.lines.length) * root.lineHeight
        clip: !root.multiline

        Repeater {
            model: root.activeFocus ? root.lines : []
            Rectangle {
                required property var modelData
                required property int index
                readonly property int from: Math.max(root.selectionStart, modelData.start)
                readonly property int to: Math.min(root.selectionEnd, modelData.end)
                visible: to > from
                x: root.lineX(index) + root.measure(root.shown.slice(modelData.start, from))
                y: index * root.lineHeight
                width: root.measure(root.shown.slice(from, to))
                height: root.lineHeight
                color: root.selectionColor
            }
        }
        Text {
            visible: root.text === ""
            width: parent.width
            height: root.lineHeight
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: root.horizontalAlignment
            textFormat: Text.PlainText
            elide: Text.ElideRight
            text: root.placeholderText
            color: root.placeholderTextColor
            font: metrics.font
        }
        Repeater {
            model: root.lines
            Text {
                required property var modelData
                required property int index
                x: root.lineX(index)
                y: index * root.lineHeight
                height: root.lineHeight
                verticalAlignment: Text.AlignVCenter
                textFormat: Text.PlainText
                text: root.shown.slice(modelData.start, modelData.end)
                color: root.foreground
                font: metrics.font
            }
        }
        Rectangle {
            id: caret
            readonly property rect at: root.cursorRectangle
            visible: root.activeFocus && blink.on
            x: at.x - inner.x
            y: at.y - inner.y + (root.lineHeight - height) / 2
            width: Math.max(1, Style.spaceReal(1))
            height: Math.min(root.lineHeight, metrics.font.pixelSize * 1.25)
            color: root.foreground
        }
    }

    Timer {
        id: blink
        property bool on: true
        interval: 530
        repeat: true
        running: root.activeFocus
        onRunningChanged: on = true
        onTriggered: on = !on
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.IBeamCursor
        onPressed: function(event) {
            root.forceActiveFocus();
            var position = root.positionAt(event.x, event.y);
            root.apply(KeyEdit.moveTo(root.current(), position, false));
        }
    }

    // The only clipboard read: on an explicit paste, out of process, bounded
    // in time (timeout) and size (head). The command holds no user data.
    Process {
        id: paste
        command: ["sh", "-c", "timeout -k 1 2 wl-paste --no-newline --type text 2>/dev/null | head -c 4096"]
        stdout: StdioCollector { id: pasteOutput }
        onExited: { pasteDeadline.stop(); if (root.activeFocus) root.pasteText(pasteOutput.text); root.pasting = false; }
    }
    Timer { id: pasteDeadline; interval: 4000; onTriggered: { paste.running = false; root.pasting = false; } }
}
