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
  assert.equal(draft.quickText(input({text: 'Review', due: 'today'})), 'today Review');
  assert.equal(draft.quickText(input({text: 'Read chaque lundi', due: ''})), 'Read chaque lundi');
  assert.equal(draft.dateToken('Review every other Tuesday at 10am').value, 'every other Tuesday at 10am');
  assert.equal(draft.dateToken('Review // Tomorrow is background context'), null);
});

test('Natural date previews cover times, abbreviations, relative dates and recurrence without altering text', () => {
  for (const expression of ['today', 'tomorrow at 4pm', 'next Monday', 'Fri at noon', 'Fri at 1900', 'tonight', 'in 3 days', '+5 days', 'in 2 hours', 'in the morning', 'tom morning', 'tomafternoon', 'later this week', 'no date', 'no due date', 'March 30', '30 March 2027', '2026-10-12', '2026/10/12', '10/12/2026', '27th', 'mid January', 'end of month', '3rd friday jan', '6 weeks before 21 Jul', '28 days after 21 July', 'at 14:30', '9am', 'every! 2 weeks', 'every other Tuesday starting March 3 at 10am', 'every mon, fri at 20:00', 'every 3rd Tuesday starting Aug 29 ending in 6 months', 'every July 19', 'every last workday at 3pm', 'monthly']) {
    const text = `Review ${expression} carefully`;
    const token = draft.dateToken(text);
    assert.ok(token, expression);
    assert.equal(token.value, expression);
    assert.equal(text.slice(token.start, token.end), expression, 'highlight covers exactly the recognized date');
  }
  assert.equal(draft.dateToken('Review today tomorrow').value, 'tomorrow');
  for (const text of ['Email alex@example.com', 'Visit https://example.com/tomorrow', 'Read todayish', 'Read #Tomorrow @today {Friday} !14:00', 'Read // today p1 #Client']) assert.equal(draft.dateToken(text), null, text);
});

test('Explicit no-date and unknown language dates override contextual defaults on the server', () => {
  for (const expression of ['no date', 'no due date']) {
    const text = 'Review ' + expression;
    assert.equal(draft.quickText(input({text, due: 'today', parsed: draft.parse(text, service, null)})), text);
  }
  assert.equal(draft.quickText(input({text: 'Read chaque lundi', due: 'today'})), 'today Read chaque lundi');
});

test('Both priority syntaxes update the preview, preserving literal punctuation and invalid priorities', () => {
  for (const prefix of ['p', 'P', '!!']) {
    for (const p of [1, 2, 3, 4]) {
      const text = `Review ${prefix}${p}`;
      const parsed = draft.parse(text, service, null);
      assert.equal(parsed.priority, p);
      assert.equal(text.slice(parsed.tokens[0].start, parsed.tokens[0].end), prefix + p);
      assert.equal(draft.quickText(input({text, parsed, priority: 2})), text);
    }
  }
  assert.equal(draft.tokenAt('Review !!', 9).kind, 'priority');
  assert.equal(draft.tokenAt('Review !!1', 10).query, '1');
  for (const text of ['Review p10', 'Review !!5', 'Hello!!1', 'Email alex+p1@example.com']) assert.equal(draft.parse(text, service, null).priority, undefined);
});

test('A pasted task previews every property and serializes once with typed project and date taking precedence', () => {
  const text = 'Review tomorrow at 4pm !!1 #Client Work /Review @email %next +Alex Smith !30 min before {Friday}';
  const shared = {...service, projects: service.projects.map(p => ({...p, is_shared: p.id === 'a'}))};
  const parsed = draft.parse(text, shared, service.projects[0]);
  assert.equal(parsed.project.id, 'a'); assert.equal(parsed.section.id, 's1');
  assert.equal(parsed.priority, 1); assert.equal(parsed.due, 'tomorrow at 4pm');
  assert.equal(parsed.reminder, '30 min before'); assert.equal(parsed.deadline, 'Friday');
  assert.equal(parsed.assignee.id, 'me'); assert.deepEqual(Array.from(parsed.labels), ['email', 'next']);
  assert.equal(parsed.tokens.length, 9);
  assert.equal(draft.quickText(input({text, parsed, project: service.projects[0], priority: 3, due: 'today', labels: ['email'], deadline: 'Monday'})), text);
});

test('Escaped names, name boundaries, project scoping and metadata dates are recognized safely', () => {
  for (const text of ['Review #Client Work /Review', 'Review #Client\\ Work /Review']) {
    const parsed = draft.parse(text, service, null);
    assert.equal(parsed.project.id, 'a'); assert.equal(parsed.section.id, 's1');
    assert.equal(parsed.due, undefined);
  }
  const namedDates = {...service, projects: [{id: 'dates', name: 'Next Monday'}], labels: [{name: 'today'}]};
  assert.equal(draft.parse('Review #Next Monday @today {tomorrow} !14:00', namedDates, null).due, undefined);
  assert.equal(draft.quickText(input({text: 'Review #Next Monday', due: 'today', parsed: draft.parse('Review #Next Monday', namedDates, null)})), 'today Review #Next Monday');
  assert.equal(draft.parse('Review #Client Workplace', service, null).project, undefined);
  assert.equal(draft.parse('Review #Archived', service, null).project, undefined);
  assert.equal(draft.parse('Review #Inbox /Review +Alex Smith', service, null).section, undefined);
  assert.equal(draft.parse('Review #Inbox /Review +Alex Smith', service, null).assignee, undefined);
  assert.equal(draft.tokenAt('Review // tomorrow #Client', 25), null);
  assert.equal(draft.parse('Review // tomorrow p1 #Client Work', service, null).tokens.length, 0);
});

test('Removing or replacing metadata preserves the rest of the title and description', () => {
  const text = 'Review tomorrow p1 #Client Work @email // Explain tomorrow p2';
  const parsed = draft.parse(text, service, null);
  assert.equal(draft.withoutTokens(text, parsed.tokens.filter(t => t.kind === 'priority')), 'Review tomorrow  #Client Work @email // Explain tomorrow p2');
  assert.equal(draft.spelling('project', {name: 'Client Work'}), '#Client\\ Work');
  assert.equal(draft.spelling('deadline', 'in 3 days'), '{in 3 days}');
});

test('Reminders consume their full date/time and durations only preview on timed tasks', () => {
  for (const expression of ['30m', '1h', '0mb', '14:00', '7pm', '30 min before', 'tomorrow at 9am', 'in 2 hours']) {
    const parsed = draft.parse('Review !' + expression, service, null);
    assert.equal(parsed.reminder, expression); assert.equal(parsed.due, undefined);
  }
  assert.equal(draft.parse('Review tomorrow at 10am for 2 hours', service, null).duration, 'for 2 hours');
  assert.equal(draft.parse('Review for 2 hours', service, null).duration, undefined);
});

test('Date-chip colors use calendar days, including Todoist next-weekday rules and distant dates', () => {
  const friday = new Date(2026, 9, 2, 9);
  for (const [value, offset] of [['today', 0], ['tomorrow at 4pm', 1], ['yesterday', -1], ['Monday', 3], ['next Monday', 3], ['next Saturday', 8], ['in 3 weeks', 21], ['2026-10-12', 10], ['next week', 3]]) assert.equal(draft.dateOffset(value, friday, {}), offset);
  assert.equal(draft.dateOffset('next week', friday, {next_week: 2}), 4);
});
