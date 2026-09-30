// Run the shared composer's JavaScript with synthetic accounts and requests.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

function composer(defaults, overrides = {}, shared) {
    const writes = [], requests = [];
    const service = shared || {
        preferencesLoaded: true, loaded: true, user: {id: 'me'}, preferences: {composer: {defaults}}, error: '',
        projectMap: {work: {id: 'work', name: 'Work'}, other: {id: 'other', name: 'Other'}, inbox: {id: 'inbox', name: 'Inbox', inbox_project: true}},
        setOption(group, key, value) { this.preferences[group] = {[key]: value}; writes.push(value); },
        addTask(text, id) { requests.push({text, id}); return true; }
    };
    const Draft = vm.createContext({});
    vm.runInContext(fs.readFileSync('ui/ComposerModel.js', 'utf8'), Draft);
    let sequence = 0;
    const ctx = vm.createContext({service, Draft, Model: {uuid: () => 'request-' + ++sequence}, editing: false, submitting: false, draftTouched: false, draftAccountId: '', sentDefaults: null, initialProjectId: '', initialDue: '', project: null, priority: 0, due: '', section: null, taskLabels: [], deadline: '', reminder: '', assignee: null, sentText: '', requestId: '', message: '', descriptionVisible: false, pickerKind: '', activeToken: null, input: {text: '', forceActiveFocus() {}}, description: {text: ''}, finished() {}, ...overrides});
    ctx.root = ctx;
    Object.defineProperty(ctx, 'shownDate', {get() { return Draft.dateToken(ctx.input.text)?.value || ctx.due; }});
    const source = fs.readFileSync('ui/Composer.qml', 'utf8');
    vm.runInContext([...source.matchAll(/^    function .+?\{[\s\S]*?^    \}/gm)].map(m => m[0]).join('\n'), ctx);
    const connections = source.slice(source.lastIndexOf('    Connections {'));
    vm.runInContext(connections.match(/^        function onUserChanged\([^]*?^        \}/m)[0], ctx);
    for (const name of ['onTaskAdded', 'onOperationFailed']) vm.runInContext(connections.match(new RegExp('^        function ' + name + '.*$', 'm'))[0], ctx);
    return {c: ctx, service, writes, requests};
}
const saved = () => ({accountId: 'me', projectId: 'work', priority: 1, due: 'today'});
const result = overrides => ({id: 'task', project_id: 'work', priority: 4, due: {string: 'today', date: '2026-09-29'}, ...overrides});

test('New composers wait for preferences and account data, then share remembered defaults', () => {
    const f = composer(saved());
    f.service.preferencesLoaded = false; f.c.restoreDefaults(); assert.equal(f.c.priority, 0);
    f.service.preferencesLoaded = true; f.service.loaded = false; f.c.restoreDefaults(); assert.equal(f.c.priority, 0);
    f.service.loaded = true; f.c.restoreDefaults();
    assert.equal(f.c.priority, 1); assert.equal(f.c.due, 'today'); assert.equal(f.c.project.id, 'work');
    const inline = composer(null, {initialDue: 'today', initialProjectId: 'other'}, f.service);
    f.service.preferences.composer.defaults.due = 'tomorrow'; inline.c.restoreDefaults();
    assert.equal(inline.c.priority, 1); assert.equal(inline.c.project.id, 'other'); assert.equal(inline.c.due, 'today');
    f.c.restoreDefaults(); assert.equal(f.c.due, 'tomorrow');
});

test('Five successful additions retain defaults while clearing text and other metadata', () => {
    const f = composer(saved()); f.c.restoreDefaults();
    for (let i = 0; i < 5; i++) {
        f.c.input.text = 'Task ' + i; f.c.description.text = 'Description'; f.c.taskLabels = ['label']; f.c.reminder = '30mb';
        f.c.submit(); f.c.onTaskAdded(result({id: String(i)}));
        assert.equal(f.c.input.text, ''); assert.equal(f.c.description.text, ''); assert.equal(f.c.taskLabels.length, 0); assert.equal(f.c.reminder, '');
        assert.equal(f.c.priority, 1); assert.equal(f.c.due, 'today'); assert.equal(f.c.project.id, 'work');
    }
    assert.equal(f.writes.length, 5); assert.equal(new Set(f.requests.map(r => r.id)).size, 5);
    const restarted = composer(JSON.parse(JSON.stringify(f.service.preferences.composer.defaults)));
    restarted.c.restoreDefaults(); assert.equal(restarted.c.priority, 1); assert.equal(restarted.c.due, 'today'); assert.equal(restarted.c.project.id, 'work');
    assert.deepEqual(Object.keys(f.writes[0]).sort(), ['accountId', 'due', 'priority', 'projectId']);
});

