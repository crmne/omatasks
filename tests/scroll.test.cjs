// Exercise the shared QML wheel handler without rendering or a Todoist account.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const source = fs.readFileSync('ui/ScrollHandler.qml', 'utf8');
const handler = source.match(/onWheel: function\(event\) \{([\s\S]*?)^    \}/m)[1];
function scroll(pixelDelta, angleDelta, position = 100, origin = 0, contentHeight = 1000, height = 200, lines = 3) {
    const flickable = {contentY: position, originY: origin, contentHeight, height, cancelled: 0, cancelFlick() { this.cancelled++; }};
    const event = {pixelDelta, angleDelta, accepted: false};
    vm.runInNewContext('(function(event) {' + handler + '})(event);', {flickable, event, Qt: {styleHints: {wheelScrollLines: lines}}});
    return {flickable, event};
}

test('Touchpad deltas move three times their pixel distance without also applying the angle delta', () => {
    const {flickable, event} = scroll({x: 0, y: -4}, {x: 0, y: -48});
    assert.equal(flickable.contentY, 112);
    assert.equal(flickable.cancelled, 1);
    assert.equal(event.accepted, true);
    assert.equal(scroll({x: 0, y: 4}, {x: 0, y: 48}).flickable.contentY, 88);
});

test('Mouse wheels respect the system line count and partial wheel steps', () => {
    assert.equal(scroll({x: 0, y: 0}, {x: 0, y: -120}).flickable.contentY, 172);
    assert.equal(scroll({x: 0, y: 0}, {x: 0, y: -60}, 100, 0, 1000, 200, 5).flickable.contentY, 160);
});

test('Scrolling clamps to both bounds and accounts for a shifted ListView origin', () => {
    assert.equal(scroll({x: 0, y: 100}, {x: 0, y: 0}, 50, -20).flickable.contentY, -20);
    assert.equal(scroll({x: 0, y: -100}, {x: 0, y: 0}, 750, -20).flickable.contentY, 780);
    assert.equal(scroll({x: 0, y: -10}, {x: 0, y: 0}, 20, 20, 100, 200).flickable.contentY, 20);
});

test('Horizontal gestures and zero-distance events do not move the vertical position', () => {
    for (const pixelDelta of [{x: 4, y: 0}, {x: 0, y: 0}]) {
        const {flickable, event} = scroll(pixelDelta, {x: 48, y: 0});
        assert.equal(flickable.contentY, 100);
        assert.equal(flickable.cancelled, 0);
        assert.equal(event.accepted, false);
    }
});
