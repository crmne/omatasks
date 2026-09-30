// Exercise the shared QML wheel handler without rendering or a Todoist account.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const source = fs.readFileSync('ui/ScrollHandler.qml', 'utf8');
const handler = source.match(/onWheel: function\(event\) \{([\s\S]*?)^    \}/m)[1];
function fixture(position = 100, origin = 0, contentHeight = 1000, height = 200, lines = 3) {
    const flickable = {contentY: position, originY: origin, contentHeight, height, flickDeceleration: 1500, flickingVertically: false, flicks: [], flick(x, y) { this.flicks.push([x, y]); this.flickingVertically = true; }};
    const context = vm.createContext({flickable, targetY: NaN, Qt: {styleHints: {wheelScrollLines: lines}}});
    return {flickable, context, scroll(pixelDelta, angleDelta = {x: 0, y: 0}) {
        context.event = {pixelDelta, angleDelta, accepted: false};
        vm.runInContext('(function(event) {' + handler + '})(event);', context);
        return context.event;
    }};
}

test('Touchpad input starts a native flick toward three times the pixel distance without jumping', () => {
    const f = fixture();
    const event = f.scroll({x: 0, y: -4}, {x: 0, y: -48});
    assert.equal(f.context.targetY, 112);
    assert.equal(f.flickable.contentY, 100);
    assert.equal(f.flickable.flicks.length, 1);
    assert.deepEqual(f.flickable.flicks[0], [0, -Math.sqrt(2 * 1500 * 12)]);
    assert.equal(event.accepted, true);
});

test('Consecutive input accumulates while animating and direction reversal responds immediately', () => {
    const f = fixture();
    f.scroll({x: 0, y: -4});
    f.flickable.contentY = 104;
    f.scroll({x: 0, y: -4});
    assert.equal(f.context.targetY, 124);
    assert.equal(f.flickable.contentY, 104);
    f.scroll({x: 0, y: 4});
    assert.equal(f.context.targetY, 92);
    assert.ok(f.flickable.flicks.at(-1)[1] > 0);
});

test('A new gesture starts at the current position after scrolling ends or the position changes', () => {
    const f = fixture();
    f.scroll({x: 0, y: -4});
    f.flickable.flickingVertically = false;
    f.flickable.contentY = 300;
    f.scroll({x: 0, y: -4});
    assert.equal(f.context.targetY, 312);
});

test('Mouse wheels respect the system line count and partial wheel steps', () => {
    const f = fixture(), custom = fixture(100, 0, 1000, 200, 5);
    f.scroll({x: 0, y: 0}, {x: 0, y: -120});
    custom.scroll({x: 0, y: 0}, {x: 0, y: -60});
    assert.equal(f.context.targetY, 172);
    assert.equal(custom.context.targetY, 160);
});

test('Destinations clamp to both bounds and account for a shifted ListView origin', () => {
    const top = fixture(50, -20), bottom = fixture(750, -20), short = fixture(20, 20, 100, 200);
    top.scroll({x: 0, y: 100});
    bottom.scroll({x: 0, y: -100});
    short.scroll({x: 0, y: -10});
    assert.equal(top.context.targetY, -20);
    assert.equal(bottom.context.targetY, 780);
    assert.equal(short.context.targetY, 20);
    assert.equal(short.flickable.flicks.length, 0);
});

test('Horizontal gestures and zero-distance events do not start a vertical flick', () => {
    for (const pixelDelta of [{x: 4, y: 0}, {x: 0, y: 0}]) {
        const f = fixture();
        const event = f.scroll(pixelDelta, {x: 48, y: 0});
        assert.equal(f.flickable.contentY, 100);
        assert.equal(f.flickable.flicks.length, 0);
        assert.equal(event.accepted, false);
    }
});
