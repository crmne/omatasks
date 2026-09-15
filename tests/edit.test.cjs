const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const edit = vm.createContext({ Date });
vm.runInContext(fs.readFileSync('ui/EditModel.js', 'utf8'), edit);
const task = {id: 'task', content: 'Write the report', description: 'Original **formatting**', project_id: 'work', section_id: 'drafts', priority: 4, labels: ['next', 'email'], responsible_uid: 'me', due: {date: '2026-09-18T08:00:00Z', string: 'every Friday at 10am', is_recurring: true, timezone: 'Europe/Berlin'}, deadline: {date: '2026-10-01'}, duration: {amount: 30, unit: 'minute'}};
const now = new Date(2026, 8, 15);
const plain = data => JSON.parse(JSON.stringify(data));
test('Editing only a description preserves the exact recurring due date and other metadata', () => {
    const draft = edit.snapshot(task); draft.description = 'Updated **formatting**';
    assert.deepEqual(plain(edit.changes(task, draft, now)), {update: {description: 'Updated **formatting**'}, move: null});
});
test('An unchanged editor produces no update; title text is literal', () => {
    const draft = edit.snapshot(task);
    assert.deepEqual(plain(edit.changes(task, draft, now)), {update: {}, move: null});
    draft.text = 'Discuss tomorrow @work #project p1';
    assert.deepEqual(plain(edit.changes(task, draft, now).update), {content: draft.text});
});
test('Clearing optional fields explicitly sends null or empty collections', () => {
    const draft = edit.snapshot(task);
    Object.assign(draft, {due: '', deadline: '', assigneeId: '', duration: '0', labels: [], priority: 4});
    assert.deepEqual(plain(edit.changes(task, draft, now).update), {labels: [], priority: 1, due: null, deadline: null, responsible_uid: null, duration: null});
});
test('Moving to a project or section uses one destination and does not rewrite the task', () => {
    const draft = edit.snapshot(task); draft.projectId = 'home'; draft.sectionId = '';
    assert.deepEqual(plain(edit.changes(task, draft, now)), {update: {}, move: {project_id: 'home'}});
    draft.sectionId = 'review';
    assert.deepEqual(plain(edit.changes(task, draft, now).move), {section_id: 'review'});
});
test('Changed dates retain fixed timezone; deadlines validate actual calendar dates', () => {
    const draft = edit.snapshot(task); draft.due = 'every Monday at 3pm'; draft.deadline = 'tomorrow';
    assert.deepEqual(plain(edit.changes(task, draft, now).update), {due: {string: 'every Monday at 3pm', timezone: 'Europe/Berlin'}, deadline: {date: '2026-09-16'}});
    draft.deadline = '2026-02-30'; assert.throws(() => edit.changes(task, draft, now), /YYYY-MM-DD/);
    draft.deadline = ''; draft.duration = '1.5'; assert.throws(() => edit.changes(task, draft, now), /whole number/);
});
test('Reminder additions distinguish relative offsets and absolute date strings', () => {
    assert.deepEqual(plain(edit.reminderArgs('30mb', 'task')), {item_id: 'task', type: 'absolute', minute_offset: 30});
    assert.deepEqual(plain(edit.reminderArgs('1h', 'task')), {item_id: 'task', type: 'absolute', minute_offset: 60});
    assert.deepEqual(plain(edit.reminderArgs('tomorrow at 4pm', 'task')), {item_id: 'task', type: 'absolute', due: {string: 'tomorrow at 4pm'}});
    assert.equal(edit.reminderText({type: 'absolute', minute_offset: 0}), 'At due time');
});
