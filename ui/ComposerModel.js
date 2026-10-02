// Quick Add syntax is interpreted by Todoist. Only selected properties are
// serialized here; arbitrary dates and recurring expressions stay intact.
function escapeName(name) {
    return String(name).replace(/\\/g, "\\\\").replace(/\s/g, "\\ ");
}

// Recognition is a local English preview. The original expression is always
// sent to Todoist's Quick Add endpoint, which uses the official clients' parser.
// Mask metadata first: @today, #Tomorrow, {Friday} and !14:00 are not due dates.
function dateTokens(text, excluded) {
    var source = text.split(" // ")[0];
    (excluded || []).forEach(function(token) {
        source = source.slice(0, token.start) + " ".repeat(token.end - token.start) + source.slice(token.end);
    });
    source = source.replace(/(^|\s)(?:\{[^}]*\}|!![1-4]|[#@%/](?:\\.|[^\s])+|\+(?!\d)(?:\\.|[^\s])+|!(?:\d+\s+(?:min(?:ute)?s?|hours?)\s+before|[^\s]+))/g, function(match) { return " ".repeat(match.length); });
    var day = "(?:mon(?:day)?|tue(?:s(?:day)?)?|wed(?:nesday)?|thu(?:rs(?:day)?)?|fri(?:day)?|sat(?:urday)?|sun(?:day)?)";
    var month = "(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)";
    var number = "(?:[1-9]|[12]\\d|3[01])(?:st|nd|rd|th)?";
    var ordinal = "(?:[1-9]|[12]\\d|3[01])(?:st|nd|rd|th)";
    var calendar = "(?:\\d{4}[/.-]\\d{2}[/.-]\\d{2}|" + month + " " + number + "(?:,? \\d{4})?|" + number + " " + month + "(?: \\d{4})?|(?:0?[1-9]|[12]\\d|3[01])[/.-](?:0?[1-9]|[12]\\d|3[01])(?:[/.-]\\d{2,4})?|mid " + month + "|" + ordinal + "(?: " + day + "(?: " + month + ")?)?|end of (?:the )?(?:month|year)|new year'?s eve)";
    var time = "(?:(?:[01]?\\d|2[0-3]):[0-5]\\d(?:\\s?[ap]m)?|(?:0?[1-9]|1[0-2])(?:\\s?[ap]m)|noon|midnight)";
    var relative = "(?:no (?:due )?date|later this week|in the (?:morning|afternoon|evening)|someday|(?:in|after|\\+) ?\\d+ (?:minutes?|mins?|hours?|hrs?|days?|weeks?|months?|years?)|(?:tomorrow|tom|tmr)(?: ?(?:morning|afternoon|evening|night))?|(?:today|tod|tonight|yesterday)|(?:next|this) (?:week|month|year|weekend)|(?:next |this )?" + day + "|\\d+ (?:days?|weeks?|months?|years?)(?: (?:before|after) " + calendar + ")?|" + calendar + ")";
    var recurringDay = "(?:(?:(?:first|last|" + ordinal + ") )?(?:workday|weekday|" + day + ")|" + calendar + "|" + number + ")";
    var recurrence = "(?:(?:every!?|ev!?) (?:(?:other|\\d+) )?(?:day|weekday|workday|week|month|year|hour|minute|" + recurringDay + ")s?(?:, ?" + recurringDay + "s?)*|daily|weekly|monthly|yearly|annually|everyday)";
    var rule = recurrence + "(?: (?:(?:starting|from|until|ending) " + relative + "|for \\d+ (?:days?|weeks?|months?)|on (?:the )?" + number + "))*";
    var scheduled = "(?:" + rule + "|" + relative + ")(?: (?:at )?(?:" + time + "|(?:[01]?\\d|2[0-3])(?=\\s|$)|(?:[01]\\d|2[0-3])[0-5]\\d))?";
    var pattern = new RegExp("(?:^|\\s)(" + scheduled + "|(?:at )?" + time + ")(?![\\w/-])", "ig"), match, result = [];
    while ((match = pattern.exec(source))) {
        var start = match.index + (/^\s/.test(match[0]) ? 1 : 0);
        result.push({kind: "due", value: match[1], start: start, end: start + match[1].length});
    }
    return result;
}

function dateToken(text, excluded) {
    var tokens = dateTokens(text, excluded);
    return tokens.length ? tokens[tokens.length - 1] : null;
}

function nameToken(source, start, rows, nameOf) {
    var best = null, tail = source.slice(start + 1);
    rows.forEach(function(row) {
        var name = nameOf(row);
        [name, escapeName(name)].forEach(function(spelling) {
            if (tail.slice(0, spelling.length).toLowerCase() === spelling.toLowerCase() && /^(?:\s|$|[,;])/.test(tail.slice(spelling.length))) {
                if (!best || spelling.length > best.end - start - 1) best = {start: start, end: start + spelling.length + 1, value: row};
            }
        });
    });
    return best;
}

function parse(text, service, defaultProject) {
    var source = text.split(" // ")[0], tokens = [], project = defaultProject || null;
    var pattern = /(^|\s)(#[^\n]*|!![1-4](?=\s|$)|p[1-4](?=\s|$)|\{[^{}]+\}|!(?:\d+\s+(?:min(?:ute)?s?|hours?)\s+before|\d+(?:mb|m|h|d)\b|(?:(?:today|tomorrow) (?:at )?)?(?:(?:[01]?\d|2[0-3]):[0-5]\d(?:\s?[ap]m)?|(?:0?[1-9]|1[0-2])\s?[ap]m)|(?:today|tomorrow)|in \d+ (?:minutes?|hours?))|[@%/+](?:\\.|[^\s])+)/ig, match;
    // Resolve projects before sections and collaborators, including pasted text.
    var projects = service.projects.filter(function(p) { return !p.is_deleted && !p.is_archived; });
    var projectsPattern = /(^|\s)#/g;
    while ((match = projectsPattern.exec(source))) {
        var found = nameToken(source, match.index + match[1].length, projects, function(p) { return p.name; });
        if (found) { found.kind = "project"; tokens.push(found); project = found.value; projectsPattern.lastIndex = found.end; }
    }
    while ((match = pattern.exec(source))) {
        var start = match.index + match[1].length, raw = match[2], token = null;
        if (tokens.some(function(t) { return start >= t.start && start < t.end; })) { pattern.lastIndex = tokens.filter(function(t) { return start >= t.start && start < t.end; })[0].end; continue; }
        if (raw[0] === "#") { pattern.lastIndex = start + 1; continue; }
        if (/^(?:p|!!)[1-4]$/i.test(raw)) token = {kind: "priority", value: Number(raw.slice(-1))};
        else if (raw[0] === "{") token = {kind: "deadline", value: raw.slice(1, -1).trim()};
        else if (raw[0] === "!") token = {kind: "reminder", value: raw.slice(1)};
        else if (raw[0] === "@" || raw[0] === "%") {
            var label = nameToken(source, start, service.labels, function(l) { return l.name; });
            token = label || {value: raw.slice(1).replace(/\\(.)/g, "$1")}; token.kind = "label";
            if (label) token.value = label.value.name;
        } else if (raw[0] === "/" && project) {
            token = nameToken(source, start, service.sections.filter(function(s) { return String(s.project_id) === String(project.id) && !s.is_deleted && !s.is_archived; }), function(s) { return s.name; });
            if (token) token.kind = "section";
        } else if (raw[0] === "+" && project && project.is_shared) {
            token = nameToken(source, start, service.collaborators.filter(function(c) { return !c.project_id || String(c.project_id) === String(project.id); }), function(c) { return c.full_name || c.name || c.email; });
            if (token) { token.kind = "assignee"; token.value = {id: token.value.id, name: token.value.full_name || token.value.name || token.value.email}; }
        }
        if (token) { token.start = start; token.end = token.end || start + raw.length; tokens.push(token); pattern.lastIndex = token.end; }
    }
    var dates = dateTokens(text, tokens), due = dates.length ? dates[dates.length - 1] : null;
    tokens = tokens.concat(dates);
    if (due && /\d(?::\d|\s?[ap]m)|\b(?:noon|midnight)\b/i.test(due.value)) {
        var length = /(?:^|\s)(for (\d+(?:\.\d+)?) (minutes?|mins?|hours?|hrs?))(?=\s|$)/i.exec(source.slice(due.end));
        if (length) {
            var durationStart = due.end + length.index + length[0].length - length[1].length;
            tokens.push({kind: "duration", value: length[1], start: durationStart, end: durationStart + length[1].length});
        }
    }
    tokens.sort(function(a, b) { return a.start - b.start; });
    var result = {tokens: tokens, labels: []};
    tokens.forEach(function(token) {
        if (token.kind === "label") { if (result.labels.indexOf(token.value) < 0) result.labels.push(token.value); }
        else result[token.kind] = token.value;
    });
    return result;
}

function withoutTokens(text, tokens) {
    tokens.slice().sort(function(a, b) { return b.start - a.start; }).forEach(function(t) { text = text.slice(0, t.start) + text.slice(t.end); });
    return text;
}

function spelling(kind, value) {
    if (kind === "project") return "#" + escapeName(value.name);
    if (kind === "section") return "/" + escapeName(value.name);
    if (kind === "label") return "@" + escapeName(value);
    if (kind === "assignee") return "+" + escapeName(value.name || value.full_name);
    if (kind === "priority") return "p" + value;
    if (kind === "deadline") return "{" + value + "}";
    if (kind === "reminder") return "!" + value;
    return value;
}

// Only resolve unambiguous calendar days for the preview's date-chip colors.
// Scheduling still belongs to Todoist, including account-specific grammar.
function dateOffset(value, now, user) {
    var text = value.toLowerCase(), day = null, date = new Date(now.getFullYear(), now.getMonth(), now.getDate()), match;
    if (/^(today|tod|tonight)\b/.test(text)) return 0;
    if (/^(tomorrow|tom|tmr)\b/.test(text)) return 1;
    if (/^yesterday\b/.test(text)) return -1;
    match = /^(?:in |after |\+)?(\d+) (days?|weeks?)\b/.exec(text);
    if (match) return Number(match[1]) * (match[2].indexOf("week") === 0 ? 7 : 1);
    if (/^next week\b/.test(text)) return ((Number((user || {}).next_week) || 1) - date.getDay() + 7) % 7 || 7;
    match = /^(?:(next|this) )?(sun|mon|tue|wed|thu|fri|sat)(?:day|sday|nesday|rsday|urday)?\b/.exec(text);
    if (match) {
        var target = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"].indexOf(match[2]);
        var offset = (target - date.getDay() + 7) % 7;
        return offset + (match[1] === "next" && target >= date.getDay() ? 7 : 0);
    }
    match = /^(\d{4})-(\d{2})-(\d{2})\b/.exec(text);
    if (match) day = Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3]));
    return day === null ? null : Math.round((day - Date.UTC(date.getFullYear(), date.getMonth(), date.getDate())) / 86400000);
}

