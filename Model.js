// Pure data transformations; also exercised by node --test.
var DEFAULT_VIEW = { grouping: "none", sorting: "smart", assignee: "mine", priority: "all", label: "all", deadline: "all" };
var API_BASE = "https://api.todoist.com/api/v1";
var TOKEN_URL = "https://app.todoist.com/app/settings/integrations/developer";

function dateKey(date) {
    return date.getFullYear() + "-" + String(date.getMonth() + 1).padStart(2, "0") + "-" + String(date.getDate()).padStart(2, "0");
}
function dateFromKey(key) {
    var p = key.split("-").map(Number);
    return new Date(p[0], p[1] - 1, p[2]);
}
function addDays(key, count) { var d = dateFromKey(key); d.setDate(d.getDate() + count); return dateKey(d); }
function dueTime(task) {
    var due = task.due || {};
    var value = due.datetime || due.date || "";
    return value.indexOf("T") >= 0 ? new Date(value) : null;
}
function dueDay(task) {
    var timed = dueTime(task);
    return timed && isFinite(timed.getTime()) ? dateKey(timed) : String((task.due || {}).date || "").slice(0, 10);
}
function scheduledDay(task) { return dueDay(task) || String((task.deadline || {}).date || ""); }
function overdue(task, now) {
    var time = dueTime(task);
    return time ? time.getTime() < now.getTime() : !!scheduledDay(task) && scheduledDay(task) < dateKey(now);
}
function clockText(date) { return String(date.getHours()).padStart(2, "0") + ":" + String(date.getMinutes()).padStart(2, "0"); }
function dayLabel(key, today) {
    if (!key) return "No date";
    if (key === today) return "Today";
    if (key === addDays(today, 1)) return "Tomorrow";
    return typeof Qt !== "undefined" ? Qt.formatDate(dateFromKey(key), "d MMM") : dateFromKey(key).toLocaleDateString(undefined, { month: "short", day: "numeric" });
}
function dueLabel(task, now, view, grouping) {
    var day = dueDay(task), time = dueTime(task), text = "";
    if (day && (day !== dateKey(now) || view !== "today" || grouping !== "none")) text = dayLabel(day, dateKey(now));
    if (time) {
        text += (text ? " " : "") + clockText(time);
        if (task.duration && task.duration.unit === "minute") text += "–" + clockText(new Date(time.getTime() + task.duration.amount * 60000));
    }
    return text;
}
function plain(text) {
    return String(text || "").replace(/\[([^\]]+)\]\([^)]+\)/g, "$1").replace(/\*\*([^*]+)\*\*/g, "$1").replace(/`([^`]+)`/g, "$1").replace(/\s+/g, " ").trim();
}
function asArray(items) { return Array.isArray(items) ? items : items && typeof items === "object" ? Object.keys(items).map(function(k) { return items[k]; }).filter(function(x) { return x && typeof x === "object"; }) : []; }
function byId(items) { var out = {}; asArray(items).forEach(function(x) { out[String(x.id)] = x; }); return out; }
function merge(previous, updates, full) {
    var map = full ? {} : byId(previous);
    asArray(updates).forEach(function(x) { if (x.is_deleted) delete map[String(x.id)]; else map[String(x.id)] = x; });
    return Object.keys(map).map(function(k) { return map[k]; });
}
function projectPath(id, projects, sectionId, sections) {
    var project = projects[String(id)], section = sections ? sections[String(sectionId)] : null;
    return (project ? project.name : "Inbox") + (section ? " / " + section.name : "");
}
function mergeCompleted(previous, updates, full) {
    var map = {};
    (full ? [] : asArray(previous)).concat(asArray(updates)).forEach(function(x) {
        var key = x.item_id ? "task:" + x.item_id : x.section_id ? "section:" + x.section_id : "project:" + x.project_id;
        map[key] = x;
    });
    return Object.keys(map).map(function(key) { return map[key]; });
}
function assigned(task) { return String(task.responsible_uid || task.assignee_id || ""); }
function active(task) { return !task.checked && !task.is_completed && !task.is_deleted; }
function inView(task, view, today, projects) {
    if (!active(task)) return false;
    var day = scheduledDay(task), project = projects[String(task.project_id)] || {};
    if (view === "inbox") return !!(project.inbox_project || project.is_inbox_project);
    if (view === "today") return !!day && day <= today;
    return !!day; // Upcoming includes every scheduled task, with overdue first.
}
function matches(task, options, userId, today) {
    var who = assigned(task);
    if (options.assignee === "mine" && who && who !== String(userId)) return false;
    if (options.assignee === "me" && who !== String(userId)) return false;
    if (options.assignee === "unassigned" && who) return false;
    if (options.priority !== "all" && Number(task.priority) !== Number(options.priority)) return false;
    if (options.label !== "all" && (task.labels || []).indexOf(options.label) < 0) return false;
    var deadline = (task.deadline || {}).date;
    if (options.deadline === "has" && !deadline) return false;
    if (options.deadline === "none" && deadline) return false;
    if (options.deadline === "overdue" && (!deadline || deadline >= today)) return false;
    return true;
}
function compareText(a, b) { return String(a || "").localeCompare(String(b || "")); }
function manualCompare(a, b, view) {
    if (view !== "inbox") {
        var ao = a.day_order >= 0 ? a.day_order : 1e12, bo = b.day_order >= 0 ? b.day_order : 1e12;
        if (ao !== bo) return ao - bo;
    }
    if (a.order_key && b.order_key) return a.order_key < b.order_key ? -1 : a.order_key > b.order_key ? 1 : 0;
    return Number(a.child_order || a.order || 0) - Number(b.child_order || b.order || 0);
}
function sortTasks(tasks, mode, view, projects, people) {
    function dateSort(t) { var time = dueTime(t); return time ? time.getTime() : scheduledDay(t) ? dateFromKey(scheduledDay(t)).getTime() + 86399999 : Infinity; }
    return tasks.slice().sort(function(a, b) {
        var result = 0;
        if (mode === "name") result = compareText(plain(a.content), plain(b.content));
        else if (mode === "priority") result = b.priority - a.priority;
        else if (mode === "date") result = dateSort(a) - dateSort(b);
        else if (mode === "added") result = compareText(a.added_at || a.created_at, b.added_at || b.created_at);
        else if (mode === "deadline") result = compareText((a.deadline || {}).date || "9999", (b.deadline || {}).date || "9999");
        else if (mode === "project") result = compareText(projectPath(a.project_id, projects), projectPath(b.project_id, projects));
        else if (mode === "assignee") result = compareText((people[assigned(a)] || {}).full_name, (people[assigned(b)] || {}).full_name);
        else if (mode === "smart") result = dateSort(a) - dateSort(b) || b.priority - a.priority || compareText((a.deadline || {}).date || "9999", (b.deadline || {}).date || "9999");
        return result || manualCompare(a, b, view) || compareText(a.added_at, b.added_at) || compareText(a.id, b.id);
    });
}
function viewRows(tasks, projectList, collaborators, options, view, userId, now) {
    var projects = byId(projectList), people = byId(collaborators), today = dateKey(now);
    var selected = tasks.filter(function(t) { return inView(t, view, today, projects) && matches(t, options, userId, today); });
    selected = sortTasks(selected, options.sorting, view, projects, people);
    var groups = {}, keys = [];
    var hasOverdue = view === "today" && selected.some(function(t) { return scheduledDay(t) < today; });
    selected.forEach(function(t) {
        if (options.grouping === "label") {
            ((t.labels || []).length ? t.labels : ["No label"]).forEach(function(label) {
                if (!groups[label]) { groups[label] = {label: label, rank: label, tasks: [], projectId: ""}; keys.push(label); }
                groups[label].tasks.push(t);
            });
            return;
        }
        var key = "", label = "", rank = "", projectId = "";
        if (options.grouping === "project") { var p = projects[String(t.project_id)] || {id: t.project_id, name: "Inbox"}; key = String(p.id); label = p.name; rank = p.order_key || String(p.child_order || 0).padStart(8, "0"); projectId = String(p.id); }
        else if (options.grouping === "priority") { key = String(5 - t.priority); label = t.priority > 1 ? "Priority " + key : "No priority"; rank = key; }
        else if (options.grouping === "date" || view === "upcoming") { key = scheduledDay(t) || "9999"; if (key < today) key = "0000"; label = key === "0000" ? "Overdue" : key === "9999" ? "No date" : dayLabel(key, today); rank = key; }
        else if (view === "today" && scheduledDay(t) < today) { key = "overdue"; label = "Overdue"; rank = "0"; }
        else if (hasOverdue) { key = "today"; label = "Today"; rank = "1"; }
        if (!groups[key]) { groups[key] = {label: label, rank: rank, tasks: [], projectId: projectId}; keys.push(key); }
        groups[key].tasks.push(t);
    });
    keys.sort(function(a, b) { return compareText(groups[a].rank, groups[b].rank); });
    var rows = [];
    keys.forEach(function(k) {
        var g = groups[k];
        if (g.label) rows.push({kind: "group", key: k, title: g.label});
        g.tasks.forEach(function(t) { rows.push({kind: "task", key: String(t.id), groupKey: k, task: t}); });
        if (options.grouping === "project") rows.push({kind: "add", key: "add:" + k, projectId: g.projectId});
    });
    if (options.grouping !== "project" || !keys.length) rows.push({kind: "add", key: "add", projectId: ""});
    return rows;
}
function uuid() { return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, function(c) { var r = Math.random() * 16 | 0; return (c === "x" ? r : (r & 3 | 8)).toString(16); }); }
function errorMessage(status) {
    if (status === 401 || status === 403) return "Todoist could not authorize this request. Check your API token in Settings.";
    if (status === 429) return "Todoist is receiving too many requests. Please wait a moment.";
    if (status === 0) return "Could not reach Todoist. Check your connection and try again.";
    if (status === 400) return "Todoist could not save that task. Check the text and try again.";
    return "Todoist could not finish the request (" + status + "). Try again.";
}
