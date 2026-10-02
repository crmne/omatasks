// Exercise the panel's persistence methods without rendering or account access.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

function panel(state, overrides = {}) {
    const pending = [], writes = [];
    const service = {preferencesLoaded: true, loaded: true, preferences: {navigation: {state}}, viewOptions(view) { return {sorting: 'smart', ...(this.preferences[view] || {})}; }, setOption(group, key, value) { this.preferences[group] = {[key]: value}; writes.push(value); }, ...overrides};
    const list = {contentY: -20, originY: -20, contentHeight: 1200, height: 400, forceLayout() {}};
    const ctx = vm.createContext({service, list, rows: [], options: {sorting: 'smart'}, scrollPositions: {}, navigationReady: false, restoredView: '', restoringScroll: false, visible: true, setupVisible: false, scrollSave: {stop() {}}, Qt: {callLater(fn) { pending.push(fn); }}});
    ctx.root = ctx;
    let view = 'today';
    Object.defineProperty(ctx, 'view', {get() { return view; }, set(value) { if (value !== view) { view = value; ctx.restoredView = ''; pending.push(() => ctx.restoreScroll()); } }});
    const source = fs.readFileSync('ui/TaskList.qml', 'utf8');
    for (const name of ['updateOptions', 'updateListModel', 'saveNavigation', 'restoreNavigation', 'restoreScroll', 'selectView']) {
        vm.runInContext(source.match(new RegExp('^    function ' + name + '\\([^]*?^    \\}', 'm'))[0], ctx);
    }
    return {p: ctx, list, service, writes, flush() { while (pending.length) pending.shift()(); }};
}

test('Panel initialization waits for the shell to attach its service', () => {
    const f = panel({view: 'inbox', scrollPositions: {inbox: 150}});
    f.p.service = null;
    f.p.updateOptions(); f.p.updateListModel(); f.p.restoreNavigation(); f.p.restoreScroll(); f.p.saveNavigation(); f.flush();
    assert.equal(f.writes.length, 0); assert.equal(f.p.navigationReady, false);
    f.p.service = f.service;
    f.p.updateOptions(); f.p.updateListModel(); f.p.restoreNavigation(); f.flush();
    assert.equal(f.p.view, 'inbox'); assert.equal(f.list.contentY - f.list.originY, 150);
});

test('Restores saved tab and scroll only after preferences, tasks and panel geometry are ready', () => {
    const f = panel({view: 'upcoming', scrollPositions: {upcoming: 275}}, {preferencesLoaded: false, loaded: false});
    f.p.restoreNavigation(); f.flush();
    assert.equal(f.p.navigationReady, false); assert.equal(f.writes.length, 0);
    f.service.preferencesLoaded = true; f.p.restoreNavigation(); f.flush();
    assert.equal(f.p.view, 'upcoming'); assert.equal(f.list.contentY, -20); assert.equal(f.writes.length, 0);
    f.service.loaded = true; f.p.visible = false; f.p.restoreScroll();
    assert.equal(f.writes.length, 0);
    f.p.visible = true; f.list.height = 0; f.p.restoreScroll();
    assert.equal(f.writes.length, 0);
    f.list.height = 400; f.p.restoreScroll();
    assert.equal(f.list.contentY - f.list.originY, 275);
});

test('Switching tabs saves the outgoing position and restores each tab independently', () => {
    const f = panel({view: 'today', scrollPositions: {inbox: 150}});
    f.p.restoreNavigation(); f.flush();
    f.list.contentY = f.list.originY + 350;
    f.p.selectView('inbox'); f.p.updateListModel(); f.flush();
    assert.equal(f.list.contentY - f.list.originY, 150);
    assert.equal(f.service.preferences.navigation.state.view, 'inbox');
    assert.equal(f.service.preferences.navigation.state.scrollPositions.today, 350);
    f.p.selectView('today'); f.p.updateListModel(); f.flush();
    assert.equal(f.list.contentY - f.list.originY, 350);
    const reopened = panel(JSON.parse(JSON.stringify(f.service.preferences.navigation.state)));
    reopened.p.restoreNavigation(); reopened.flush();
    assert.equal(reopened.list.contentY - reopened.list.originY, 350);
});

test('Clamps scroll after a shorter list loads and rejects invalid saved navigation', () => {
    const f = panel({view: 'inbox', scrollPositions: {inbox: 9000, today: -1, upcoming: '400'}});
    f.p.restoreNavigation(); f.flush();
    assert.equal(f.list.contentY - f.list.originY, 800);
    assert.equal(f.p.scrollPositions.today, 0); assert.equal(f.p.scrollPositions.upcoming, 0);
    const invalid = panel({view: 'settings', scrollPositions: {today: Infinity}});
    invalid.p.restoreNavigation(); invalid.flush();
    assert.equal(invalid.p.view, 'today'); assert.equal(invalid.list.contentY, invalid.list.originY);
});

test('Model updates preserve current scroll and unchanged navigation does not write again', () => {
    const f = panel({view: 'today', scrollPositions: {today: 100}});
    f.p.restoreNavigation(); f.flush();
    f.list.contentY = f.list.originY + 250;
    f.list.forceLayout = () => { f.list.originY = -60; };
    f.p.updateListModel(); f.flush();
    assert.equal(f.list.contentY - f.list.originY, 250);
    f.p.saveNavigation(); const count = f.writes.length;
    f.p.saveNavigation(); assert.equal(f.writes.length, count);
    f.p.setupVisible = true; f.list.contentY = f.list.originY;
    f.p.saveNavigation(); assert.equal(f.writes.length, count);
});

test('Saving navigation or task defaults does not invalidate display options or reload rows', () => {
    const f = panel({view: 'today', scrollPositions: {today: 100}});
    f.p.restoreNavigation(); f.flush();
    const options = f.p.options;
    let reloads = 0;
    f.p.updateListModel = () => { reloads++; };
    f.list.contentY += 100; f.p.saveNavigation(); f.p.updateOptions();
    f.service.setOption('composer', 'defaults', {priority: 1, due: 'today'}); f.p.updateOptions();
    assert.equal(f.p.options, options); assert.equal(reloads, 0);
    f.service.setOption('today', 'sorting', 'priority'); f.p.updateOptions();
    assert.notEqual(f.p.options, options); assert.equal(f.p.options.sorting, 'priority');
});
