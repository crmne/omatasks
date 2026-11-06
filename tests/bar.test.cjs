const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
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

// The marketplace review found a task name reaching a Text in Qt's default
// AutoText format, which fetches the image in a name like <img src=...>.
test('An image tag in a task name stays literal text', () => {
    const name = '<img src="https://x.io/a">';
    const list = B.selection('task', [timed(name, 10)], 'me', at(9, 50));
    assert.equal(B.title(list), name);
    assert.equal(B.label(list, at(9, 50)), `${name} · in 10m`);
    assert.equal(B.tooltip(list, at(9, 50)), `${name} · in 10m`);
});

test('Every Text in the plugin is plain text, so synced text cannot load anything', () => {
    const files = [];
    const walk = dir => fs.readdirSync(dir, { withFileTypes: true }).forEach(entry => {
        const file = path.join(dir, entry.name);
        if (entry.isDirectory() && !['.git', 'tests', 'node_modules'].includes(entry.name)) walk(file);
        else if (entry.isFile() && /\.qml$/.test(entry.name)) files.push(file);
    });
    walk('.');
    assert.ok(files.includes('BarWidget.qml'));
    let found = 0;
    for (const file of files) {
        const source = fs.readFileSync(file, 'utf8').replace(/\/\/.*$/gm, '');
        assert.doesNotMatch(source, /Text\.(?:AutoText|RichText|StyledText|MarkdownText)\b/, file);
        assert.doesNotMatch(source, /\bonLinkActivated\b/, file);
        for (const match of source.matchAll(/(?<![\w.])Text\s*\{/g)) {
            let depth = 1, end = match.index + match[0].length;
            while (depth > 0 && end < source.length) {
                if (source[end] === '{') depth++;
                if (source[end] === '}') depth--;
                end++;
            }
            found++;
            const line = source.slice(0, match.index).split('\n').length;
            assert.match(source.slice(match.index, end), /textFormat:\s*Text\.PlainText/, `${file}:${line}`);
        }
    }
    assert.ok(found >= 8, `only ${found} Text items found`);
});