test('Success remembers the API project and priority and keeps relative or explicit dates', () => {
    for (const due of ['today', 'tomorrow', '2026-12-20', 'every Monday']) {
        const f = composer(saved()); f.c.restoreDefaults();
        f.c.input.text = 'Review ' + due + ' #Other p2'; f.c.submit();
        f.c.onTaskAdded(result({project_id: 'other', priority: 3, due: {string: due, date: '2026-12-20'}}));
        assert.equal(f.writes[0].due.toLowerCase(), due.toLowerCase()); assert.equal(f.writes[0].projectId, 'other'); assert.equal(f.writes[0].priority, 2);
        const nextDay = composer(JSON.parse(JSON.stringify(f.writes[0]))); nextDay.service.now = new Date(2026, 8, 30); nextDay.c.restoreDefaults();
        assert.equal(nextDay.c.due.toLowerCase(), due.toLowerCase());
    }
});

test('Cleared date and priority and an explicit Inbox replace remembered choices', () => {
    const f = composer(saved()); f.c.restoreDefaults();
    f.c.due = ''; f.c.priority = 0; f.c.project = f.service.projectMap.inbox; f.c.input.text = 'Unscheduled'; f.c.submit();
    f.c.onTaskAdded(result({priority: 1, project_id: 'inbox', due: null}));
    assert.equal(f.c.due, ''); assert.equal(f.c.priority, 0); assert.equal(f.c.project.id, 'inbox');
});

test('Failure preserves the draft and retry ID without changing defaults; Cancel restores defaults', () => {
    const f = composer(saved()); f.c.restoreDefaults();
    f.c.input.text = 'Retry tomorrow'; f.c.priority = 3; f.c.submit();
    f.c.onOperationFailed('Offline');
    assert.equal(f.c.input.text, 'Retry tomorrow'); assert.equal(f.c.priority, 3); assert.equal(f.writes.length, 0);
    f.c.submit(); assert.equal(f.requests[0].id, f.requests[1].id);
    f.c.onOperationFailed('Offline'); f.c.reset();
    assert.equal(f.writes.length, 0); assert.equal(f.c.input.text, ''); assert.equal(f.c.priority, 1); assert.equal(f.c.due, 'today');
});

test('Reopening an untouched composer refreshes defaults but never overwrites a draft', () => {
    const f = composer(saved()); f.c.restoreDefaults();
    f.service.preferences.composer.defaults = {...saved(), priority: 2, due: 'tomorrow'};
    f.c.restoreDefaults(); assert.equal(f.c.priority, 2);
    f.c.input.text = 'Unfinished'; f.c.priority = 3; f.c.restoreDefaults(); assert.equal(f.c.priority, 3);
    f.c.input.text = ''; f.c.draftTouched = true; f.c.due = ''; f.c.restoreDefaults(); assert.equal(f.c.due, '');
});

test('Missing, malformed, archived and deleted projects fall back to Inbox without erasing saved data', () => {
    for (const defaults of [null, 'invalid', {...saved(), projectId: 'missing'}, {...saved(), priority: '1', due: 123, projectId: []}]) {
        const f = composer(defaults); f.c.restoreDefaults(); assert.equal(f.c.project, null); assert.equal(f.writes.length, 0);
    }
    for (const flag of ['is_archived', 'is_deleted']) {
        const f = composer(saved()); f.service.projectMap.work[flag] = true; f.c.restoreDefaults();
        assert.equal(f.c.project, null); assert.equal(f.c.priority, 1); assert.equal(f.writes.length, 0);
    }
});

test('Account changes discard old drafts and ignore old defaults and late success', () => {
    const f = composer(saved()); f.c.restoreDefaults(); f.c.input.text = 'Old account'; f.c.submit();
    f.service.loaded = false; f.service.user = {}; f.c.onUserChanged();
    assert.equal(f.c.input.text, ''); assert.equal(f.c.submitting, false);
    f.service.user = {id: 'another'}; f.service.loaded = true; f.c.onUserChanged();
    assert.equal(f.c.priority, 0); assert.equal(f.c.project, null); assert.equal(f.c.due, '');
    f.c.onTaskAdded(result()); assert.equal(f.writes.length, 0);
});

test('Existing-task editors never load or save new-task defaults', () => {
    const f = composer(saved(), {editing: true, priority: 3, due: '2026-10-01'});
    f.c.restoreDefaults(); assert.equal(f.c.priority, 3); assert.equal(f.c.due, '2026-10-01');
    let edits = 0; f.c.submitEdit = () => { edits++; }; f.c.input.text = 'Existing'; f.c.submit();
    assert.equal(edits, 1); assert.equal(f.requests.length, 0);
    f.c.submitting = true; f.c.onTaskAdded(result()); assert.equal(f.writes.length, 0); assert.equal(f.c.input.text, 'Existing');
});
