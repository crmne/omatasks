// Replacement bars give widgets no serviceFor, so the widget reads the service from Bridge.js.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

test('a retired service does not clear its hot-reloaded replacement', () => {
    const Bridge = vm.createContext({});
    vm.runInContext(fs.readFileSync('Bridge.js', 'utf8').replace(/^\.pragma.*$/m, ''), Bridge);
    const old = {}, next = {};
    Bridge.publish(old);
    Bridge.publish(next);
    Bridge.clear(old);
    assert.equal(Bridge.current(), next);
    Bridge.clear(next);
    assert.equal(Bridge.current(), null);
});

test('the service publishes itself and the widget falls back to it', () => {
    assert.match(fs.readFileSync('Service.qml', 'utf8'), /Bridge\.publish\(root\)/);
    assert.match(fs.readFileSync('BarWidget.qml', 'utf8'), /directService \|\| bridgedService/);
});
