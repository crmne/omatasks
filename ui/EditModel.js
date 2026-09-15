function snapshot(task) {
    return {
        text: task.content || "", description: task.description || "",
        projectId: String(task.project_id || ""), sectionId: String(task.section_id || ""),
        labels: (task.labels || []).slice(), priority: 5 - Number(task.priority || 1),
        due: (task.due || {}).string || (task.due || {}).date || "",
        deadline: (task.deadline || {}).date || "",
        assigneeId: String(task.responsible_uid || task.assignee_id || ""),
        duration: (task.duration || {}).amount || 0, durationUnit: (task.duration || {}).unit || "minute"
    };
}
function dateKey(date) { return date.getFullYear() + "-" + String(date.getMonth() + 1).padStart(2, "0") + "-" + String(date.getDate()).padStart(2, "0"); }
function deadlineDate(value, now) {
    var input = value.trim().toLowerCase(), date = new Date(now);
    if (!input) return "";
    if (input === "today") return dateKey(date);
    if (input === "tomorrow" || input === "next week") { date.setDate(date.getDate() + (input === "tomorrow" ? 1 : 7)); return dateKey(date); }
    if (/^\d{4}-\d{2}-\d{2}$/.test(input)) {
        var parts = input.split("-").map(Number), parsed = new Date(parts[0], parts[1] - 1, parts[2]);
        if (dateKey(parsed) === input) return input;
    }
    throw new Error("Use Today, Tomorrow, Next week, or YYYY-MM-DD for the deadline.");
}
function changes(task, draft, now) {
    var original = snapshot(task), args = {}, move = null;
    if (!draft.text.trim()) throw new Error("Enter a task name.");
    if (draft.text !== original.text) args.content = draft.text.trim();
    if (draft.description !== original.description) args.description = draft.description;
    if (JSON.stringify(draft.labels.slice().sort()) !== JSON.stringify(original.labels.slice().sort())) args.labels = draft.labels;
    if (draft.priority !== original.priority) args.priority = 5 - (draft.priority || 4);
    // Send only changed fields. In particular, editing a title must not
    // reinterpret an old 'tomorrow' string or reset a recurring schedule.
    if (draft.due !== original.due) {
        args.due = draft.due.trim() ? {string: draft.due.trim()} : null;
        if (args.due && task.due && task.due.timezone) args.due.timezone = task.due.timezone;
    }
    if (draft.deadline !== original.deadline) args.deadline = draft.deadline.trim() ? {date: deadlineDate(draft.deadline, now)} : null;
    if (draft.assigneeId !== original.assigneeId) args.responsible_uid = draft.assigneeId || null;
    var amount = Number(draft.duration);
    if (!Number.isInteger(amount) || amount < 0) throw new Error("Duration must be a whole number, or 0 for none.");
    if (amount !== original.duration || draft.durationUnit !== original.durationUnit) args.duration = amount ? {amount: amount, unit: draft.durationUnit} : null;
    if (draft.projectId !== original.projectId || draft.sectionId !== original.sectionId) {
        if (!draft.projectId) throw new Error("Choose a project.");
        move = draft.sectionId ? {section_id: draft.sectionId} : {project_id: draft.projectId};
    }
    return {update: args, move: move};
}
function reminderText(reminder) {
    var text;
    if (reminder.type === "location") text = (reminder.loc_trigger === "on_leave" ? "Leaving " : "Arriving at ") + (reminder.name || "location");
    else if (reminder.minute_offset != null && Number(reminder.minute_offset) >= 0) text = Number(reminder.minute_offset) === 0 ? "At due time" : reminder.minute_offset + " minutes before";
    else text = (reminder.due || {}).string || (reminder.due || {}).date || "Reminder";
    return text + (reminder.is_urgent ? " · Urgent" : "");
}
function reminderArgs(value, taskId) {
    var match = /^(\d+)(mb|m|h)$/i.exec(value.trim());
    return match ? {item_id: taskId, type: "absolute", minute_offset: Number(match[1]) * (match[2].toLowerCase() === "h" ? 60 : 1)}
        : {item_id: taskId, type: "absolute", due: {string: value.trim()}};
}
