const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const draft = vm.createContext({});
vm.runInContext(fs.readFileSync('ui/ComposerModel.js', 'utf8'), draft);
const input = overrides => ({text: 'Review tomorrow at 4pm', description: '', labels: [], ...overrides});
const service = {
  projects: [{id: 'in', name: 'Inbox', inbox_project: true}, {id: 'a', name: 'Client Work'}, {id: 'b', name: 'Archived', is_archived: true}],
  projectMap: {}, labels: [{name: 'email'}, {name: 'next'}],
  sections: [{id: 's1', name: 'Review', project_id: 'a'}, {id: 's2', name: 'Personal', project_id: 'in'}],
  collaborators: [{id: 'me', full_name: 'Alex Smith', project_id: 'a'}]
};
test('Selected properties serialize to documented Quick Add syntax, with description last', () => {
  assert.equal(draft.quickText(input({project: {name: 'Client Work'}, section: {name: 'Final review'}, labels: ['email', 'next'], priority: 1, deadline: 'Friday', reminder: '30mb', description: 'Check links\nThen publish.'})), 'Review tomorrow at 4pm #Client\\ Work /Final\\ review @email @next p1 {Friday} !30mb // Check links\nThen publish.');
});
test('Pasted inline descriptions stay after metadata and remain descriptions, not comments', () => {
  assert.equal(draft.quickText(input({text: 'Review // Existing details', description: 'More details', labels: ['email']})), 'Review @email // Existing details\nMore details');
});
test('Autocomplete identifies project, label, section and priority spans without matching email or URLs', () => {
  for (const [text, kind, query] of [['Call #Client W', 'project', 'Client W'], ['Call @ema', 'label', 'ema'], ['Call %ema', 'label', 'ema'], ['Call /Rev', 'section', 'Rev'], ['Call p1', 'priority', '1']]) {
    const token = draft.tokenAt(text, text.length);
    assert.equal(token.kind, kind); assert.equal(token.query, query);
    assert.equal(text.slice(0, token.start), 'Call ');
  }
  assert.equal(draft.tokenAt('Email alex@example.com', 22), null);
  assert.equal(draft.tokenAt('Visit https://example.com', 25), null);
  const middle = draft.tokenAt('Review @email now', 10);
  assert.equal('Review @email now'.slice(middle.start, middle.end), '@email');
});
test('Pickers search real projects and labels, scope sections and omit archived projects', () => {
  assert.equal(draft.choices('project', 'client', service, null)[0].value.id, 'a');
  assert.equal(draft.choices('project', '', service, null).length, 2);
  assert.equal(draft.choices('section', '', service, {id: 'a'})[0].id, 's1');
  assert.equal(draft.choices('section', '', service, null).length, 0);
  assert.equal(draft.choices('label', 'email', service, null).length, 1);
  assert.equal(draft.choices('label', 'new label', service, null)[0].value, 'new_label');
  assert.equal(draft.choices('assignee', '', service, {id: 'a', is_shared: true})[0].id, 'me');
  assert.equal(draft.choices('assignee', '', service, {id: 'in'}).length, 0);
});
test('Typed dates take precedence over the Today view default, while arbitrary input stays intact', () => {
  assert.equal(draft.quickText(input({due: 'today'})), 'Review tomorrow at 4pm');
  assert.equal(draft.quickText(input({text: 'Review', due: 'today'})), 'Review today');
  assert.equal(draft.quickText(input({text: 'Read chaque lundi', due: ''})), 'Read chaque lundi');
  assert.equal(draft.dateToken('Review every other Tuesday at 10am').value, 'every other Tuesday at 10am');
  assert.equal(draft.dateToken('Review // Tomorrow is background context'), null);
});
