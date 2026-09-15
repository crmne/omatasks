.import "../Model.js" as Model
.import "Fractional.js" as Fractional

function siblings(a, b) {
    return String(a.project_id) === String(b.project_id) &&
        String(a.section_id || "") === String(b.section_id || "") &&
        String(a.parent_id || "") === String(b.parent_id || "");
}
function canDrop(source, target, view) {
    return source && target && source.kind === "task" && target.kind === "task" &&
        source.groupKey === target.groupKey && (view !== "inbox" || siblings(source.task, target.task));
}
function changedOrder(rows, sourceIndex, targetIndex, after, view) {
    var source = rows[sourceIndex], target = rows[targetIndex];
    if (!canDrop(source, target, view) || source.task.id === target.task.id) return null;
    var ids = rows.filter(function(row) { return canDrop(source, row, view); }).map(function(row) { return String(row.task.id); });
    var original = ids.join("\n"), from = ids.indexOf(String(source.task.id));
    ids.splice(from, 1);
    ids.splice(ids.indexOf(String(target.task.id)) + (after ? 1 : 0), 0, String(source.task.id));
    return ids.join("\n") === original ? null : ids;
}
// Replace visible slots, keeping filtered-out tasks in place and preserving their
// relative order. Day ordering is independent of project/sibling ordering.
function plan(tasks, rows, view, sourceId, targetId, after, groupKey) {
    var sourceIndex = rows.findIndex(function(r) { return r.task && String(r.task.id) === sourceId && r.groupKey === groupKey; });
    var targetIndex = rows.findIndex(function(r) { return r.task && String(r.task.id) === targetId && r.groupKey === groupKey; });
    var ids = changedOrder(rows, sourceIndex, targetIndex, after, view);
    if (!ids) return null;
    var source = rows[sourceIndex].task, byId = Model.byId(tasks), included = {};
    ids.forEach(function(id) { included[id] = true; });
    var scope = tasks.filter(function(t) { return Model.active(t) && (view === "inbox" ? siblings(source, t) : !!Model.scheduledDay(t)); });
    scope = Model.sortTasks(scope, "manual", view, {}, {});
    var cursor = 0;
    var desired = scope.map(function(t) { return included[String(t.id)] ? byId[ids[cursor++]] : t; });
    var patches = {}, commands = [];
    if (view !== "inbox") {
        var orders = {};
        desired.forEach(function(t, index) {
            if (t.day_order !== index) { orders[t.id] = index; patches[t.id] = {day_order: index}; }
        });
        if (Object.keys(orders).length) commands.push({type: "item_update_day_orders", args: {ids_to_orders: orders}});
    } else {
        function keyAt(index) { return desired[index] ? desired[index].order_key : null; }
        function assign(task, key) {
            patches[task.id] = {order_key: key};
            commands.push({type: "item_update", args: {id: String(task.id), order_key: key}});
        }
        var restBefore = scope.filter(function(t) { return String(t.id) !== sourceId; }).map(function(t) { return String(t.id); });
        var restAfter = desired.filter(function(t) { return String(t.id) !== sourceId; }).map(function(t) { return String(t.id); });
        var keyed = scope.every(function(t, i) { return t.order_key && (!i || scope[i - 1].order_key < t.order_key); });
        if (keyed && restBefore.join("\n") === restAfter.join("\n")) {
            // A normal manual drag updates just the moved task, including when
            // there are hidden siblings between two visible tasks.
            var position = desired.findIndex(function(t) { return String(t.id) === sourceId; });
            assign(source, Fractional.generateKeyBetween(keyAt(position - 1), keyAt(position + 1)));
        } else if (keyed) {
            // Switching from an automatic sort can change several visible tasks.
            // Generate keys above the old keys in each visible run, below the next
            // hidden sibling. This avoids collisions with keys still on the server.
            for (var i = 0; i < desired.length;) {
                if (!included[String(desired[i].id)]) { i++; continue; }
                var start = i;
                while (i < desired.length && included[String(desired[i].id)]) i++;
                if (desired.slice(start, i).every(function(t, n) { return t.id === scope[start + n].id; })) continue;
                var keys = Fractional.generateNKeysBetween(scope[i - 1].order_key, keyAt(i), i - start);
                for (var j = start; j < i; j++) assign(desired[j], keys[j - start]);
            }
        } else {
            // Initialize older lists (or normalize colliding keys) above all
            // existing keys, preserving hidden siblings and avoiding collisions.
            var existing = scope.map(function(t) { return t.order_key; }).filter(Boolean).sort();
            var initial = Fractional.generateNKeysBetween(existing.length ? existing[existing.length - 1] : null, null, desired.length);
            desired.forEach(function(t, index) { assign(t, initial[index]); });
        }
    }
    return {commands: commands, patches: patches};
}

function apply(tasks, patches) {
    return tasks.map(function(t) { return patches[t.id] ? Object.assign({}, t, patches[t.id]) : t; });
}
function before(tasks, patches) {
    var result = {};
    tasks.forEach(function(t) {
        if (!patches[t.id]) return;
        result[t.id] = {};
        Object.keys(patches[t.id]).forEach(function(key) { result[t.id][key] = t[key]; });
    });
    return result;
}
function rollback(tasks, patches, previous) {
    return tasks.map(function(t) {
        if (!patches[t.id]) return t;
        var copy = Object.assign({}, t);
        Object.keys(patches[t.id]).forEach(function(key) {
            // Never overwrite unrelated changes received from Todoist.
            if (copy[key] !== patches[t.id][key]) return;
            if (previous[t.id][key] === undefined) delete copy[key];
            else copy[key] = previous[t.id][key];
        });
        return copy;
    });
}
