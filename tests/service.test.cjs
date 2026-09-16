// Run the service's JavaScript methods with controlled XMLHttpRequest responses.
// Rendering and FileView/Process behavior are checked separately in Quickshell.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

function service() {
    const wires = [];
    class XHR {
        static DONE = 4;
        constructor() { this.headers = {}; wires.push(this); }
        open(method, url) { this.method = method; this.url = url; }
        setRequestHeader(key, value) { this.headers[key] = value; }
        getResponseHeader(key) { return this.responseHeaders?.[key] || ''; }
        send(body) { this.body = body; }
        abort() { this.aborted = true; this.respond(0, ''); }
        respond(status, body, headers = {}) { this.status = status; this.responseText = typeof body === 'string' ? body : JSON.stringify(body); this.responseHeaders = headers; this.readyState = 4; this.onreadystatechange(); }
    }
    const Model = vm.createContext({ Date });
    vm.runInContext(fs.readFileSync('Model.js', 'utf8'), Model);
    const Fractional = vm.createContext({});
    vm.runInContext(fs.readFileSync('ui/Fractional.js', 'utf8'), Fractional);
    const Order = vm.createContext({ Model, Fractional });
    vm.runInContext(fs.readFileSync('ui/OrderModel.js', 'utf8').replace(/^\.import.*$/gm, ''), Order);
    const Edit = vm.createContext({ Date });
    vm.runInContext(fs.readFileSync('ui/EditModel.js', 'utf8'), Edit);
    const Bulk = vm.createContext({ Model, Edit, Date });
    vm.runInContext(fs.readFileSync('ui/BulkModel.js', 'utf8').replace(/^\.import.*$/gm, ''), Bulk);
    const ctx = vm.createContext({ Order, preferences: {}, now: new Date(2026, 8, 15, 12), pendingReorder: null, reorderCache: {}, settingsFile: { setText() {} }, Model, XMLHttpRequest: XHR, Date, requests: [], completionIds: {}, generation: 0, token: 'test-token', configured: true, loading: false, saving: false, connecting: false, storageReady: true, error: '', retryAfter: 0, syncToken: '*', tasks: [], projects: [], sections: [], labels: [], collaborators: [], reminders: [], completedInfo: [], user: {}, lastSync: 0, taskAdded() { ctx.added = true; }, taskUpdated(id) { ctx.updated = id; }, taskCompleted(id) { ctx.completed = id; }, operationFailed(message) { ctx.failed = message; } });
    ctx.root = ctx;
    ctx.Bulk = Bulk; ctx.bulkRetry = null; ctx.taskActionFinished = () => { ctx.bulkFinished = true; };
    const source = fs.readFileSync('Service.qml', 'utf8');
    const functions = [...source.matchAll(/^    function .+?\{[\s\S]*?^    \}/gm)].map(m => m[0]).join('\n');
    vm.runInContext(functions, ctx);
    return { s: ctx, wires };
}
function reorderFixture() {
    const fixture = service(), s = fixture.s;
    s.projects = [{id: 'inbox', name: 'Inbox', inbox_project: true}];
    s.user = {id: 'me'};
    s.tasks = ['a', 'b', 'c'].map((id, i) => ({id, content: id, project_id: 'inbox', priority: 1, day_order: i, order_key: 'a' + i, due: {date: '2026-09-15'}}));
    return fixture;
}
const commandsOf = request => JSON.parse(new URLSearchParams(request.body).get('commands'));
test('Reordering is optimistic, cancels stale sync, persists day order and switches to Manual', () => {
    const {s, wires} = reorderFixture();
    s.refresh();
    assert.equal(s.reorderTasks('today', 'c', 'a', false, ''), true);
    assert.equal(wires[0].aborted, true);
    assert.equal(s.saving, true);
    assert.equal(s.preferences.today.sorting, 'manual');
    assert.equal(s.tasks[2].day_order, 0);
    const commands = commandsOf(wires[1]);
    assert.equal(commands[0].type, 'item_update_day_orders');
    assert.deepEqual(commands[0].args.ids_to_orders, {c: 0, a: 1, b: 2});
    wires[0].respond(200, {sync_token: 'stale', day_orders: {c: 99}});
    assert.equal(s.tasks[2].day_order, 0);
    wires[1].respond(200, {sync_token: 'new', sync_status: {[commands[0].uuid]: 'ok'}, day_orders: {a: 1, b: 2, c: 0}});
    assert.equal(s.saving, false); assert.equal(s.pendingReorder, null);
    assert.equal(s.error, ''); assert.equal(s.syncToken, 'new');
});
test('Failed reorder rolls back order and sorting, and an uncertain retry reuses its command UUID', () => {
    const {s, wires} = reorderFixture();
    s.reorderTasks('today', 'c', 'a', false, '');
    const first = commandsOf(wires[0])[0];
    s.tasks[0].content = 'Concurrent title edit';
    wires[0].respond(503, {});
    assert.equal(s.preferences.today.sorting, 'smart');
    assert.equal(s.tasks[2].day_order, 2);
    assert.equal(s.tasks[0].content, 'Concurrent title edit');
    assert.equal(s.saving, false);
    assert.match(s.error, /Could not save task order/);
    s.reorderTasks('today', 'c', 'a', false, '');
    assert.equal(commandsOf(wires[1])[0].uuid, first.uuid);
    wires[1].respond(200, {sync_token: 'retry', sync_status: {[first.uuid]: 'ok'}});
    assert.equal(s.preferences.today.sorting, 'manual');
    assert.equal(s.tasks[2].day_order, 0);
});
test('HTTP 200 with a rejected reorder command rolls back and reports the API error', () => {
    const {s, wires} = reorderFixture();
    s.reorderTasks('inbox', 'c', 'a', false, '');
    const command = commandsOf(wires[0])[0];
    assert.deepEqual(Object.keys(command.args).sort(), ['id', 'order_key']);
    wires[0].respond(200, {sync_token: 'new', sync_status: {[command.uuid]: {error: 'Read-only project'}}});
    assert.equal(s.tasks[2].order_key, 'a2');
    assert.equal(s.preferences.inbox.sorting, 'smart');
    assert.match(s.error, /Read-only project/);
});
test('Account changes cancel pending reorders without restoring old account tasks', () => {
    const {s, wires} = reorderFixture();
    s.reorderTasks('today', 'c', 'a', false, '');
    const command = commandsOf(wires[0])[0];
    s.applyToken('another-token');
    assert.equal(s.pendingReorder, null);
    wires[0].respond(200, {sync_token: 'old', items: [{id: 'old-task'}], sync_status: {[command.uuid]: 'ok'}});
    assert.equal(s.tasks.length, 0);
    assert.equal(s.preferences.today.sorting, 'smart');
});
test('Large Inbox reorders batch commands and roll back only unconfirmed changes', () => {
    const {s, wires} = reorderFixture();
    s.tasks = Array.from({length: 120}, (_, i) => ({id: String(i), content: String(i), project_id: 'inbox', child_order: i, priority: 1}));
    assert.equal(s.reorderTasks('inbox', '119', '0', false, ''), true);
    const first = commandsOf(wires[0]);
    assert.equal(first.length, 100);
    wires[0].respond(200, {sync_token: 'batch-one', sync_status: Object.fromEntries(first.map(c => [c.uuid, 'ok']))});
    const second = commandsOf(wires[1]);
    assert.equal(second.length, 20);
    assert.equal(new URLSearchParams(wires[1].body).get('sync_token'), 'batch-one');
    wires[1].respond(500, {});
    assert.equal(s.saving, false);
    assert.equal(s.preferences.inbox.sorting, 'manual');
    assert.match(s.error, /Some tasks were reordered/);
    assert.equal(s.tasks.filter(t => t.order_key).length, 100);
});
test('Sync uses form encoding, Bearer auth and the incremental token', () => {
    const { s, wires } = service();
    s.refresh();
    const req = wires[0];
    assert.equal(req.headers['Content-Type'], 'application/x-www-form-urlencoded');
    assert.equal(req.headers.Authorization, 'Bearer test-token');
    assert.ok(new URLSearchParams(req.body).get('resource_types').includes('items'));
    req.respond(200, { sync_token: 'next', full_sync: true, items: [{ id: 'a' }] });
    assert.equal(s.loaded, true);
    s.refresh();
    assert.equal(new URLSearchParams(wires[1].body).get('sync_token'), 'next');
});
test('Completing a recurring task uses close and syncs its next occurrence', () => {
    const { s, wires } = service();
    const task = { id: 'recurring', due: { date: '2026-09-15', is_recurring: true } };
    s.tasks = [task];
    s.completeTask(task);
    assert.match(wires[0].url, /\/tasks\/recurring\/close$/);
    wires[0].respond(200, null);
    wires[1].respond(200, { sync_token: 'next', items: [{ ...task, due: { date: '2026-09-16', is_recurring: true } }] });
    assert.equal(s.tasks[0].due.date, '2026-09-16');
});
test('A write cancels an older sync so stale responses cannot restore completed tasks', () => {
    const { s, wires } = service();
    s.refresh();
    s.addTask('Buy milk tomorrow p2', 'stable-request-id');
    assert.equal(wires[0].aborted, true);
    wires[0].respond(200, { sync_token: 'stale', items: [{ id: 'stale' }] });
    assert.equal(s.tasks.length, 0);
    assert.equal(wires[1].headers['X-Request-Id'], 'stable-request-id');
    assert.equal(JSON.parse(wires[1].body).text, 'Buy milk tomorrow p2');
});
test('Failed additions keep a recoverable error and never emit success', () => {
    const { s, wires } = service();
    s.addTask('Draft', 'same-id');
    wires[0].respond(500, {});
    assert.equal(s.saving, false);
    assert.equal(s.added, undefined);
    assert.ok(s.failed.includes('500'));
    assert.equal(s.addTask('Draft', 'same-id'), true);
    assert.equal(wires[1].headers['X-Request-Id'], 'same-id');
});
test('Rate limits back off; timeouts release loading state', () => {
    const { s, wires } = service();
    s.refresh(); wires[0].respond(429, {}, { 'Retry-After': '120' });
    s.refresh(); assert.equal(wires.length, 1);
    s.retryAfter = 0;
    s.refresh(); s.requests[0].timeout();
    assert.equal(s.loading, false);
    assert.ok(s.error.includes('connection'));
});
test('Changing accounts ignores the previous account’s in-flight response', () => {
    const { s, wires } = service();
    s.refresh(); s.applyToken('replacement');
    wires[0].respond(200, { sync_token: 'old-account', items: [{ id: 'private-old-task' }] });
    assert.equal(s.tasks.length, 0);
    assert.equal(s.token, 'replacement');
});
test('Retrying an uncertain recurring completion reuses its request ID', () => {
    const { s, wires } = service();
    const task = { id: 'daily', updated_at: '2026-09-15', due: { date: '2026-09-15', is_recurring: true } };
    s.completeTask(task);
    wires[0].respond(0, '');
    s.completeTask(task);
    assert.equal(wires[0].headers['X-Request-Id'], wires[1].headers['X-Request-Id']);
});
test('Task edits use Sync commands, check command statuses and ingest the server result', () => {
    const { s, wires } = service();
    s.tasks = [{id: 'task', content: 'Before'}];
    const commands = [{uuid: 'edit-id', type: 'item_update', args: {id: 'task', content: 'After'}}];
    assert.equal(s.updateTask('task', commands), true);
    const body = new URLSearchParams(wires[0].body);
    assert.deepEqual(JSON.parse(body.get('commands')), commands);
    wires[0].respond(200, {sync_token: 'next', sync_status: {'edit-id': 'ok'}, items: [{id: 'task', content: 'After'}]});
    assert.equal(s.updated, 'task'); assert.equal(s.tasks[0].content, 'After'); assert.equal(s.saving, false);
});
test('Partial edit failures retain synced changes and report failure, even with HTTP 200', () => {
    const { s, wires } = service();
    const commands = [{uuid: 'move', type: 'item_move', args: {id: 'task', project_id: 'new'}}, {uuid: 'edit', type: 'item_update', args: {id: 'task', due: {string: 'invalid'}}}];
    s.updateTask('task', commands);
    wires[0].respond(200, {sync_token: 'next', sync_status: {move: 'ok', edit: {error: 'Invalid date'}}, items: [{id: 'task', project_id: 'new'}]});
    assert.equal(s.updated, undefined); assert.match(s.failed, /Some changes were saved.*Invalid date/);
    assert.equal(s.tasks[0].project_id, 'new'); assert.equal(s.saving, false);
});
test('An uncertain task edit can retry the same command UUID without reporting false success', () => {
    const { s, wires } = service();
    const commands = [{uuid: 'stable', type: 'reminder_add', args: {item_id: 'task', minute_offset: 30, type: 'absolute'}}];
    s.updateTask('task', commands); wires[0].respond(0, '');
    assert.equal(s.updated, undefined);
    s.updateTask('task', commands);
    assert.equal(JSON.parse(new URLSearchParams(wires[1].body).get('commands'))[0].uuid, 'stable');
    wires[1].respond(200, {sync_token: 'next'});
    assert.equal(s.updated, undefined); assert.match(s.failed, /did not confirm/);
});
test('Bulk writes cancel stale syncs, deduplicate tasks and ingest confirmed changes', () => {
    const {s, wires} = reorderFixture();
    s.refresh();
    assert.equal(s.applyTaskAction(['a', 'b', 'a'], 'priority', 4), true);
    assert.equal(wires[0].aborted, true);
    const commands = commandsOf(wires[1]);
    assert.deepEqual(commands.map(c => c.args), [{id: 'a', priority: 4}, {id: 'b', priority: 4}]);
    wires[1].respond(200, {sync_token: 'bulk', sync_status: Object.fromEntries(commands.map(c => [c.uuid, 'ok'])), items: [{...s.tasks[0], priority: 4}, {...s.tasks[1], priority: 4}]});
    assert.equal(s.tasks[0].priority, 4); assert.equal(s.tasks[2].priority, 1);
    assert.equal(s.saving, false); assert.equal(s.bulkFinished, true); assert.equal(s.bulkRetry, null);
});
test('A partial bulk failure retries only unconfirmed commands with their original UUIDs', () => {
    const {s, wires} = reorderFixture();
    s.applyTaskAction(['a', 'b', 'c'], 'duplicate', null);
    const first = commandsOf(wires[0]);
    wires[0].respond(200, {sync_token: 'partial', sync_status: {[first[0].uuid]: 'ok', [first[1].uuid]: {error: 'Project unavailable'}}});
    assert.equal(s.bulkFinished, undefined); assert.match(s.error, /1 changes saved.*Project unavailable/);
    assert.equal(s.bulkRetry.commands.length, 2);
    assert.equal(s.applyTaskAction(['c', 'b', 'a'], 'duplicate', null), true);
    assert.deepEqual(commandsOf(wires[1]), first.slice(1));
    wires[1].respond(200, {sync_token: 'done', sync_status: Object.fromEntries(first.slice(1).map(c => [c.uuid, 'ok']))});
    assert.equal(s.bulkFinished, true); assert.equal(s.bulkRetry, null);
});
test('Bulk batches stop on a transport error and retain later tasks for an explicit retry', () => {
    const {s, wires} = reorderFixture();
    s.tasks = Array.from({length: 205}, (_, i) => ({id: String(i), content: 'Task ' + i}));
    s.applyTaskAction(s.tasks.map(t => t.id), 'priority', 3);
    const first = commandsOf(wires[0]); assert.equal(first.length, 100);
    wires[0].respond(200, {sync_token: 'first', sync_status: Object.fromEntries(first.map(c => [c.uuid, 'ok']))});
    const second = commandsOf(wires[1]); assert.equal(second.length, 100);
    assert.equal(new URLSearchParams(wires[1].body).get('sync_token'), 'first');
    wires[1].respond(503, {});
    assert.equal(s.saving, false); assert.equal(s.bulkRetry.commands.length, 105); assert.equal(s.syncToken, '*');
    assert.equal(s.retryTaskAction(), true);
    assert.deepEqual(commandsOf(wires[2]), second);
    wires[2].respond(200, {sync_token: 'second', sync_status: Object.fromEntries(second.map(c => [c.uuid, 'ok']))});
    const last = commandsOf(wires[3]); assert.equal(last.length, 5);
    wires[3].respond(200, {sync_token: 'last', sync_status: Object.fromEntries(last.map(c => [c.uuid, 'ok']))});
    assert.equal(s.bulkFinished, true); assert.equal(s.saving, false);
});
test('Duplicate subtask parents are resolved across batch boundaries', () => {
    const {s, wires} = reorderFixture();
    s.tasks = Array.from({length: 101}, (_, i) => ({id: String(i), content: 'Task ' + i, project_id: 'inbox', parent_id: i ? String(i - 1) : null}));
    s.applyTaskAction(['0'], 'duplicate', null);
    const first = commandsOf(wires[0]);
    wires[0].respond(200, {sync_token: 'first', sync_status: Object.fromEntries(first.map(c => [c.uuid, 'ok'])), temp_id_mapping: {[first[99].temp_id]: 'new-parent'}});
    assert.equal(commandsOf(wires[1])[0].args.parent_id, 'new-parent');
});
test('Bulk recurring completions use close and trust the new occurrence returned by sync', () => {
    const {s, wires} = reorderFixture();
    s.tasks[0].due.is_recurring = true;
    s.applyTaskAction(['a'], 'complete', null);
    const command = commandsOf(wires[0])[0]; assert.equal(command.type, 'item_close');
    wires[0].respond(200, {sync_token: 'next', sync_status: {[command.uuid]: 'ok'}, items: [{...s.tasks[0], due: {date: '2026-09-16', is_recurring: true}}]});
    assert.equal(s.tasks[0].due.date, '2026-09-16'); assert.equal(s.bulkFinished, true);
});
test('Account changes discard bulk retries and ignore a previous account’s in-flight batch', () => {
    const {s, wires} = reorderFixture();
    s.applyTaskAction(['a', 'b'], 'delete', null);
    const commands = commandsOf(wires[0]);
    s.applyToken('new-account');
    wires[0].respond(200, {sync_token: 'old', sync_status: Object.fromEntries(commands.map(c => [c.uuid, 'ok'])), items: [{id: 'old-task'}]});
    assert.equal(s.tasks.length, 0); assert.equal(s.bulkRetry, null); assert.equal(s.bulkFinished, undefined);
});
