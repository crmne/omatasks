const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const Model = vm.createContext({ Date });
vm.runInContext(fs.readFileSync('Model.js', 'utf8'), Model);
const Fractional = vm.createContext({});
vm.runInContext(fs.readFileSync('ui/Fractional.js', 'utf8'), Fractional);
const O = vm.createContext({ Model, Fractional });
vm.runInContext(fs.readFileSync('ui/OrderModel.js', 'utf8').replace(/^\.import.*$/gm, ''), O);
const plain = x => JSON.parse(JSON.stringify(x));
const projects = [{ id: 'inbox', name: 'Inbox', inbox_project: true }, { id: 'work', name: 'Work' }];
const now = new Date(2026, 8, 15, 12);
const task = (id, props = {}) => ({ id, content: id, project_id: 'inbox', priority: 1, due: {date: '2026-09-15'}, ...props });
function rows(tasks, view = 'today', opts = {}) {
    return Model.viewRows(tasks, projects, [], {...Model.DEFAULT_VIEW, sorting: 'manual', ...opts}, view, 'me', now);
}
function order(tasks, view = 'today') { return plain(Model.sortTasks(tasks, 'manual', view, {}, {}).map(t => t.id)); }
test('Day drag persists the visible order and retains filtered-out tasks and project keys', () => {
    const tasks = [task('a', {day_order: 0, order_key: 'a0'}), task('hidden', {day_order: 1, responsible_uid: 'other'}), task('b', {day_order: 2}), task('c', {day_order: 3})];
    const plan = O.plan(tasks, rows(tasks), 'today', 'c', 'a', false, '');
    assert.equal(plan.commands.length, 1);
    assert.equal(plan.commands[0].type, 'item_update_day_orders');
    const result = O.apply(tasks, plan.patches);
    assert.deepEqual(order(result), ['c', 'hidden', 'a', 'b']);
    assert.equal(result[0].order_key, 'a0');
    assert.deepEqual(result[0].due, tasks[0].due);
    assert.equal(tasks[0].day_order, 0);
});
test('Inbox drag updates only the moved sibling key and leaves day order untouched', () => {
    const tasks = ['a', 'b', 'c'].map((id, i) => task(id, {order_key: 'a' + i, day_order: i}));
    for (const [source, target, after, expected] of [['c', 'a', false, ['c', 'a', 'b']], ['a', 'c', true, ['b', 'c', 'a']], ['a', 'b', true, ['b', 'a', 'c']]]) {
        const plan = O.plan(tasks, rows(tasks, 'inbox'), 'inbox', source, target, after, '');
        assert.equal(plan.commands.length, 1);
        assert.equal(plan.commands[0].type, 'item_update');
        assert.equal(plan.commands[0].args.id, source);
        assert.deepEqual(order(O.apply(tasks, plan.patches), 'inbox'), expected);
        assert.ok(!('day_order' in plan.commands[0].args));
    }
});
test('Automatic Inbox sort converts to the dropped order without displacing hidden siblings', () => {
    const tasks = ['a', 'hidden', 'b', 'c'].map((id, i) => task(id, {order_key: 'a' + i, priority: id === 'c' ? 4 : 1, responsible_uid: id === 'hidden' ? 'other' : null}));
    const displayed = rows(tasks, 'inbox', {sorting: 'smart'});
    const plan = O.plan(tasks, displayed, 'inbox', 'b', 'c', false, '');
    assert.deepEqual(order(O.apply(tasks, plan.patches), 'inbox'), ['b', 'hidden', 'c', 'a']);
    assert.ok(!plan.patches.hidden);
    const oldKeys = tasks.map(t => t.order_key);
    assert.ok(plan.commands.every(c => !oldKeys.includes(c.args.order_key)));
});
test('Missing keys are initialized without losing sibling or day ordering', () => {
    const tasks = [task('a', {child_order: 0}), task('hidden', {child_order: 1, responsible_uid: 'other'}), task('b', {child_order: 2}), task('child', {parent_id: 'a', order_key: 'a0'})];
    const plan = O.plan(tasks, rows(tasks, 'inbox'), 'inbox', 'b', 'a', false, '');
    assert.deepEqual(order(O.apply(tasks, plan.patches).filter(t => !t.parent_id), 'inbox'), ['b', 'hidden', 'a']);
    assert.ok(plan.commands.every(c => c.type === 'item_update'));
    assert.ok(!plan.patches.child);
});
test('No-op, stale tasks, cross-group and cross-parent drops never produce writes', () => {
    const tasks = [task('a', {day_order: 0}), task('b', {day_order: 1}), task('child', {parent_id: 'a'}), task('section', {section_id: 's'}), task('future', {due: {date: '2026-09-16'}})];
    assert.equal(O.plan(tasks, rows(tasks), 'today', 'a', 'b', false, ''), null);
    assert.equal(O.plan(tasks, rows(tasks), 'today', 'gone', 'b', false, ''), null);
    for (const target of ['child', 'section']) assert.equal(O.plan(tasks, rows(tasks, 'inbox'), 'inbox', 'a', target, true, ''), null);
    assert.equal(O.plan(tasks, rows(tasks, 'upcoming'), 'upcoming', 'a', 'future', true, '2026-09-15'), null);
});
test('Label duplicates reorder a task only once within the selected group', () => {
    const tasks = ['a', 'b', 'c'].map((id, i) => task(id, {day_order: i, labels: ['email', 'next']}));
    const displayed = rows(tasks, 'today', {grouping: 'label'});
    const plan = O.plan(tasks, displayed, 'today', 'c', 'a', false, 'next');
    const reordered = rows(O.apply(tasks, plan.patches), 'today', {grouping: 'label'});
    for (const group of ['email', 'next']) assert.deepEqual(plain(reordered.filter(r => r.task && r.groupKey === group).map(r => r.task.id)), ['c', 'a', 'b']);
    assert.equal(Object.keys(plan.commands[0].args.ids_to_orders).length, 3);
});
test('Rollback restores only unchanged optimistic fields, preserving other task edits', () => {
    const tasks = [task('a'), task('b', {day_order: 5})], patches = {a: {day_order: 1}, b: {day_order: 0}};
    const before = O.before(tasks, patches);
    const optimistic = O.apply(tasks, patches);
    optimistic[0].content = 'Updated elsewhere'; optimistic[1].day_order = 42;
    const restored = O.rollback(optimistic, patches, before);
    assert.equal(restored[0].content, 'Updated elsewhere');
    assert.ok(!('day_order' in restored[0]));
    assert.equal(restored[1].day_order, 42);
});
test('Repeated Inbox moves generate valid unique keys at either end and between close neighbors', () => {
    let tasks = Array.from({length: 12}, (_, i) => task(String(i), {order_key: Fractional.generateNKeysBetween(null, null, 12)[i]}));
    let expected = tasks.map(t => t.id);
    for (let i = 0; i < 240; i++) {
        const from = i % 12, to = (i * 7 + 3) % 12;
        if (from === to) continue;
        const source = expected[from], target = expected[to], after = i % 2 === 0;
        const plan = O.plan(tasks, rows(tasks, 'inbox'), 'inbox', source, target, after, '');
        expected.splice(from, 1); expected.splice(expected.indexOf(target) + (after ? 1 : 0), 0, source);
        if (plan) tasks = O.apply(tasks, plan.patches);
        assert.deepEqual(order(tasks, 'inbox'), expected);
        assert.equal(new Set(tasks.map(t => t.order_key)).size, 12);
    }
});
