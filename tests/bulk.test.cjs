const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const Model = vm.createContext({ Date });
vm.runInContext(fs.readFileSync('Model.js', 'utf8'), Model);
const Edit = vm.createContext({ Date });
vm.runInContext(fs.readFileSync('ui/EditModel.js', 'utf8'), Edit);
const bulk = vm.createContext({ Model, Edit, Date });
vm.runInContext(fs.readFileSync('ui/BulkModel.js', 'utf8').replace(/^\.import.*$/gm, ''), bulk);
const plain = value => JSON.parse(JSON.stringify(value));
const now = new Date(2026, 8, 16, 12);
const tasks = [
    {id: 'parent', content: 'Parent', project_id: 'work', section_id: 'draft', labels: ['work'], priority: 4, due: {date: '2026-09-18T08:00:00Z', string: 'every Friday at 10am', is_recurring: true, timezone: 'Europe/Berlin'}},
    {id: 'child', parent_id: 'parent', content: 'Child', project_id: 'work'},
    {id: 'grandchild', parent_id: 'child', content: 'Grandchild', project_id: 'work'},
    {id: 'another', content: 'Another task', project_id: 'work'}
];
test('Selection uses task IDs across duplicate label groups and ignores non-task rows', () => {
    const rows = [{kind: 'group'}, {kind: 'task', task: tasks[0]}, {kind: 'task', task: tasks[0]}, {kind: 'add'}, {kind: 'task', task: tasks[1]}];
    assert.deepEqual(plain(bulk.visibleIds(rows)), ['parent', 'child']);
    assert.deepEqual(plain(bulk.toggle(['parent'], 'child')), ['parent', 'child']);
    assert.deepEqual(plain(bulk.toggle(['parent', 'child'], 'parent')), ['child']);
});
test('Completion, deletion and moves handle selected descendants only once', () => {
    for (const [action, type] of [['complete', 'item_close'], ['delete', 'item_delete'], ['move', 'item_move']]) {
        const commands = bulk.commands(tasks, ['parent', 'grandchild', 'another', 'parent'], action, {project_id: 'home'}, now);
        assert.deepEqual(plain(commands.map(c => c.args.id)), ['parent', 'another']);
        assert.equal(commands[0].type, type);
    }
    const priority = bulk.commands(tasks, ['parent', 'child'], 'priority', 2, now);
    assert.deepEqual(plain(priority.map(c => c.args)), [{id: 'parent', priority: 2}, {id: 'child', priority: 2}]);
});
test('Quick dates retain recurrence, time and timezone; removal clears the schedule', () => {
    const command = bulk.commands(tasks, ['parent'], 'date', 'tomorrow', now)[0];
    assert.deepEqual(plain(command.args.due), {...tasks[0].due, date: '2026-09-17T08:00:00Z'});
    assert.equal(bulk.commands(tasks, ['parent'], 'date', '', now)[0].args.due, null);
    assert.equal(bulk.scheduledDate('weekend', now), '2026-09-19');
    assert.equal(bulk.scheduledDate('nextweek', now), '2026-09-21');
    assert.equal(bulk.scheduledDate('nextweek', new Date(2026, 8, 21)), '2026-09-28');
});
test('Bulk custom dates, deadlines and reminders validate input and preserve unrelated fields', () => {
    assert.deepEqual(plain(bulk.commands(tasks, ['parent'], 'customDate', 'every Monday', now)[0].args), {id: 'parent', due: {string: 'every Monday', timezone: 'Europe/Berlin'}});
    assert.deepEqual(plain(bulk.commands(tasks, ['parent'], 'deadline', 'tomorrow', now)[0].args), {id: 'parent', deadline: {date: '2026-09-17'}});
    assert.throws(() => bulk.commands(tasks, ['parent'], 'deadline', '2026-02-30', now), /YYYY-MM-DD/);
    assert.deepEqual(plain(bulk.commands(tasks, ['parent'], 'reminder', '30mb', now)[0].args), {item_id: 'parent', type: 'absolute', minute_offset: 30});
    assert.throws(() => bulk.commands(tasks, ['parent'], 'priority', 0, now), /priority/);
});
test('Duplication preserves task fields and copies each descendant under its new parent once', () => {
    const commands = bulk.commands(tasks, ['parent', 'child'], 'duplicate', null, now);
    assert.equal(commands.length, 3);
    assert.equal(commands[0].type, 'item_add');
    assert.equal(commands[0].args.section_id, 'draft');
    assert.deepEqual(plain(commands[0].args.due), tasks[0].due);
    assert.equal(commands[1].args.parent_id, commands[0].temp_id);
    assert.equal(commands[2].args.parent_id, commands[1].temp_id);
    assert.equal(new Set(commands.map(c => c.uuid)).size, 3);
    assert.equal(commands[0].args.id, undefined);
});
