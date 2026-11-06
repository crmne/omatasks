const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const vm = require('node:vm');
const Model = vm.createContext({ Date });
vm.runInContext(fs.readFileSync('Model.js', 'utf8'), Model);
const N = vm.createContext({ Model, Date });
vm.runInContext(fs.readFileSync('ui/NotifyModel.js', 'utf8').replace(/^\.import.*$/gm, ''), N);
const plain = value => JSON.parse(JSON.stringify(value));
const at = (h, m = 0, day = 21) => new Date(2026, 9, day, h, m).getTime();
const task = (id, props = {}) => ({ id, content: id, project_id: 'work', priority: 1, ...props });
const timed = (id, h, m = 0, props = {}) => task(id, { due: { date: `2026-10-21T${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}:00` }, ...props });
const defaults = N.settings({});
const keys = alerts => plain(alerts.map(a => [a.task.id, a.kind]));

test('Settings fall back to defaults and reject invalid values', () => {
    assert.deepEqual(plain(defaults), { enabled: true, recap: true, recapTime: '08:00', atDueTime: true, deadlines: true, overdueHours: 0 });
    assert.deepEqual(plain(N.settings({ notifications: { recapTime: '7:5', overdueHours: 3, recap: false } })), { ...plain(defaults), recap: false });
    assert.equal(N.settings({ notifications: { recapTime: '7:30' } }).recapTime, '07:30');
    assert.equal(N.normalClock('24:00'), '');
});

test('Reminders, due times and their shared moment are announced once each', () => {
    const tasks = [timed('standup', 9, 30), timed('call', 9, 45)];
    const reminders = [{ id: 'r1', item_id: 'standup', type: 'relative', minute_offset: 15 }, { id: 'r2', item_id: 'call', type: 'relative', minute_offset: 0, is_urgent: true }];
    assert.deepEqual(keys(N.taskAlerts(tasks, reminders, 'me', defaults, at(9, 15), 0, {}, {})), [['standup', 'reminder']]);
    assert.deepEqual(keys(N.taskAlerts(tasks, reminders, 'me', defaults, at(9, 30), 0, { ['standup@' + at(9, 15)]: at(9, 15) }, {})), [['standup', 'due']]);
    const call = N.taskAlerts(tasks, reminders, 'me', defaults, at(9, 46), 0, {}, {}).filter(a => a.task.id === 'call');
    assert.deepEqual(plain(call.map(a => [a.kind, a.urgent])), [['reminder', true]]);
});

test('Absolute reminders fire at their own time; location reminders and other people are skipped', () => {
    const tasks = [task('a'), task('b', { responsible_uid: 'other' }), task('done', { checked: true })];
    const reminders = [
        { item_id: 'a', type: 'absolute', due: { date: '2026-10-21T08:00:00' } },
        { item_id: 'a', type: 'location', name: 'Office' },
        { item_id: 'a', type: 'absolute', due: { date: '2026-10-21T08:00:00' }, notify_uid: 'other' },
        { item_id: 'b', type: 'absolute', due: { date: '2026-10-21T08:00:00' } },
        { item_id: 'done', type: 'absolute', due: { date: '2026-10-21T08:00:00' } }
    ];
    assert.deepEqual(keys(N.taskAlerts(tasks, reminders, 'me', defaults, at(8, 1), 0, {}, {})), [['a', 'reminder']]);
});

test('Nothing older than the grace period or the start of the shell is replayed', () => {
    const tasks = [timed('early', 9), timed('late', 10)];
    assert.deepEqual(keys(N.taskAlerts(tasks, [], 'me', defaults, at(10, 5), 0, {}, {})), [['late', 'due']]);
    assert.deepEqual(keys(N.taskAlerts(tasks, [], 'me', defaults, at(10, 5), at(10, 1), {}, {})), []);
    const shown = { ['late@' + at(10)]: at(10) };
    assert.deepEqual(keys(N.taskAlerts(tasks, [], 'me', defaults, at(10, 5), 0, shown, {})), []);
});

test('At-time notifications can be switched off, and snoozed tasks come back', () => {
    const tasks = [timed('a', 10)];
    assert.deepEqual(keys(N.taskAlerts(tasks, [], 'me', { ...defaults, atDueTime: false }, at(10), 0, {}, {})), []);
    assert.deepEqual(keys(N.taskAlerts(tasks, [], 'me', { ...defaults, atDueTime: false }, at(10, 15), 0, {}, { a: at(10, 15) })), [['a', 'snooze']]);
});

test('Overdue reminders repeat at the chosen interval only on the task’s day', () => {
    const options = { ...defaults, overdueHours: 2 };
    const tasks = [timed('a', 9), task('yesterday', { due: { date: '2026-10-20T09:00:00' } })];
    assert.deepEqual(keys(N.taskAlerts(tasks, [], 'me', options, at(10, 59), 0, {}, {})), []);
    const nag = N.taskAlerts(tasks, [], 'me', options, at(11, 3), 0, {}, {});
    assert.deepEqual(plain(nag.map(a => [a.key, a.kind])), [['a@' + at(11), 'overdue']]);
    assert.deepEqual(keys(N.taskAlerts(tasks, [], 'me', defaults, at(11, 3), 0, {}, {})), []);
});

