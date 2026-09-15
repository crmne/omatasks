const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const M = vm.createContext({ Date, console });
vm.runInContext(fs.readFileSync('Model.js', 'utf8'), M);
const plain = value => JSON.parse(JSON.stringify(value));
const today = new Date(2026, 8, 15, 12);
const projects = [{ id: 'inbox', name: 'Inbox', inbox_project: true }, { id: 'work', name: 'Work' }, { id: 'release', name: 'Release', parent_id: 'work' }];
const task = (id, props = {}) => ({ id, content: id, project_id: 'work', priority: 1, due: { date: '2026-09-15' }, ...props });

test('Today includes overdue and deadline-only tasks, but excludes completed, future, and other assignees', () => {
    const tasks = [task('today'), task('overdue', { due: { date: '2026-09-14' } }), task('deadline', { due: null, deadline: { date: '2026-09-15' } }), task('future', { due: { date: '2026-09-16' } }), task('done', { checked: true }), task('other', { responsible_uid: 'other' })];
    const rows = M.viewRows(tasks, projects, [], M.DEFAULT_VIEW, 'today', 'me', today);
    assert.deepEqual(plain(rows.filter(r => r.task).map(r => r.task.id)), ['overdue', 'deadline', 'today']);
    assert.equal(rows[0].title, 'Overdue');
    assert.equal(rows.at(-1).kind, 'add');
});
test('Smart sorts timed work before priority, then deadline and manual order', () => {
    const tasks = [task('p1', { priority: 4 }), task('early', { due: { date: '2026-09-15T09:00:00' } }), task('late', { due: { date: '2026-09-15T16:00:00' } }), task('deadline', { priority: 4, deadline: { date: '2026-09-16' } }), task('manual2', { day_order: 2 }), task('manual1', { day_order: 1 })];
    assert.deepEqual(plain(M.sortTasks(tasks, 'smart', 'today', {}, {}).map(t => t.id)), ['early', 'late', 'deadline', 'p1', 'manual1', 'manual2']);
});
test('Manual uses Todoist day order, while Inbox uses case-sensitive fractional order keys', () => {
    const tasks = [task('lower', { order_key: 'a1', day_order: 0 }), task('upper', { order_key: 'A1', day_order: 1 })];
    assert.deepEqual(plain(M.sortTasks(tasks, 'manual', 'today', {}, {}).map(t => t.id)), ['lower', 'upper']);
    assert.deepEqual(plain(M.sortTasks(tasks, 'manual', 'inbox', {}, {}).map(t => t.id)), ['upper', 'lower']);
});
test('Project grouping keeps each project distinct and shows its section on task rows', () => {
    const rows = M.viewRows([task('child', { project_id: 'release' }), task('parent')], projects, [], { ...M.DEFAULT_VIEW, grouping: 'project' }, 'today', 'me', today);
    assert.deepEqual(plain(rows.filter(r => r.kind === 'group').map(r => r.title)).sort(), ['Release', 'Work']);
    assert.equal(rows.filter(r => r.kind === 'add').length, 2);
    assert.equal(M.projectPath('release', M.byId(projects), 'docs', { docs: {name: 'Documentation'} }), 'Release / Documentation');
});
test('Date-only tasks do not shift across timezones; UTC times do', () => {
    assert.equal(M.dueDay(task('date')), '2026-09-15');
    const due = '2026-09-14T23:30:00Z';
    assert.equal(M.dueDay(task('timed', { due: { date: due } })), M.dateKey(new Date(due)));
    assert.equal(M.dueLabel(task('duration', { due: { date: '2026-09-15T09:00:00' }, duration: { amount: 15, unit: 'minute' } }), today, 'today', 'none'), '09:00–09:15');
    assert.equal(M.overdue(task('date'), today), false);
});
test('Upcoming has no arbitrary seven-day cutoff; Inbox also contains undated tasks', () => {
    const tasks = [task('distant', { due: { date: '2027-01-01' } }), task('inbox', { due: null, project_id: 'inbox' })];
    assert.equal(M.viewRows(tasks, projects, [], M.DEFAULT_VIEW, 'upcoming', 'me', today).filter(r => r.task)[0].task.id, 'distant');
    assert.equal(M.viewRows(tasks, projects, [], M.DEFAULT_VIEW, 'inbox', 'me', today).filter(r => r.task)[0].task.id, 'inbox');
});
test('Incremental sync retains unchanged items, replaces changed items and removes tombstones', () => {
    const merged = M.merge([task('a'), task('b')], [task('a', { content: 'updated' }), { id: 'b', is_deleted: true }, task('c')], false);
    assert.deepEqual(plain(merged.map(t => [t.id, t.content])), [['a', 'updated'], ['c', 'c']]);
    assert.deepEqual(plain(M.merge(merged, [task('d')], true).map(t => t.id)), ['d']);
});
test('Combined filters and readable markdown preserve task content', () => {
    const t = task('a', { priority: 4, labels: ['next'], responsible_uid: 'me', deadline: { date: '2026-09-14' } });
    const options = { assignee: 'me', priority: '4', label: 'next', deadline: 'overdue' };
    assert.equal(M.matches(t, options, 'me', '2026-09-15'), true);
    assert.equal(M.matches(t, { ...options, label: 'email' }, 'me', '2026-09-15'), false);
    assert.equal(M.plain('**Review** [the PR](https://example.com)\nwith `tests`'), 'Review the PR with tests');
});
test('A task appears under every label when grouped by label', () => {
    const rows = M.viewRows([task('a', { labels: ['email', 'next'] })], projects, [], { ...M.DEFAULT_VIEW, grouping: 'label' }, 'today', 'me', today);
    assert.deepEqual(plain(rows.filter(r => r.kind === 'group').map(r => r.title)), ['email', 'next']);
    assert.equal(rows.filter(r => r.task).length, 2);
});
