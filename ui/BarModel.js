.import "../Model.js" as Model

// What the bar shows beside the Todoist icon. "task" names what to do next
// among today's timed tasks and falls back to today's count once none is
// left; "count" keeps the count and "icon" shows the icon alone.
var MODES = ["task", "count", "icon"];
var LEAD_MS = 15 * 60000;
// How long a task without a duration stays in the bar after its time.
var OPEN_MS = 30 * 60000;
var TITLE_LIMIT = 28;

// "soon" and "next" were earlier names for what "task" now does.
function mode(value) { return MODES.indexOf(value) >= 0 ? value : "task"; }
function mine(task, userId) { return Model.active(task) && Model.matches(task, Model.DEFAULT_VIEW, userId, ""); }
function span(task) {
    var due = Model.dueTime(task);
    if (!due || !isFinite(due.getTime())) return null;
    var minutes = task.duration && task.duration.unit === "minute" ? Number(task.duration.amount) || 0 : 0;
    return {start: due.getTime(), end: due.getTime() + (minutes > 0 ? minutes * 60000 : OPEN_MS), timed: minutes > 0};
}

// The timed tasks to name now: one starting within the lead first, then one
// under way, ending soonest first, then today's that are late, oldest first.
// With none of those, today's next timed task.
function selection(barMode, tasks, userId, nowMs) {
    if (barMode !== "task") return [];
    var open = [], today = Model.dateKey(new Date(nowMs)), next = null;
    tasks.forEach(function(task) {
        var s = mine(task, userId) ? span(task) : null;
        if (!s) return;
        if (nowMs >= s.start - LEAD_MS && nowMs < s.end) open.push({task: task, span: s, rank: s.start > nowMs ? 1 : 2, order: s.start > nowMs ? s.start : s.end});
        else if (nowMs >= s.end && Model.dateKey(new Date(s.start)) === today) open.push({task: task, span: s, rank: 3, order: s.start});
        else if (s.start > nowMs && Model.dateKey(new Date(s.start)) === today && (!next || s.start < next.span.start)) next = {task: task, span: s};
    });
    open.sort(function(a, b) { return a.rank - b.rank || a.order - b.order; });
    if (open.length === 0 && next) return [next];
    return open;
}

function when(entry, nowMs) {
    var s = entry.span;
    if (nowMs < s.start) {
        var minutes = Math.round((s.start - nowMs) / 60000);
        return minutes <= 0 ? "now" : minutes < 60 ? "in " + minutes + "m" : "at " + Model.clockText(new Date(s.start));
    }
    if (nowMs >= s.end) return late(nowMs - s.start);
    return s.timed ? "until " + Model.clockText(new Date(s.end)) : "now";
}
// "35m late", "2h late", "1h 30m late"
function late(ms) {
    var minutes = Math.floor(ms / 60000), hours = Math.floor(minutes / 60), rest = minutes % 60;
    return (hours ? hours + "h" + (rest ? " " + rest + "m" : "") : rest + "m") + " late";
}
// The bar shortens the title further, or drops it, when space runs out.
function title(list) {
    if (!list || list.length === 0) return "";
    var text = Model.plain(list[0].task.content);
    return text.length > TITLE_LIMIT ? text.substr(0, TITLE_LIMIT - 1).replace(/\s+$/, "") + "…" : text;
}
// "in 12m  +1"
function detail(list, nowMs) {
    if (!list || list.length === 0) return "";
    return when(list[0], nowMs) + (list.length > 1 ? "  +" + (list.length - 1) : "");
}
// "Call Ana · in 12m  +1"
function label(list, nowMs) {
    return list && list.length ? title(list) + " · " + detail(list, nowMs) : "";
}
function tooltip(list, nowMs) {
    return list.map(function(entry) { return Model.plain(entry.task.content) + " · " + when(entry, nowMs); }).join("\n");
}

// The free width between this widget's section and the next section toward
// the bar's middle, from each module list's {region, left, right}. Negative
// when they already overlap; unlimited in the centre section.
function sectionGap(region, boxes) {
    var mine = boxes.filter(function(b) { return b.region === region; });
    var others = boxes.filter(function(b) { return b.region !== region; });
    if (mine.length === 0 || others.length === 0 || (region !== "left" && region !== "right")) return Infinity;
    if (region === "right") {
        var start = Math.min.apply(null, mine.map(function(b) { return b.left; }));
        return start - Math.max.apply(null, others.map(function(b) { return b.right; }));
    }
    var end = Math.max.apply(null, mine.map(function(b) { return b.right; }));
    return Math.min.apply(null, others.map(function(b) { return b.left; })) - end;
}
