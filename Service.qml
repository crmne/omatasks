import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import "Model.js" as Model
import "ui/OrderModel.js" as Order
import "ui/BulkModel.js" as Bulk
import "ui/NotifyModel.js" as Notify
import "ui/BarModel.js" as Bar

Item {
    id: root
    property var shell: null
    property var manifest: null
    property string token: ""
    property bool storageReady: false
    property bool preferencesLoaded: false
    property bool enableShortcuts: true
    property bool enableNotifications: true
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
    property var bulkRetry: null
    property int generation: 0
    property real lastSync: 0
    property real retryAfter: 0
    property real nextSyncRetry: 0
    property int syncFailures: 0
    property date now: clock.date
    property var widgets: []
    property real startedAt: Date.now()
    property var shownAlerts: ({})
    property var snoozed: ({})
    readonly property string barMode: Bar.mode(preferences.barTask)
    readonly property var barTasks: loaded ? Bar.selection(barMode, tasks, user.id, now.getTime()) : []
    readonly property string barText: Bar.label(barTasks, now.getTime())
    readonly property string barTitle: Bar.title(barTasks)
    readonly property string barDetail: Bar.detail(barTasks, now.getTime())
    readonly property var notifySettings: Notify.settings(preferences)
    readonly property bool notifying: enableNotifications && configured && notifySettings.enabled
    readonly property string notifierPath: decodeURIComponent(Qt.resolvedUrl("Notifier.py").toString().replace(/^file:\/\//, ""))
    // The bar uses a terminal font. Task text follows the desktop's UI font.
    readonly property string fontFamily: Qt.application.font.family
    readonly property bool configured: token.length > 0
    readonly property var projectMap: Model.byId(projects)
    readonly property var sectionMap: Model.byId(sections)
    readonly property int panelWidth: Math.max(440, Math.min(1000, Number(preferences.panelWidth) || 460))
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
    signal taskActionFinished()

    function registerWidget(widget) { if (widgets.indexOf(widget) < 0) widgets = widgets.concat([widget]); }
    function unregisterWidget(widget) { widgets = widgets.filter(function(w) { return w !== widget; }); }
    function closePanels() { widgets.forEach(function(w) { w.close(); }); }
    function openPanel() {
        var name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
        var widget = widgets.filter(function(w) { return w.QsWindow.window && w.QsWindow.window.screen.name === name; })[0] || widgets[0];
        if (widget) widget.open();
    }
    function quickAdd() {
        closePanels();
        if (shell) shell.summon(manifest && manifest.id ? manifest.id : "crmne.todoist", "{}");
    }
    function togglePanel() { if (widgets.some(function(w) { return w.opened; })) closePanels(); else openPanel(); }
    function viewOptions(view) { return Object.assign({}, Model.DEFAULT_VIEW, Model.VIEW_DEFAULTS[view] || {}, preferences[view] || {}); }
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
    function setBarMode(value) {
        if (Bar.MODES.indexOf(value) < 0) return;
        preferences = Object.assign({}, preferences, {barTask: value});
        if (storageReady) settingsFile.setText(JSON.stringify(preferences));
    }
    function setNotification(key, value) {
        var next = Object.assign({}, preferences), options = Notify.settings(preferences);
        if (key === "recapTime") value = Notify.normalClock(value);
        if (!(key in options) || value === "") return false;
        options[key] = value;
        next.notifications = options;
        preferences = next;
        if (storageReady) settingsFile.setText(JSON.stringify(next));
        return true;
    }
    function setPanelSize(key, value) {
        if (key !== "panelWidth" && key !== "panelHeight") return;
        var next = Object.assign({}, preferences);
        next[key] = Math.max(key === "panelWidth" ? 440 : 280, Math.min(key === "panelWidth" ? 1000 : 1200, Math.round(Number(value))));
        if (!isFinite(next[key])) return;
        preferences = next;
        if (storageReady) settingsFile.setText(JSON.stringify(preferences));
    }
    function cancelRequests() {
        nextSyncRetry = 0;
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
        syncFailures = 0;
        completionIds = {};
        reorderCache = {};
        bulkRetry = null;
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
        function finish(data, message, status) {
            if (entry.done) return;
            entry.done = true;
            requests = requests.filter(function(r) { return r !== entry; });
            if (epoch === generation) callback(data, message, status);
        }
        entry.timeout = function() { finish(null, Model.errorMessage(0), 0); xhr.abort(); };
        requests = requests.concat([entry]);
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE || epoch !== generation) return;
            if (xhr.status < 200 || xhr.status >= 300) {
                if (xhr.status === 429) root.retryAfter = Date.now() + Math.max(60, Number(xhr.getResponseHeader("Retry-After")) || 60) * 1000;
                finish(null, Model.errorMessage(xhr.status), xhr.status); return;
            }
            try { var data = xhr.responseText ? JSON.parse(xhr.responseText) : {}; }
            catch (e) { finish(null, "Todoist returned an unreadable response. Try refreshing.", 502); return; }
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
    function scheduleSyncRetry(message) {
        syncFailures = Math.min(syncFailures + 1, 7);
        var delay = Math.min(300000, 5000 * Math.pow(2, syncFailures - 1));
        nextSyncRetry = Math.max(Date.now() + delay, retryAfter);
        error = message + " Retrying automatically.";
    }
    function refresh(manual) {
        if (!configured || loading || saving || connecting || Date.now() < retryAfter) return;
        if (manual !== true && Date.now() < nextSyncRetry) return;
        nextSyncRetry = 0;
        loading = true;
        request("POST", "/sync", {sync_token: syncToken, resource_types: ["items", "projects", "sections", "labels", "user", "collaborators", "reminders", "completed_info"]}, token, function(data, message, status) {
            loading = false;
            if (message) {
                if (status === 0 || status === 408 || status === 429 || status >= 500) scheduleSyncRetry(message);
                else error = message;
                return;
            }
            if (!data || !data.sync_token) { scheduleSyncRetry("Todoist returned an incomplete sync response."); return; }
            ingest(data); error = ""; syncFailures = 0;
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
    function applyTaskAction(ids, action, value) {
        if (!configured || saving || connecting || Date.now() < retryAfter) return false;
        var signature = JSON.stringify([ids.slice().sort(), action, value]);
        if (bulkRetry && bulkRetry.signature === signature) return retryTaskAction();
        var commands;
        try { commands = Bulk.commands(tasks, ids, action, value, now); }
        catch (e) { error = e.message; operationFailed(error); return false; }
        if (!commands.length || !beginWrite()) return false;
        bulkRetry = {signature: signature, commands: commands, saved: 0};
        sendTaskActionBatch(bulkRetry);
        return true;
    }
    function retryTaskAction() {
        if (!bulkRetry || !beginWrite()) return false;
        sendTaskActionBatch(bulkRetry);
        return true;
    }
    function sendTaskActionBatch(job) {
        var batch = job.commands.slice(0, 100);
        request("POST", "/sync", {sync_token: syncToken, resource_types: ["items", "projects", "sections", "labels", "user", "collaborators", "reminders", "completed_info"], commands: batch}, token, function(data, message) {
            var statuses = data && data.sync_status || {}, failed = [];
            batch.forEach(function(command) {
                if (message || statuses[command.uuid] !== "ok") failed.push(command);
                else job.saved++;
            });
            job.commands = failed.concat(job.commands.slice(batch.length));
            // Duplicated children may be sent in a later batch than their parent.
            var mapping = data && data.temp_id_mapping || {};
            job.commands.forEach(function(command) {
                if (mapping[command.args.parent_id]) command.args.parent_id = mapping[command.args.parent_id];
            });
            if (data && data.sync_token) ingest(data);
            else syncToken = "*";
            if (failed.length) {
                var result = statuses[failed[0].uuid];
                saving = false;
                error = (job.saved ? job.saved + " changes saved. " : "") + (message || (result && result.error) || "Todoist did not confirm the changes.") + " Retry to finish the remaining changes.";
                operationFailed(error); return;
            }
            if (job.commands.length) { sendTaskActionBatch(job); return; }
            bulkRetry = null; saving = false; error = "";
            taskActionFinished();
            if (!data || !data.sync_token) refresh();
        });
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

    function notify(request) {
        if (!notifier.running) return false;
        notifier.write(JSON.stringify(request) + "\n");
        return true;
    }
    function notifyTask(alert, nowMs) {
        var task = alert.task;
        return notify({id: "task:" + task.id, marker: alert.key, urgent: alert.urgent, title: Model.plain(task.content),
            body: Notify.taskBody(alert, nowMs, Model.projectPath(task.project_id, projectMap, task.section_id, sectionMap)),
            actions: [["default", "Open"], ["complete", "Complete"], ["snooze", "Snooze 15 min"]]});
    }
    // `preview` sends the recap now, even if this morning's was already shown.
    function notifyRecap(preview) {
        var date = new Date(), summary = Notify.recap(tasks, projects, user.id, date);
        return notify({id: "recap", marker: preview === true ? "" : "recap-" + Model.dateKey(date), title: summary.title, body: summary.body, actions: [["default", "Open"]]});
    }
    function checkNotifications(idle) {
        if (!notifying || !loaded) return;
        var nowMs = Date.now(), date = new Date(nowMs), options = notifySettings, shown = Object.assign({}, shownAlerts), rest = Object.assign({}, snoozed);
        Notify.taskAlerts(tasks, reminders, user.id, options, nowMs, startedAt - 60000, shown, snoozed).forEach(function(alert) {
            if (alert.kind === "snooze") delete rest[String(alert.task.id)];
            if (notifyTask(alert, nowMs)) shown[alert.key] = nowMs;
        });
        // The recap waits until you are at the computer, so it is not missed
        // behind a lock screen or while you are away.
        if (!idle && Notify.recapDue(options, date)) {
            var recapKey = "recap-" + Model.dateKey(date);
            if (options.recap && !shown[recapKey] && notifyRecap()) shown[recapKey] = nowMs;
            if (options.deadlines) Notify.deadlineAlerts(tasks, user.id, date).forEach(function(alert) {
                if (!shown[alert.key] && notifyTask(alert, nowMs)) shown[alert.key] = nowMs;
            });
        }
        // Forgets what is long past, so the set does not grow for as long as the shell runs.
        for (var key in shown) if (nowMs - shown[key] > 2 * 86400000) delete shown[key];
        shownAlerts = shown; snoozed = rest;
    }
    function answerNotification(line) {
        var answer;
        try { answer = JSON.parse(line); } catch (e) { return; }
        var id = String(answer.id || ""), action = String(answer.action || "");
        var taskId = id.indexOf("task:") === 0 ? id.slice(5) : "";
        var task = tasks.filter(function(t) { return String(t.id) === taskId; })[0];
        if (action === "complete" && task) {
            if (!completeTask(task)) error = "Could not complete “" + Model.plain(task.content) + "” while another change is saving. Try again.";
        } else if (action === "snooze" && task) {
            var next = Object.assign({}, snoozed);
            next[taskId] = Date.now() + Notify.SNOOZE_MS;
            snoozed = next;
        } else if (action === "default") openPanel();
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
    // The commands every Omarchy panel answers to, and Quick Add. `shell
    // toggle crmne.todoist` reaches the Quick Add overlay, not the panel.
    IpcHandler {
        target: "crmne.todoist"
        function open(): void { root.openPanel(); }
        function close(): void { root.closePanels(); }
        function show(): void { root.openPanel(); }
        function hide(): void { root.closePanels(); }
        function toggle(): void { root.togglePanel(); }
        function quickAdd(): void { root.quickAdd(); }
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
    Process {
        id: notifier
        command: ["/usr/bin/python3", root.notifierPath]
        stdinEnabled: true
        stdout: SplitParser { onRead: function(line) { root.answerNotification(line); } }
        onExited: if (root.notifying) notifierRestart.start()
    }
    onNotifyingChanged: notifier.running = notifying
    Component.onCompleted: notifier.running = notifying
    Timer { id: notifierRestart; interval: 30000; onTriggered: if (root.notifying) notifier.running = true }
    Timer {
        interval: 15000; running: root.notifying && root.loaded; repeat: true; triggeredOnStart: true
        onTriggered: root.checkNotifications(idleMonitor.isIdle)
    }
    IdleMonitor { id: idleMonitor; timeout: 120; respectInhibitors: true }
    SystemClock { id: clock; precision: SystemClock.Minutes; onDateChanged: root.refresh() }
    Timer { interval: 60000; running: root.configured; repeat: true; onTriggered: root.refresh() }
    Timer {
        interval: 1000; running: root.configured && root.nextSyncRetry > 0; repeat: true
        onTriggered: { if (Date.now() >= root.nextSyncRetry) root.refresh(); }
    }
    Timer {
        interval: 1000; running: root.requests.length > 0; repeat: true
        onTriggered: root.requests.slice().forEach(function(r) { if (Date.now() - r.started > 20000) r.timeout(); })
    }
}
