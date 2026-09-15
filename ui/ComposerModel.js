// Quick Add syntax is interpreted by Todoist. Only selected properties are
// serialized here; arbitrary dates and recurring expressions stay intact.
function escapeName(name) {
    return String(name).replace(/\\/g, "\\\\").replace(/\s/g, "\\ ");
}

// Preview common date expressions without attempting to replace Todoist's
// multilingual parser. Unsupported expressions are sent to the API unchanged.
function dateToken(text) {
    var source = text.split(" // ")[0];
    var match = /(?:^|\s)((?:every (?:other )?(?:\d+ )?(?:days?|weekdays?|weeks?|months?|years?|mondays?|tuesdays?|wednesdays?|thursdays?|fridays?|saturdays?|sundays?)|today|tomorrow|tonight|(?:next |this )?(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday)|next week|in \d+ (?:days?|weeks?)|\d{4}-\d{2}-\d{2})(?: (?:at )?\d{1,2}(?::\d{2})?\s?(?:am|pm)?)?)(?=\s|$)/i.exec(source);
    if (!match) return null;
    var start = match.index + (match[0][0] === " " ? 1 : 0);
    return {value: match[1], start: start, end: start + match[1].length};
}

function quickText(draft) {
    var text = draft.text.trim(), suffix = [], description = draft.description.trim();
    // Preserve Todoist's inline description syntax if the user pasted it.
    var split = text.indexOf(" // ");
    if (split >= 0) { description = [text.slice(split + 4), description].filter(Boolean).join("\n"); text = text.slice(0, split).trim(); }
    if (draft.project) suffix.push("#" + escapeName(draft.project.name));
    if (draft.section) suffix.push("/" + escapeName(draft.section.name));
    (draft.labels || []).forEach(function(label) { suffix.push("@" + escapeName(label)); });
    if (draft.priority) suffix.push("p" + draft.priority);
    if (draft.assignee) suffix.push("+" + escapeName(draft.assignee.name || draft.assignee.full_name));
    if (draft.due && !dateToken(text)) suffix.push(draft.due);
    if (draft.deadline) suffix.push("{" + draft.deadline.replace(/[{}]/g, "") + "}");
    if (draft.reminder) suffix.push("!" + draft.reminder);
    return [text].concat(suffix).join(" ") + (description ? " // " + description : "");
}

function tokenAt(text, cursor) {
    var before = text.slice(0, cursor);
    var match = /(^|\s)([#@%\/+!{])([^\n#@%\/+!{}]*)$/.exec(before);
    if (!match) match = /(^|\s)(p)([1-4]?)$/i.exec(before);
    if (!match) return null;
    var kinds = {"#": "project", "@": "label", "%": "label", "/": "section", "+": "assignee", "!": "reminder", "{": "deadline", "p": "priority"};
    var start = match.index + match[1].length;
    var tail = /^[^\s#@%\/+!{}]*/.exec(text.slice(cursor))[0];
    return {kind: kinds[match[2].toLowerCase()], query: match[3], start: start, end: cursor + tail.length};
}

function choices(kind, query, service, project) {
    var rows = [], q = query.trim().toLowerCase();
    if (kind === "project") rows = service.projects.filter(function(p) { return !p.is_archived && !p.is_deleted; }).map(function(p) {
        var parent = service.projectMap[p.parent_id];
        return {id: p.id, label: p.name, detail: parent ? parent.name : "", value: p, icon: p.inbox_project ? "inbox" : "", prefix: p.inbox_project ? "" : "#"};
    });
    if (kind === "section") rows = service.sections.filter(function(s) { return project && s.project_id === project.id && !s.is_deleted && !s.is_archived; }).map(function(s) { return {id: s.id, label: s.name, value: s, prefix: "/"}; });
    if (kind === "label") {
        rows = service.labels.map(function(l) { return {id: l.name, label: l.name, value: l.name, icon: "label"}; });
        if (q && !rows.some(function(r) { return r.label.toLowerCase() === q; })) rows.push({id: "new", label: query.trim(), detail: "Create label", value: query.trim().replace(/\s+/g, "_"), icon: "label"});
    }
    if (kind === "priority") rows = [1, 2, 3, 4].map(function(p) { return {id: String(p), label: "Priority " + p, detail: p === 4 ? "Default" : "", value: p, icon: "flag", color: ["#ef615b", "#e49b40", "#5295e4", ""][p - 1]}; });
    if (kind === "assignee" && project && project.is_shared) rows = service.collaborators.filter(function(c) { return !c.project_id || c.project_id === project.id; }).map(function(c) { return {id: c.id, label: c.full_name || c.name || c.email, value: {id: c.id, name: c.full_name || c.name || c.email}, prefix: "+"}; });
    if (kind === "due" || kind === "deadline") {
        rows = [{id: "today", label: "Today", value: "today", icon: "today"}, {id: "tomorrow", label: "Tomorrow", value: "tomorrow", icon: "upcoming"}, {id: "next week", label: "Next week", value: "next week", icon: "upcoming"}];
        if (q && !rows.some(function(r) { return r.id === q; })) rows.unshift({id: "custom", label: query.trim(), value: query.trim(), icon: "today"});
        rows.push({id: "none", label: kind === "due" ? "No date" : "No deadline", value: "", icon: "close"});
    }
    if (kind === "reminder") {
        rows = [{id: "0mb", label: "At due time", value: "0mb", icon: "bell"}, {id: "30mb", label: "30 minutes before", value: "30mb", icon: "bell"}, {id: "1h", label: "1 hour before", value: "1h", icon: "bell"}];
        if (q) rows.unshift({id: "custom", label: query.trim(), value: query.trim(), icon: "bell"});
        rows.push({id: "none", label: "No reminder", value: "", icon: "close"});
    }
    return rows.filter(function(r) { return !q || r.id === "custom" || (r.label + " " + (r.detail || "")).toLowerCase().indexOf(q) >= 0; });
}
