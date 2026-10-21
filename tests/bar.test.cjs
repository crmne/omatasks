const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const Model = vm.createContext({ Date });
vm.runInContext(fs.readFileSync('Model.js', 'utf8'), Model);
const B = vm.createContext({ Model, Date });
vm.runInContext(fs.readFileSync('ui/BarModel.js', 'utf8').replace(/^\.import.*$/gm, ''), B);
const at = (h, m = 0) => new Date(2026, 9, 21, h, m).getTime();
const timed = (id, h, m = 0, props = {}) => ({ id, content: id, project_id: 'work', priority: 1, due: { date: `2026-10-21T${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}:00` }, ...props });
const shown = (mode, tasks, now) => B.label(B.selection(mode, tasks, 'me', now), now);

test('A task is named ahead, while under way, and once late', () => {
    const tasks = [timed('Review designs', 10, 0, { duration: { amount: 30, unit: 'minute' } })];
    assert.equal(shown('task', tasks, at(9, 44)), 'Review designs · in 16m');
    assert.equal(shown('task', tasks, at(9, 48)), 'Review designs · in 12m');
    assert.equal(shown('task', tasks, at(10, 5)), 'Review designs · until 10:30');
    assert.equal(shown('task', tasks, at(10, 30)), 'Review designs · 30m late');
});

test('A task without a duration says now for half an hour', () => {
    const tasks = [timed('Call Ana', 10)];
    assert.equal(shown('task', tasks, at(10, 10)), 'Call Ana · now');
    assert.equal(shown('task', tasks, at(10, 30)), 'Call Ana · 30m late');
});

test('An imminent task comes before one under way, with a count of the rest', () => {
    const tasks = [timed('Long meeting', 9, 0, { duration: { amount: 120, unit: 'minute' } }), timed('Call Ana', 10)];
    assert.equal(shown('task', tasks, at(9, 50)), 'Call Ana · in 10m  +1');
});

test('Today’s next timed task is named when nothing is due now; count and icon name none', () => {
    const tasks = [timed('Lunch', 13), { id: 'untimed', content: 'untimed', due: { date: '2026-10-21' } }, timed('Other person', 12, 0, { responsible_uid: 'other' }), timed('Tomorrow', 9, 0, { due: { date: '2026-10-22T09:00:00' } })];
    assert.equal(shown('task', tasks, at(9)), 'Lunch · at 13:00');
    assert.equal(shown('task', [tasks[1], tasks[3]], at(9)), '');
    assert.equal(shown('count', tasks, at(12, 50)), '');
    assert.equal(shown('icon', tasks, at(12, 50)), '');
    assert.equal(B.mode('bogus'), 'task');
    assert.equal(B.mode('soon'), 'task');
    assert.equal(B.mode('next'), 'task');
});

test('Long names are shortened for the bar but not the tooltip', () => {
    const name = 'Prepare the quarterly planning document for the team';
    const list = B.selection('task', [timed(name, 10)], 'me', at(10));
    assert.equal(B.label(list, at(10)), 'Prepare the quarterly plann… · now');
    assert.equal(B.tooltip(list, at(10)), name + ' · now');
});

test('A late task stays until done or the day ends, behind anything due now', () => {
    const tasks = [timed('Tweet about the survey', 12), timed('Post mxc', 13)];
    assert.equal(shown('task', tasks, at(12, 50)), 'Post mxc · in 10m  +1');
    assert.equal(shown('task', tasks, at(13, 5)), 'Post mxc · now  +1');
    assert.equal(shown('task', tasks, at(14, 0)), 'Tweet about the survey · 2h late  +1');
    assert.equal(shown('task', tasks, at(14, 15)), 'Tweet about the survey · 2h 15m late  +1');
    assert.equal(shown('task', [timed('Yesterday', 12, 0, { due: { date: '2026-10-20T12:00:00' } })], at(9)), '');
});

test('The gap runs from this section to the nearest one toward the middle', () => {
    const boxes = [{ region: 'left', left: 8, right: 300 }, { region: 'center', left: 900, right: 1100 }, { region: 'right', left: 1300, right: 1912 }];
    assert.equal(B.sectionGap('right', boxes), 200);
    assert.equal(B.sectionGap('left', boxes), 600);
    assert.equal(B.sectionGap('center', boxes), Infinity);
    assert.equal(B.sectionGap('right', [{ region: 'center', left: 900, right: 1350 }, { region: 'right', left: 1300, right: 1912 }]), -50);
    assert.equal(B.sectionGap('right', [{ region: 'right', left: 1300, right: 1912 }]), Infinity);
    assert.equal(B.label([], 0), '');
});