test('The recap lists today in Smart order, then deadlines within three days', () => {
    const now = new Date(at(8));
    const tasks = [
        task('Write notes', { due: { date: '2026-10-21' }, priority: 4 }),
        timed('Standup', 9, 30),
        task('Old thing', { due: { date: '2026-10-19' } }),
        task('Ship beta', { deadline: { date: '2026-10-23' } }),
        task('Far away', { deadline: { date: '2026-10-30' } }),
        task('Someone else', { due: { date: '2026-10-21' }, responsible_uid: 'other' })
    ];
    const summary = N.recap(tasks, [], 'me', now);
    assert.equal(summary.title, '3 tasks today, 1 overdue');
    assert.deepEqual(summary.body.split('\n'), ['Overdue  Old thing', '09:30  Standup', 'Write notes', 'Deadline Friday: Ship beta']);
    assert.equal(N.recap([], [], 'me', now).title, 'Nothing due today');
});

test('Deadline warnings cover today and tomorrow, urgent on the day', () => {
    const tasks = [task('now', { deadline: { date: '2026-10-21' } }), task('next', { deadline: { date: '2026-10-22' } }), task('later', { deadline: { date: '2026-10-23' } })];
    assert.deepEqual(plain(N.deadlineAlerts(tasks, 'me', new Date(at(8))).map(a => [a.task.id, a.urgent])), [['now', true], ['next', false]]);
    assert.equal(N.recapDue(defaults, new Date(at(7, 59))), false);
    assert.equal(N.recapDue(defaults, new Date(at(8))), true);
});

test('Task notifications lead with how soon the task is', () => {
    const alert = { task: timed('a', 10, 0, { duration: { amount: 30, unit: 'minute' } }), kind: 'reminder' };
    assert.equal(N.lead(alert, at(9, 45)), 'In 15 min · 10:00–10:30');
    assert.equal(N.lead(alert, at(10)), 'Now · 10:00–10:30');
    assert.equal(N.lead(alert, at(11)), 'Overdue since 10:00');
    assert.equal(N.taskBody({ ...alert, kind: 'deadline', today: true }, at(8), 'Work'), 'Deadline today\nWork');
});

// Runs the real Notifier.py against a stand-in for PyGObject that records the
// D-Bus call, since notification servers read the body as markup.
test('Notifier escapes markup in the body and sends the title as plain text', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'omatasks-notifier-'));
    try {
        fs.mkdirSync(path.join(dir, 'gi'));
        fs.writeFileSync(path.join(dir, 'gi', '__init__.py'), '');
        fs.writeFileSync(path.join(dir, 'gi', 'repository.py'), `
import html, json, os, sys
class Variant:
    def __init__(self, kind, value=None): self.value = value
class Error(Exception): pass
class MainLoop:
    def run(self):
        while watch[0](sys.stdin.fileno(), None): pass
    def quit(self): pass
watch = []
class GLib:
    Variant = Variant; VariantType = Variant; Error = Error; MainLoop = MainLoop
    PRIORITY_DEFAULT = IO_IN = IO_HUP = 0
    markup_escape_text = staticmethod(lambda text: html.escape(text))
    io_add_watch = staticmethod(lambda fd, priority, condition, callback: watch.append(callback))
class Reply:
    def unpack(self): return [1]
class Bus:
    def signal_subscribe(self, *args): pass
    def call_sync(self, name, path, iface, method, params, *rest):
        with open(os.environ['NOTIFY_LOG'], 'a') as log: log.write(json.dumps(params.value[3:5]) + chr(10))
        return Reply()
class Gio:
    class BusType: SESSION = 0
    class DBusSignalFlags: NONE = 0
    class DBusCallFlags: NONE = 0
    bus_get_sync = staticmethod(lambda *args: Bus())
`);
        const NOTIFY_LOG = path.join(dir, 'calls');
        const name = '<img src="https://x.io/a">';
        execFileSync('python3', ['Notifier.py'], {
            env: { ...process.env, PYTHONPATH: dir, PYTHONDONTWRITEBYTECODE: '1', XDG_RUNTIME_DIR: dir, NOTIFY_LOG },
            input: JSON.stringify({ id: 'task:1', title: name, body: `Now\n${name} & co` }) + '\n',
        });
        assert.deepEqual(JSON.parse(fs.readFileSync(NOTIFY_LOG, 'utf8')), [name, 'Now\n&lt;img src=&quot;https://x.io/a&quot;&gt; &amp; co']);
    } finally {
        fs.rmSync(dir, { recursive: true, force: true });
    }
});
