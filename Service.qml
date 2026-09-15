import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "Model.js" as Model
import "ui/OrderModel.js" as Order

Item {
    id: root
    property var shell: null
    property var manifest: null
    property string token: ""
    property bool storageReady: false
    property bool preferencesLoaded: false
    property bool enableShortcuts: true
    property alias shortcut: shortcuts
    property bool loaded: false
    property bool loading: false
    property bool saving: false
    property bool connecting: false
    property string error: ""
    property string syncToken: "*"
    property var tasks: []
    property var projects: []
    property var sections: []
    property var labels: []
    property var collaborators: []
    property var reminders: []
    property var completedInfo: []
    property var user: ({})
    property var preferences: ({})
    property var requests: []
    property var completionIds: ({})
    property var reorderCache: ({})
    property var pendingReorder: null
    property int generation: 0
    property real lastSync: 0
    property real retryAfter: 0
    property date now: clock.date
    property var widgets: []
    readonly property bool configured: token.length > 0
    readonly property var projectMap: Model.byId(projects)
    readonly property var sectionMap: Model.byId(sections)
    readonly property int panelWidth: Math.max(360, Math.min(1000, Number(preferences.panelWidth) || 420))
    readonly property int panelHeight: Math.max(280, Math.min(1200, Number(preferences.panelHeight) || 560))
    readonly property int todayCount: tasks.filter(function(t) {
        return Model.inView(t, "today", Model.dateKey(now), projectMap) && Model.matches(t, Model.DEFAULT_VIEW, user.id, Model.dateKey(now));
    }).length
    property string stateDir: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/omarchy-todoist"

    signal taskAdded()
    signal taskUpdated(string taskId)
    signal taskCompleted(string taskId)
    signal connected()
    signal operationFailed(string message)

    function registerWidget(widget) { if (widgets.indexOf(widget) < 0) widgets = widgets.concat([widget]); }
    function unregisterWidget(widget) { widgets = widgets.filter(function(w) { return w !== widget; }); }
    function closePanels() { widgets.forEach(function(w) { w.close(); }); }
    function openPanel() {
        var name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
        var widget = widgets.filter(function(w) { return w.QsWindow.window && w.QsWindow.window.screen.name === name; })[0] || widgets[0];
        if (widget) widget.open();
    }
    function viewOptions(view) { return Object.assign({}, Model.DEFAULT_VIEW, preferences[view] || {}); }
    function setOption(view, key, value) {
        var next = Object.assign({}, preferences), options = viewOptions(view);
        options[key] = value;
        next[view] = options;
        preferences = next;
        if (storageReady) settingsFile.setText(JSON.stringify(next));
    }
    function resetView(view) {
        var next = Object.assign({}, preferences);
        delete next[view]; preferences = next;
        if (storageReady) settingsFile.setText(JSON.stringify(next));
    }
    function saveShortcut(value) {
        preferences = Object.assign({}, preferences, {quickAddShortcut: value});
        if (storageReady) settingsFile.setText(JSON.stringify(preferences));
    }
    function setPanelSize(key, value) {
        if (key !== "panelWidth" && key !== "panelHeight") return;
        var next = Object.assign({}, preferences);
        next[key] = Math.max(key === "panelWidth" ? 360 : 280, Math.min(key === "panelWidth" ? 1000 : 1200, Math.round(Number(value))));
        if (!isFinite(next[key])) return;
        preferences = next;
        if (storageReady) settingsFile.setText(JSON.stringify(preferences));
    }
    function cancelRequests() {
        generation++;
        var old = requests; requests = [];
        old.forEach(function(r) { r.xhr.abort(); });
        loading = false; saving = false; connecting = false;
        if (pendingReorder) finishReorder(false);
    }
    function applyToken(value) {
        cancelRequests();
        token = String(value || "").trim();
        tasks = []; projects = []; sections = []; labels = []; collaborators = []; reminders = []; completedInfo = []; user = {};
        syncToken = "*"; loaded = false; error = ""; retryAfter = 0; lastSync = 0;
        completionIds = {};
        reorderCache = {};
        if (configured) refresh();
    }
    function connectToken(value) {
        if (connecting || saving || !storageReady) return;
        var candidate = value.trim();
        if (!candidate || /\s/.test(candidate)) { error = "Paste the API token from Todoist’s Developer settings."; return; }
        connecting = true; error = "";
        request("POST", "/sync", {sync_token: "*", resource_types: ["user"]}, candidate, function(data, message) {
            if (message) { connecting = false; error = message; return; }
            credentialWriter.pendingToken = candidate;
            credentialWriter.running = true;
        });
    }
    function disconnect() {
        if (saving || connecting) return;
        connecting = true;
        credentialWriter.pendingToken = "";
        credentialWriter.running = true;
    }
    function request(method, path, body, credential, callback, requestId) {
        var xhr = new XMLHttpRequest(), epoch = generation;
        var entry = {xhr: xhr, started: Date.now(), done: false};
        function finish(data, message) {
            if (entry.done) return;
            entry.done = true;
            requests = requests.filter(function(r) { return r !== entry; });
            if (epoch === generation) callback(data, message);
        }
        entry.timeout = function() { finish(null, Model.errorMessage(0)); xhr.abort(); };
        requests = requests.concat([entry]);
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE || epoch !== generation) return;
            if (xhr.status < 200 || xhr.status >= 300) {
                if (xhr.status === 429) root.retryAfter = Date.now() + Math.max(60, Number(xhr.getResponseHeader("Retry-After")) || 60) * 1000;
                finish(null, Model.errorMessage(xhr.status)); return;
            }
            try { var data = xhr.responseText ? JSON.parse(xhr.responseText) : {}; }
            catch (e) { finish(null, "Todoist returned an unreadable response. Try refreshing."); return; }
            finish(data, "");
        };
        xhr.open(method, Model.API_BASE + path);
        xhr.setRequestHeader("Authorization", "Bearer " + credential);
        xhr.setRequestHeader("Content-Type", path === "/sync" ? "application/x-www-form-urlencoded" : "application/json");
        if (requestId) xhr.setRequestHeader("X-Request-Id", requestId);
        var payload = body === null ? "" : JSON.stringify(body);
        if (path === "/sync") payload = Object.keys(body).map(function(key) {
            return encodeURIComponent(key) + "=" + encodeURIComponent(typeof body[key] === "string" ? body[key] : JSON.stringify(body[key]));
        }).join("&");
        xhr.send(payload);
    }
    function ingest(data) {
        var full = data.full_sync === true;
        tasks = Model.merge(tasks, data.items, full).filter(Model.active);
        projects = Model.merge(projects, data.projects, full).filter(function(p) { return !p.is_archived; });
        sections = Model.merge(sections, data.sections, full).filter(function(s) { return !s.is_archived; });
        labels = Model.merge(labels, data.labels, full);
        collaborators = Model.merge(collaborators, data.collaborators, full);
        reminders = Model.merge(reminders, data.reminders, full);
        completedInfo = Model.mergeCompleted(completedInfo, data.completed_info, full);
        if (data.user) user = data.user;
        if (data.day_orders) tasks = tasks.map(function(t) {
            return data.day_orders[t.id] !== undefined ? Object.assign({}, t, {day_order: data.day_orders[t.id]}) : t;
        });
        syncToken = data.sync_token || "*";
        loaded = true; lastSync = Date.now();
    }
    function refresh() {
        if (!configured || loading || saving || Date.now() < retryAfter) return;
        loading = true;
        request("POST", "/sync", {sync_token: syncToken, resource_types: ["items", "projects", "sections", "labels", "user", "collaborators", "reminders", "completed_info"]}, token, function(data, message) {
            loading = false;
            if (message) { error = message; return; }
            if (!data || !data.sync_token) { error = "Todoist returned an incomplete sync response. Try refreshing."; return; }
            ingest(data); error = "";
        });
    }
    function beginWrite() {
        if (!configured || saving || connecting || Date.now() < retryAfter) return false;
        // An older sync must never restore a task after a successful completion.
        cancelRequests(); saving = true; error = "";
        return true;
    }
    function addTask(text, requestId) {
        if (!text.trim() || !beginWrite()) return false;
        request("POST", "/tasks/quick", {text: text.trim(), auto_reminder: true}, token, function(data, message) {
            saving = false;
            if (message) { error = message; operationFailed(message); return; }
            taskAdded(); refresh();
        }, requestId);
        return true;
    }
    function completeTask(task) {
        if (!beginWrite()) return false;
        var key = task.id + ":" + String(task.updated_at || "") + ":" + String((task.due || {}).date || "");
        if (!completionIds[key]) completionIds[key] = Model.uuid();
        request("POST", "/tasks/" + encodeURIComponent(task.id) + "/close", null, token, function(data, message) {
            saving = false;
            if (message) { error = message; operationFailed(message); return; }
            // Recurring tasks are rescheduled by Todoist, then restored by sync.
            tasks = tasks.filter(function(t) { return t.id !== task.id && t.parent_id !== task.id; });
            delete completionIds[key];
            taskCompleted(String(task.id));
            refresh();
        }, completionIds[key]);
        return true;
    }
    function updateTask(taskId, commands) {
        if (!commands.length || !beginWrite()) return false;
        request("POST", "/sync", {sync_token: syncToken, resource_types: ["items", "projects", "sections", "labels", "user", "collaborators", "reminders", "completed_info"], commands: commands}, token, function(data, message) {
            saving = false;
            if (message) { error = message; operationFailed(message); return; }
            var status = data && data.sync_status || {};
            var failed = commands.filter(function(command) { return status[command.uuid] !== "ok"; });
            if (data && data.sync_token) ingest(data);
            if (failed.length) {
                var result = status[failed[0].uuid];
                message = (failed.length < commands.length ? "Some changes were saved. " : "") + (result && result.error ? result.error : "Todoist did not confirm the changes. Please retry.");
                error = message; operationFailed(message); return;
            }
            error = ""; taskUpdated(String(taskId));
            if (!data.sync_token) refresh();
        });
        return true;
    }
    function finishReorder(success) {
        var pending = pendingReorder;
        if (!pending) return;
        pendingReorder = null;
        if (success) { reorderCache = {}; return; }
        tasks = Order.rollback(tasks, pending.patches, pending.previous);
        if (!pending.saved && viewOptions(pending.view).sorting === "manual") setOption(pending.view, "sorting", pending.sorting);
    }
    function reorderTasks(view, sourceId, targetId, after, groupKey) {
        if (!configured || saving || connecting || Date.now() < retryAfter) return false;
        var options = viewOptions(view), plan;
        try {
            var rows = Model.viewRows(tasks, projects, collaborators, options, view, user.id, now);
            plan = Order.plan(tasks, rows, view, sourceId, targetId, after, groupKey);
        } catch (e) { error = "Could not calculate the task order. Refresh and try again."; return false; }
        if (!plan) return false;
        if (!plan.commands.length) { setOption(view, "sorting", "manual"); return true; }
        if (!beginWrite()) return false;
        var signature = JSON.stringify(plan.commands);
        if (reorderCache.signature !== signature) reorderCache = {signature: signature, commands: plan.commands.map(function(c) { return Object.assign({uuid: Model.uuid()}, c); })};
        pendingReorder = {view: view, sorting: options.sorting, patches: plan.patches, previous: Order.before(tasks, plan.patches), commands: reorderCache.commands, offset: 0, saved: false};
        tasks = Order.apply(tasks, plan.patches);
        setOption(view, "sorting", "manual");
        sendReorderBatch();
        return true;
    }
    function sendReorderBatch() {
        var pending = pendingReorder, batch = pending.commands.slice(pending.offset, pending.offset + 100);
        request("POST", "/sync", {sync_token: syncToken, resource_types: ["items", "projects", "sections", "labels", "user", "collaborators", "reminders", "completed_info"], commands: batch}, token, function(data, message) {
            var statuses = data && data.sync_status || {}, failed = [];
            batch.forEach(function(command) {
                if (message || statuses[command.uuid] !== "ok") { failed.push(command); return; }
                pending.saved = true;
                var ids = command.type === "item_update_day_orders" ? Object.keys(command.args.ids_to_orders) : [command.args.id];
                ids.forEach(function(id) { delete pending.patches[id]; });
            });
            if (failed.length) {
                var result = statuses[failed[0].uuid];
                message = message || (result && result.error) || "Todoist did not confirm the new order. Try again.";
                finishReorder(false);
                if (data && data.sync_token) ingest(data);
                // After an uncertain write, the next sync reconciles server state.
                else syncToken = "*";
                saving = false;
                error = (pending.saved ? "Some tasks were reordered. " : "Could not save task order. ") + message;
                operationFailed(error); return;
            }
            if (data && data.sync_token) {
                tasks = Order.rollback(tasks, pending.patches, pending.previous);
                ingest(data);
                pending.previous = Order.before(tasks, pending.patches);
                tasks = Order.apply(tasks, pending.patches);
            }
            pending.offset += batch.length;
            if (pending.offset < pending.commands.length) { sendReorderBatch(); return; }
            finishReorder(true); saving = false; error = "";
            if (!data.sync_token) refresh();
        });
    }

    Process {
        id: initializeStorage
        command: ["sh", "-c", "umask 077; mkdir -p \"$1\" && chmod 700 \"$1\" && touch \"$1/token\" \"$1/views.json\" && chmod 600 \"$1/token\" \"$1/views.json\"", "todoist-storage", root.stateDir]
        running: true
        onExited: function(code) {
            if (code === 0) root.storageReady = true;
            else root.error = "Could not create the Todoist settings directory.";
        }
    }
    FileView {
        id: tokenFile
        path: root.storageReady ? root.stateDir + "/token" : ""
        onLoaded: root.applyToken(text())
    }
    FileView {
        id: settingsFile
        path: root.storageReady ? root.stateDir + "/views.json" : ""
        onLoaded: {
            try { var data = JSON.parse(text() || "{}"); root.preferences = data && typeof data === "object" && !Array.isArray(data) ? data : {}; }
            catch (e) { root.preferences = {}; }
            root.preferencesLoaded = true;
        }
        onSaveFailed: root.error = "Could not save the display preferences."
    }
    ShortcutManager { id: shortcuts; service: root; enabled: root.enableShortcuts && root.preferencesLoaded }
    Process {
        id: credentialWriter
        property string pendingToken: ""
        command: ["sh", "-c", "umask 077; cat > \"$1/token.new\" && chmod 600 \"$1/token.new\" && mv -f \"$1/token.new\" \"$1/token\"", "todoist-token", root.stateDir]
        stdinEnabled: true
        onStarted: { write(pendingToken); stdinEnabled = false; }
        onExited: function(code) {
            stdinEnabled = true;
            root.connecting = false;
            if (code !== 0) { root.error = "Could not save the API token. Please try again."; pendingToken = ""; return; }
            root.applyToken(pendingToken); pendingToken = "";
            root.connected();
        }
    }
    SystemClock { id: clock; precision: SystemClock.Minutes; onDateChanged: root.refresh() }
    Timer { interval: 60000; running: root.configured; repeat: true; onTriggered: root.refresh() }
    Timer {
        interval: 1000; running: root.requests.length > 0; repeat: true
        onTriggered: root.requests.slice().forEach(function(r) { if (Date.now() - r.started > 20000) r.timeout(); })
    }
}
