const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const M = vm.createContext({});
vm.runInContext(fs.readFileSync('ShortcutModel.js', 'utf8'), M);
const sample = `bindd
    modmask: 68
    submap:
    key: A
    description: Audio
    dispatcher: __lua

bindd
    modmask: 72
    submap:
    key: T
    description: Todoist quick add
    dispatcher: __lua
`;
test('Shortcut normalizes supported modifiers and rejects invalid or injectable input', () => {
    assert.equal(M.parse('alt + Super + t').text, 'SUPER + ALT + T');
    assert.equal(M.parse('CONTROL shift F12').mask, 5);
    assert.equal(M.parse('').text, '');
    for (const value of ['A', 'SUPER + SUPER + T', 'SUPER + NO_SUCH_KEY', 'SUPER + T"); os.execute("bad")']) assert.equal(M.parse(value), null);
});
test('Shortcut conflicts name the existing action and permit the plugin’s own binding', () => {
    const list = M.bindings(sample);
    assert.equal(M.conflict(list, M.parse('SUPER + CTRL + A')).description, 'Audio');
    assert.equal(M.conflict(list, M.parse('SUPER + ALT + T')), null);
});
test('Registration only unbinds this plugin’s shortcuts, and cleanup is owner-guarded', () => {
    const list = M.bindings(sample);
    const code = M.registerCode(list, 'SUPER + CTRL + A', 'SUPER + ALT + T', 'owner-123');
    assert.ok(!code.includes('hl.unbind("SUPER + CTRL + A")'));
    assert.ok(code.includes('hl.unbind("SUPER + ALT + T")'));
    assert.ok(code.includes('hl.bind("SUPER + ALT + T"'));
    assert.match(M.releaseCode('SUPER + ALT + T', 'owner-123'), /^if _G\.__omatasks_shortcut_owner == "owner-123" then/);
});
test('Changing the default migrates an old owned binding without touching Omarchy shortcuts', () => {
    assert.equal(M.DEFAULT, 'ALT + SPACE');
    const code = M.registerCode(M.bindings(sample), '', M.DEFAULT, 'new-owner');
    assert.ok(code.includes('hl.unbind("SUPER + ALT + T")'));
    assert.ok(code.includes('hl.bind("ALT + SPACE"'));
    assert.ok(!code.includes('hl.unbind("SUPER + CTRL + A")'));
});
