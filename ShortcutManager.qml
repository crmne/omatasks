import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "ShortcutModel.js" as Model
import "Model.js" as Tasks

Item {
    id: root
    required property var service
    readonly property string value: service.preferences.quickAddShortcut === undefined ? Model.DEFAULT : String(service.preferences.quickAddShortcut)
    readonly property string ownerId: Tasks.uuid()
    property string registered: ""
    property string candidate: ""
    property string message: ""
    property bool busy: false
    property bool persistPending: false
    property bool successful: true
    property bool destroying: false

    function apply(value, persist) {
        if (busy || !enabled) return;
        var parsed = Model.parse(value);
        successful = false;
        if (!parsed) { message = "Use modifiers and a key, for example ALT + SPACE."; return; }
        candidate = parsed.text; persistPending = persist === true;
        message = ""; busy = true; readBindings.running = true;
    }
    function checkBindings(text, code) {
        if (code !== 0 || !text.trim()) { busy = false; message = "Could not read Hyprland’s shortcuts."; return; }
        var list = Model.bindings(text), conflict = Model.conflict(list, Model.parse(candidate));
        if (conflict) { busy = false; message = candidate + " is already assigned to " + (conflict.description || "another action") + "."; return; }
        registerBinding.command = ["hyprctl", "eval", Model.registerCode(list, registered, candidate, ownerId)];
        registerBinding.running = true;
    }
    onValueChanged: if (enabled) applyLater.restart()
    onEnabledChanged: if (enabled) applyLater.restart()
    Component.onDestruction: {
        destroying = true;
        if (registered) Quickshell.execDetached(["hyprctl", "eval", Model.releaseCode(registered, ownerId)]);
    }
    Timer { id: applyLater; interval: 250; onTriggered: if (root.busy) restart(); else root.apply(root.value, false) }
    Connections {
        target: Hyprland
        function onRawEvent(event) { if (root.enabled && event.name === "configreloaded") applyLater.restart(); }
    }
    Process {
        id: readBindings
        command: ["hyprctl", "binds"]
        stdout: StdioCollector { id: bindsOutput }
        onExited: function(code) { root.checkBindings(bindsOutput.text, code); }
    }
    Process {
        id: registerBinding
        stdout: StdioCollector { id: registerOutput }
        onExited: function(code) {
            root.busy = false;
            if (code !== 0 || registerOutput.text.trim() !== "ok") { root.message = "Could not apply the shortcut. Check your Hyprland configuration."; return; }
            root.registered = root.candidate; root.successful = true;
            root.message = root.candidate ? "Shortcut saved." : "Quick-add shortcut disabled.";
            if (root.persistPending) root.service.saveShortcut(root.candidate);
        }
    }
}
