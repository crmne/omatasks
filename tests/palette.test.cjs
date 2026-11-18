// Qt 6.12 adds a QtQuick Color type that hides Omarchy's palette from a bare
// `Color.popups.text` in any file that imports QtQuick, so the palette reads
// as undefined and the colours fall back to transparent or Qt's defaults.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

test('Every palette reference in QML is qualified as Commons.Color', () => {
    const files = [];
    const walk = dir => fs.readdirSync(dir, { withFileTypes: true }).forEach(entry => {
        const file = path.join(dir, entry.name);
        if (entry.isDirectory() && !['.git', 'node_modules'].includes(entry.name)) walk(file);
        else if (entry.isFile() && /\.qml$/.test(entry.name)) files.push(file);
    });
    walk('.');
    assert.ok(files.includes(path.join('ui', 'FolderFilter.qml')));
    for (const file of files) {
        const source = fs.readFileSync(file, 'utf8').replace(/\/\/.*$/gm, '');
        assert.doesNotMatch(source, /(?<![\w.])Color\.[a-z]/, file);
        if (/Commons\.Color\./.test(source)) assert.match(source, /^import qs\.Commons as Commons$/m, file);
    }
});
