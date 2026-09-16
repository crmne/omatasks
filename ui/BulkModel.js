.import "../Model.js" as Model
.import "EditModel.js" as Edit

function visibleIds(rows) {
    return rows.filter(function(r) { return r.kind === "task"; }).map(function(r) { return String(r.task.id); })
        .filter(function(id, i, ids) { return ids.indexOf(id) === i; });
}
function toggle(ids, id) {
    id = String(id);
    return ids.indexOf(id) < 0 ? ids.concat([id]) : ids.filter(function(value) { return value !== id; });
}
function roots(selected, tasks) {
    var ids = selected.map(function(t) { return String(t.id); }), map = Model.byId(tasks);
    return selected.filter(function(task) {
        var parent = task.parent_id, seen = {};
        while (parent && !seen[parent]) {
            if (ids.indexOf(String(parent)) >= 0) return false;
            seen[parent] = true;
            parent = map[parent] && map[parent].parent_id;
        }
        return true;
    });
}
function scheduledDate(value, now) {
    var date = new Date(now);
    if (value === "tomorrow") date.setDate(date.getDate() + 1);
    else if (value === "weekend") date.setDate(date.getDate() + ((6 - date.getDay() + 7) % 7 || 7));
    else if (value === "nextweek") date.setDate(date.getDate() + ((8 - date.getDay()) % 7 || 7));
    return Model.dateKey(date);
}
function commands(tasks, ids, action, value, now) {
    var selected = tasks.filter(function(t) { return ids.indexOf(String(t.id)) >= 0; }), result = [];
    function add(type, args, temporary) {
        var command = {type: type, uuid: Model.uuid(), args: args};
        if (temporary) command.temp_id = Model.uuid();
        result.push(command);
        return command;
    }
    if (["complete", "delete", "move", "duplicate"].indexOf(action) >= 0) selected = roots(selected, tasks);
    function duplicate(task, parentId) {
        var args = {content: task.content, description: task.description || "", project_id: task.project_id, priority: task.priority || 1, labels: (task.labels || []).slice()};
        ["due", "deadline", "duration", "section_id", "responsible_uid"].forEach(function(key) { if (task[key]) args[key] = task[key]; });
        if (parentId || task.parent_id) args.parent_id = parentId || task.parent_id;
        var command = add("item_add", args, true);
        tasks.filter(function(t) { return String(t.parent_id) === String(task.id); }).forEach(function(child) { duplicate(child, command.temp_id); });
    }
    selected.forEach(function(task) {
        var args = {id: String(task.id)};
        if (action === "complete" || action === "delete") { add(action === "complete" ? "item_close" : "item_delete", args); return; }
        if (action === "duplicate") { duplicate(task, null); return; }
        if (action === "move") {
            if (!value || (!value.section_id && !value.project_id)) throw new Error("Choose a project or section.");
            add("item_move", Object.assign(args, value.section_id ? {section_id: value.section_id} : {project_id: value.project_id})); return;
        }
        if (action === "reminder") {
            if (!String(value || "").trim()) throw new Error("Enter a reminder time.");
            add("reminder_add", Edit.reminderArgs(value, task.id), true); return;
        }
        if (action === "priority") {
            if ([1, 2, 3, 4].indexOf(value) < 0) throw new Error("Choose a priority.");
            args.priority = value;
        } else if (action === "date") {
            if (!value) args.due = null;
            else {
                var due = task.due || {}, date = scheduledDate(value, now);
                args.due = {date: date + (due.date && due.date.length > 10 ? due.date.slice(10) : "")};
                if (due.timezone) args.due.timezone = due.timezone;
                if (due.is_recurring) { args.due.string = due.string; args.due.is_recurring = true; if (due.lang) args.due.lang = due.lang; }
            }
        } else if (action === "customDate") {
            if (!String(value || "").trim()) throw new Error("Enter a date.");
            args.due = {string: value.trim()};
            if ((task.due || {}).timezone) args.due.timezone = task.due.timezone;
        } else if (action === "deadline") args.deadline = value ? {date: Edit.deadlineDate(value, now)} : null;
        else throw new Error("Unknown task action.");
        add("item_update", args);
    });
    return result;
}
