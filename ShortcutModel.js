var DEFAULT = "ALT + SPACE";
var DESCRIPTION = "Todoist quick add";
var COMMAND = "omarchy-shell shell toggle crmne.todoist";
var MODIFIERS = {SUPER: 64, CTRL: 4, ALT: 8, SHIFT: 1};

function parse(value) {
    var raw = String(value || "").trim();
    if (!raw) return {text: "", mask: 0, key: ""};
    var tokens = raw.toUpperCase().split(/\s*\+\s*|\s+/).filter(Boolean);
    var key = tokens.pop(), mask = 0, seen = {};
    if (!/^(?:[A-Z0-9]|F(?:[1-9]|[12][0-9]|3[0-5])|SPACE|RETURN|TAB|INSERT|DELETE|HOME|END|PAGE_UP|PAGE_DOWN)$/.test(key)) return null;
    for (var i = 0; i < tokens.length; i++) {
        var modifier = tokens[i] === "CONTROL" ? "CTRL" : tokens[i];
        if (!MODIFIERS[modifier] || seen[modifier]) return null;
        seen[modifier] = true; mask += MODIFIERS[modifier];
    }
    if (!mask) return null;
    var mods = ["SUPER", "CTRL", "ALT", "SHIFT"].filter(function(m) { return seen[m]; });
    return {text: mods.concat([key]).join(" + "), mask: mask, key: key};
}
function bindings(text) {
    return String(text).split(/\n\s*\n/).map(function(block) {
        var result = {};
        block.split("\n").forEach(function(line) {
            var match = line.match(/^\s*(\w+):\s*(.*?)\s*$/);
            if (match) result[match[1]] = match[2];
        });
        result.key = String(result.key || "").split(" + ").pop().toUpperCase();
        result.modmask = Number(result.modmask);
        return result;
    }).filter(function(b) { return b.key; });
}
function same(binding, shortcut) { return binding.modmask === shortcut.mask && binding.key === shortcut.key && !binding.submap; }
function conflict(list, shortcut) {
    if (!shortcut.text) return null;
    return list.filter(function(b) { return same(b, shortcut) && b.description !== DESCRIPTION; })[0] || null;
}
function registerCode(list, previous, next, owner) {
    var code = "";
    var owned = list.filter(function(b) { return b.description === DESCRIPTION && !b.submap; }).map(function(b) {
        return ["SUPER", "CTRL", "ALT", "SHIFT"].filter(function(m) { return b.modmask & MODIFIERS[m]; }).concat([b.key]).join(" + ");
    });
    owned.concat([previous, next]).filter(Boolean).forEach(function(value, index, values) {
        if (values.indexOf(value) !== index) return;
        var shortcut = parse(value);
        if (shortcut && !conflict(list, shortcut) && list.some(function(b) { return same(b, shortcut) && b.description === DESCRIPTION; })) code += "hl.unbind(" + JSON.stringify(shortcut.text) + "); ";
    });
    if (next) code += "hl.bind(" + JSON.stringify(next) + ", hl.dsp.exec_cmd(" + JSON.stringify(COMMAND) + "), {description=" + JSON.stringify(DESCRIPTION) + "}); ";
    return code + "_G.__omatasks_shortcut_owner = " + JSON.stringify(owner);
}
function releaseCode(shortcut, owner) {
    return "if _G.__omatasks_shortcut_owner == " + JSON.stringify(owner) + " then hl.unbind(" + JSON.stringify(shortcut) + "); _G.__omatasks_shortcut_owner = nil end";
}
