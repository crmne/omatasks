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

const tree = [
    { id: 'pro', name: 'Pro', child_order: 2 },
    { id: 'planning', name: 'Planning', parent_id: 'pro', child_order: 1 },
    { id: 'training', name: 'Training', parent_id: 'pro', child_order: 2 },
    { id: 'sprint', name: 'Sprint', parent_id: 'planning', child_order: 1 },
    { id: 'perso', name: 'Perso', child_order: 1 },
    { id: 'errands', name: 'Errands', parent_id: 'perso', child_order: 1 },
];
const ids = folder => Object.keys(M.folderIds(tree, folder) || {}).sort();

test('Folder tree lists every project under its parent, in Todoist order, with its depth', () => {
    assert.deepEqual(plain(M.folderTree(tree).map(f => [f.id, f.depth])), [['perso', 0], ['errands', 1], ['pro', 0], ['planning', 1], ['sprint', 2], ['training', 1]]);
    assert.deepEqual(plain(M.folderTree(tree).map(f => f.path)), ['', 'Perso', '', 'Pro', 'Pro / Planning', 'Pro']);
});
test('Without a selection no folder filter applies', () => {
    assert.equal(M.folderIds(tree, null), null);
    assert.equal(M.folderIds(tree, { include: [], exclude: [] }), null);
    assert.equal(M.folderIds(tree, { include: ['deleted'], exclude: [] }), null);
});
test('Selecting a folder selects its subfolders, and an excluded subfolder drops its own subtree', () => {
    assert.deepEqual(ids({ include: ['pro'], exclude: [] }), ['planning', 'pro', 'sprint', 'training']);
    assert.deepEqual(ids({ include: ['pro'], exclude: ['planning'] }), ['pro', 'training']);
    assert.deepEqual(ids({ include: ['pro', 'sprint'], exclude: ['planning'] }), ['pro', 'sprint', 'training']);
    assert.deepEqual(ids({ include: ['planning', 'errands'], exclude: [] }), ['errands', 'planning', 'sprint']);
});
test('A folder filter keeps only tasks in the selected folders', () => {
    const tasks = [task('a', { project_id: 'planning' }), task('b', { project_id: 'errands' }), task('c', { project_id: 'sprint' })];
    const rows = M.viewRows(tasks, tree, [], { ...M.DEFAULT_VIEW, folder: { include: ['pro'], exclude: [] } }, 'today', 'me', today);
    assert.deepEqual(plain(rows.filter(r => r.task).map(r => r.task.id)), ['a', 'c']);
});
const values = folder => plain(M.folderValues(tree, folder)).sort();
test('Checking a folder selects its whole subtree and checking it again unselects it', () => {
    const folder = M.toggleFolder(tree, null, 'pro');
    assert.deepEqual(plain(folder), { include: ['pro'], exclude: [] });
    assert.deepEqual(values(folder), ['planning', 'pro', 'sprint', 'training']);
    assert.deepEqual(plain(M.toggleFolder(tree, folder, 'pro')), { include: [], exclude: [] });
});
test('Unchecking a subfolder keeps its parent and siblings, and checking it back restores it', () => {
    const folder = M.toggleFolder(tree, M.toggleFolder(tree, null, 'pro'), 'planning');
    assert.deepEqual(plain(folder), { include: ['pro'], exclude: ['planning'] });
    assert.deepEqual(values(folder), ['pro', 'training']);
    assert.deepEqual(plain(M.toggleFolder(tree, folder, 'planning')), { include: ['pro'], exclude: [] });
});
test('Siblings can be selected independently, and a folder that is not checked checks its whole subtree', () => {
    let folder = M.toggleFolder(tree, M.toggleFolder(tree, null, 'planning'), 'errands');
    assert.deepEqual(values(folder), ['errands', 'planning', 'sprint']);
    folder = M.toggleFolder(tree, folder, 'pro');
    assert.deepEqual(plain(folder), { include: ['errands', 'pro'], exclude: [] });
    assert.deepEqual(values(folder), ['errands', 'planning', 'pro', 'sprint', 'training']);
});
test('A parent is partial when only some of its subtree is selected, and checked or unchecked otherwise', () => {
    const state = (folder, id) => M.folderState(tree, folder, id);
    assert.equal(state(null, 'pro'), 'unchecked');
    assert.equal(state({ include: ['pro'], exclude: [] }, 'pro'), 'checked');
    assert.equal(state({ include: ['pro'], exclude: ['planning'] }, 'pro'), 'partial');
    assert.equal(state({ include: ['pro'], exclude: ['planning'] }, 'planning'), 'unchecked');
    assert.equal(state({ include: ['pro'], exclude: ['planning'] }, 'training'), 'checked');
    assert.equal(state({ include: ['sprint'], exclude: [] }, 'pro'), 'partial');
    assert.equal(state({ include: ['sprint'], exclude: [] }, 'planning'), 'partial');
    assert.equal(state({ include: ['sprint'], exclude: [] }, 'sprint'), 'checked');
});
test('Clicking a partial folder checks its whole subtree, and clicking a checked folder unchecks it', () => {
    assert.deepEqual(plain(M.toggleFolder(tree, { include: ['pro'], exclude: ['planning'] }, 'pro')), { include: ['pro'], exclude: [] });
    assert.deepEqual(plain(M.toggleFolder(tree, { include: ['sprint'], exclude: [] }, 'pro')), { include: ['pro'], exclude: [] });
    assert.deepEqual(plain(M.toggleFolder(tree, { include: ['pro'], exclude: [] }, 'pro')), { include: [], exclude: [] });
});
test('Unchecking the last selected folder returns to showing everything', () => {
    assert.equal(M.folderIds(tree, M.toggleFolder(tree, M.toggleFolder(tree, null, 'errands'), 'errands')), null);
});
test('The folder summary names the top-most selected folders and counts a partly selected subtree', () => {
    assert.equal(M.folderSummary(tree, null), 'All');
    assert.equal(M.folderSummary(tree, { include: ['pro'], exclude: [] }), 'Pro');
    assert.equal(M.folderSummary(tree, { include: ['pro'], exclude: ['planning'] }), 'Pro (2/4)');
    assert.equal(M.folderSummary(tree, { include: ['pro'], exclude: ['sprint'] }), 'Pro (3/4)');
    assert.equal(M.folderSummary(tree, { include: ['pro', 'errands'], exclude: [] }), 'Errands, Pro');
    assert.equal(M.folderSummary(tree, { include: ['sprint'], exclude: [] }), 'Sprint');
});
test('The bar count follows the Today folder filter but ignores the other panel filters', () => {
    const tasks = [task('a', { project_id: 'planning' }), task('b', { project_id: 'errands' }), task('c', { project_id: 'sprint', priority: 4 }), task('d', { project_id: 'planning', responsible_uid: 'other' })];
    assert.equal(M.todayCount(tasks, tree, 'me', today, null), 3);
    assert.equal(M.todayCount(tasks, tree, 'me', today, { include: ['pro'], exclude: [] }), 2);
    assert.equal(M.todayCount(tasks, tree, 'me', today, { include: ['pro'], exclude: ['planning'] }), 0);
});
test('Without a folder selection the Inbox tab still shows the inbox project, whatever the other projects hold', () => {
    const projectsWithInbox = [{ id: 'inbox', name: 'Inbox', inbox_project: true }, ...tree];
    const tasks = [task('in', { project_id: 'inbox' }), task('elsewhere', { project_id: 'planning' })];
    const rows = view => M.viewRows(tasks, projectsWithInbox, [], { ...M.DEFAULT_VIEW, ...view }, 'inbox', 'me', today);
    assert.deepEqual(plain(rows({}).filter(r => r.task).map(r => r.task.id)), ['in']);
    assert.deepEqual(plain(rows({ folder: { include: [], exclude: [] } }).filter(r => r.task).map(r => r.task.id)), ['in']);
    assert.deepEqual(plain(rows({ folder: { include: ['inbox'], exclude: [] } }).filter(r => r.task).map(r => r.task.id)), ['in']);
});