function quickText(draft) {
    var text = draft.text.trim(), suffix = [], description = draft.description.trim();
    // Preserve Todoist's inline description syntax if the user pasted it.
    var split = text.indexOf(" // ");
    if (split >= 0) { description = [text.slice(split + 4), description].filter(Boolean).join("\n"); text = text.slice(0, split).trim(); }
    var typed = draft.parsed || {};
    if (draft.project && !typed.project) suffix.push("#" + escapeName(draft.project.name));
    if (draft.section && !typed.section) suffix.push("/" + escapeName(draft.section.name));
    (draft.labels || []).forEach(function(label) { if ((typed.labels || []).indexOf(label) < 0) suffix.push("@" + escapeName(label)); });
    if (draft.priority && !typed.priority) suffix.push("p" + draft.priority);
    if (draft.assignee && !typed.assignee) suffix.push("+" + escapeName(draft.assignee.name || draft.assignee.full_name));
    // Put the contextual/manual default first so Todoist can override it with
    // dates our preview doesn't recognize (including other account languages).
    if (draft.due && !typed.due && (draft.parsed || !dateToken(text))) text = draft.due + " " + text;
    if (draft.deadline && !typed.deadline) suffix.push("{" + draft.deadline.replace(/[{}]/g, "") + "}");
    if (draft.reminder && !typed.reminder) suffix.push("!" + draft.reminder);
    return [text].concat(suffix).join(" ") + (description ? " // " + description : "");
}

function tokenAt(text, cursor) {
    if (text.indexOf(" // ") >= 0 && cursor > text.indexOf(" // ")) return null;
    var before = text.slice(0, cursor);
    var match = /(^|\s)(!!)([1-4]?)$/.exec(before);
    if (!match) match = /(^|\s)([#@%\/+!{])([^\n#@%\/+!{}]*)$/.exec(before);
    if (!match) match = /(^|\s)(p)([1-4]?)$/i.exec(before);
    if (!match) return null;
    var kinds = {"#": "project", "@": "label", "%": "label", "/": "section", "+": "assignee", "!": "reminder", "!!": "priority", "{": "deadline", "p": "priority"};
    var start = match.index + match[1].length;
    var tail = /^[^\s#@%\/+!{}]*/.exec(text.slice(cursor))[0];
    if (match[2] === "{" && text[cursor + tail.length] === "}") tail += "}";
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
