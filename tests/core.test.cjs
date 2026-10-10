// Run with DevEco's Node 24: node --test tests/core.test.cjs
// Uses real SQLite for SQL/transaction checks; Harmony API adapters are simulated.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { DatabaseSync } = require('node:sqlite');
const ts = require(process.env.TAIPLAN_TYPESCRIPT || 'D:/Program Files/Huawei/DevEco Studio/tools/hvigor/hvigor/node_modules/typescript');
const root = path.join(__dirname, '../entry/src/main/ets');
const plain = value => JSON.parse(JSON.stringify(value));

function loadModule(relative, externals = {}, cache = {}) {
  const file = path.resolve(root, relative);
  if (cache[file]) return cache[file].exports;
  const module = { exports: {} };
  cache[file] = module;
  const compiled = ts.transpileModule(fs.readFileSync(file, 'utf8'), {
    fileName: file.replace(/\.ets$/, '.ts'),
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const requireLocal = name => {
    if (name in externals) return externals[name];
    if (name.startsWith('.')) return loadModule(path.relative(root, path.resolve(path.dirname(file), name + '.ets')), externals, cache);
    throw Error('Unexpected import: ' + name);
  };
  vm.runInNewContext(compiled, { exports: module.exports, module, require: requireLocal, console }, { filename: file });
  return module.exports;
}
const { TaskService: S } = loadModule('services/TaskService.ets');
const draft = (overrides = {}) => ({ title: '学习 ArkTS', note: '复习课堂笔记', priority: 1, tagsText: '学习', dueAt: 0, ...overrides });
const legacyTask = { id: 'old-1', title: '旧版任务', note: '中文 🥰', completed: true, createdAt: 10, updatedAt: 20 };
const legacyRaw = JSON.stringify({ version: 1, tasks: [legacyTask] });

function repositoryFixture(raw = '') {
  const db = new DatabaseSync(':memory:');
  let failSql = '';
  const stores = new Map([['taiplan_tasks_v1', new Map([['document', raw]])]]);
  const adapter = {
    executeSql: async (sql, args = []) => {
      if (failSql && sql.includes(failSql)) throw Error('Simulated disk failure');
      db.prepare(sql).run(...args);
    },
    querySql: async (sql, args = []) => {
      const statement = db.prepare(sql);
      const rows = statement.all(...args);
      const columns = statement.columns().map(c => c.name);
      let index = -1;
      return { rowCount: rows.length, goToNextRow: () => ++index < rows.length,
        getColumnIndex: name => columns.indexOf(name), getString: col => String(rows[index][columns[col]]),
        getLong: col => Number(rows[index][columns[col]]), close: () => {} };
    },
    beginTransaction: () => db.exec('BEGIN TRANSACTION'),
    commit: () => db.exec('COMMIT'), rollBack: () => db.exec('ROLLBACK')
  };
  const preferences = { getPreferences: async (_, options) => {
    if (!stores.has(options.name)) stores.set(options.name, new Map());
    const values = stores.get(options.name);
    return { get: async (key, fallback) => values.has(key) ? values.get(key) : fallback,
      put: async (key, value) => values.set(key, value), flush: async () => {} };
  } };
  const modes = [];
  const context = { getApplicationContext: () => ({ setColorMode: mode => modes.push(mode) }) };
  const { TaskRepository } = loadModule('data/TaskRepository.ets', {
    '@kit.AbilityKit': { ConfigurationConstant: { ColorMode: { COLOR_MODE_DARK: 0, COLOR_MODE_LIGHT: 1, COLOR_MODE_NOT_SET: -1 } } },
    '@kit.ArkData': { preferences, relationalStore: { SecurityLevel: { S1: 1 }, getRdbStore: async () => adapter } }
  });
  return { repo: new TaskRepository(), context, db, stores, modes,
    fail: value => { failSql = value; }, newRepo: () => new TaskRepository() };
}

test('Chinese and emoji survive create/edit; editing preserves identity, creation time and completion', () => {
  const task = S.toggle(S.create(draft({ title: '  完成演示 🥰  ' }), 'a', 10), 11);
  const edited = S.edit(task, draft({ title: '改好演示 🥰', priority: 2 }), 30);
  assert.equal(edited.id, 'a'); assert.equal(edited.createdAt, 10);
  assert.equal(edited.completed, true); assert.equal(edited.updatedAt, 30);
  assert.equal(edited.title, '改好演示 🥰');
});
test('Tags support Chinese separators, trim, deduplicate and enforce limits', () => {
  assert.deepEqual(plain(S.parseTags(' 学习，生活,学习、测试\n工作 ')), ['学习', '生活', '测试', '工作']);
  assert.throws(() => S.parseTags('一,二,三,四,五,六'));
  assert.throws(() => S.parseTags('a'.repeat(13)));
});
test('Reject blank titles, oversized notes, invalid priority and dates', () => {
  for (const data of [{ title: '  ' }, { title: 'x'.repeat(101) }, { note: 'x'.repeat(1001) }, { priority: 9 }, { dueAt: NaN }]) {
    assert.throws(() => S.create(draft(data), 'a', 1));
  }
});
test('Search combines keyword, exact tag and completion; default order uses creation time', () => {
  const a = S.create(draft({ title: 'ArkTS', note: 'HELLO' }), 'a', 1);
  const b = S.create(draft({ title: 'ArkUI', tagsText: '工作' }), 'b', 2);
  const c = S.toggle(S.create(draft({ title: 'ArkTS' }), 'c', 3), 4);
  assert.deepEqual(plain(S.section([a, c, b], false).map(t => t.id)), ['b', 'a']);
  assert.deepEqual(plain(S.section([a, c, b], false, 'hello', '学习').map(t => t.id)), ['a']);
  assert.equal(S.section([a, c, b], false, 'Ark', '学').length, 0);
  assert.equal(S.section([a, c, b], true, 'ark').length, 1);
  assert.equal(S.section([a], false, '学习').length, 1);
});
test('Deadline is local end-of-day, and completed tasks are never overdue', () => {
  const due = S.endOfDay(2026, 9, 11);
  const task = S.create(draft({ dueAt: due }), 'a', 1);
  assert.equal(new Date(due).getHours(), 23);
  assert.equal(S.dateLabel(due), '2026/10/11');
  assert.equal(S.isOverdue(task, due - 1), false);
  assert.equal(S.isOverdue(task, due + 1), true);
  assert.equal(S.isOverdue(S.toggle(task, 2), due + 1), false);
});
test('Legacy migration preserves all original fields and adds predictable defaults', () => {
  const [task] = S.migrateLegacy(legacyRaw);
  assert.deepEqual(plain(task), { ...legacyTask, priority: 1, tags: [], dueAt: 0, repeat: 'none', sortOrder: -10 });
  for (const raw of ['{', '{}', JSON.stringify({ version: 2, tasks: [] }), JSON.stringify({ version: 1, tasks: [legacyTask, legacyTask] })]) {
    assert.throws(() => S.migrateLegacy(raw));
  }
});
test('RDB upgrade preserves legacy data and does not reimport on subsequent launches', async () => {
  const f = repositoryFixture(legacyRaw);
  const initial = await f.repo.load(f.context);
  assert.equal(initial[0].title, legacyTask.title);
  await f.repo.save(S.edit(initial[0], draft({ title: '修改后的旧任务', tagsText: '迁移,测试' }), 50));
  const after = await f.newRepo().load(f.context);
  assert.equal(after.length, 1); assert.equal(after[0].title, '修改后的旧任务');
  assert.deepEqual(plain(after[0].tags), ['测试', '迁移']);
  assert.equal(f.stores.get('taiplan_tasks_v1').get('document'), legacyRaw);
  f.db.close();
});
test('Migration failure rolls back tasks and marker, allowing a safe retry', async () => {
  const f = repositoryFixture(legacyRaw);
  f.fail('INSERT INTO metadata');
  await assert.rejects(() => f.repo.load(f.context));
  assert.equal(f.db.prepare('SELECT COUNT(*) AS n FROM tasks').get().n, 0);
  assert.equal(f.db.prepare('SELECT COUNT(*) AS n FROM metadata').get().n, 0);
  f.fail('');
  assert.equal((await f.repo.load(f.context)).length, 1);
  f.db.close();
});
test('Corrupt legacy data fails without marking migration complete or overwriting original', async () => {
  const f = repositoryFixture('{broken');
  await assert.rejects(() => f.repo.load(f.context));
  assert.equal(f.db.prepare('SELECT COUNT(*) AS n FROM metadata').get().n, 0);
  assert.equal(f.stores.get('taiplan_tasks_v1').get('document'), '{broken');
  f.db.close();
});
test('A failed task/tag update is atomic; original task and tags remain', async () => {
  const f = repositoryFixture();
  await f.repo.load(f.context);
  const old = S.create(draft({ tagsText: '原标签' }), 'a', 1);
  await f.repo.save(old);
  f.fail('INSERT INTO task_tags');
  await assert.rejects(() => f.repo.save(S.edit(old, draft({ title: '新标题', tagsText: '新标签' }), 5)));
  f.fail('');
  const [actual] = await f.newRepo().load(f.context);
  assert.deepEqual(plain(actual), plain(old));
  f.db.close();
});
test('CRUD persists tags/dates/emoji/quotes and deletion removes associated tags', async () => {
  const f = repositoryFixture();
  await f.repo.load(f.context);
  const task = S.create(draft({ title: "O'Brien 🥰", tagsText: '学习,生活', dueAt: 123456789, priority: 2 }), 'a', 1);
  await f.repo.save(task);
  const [loaded] = await f.newRepo().load(f.context);
  assert.equal(loaded.title, task.title); assert.equal(loaded.dueAt, task.dueAt);
  assert.equal(loaded.priority, 2); assert.equal(loaded.tags.length, 2);
  await f.repo.remove('a');
  assert.equal((await f.newRepo().load(f.context)).length, 0);
  assert.equal(f.db.prepare('SELECT COUNT(*) AS n FROM task_tags').get().n, 0);
  f.db.close();
});
test('Theme selection persists and is restored during a subsequent load', async () => {
  const f = repositoryFixture();
  await f.repo.load(f.context);
  await f.repo.setTheme(f.context, 'dark');
  await f.newRepo().load(f.context);
  assert.equal(await f.repo.getTheme(), 'dark');
  assert.equal(f.modes.at(-1), 0);
  f.db.close();
});

const { ScheduleService: Calendar } = loadModule('services/ScheduleService.ets');
const { QuickEntryService: Quick } = loadModule('services/QuickEntryService.ets');
const { BackupService: Backup } = loadModule('services/BackupService.ets');
const date = key => Calendar.end(key);
const makeRepeat = (repeat, key, id = 'r') => S.create(draft({ repeat, dueAt: date(key) }), id, 10);
const state = (taskId, dateKey, completed = true, skipped = false) => ({ taskId, dateKey, completed, skipped, updatedAt: 100 });

test('Recurrence requires an anchor and rejects unknown rules and invalid dates', () => {
  assert.throws(() => S.create(draft({ repeat: 'daily' }), 'r', 1));
  assert.throws(() => S.create(draft({ repeat: 'yearly', dueAt: date('2026-10-10') }), 'r', 1));
  assert.throws(() => S.create(draft({ dueAt: 1e100 }), 'r', 1));
  assert.equal(Calendar.validKey('2026-02-30'), false);
});
test('Monthly recurrence clamps to the month end without drifting the original day', () => {
  const task = makeRepeat('monthly', '2024-01-31');
  for (const key of ['2024-01-31', '2024-02-29', '2024-03-31', '2024-04-30']) assert.equal(Calendar.occursOn(task, key), true);
  for (const key of ['2023-12-31', '2024-02-28', '2024-03-29', '2024-04-29']) assert.equal(Calendar.occursOn(task, key), false);
  assert.equal(Calendar.occursOn(makeRepeat('monthly', '2025-01-31'), '2025-02-28'), true);
});
test('Weekly recurrence respects its weekday and never starts before the anchor', () => {
  const task = makeRepeat('weekly', '2026-10-12');
  assert.equal(Calendar.occursOn(task, '2026-10-05'), false);
  assert.equal(Calendar.occursOn(task, '2026-10-19'), true);
  assert.equal(Calendar.occursOn(task, '2026-10-20'), false);
});
test('Completing or skipping one occurrence does not affect other dates', () => {
  const task = makeRepeat('daily', '2026-10-10');
  const states = [state('r', '2026-10-10'), state('r', '2026-10-11', false, true)];
  assert.equal(Calendar.project([task], states, 'calendar', '2026-10-10', date('2026-10-10'))[0].completed, true);
  assert.equal(Calendar.project([task], states, 'calendar', '2026-10-11', date('2026-10-10')).length, 0);
  assert.equal(Calendar.project([task], states, 'calendar', '2026-10-12', date('2026-10-10'))[0].completed, false);
  assert.equal(task.completed, false);
});
test('All view represents each series once, including a far-future anchor', () => {
  const now = date('2026-10-10');
  const daily = makeRepeat('daily', '2026-10-01');
  assert.equal(Calendar.project([daily], [], 'all', '', now).length, 1);
  assert.equal(Calendar.project([daily], [state('r', '2026-10-10', false, true)], 'all', '', now)[0].dateKey, '2026-10-11');
  const future = makeRepeat('monthly', '2029-01-31');
  assert.equal(Calendar.project([future], [], 'all', '', now)[0].dateKey, '2029-01-31');
});
test('Today includes overdue unfinished tasks; future is bounded to the next 30 days', () => {
  const now = date('2026-10-10');
  const overdue = S.create(draft({ dueAt: date('2026-10-09') }), 'overdue', 1);
  const noDate = S.create(draft(), 'undated', 2);
  const next = S.create(draft({ dueAt: date('2026-10-11') }), 'next', 3);
  assert.deepEqual(plain(Calendar.project([overdue, noDate, next], [], 'today', '', now).map(i => i.key)), ['overdue']);
  const items = Calendar.project([makeRepeat('daily', '2026-10-10')], [], 'future', '', now);
  assert.equal(items.length, 30); assert.equal(items[0].dateKey, '2026-10-11'); assert.equal(items.at(-1).dateKey, '2026-11-09');
});
test('Calendar produces six Monday-first weeks and counts completed but not skipped items', () => {
  const days = Calendar.month([makeRepeat('daily', '2026-10-10')], [state('r', '2026-10-10'), state('r', '2026-10-11', false, true)], '2026-10-01');
  assert.equal(days.length, 42); assert.equal(days[0].key, '2026-09-28');
  assert.equal(days.find(d => d.key === '2026-10-10').count, 1);
  assert.equal(days.find(d => d.key === '2026-10-11').count, 0);
});
test('Date-based recurrence survives daylight-saving transitions', () => {
  const previous = process.env.TZ ?? Intl.DateTimeFormat().resolvedOptions().timeZone;
  process.env.TZ = 'America/New_York';
  try {
    assert.equal(Calendar.shift('2026-03-07', 2), '2026-03-09');
    assert.equal(Calendar.shift('2026-10-31', 2), '2026-11-02');
    const task = makeRepeat('weekly', '2026-03-01');
    assert.equal(Calendar.occursOn(task, '2026-03-08'), true);
  } finally { process.env.TZ = previous; }
});
test('Natural-language quick entry creates a reviewable draft with date, tags and priority', () => {
  const parsed = Quick.parse('明天 交报告 #学习 高优先级', date('2026-10-10'));
  assert.equal(parsed.title, '交报告'); assert.equal(Calendar.key(parsed.dueAt), '2026-10-11');
  assert.equal(parsed.priority, 2); assert.equal(parsed.tagsText, '学习');
  const weekly = Quick.parse('每周一 复习英语 #学习', date('2026-10-10'));
  assert.equal(weekly.repeat, 'weekly'); assert.equal(Calendar.key(weekly.dueAt), '2026-10-12');
  assert.equal(Quick.parse('阅读原子习惯', date('2026-10-10')).dueAt, 0);
});
test('Quick entry handles year boundaries, explicit dates and rejects nonexistent dates', () => {
  assert.equal(Calendar.key(Quick.parse('明天跨年', date('2026-12-31')).dueAt), '2027-01-01');
  assert.equal(Calendar.key(Quick.parse('2028-2-29 学习', date('2026-10-10')).dueAt), '2028-02-29');
  assert.throws(() => Quick.parse('2026-02-30 学习', date('2026-10-10')));
  assert.throws(() => Quick.parse('明天 #学习', date('2026-10-10')));
});
test('Reordering moves an item rather than swapping and does not mutate the source', () => {
  const tasks = ['a', 'b', 'c'].map((id, i) => S.create(draft(), id, i + 1));
  assert.deepEqual(plain(Calendar.move(tasks, 0, 2).map(t => t.id)), ['b', 'c', 'a']);
  assert.deepEqual(tasks.map(t => t.id), ['a', 'b', 'c']);
  assert.deepEqual(plain(Calendar.move(tasks, -1, 3).map(t => t.id)), ['a', 'b', 'c']);
});
test('Pre-0.3 database without option rows upgrades without losing existing fields', async () => {
  const f = repositoryFixture();
  await f.repo.load(f.context);
  f.db.prepare('INSERT INTO tasks VALUES (?,?,?,?,?,?,?,?)').run('v02', '已有任务', '备注', 1, 20, 30, 2, date('2026-10-11'));
  f.db.prepare('INSERT INTO task_tags VALUES (?,?)').run('v02', '旧标签');
  const [task] = await f.newRepo().load(f.context);
  assert.equal(task.repeat, 'none'); assert.equal(task.sortOrder, -20);
  assert.equal(task.completed, true); assert.deepEqual(plain(task.tags), ['旧标签']);
  f.db.close();
});
test('Repeat completion persists independently; changing the rule clears stale history', async () => {
  const f = repositoryFixture(); await f.repo.load(f.context);
  const task = makeRepeat('daily', '2026-10-10'); await f.repo.save(task);
  await f.repo.setOccurrence(state('r', '2026-10-10'));
  const repo2 = f.newRepo(); await repo2.load(f.context);
  assert.equal((await repo2.getOccurrences())[0].completed, true);
  await repo2.save(S.edit(task, draft({ title: '改标题', repeat: 'daily', dueAt: task.dueAt }), 100));
  assert.equal((await repo2.getOccurrences()).length, 1);
  await repo2.save(S.edit(task, draft({ repeat: 'weekly', dueAt: task.dueAt }), 101));
  assert.equal((await repo2.getOccurrences()).length, 0);
  f.db.close();
});
test('Manual ordering persists and default creation order remains available', async () => {
  const f = repositoryFixture(); await f.repo.load(f.context);
  const a = S.create(draft(), 'a', 1), b = S.create(draft(), 'b', 2);
  await f.repo.save(a); await f.repo.save(b); await f.repo.saveOrder([a, b]); await f.repo.setSortMode('manual');
  const tasks = await f.newRepo().load(f.context);
  assert.deepEqual(plain(Calendar.ordered(tasks).map(t => t.id)), ['a', 'b']);
  assert.deepEqual(plain(S.section(tasks, false).map(t => t.id)), ['b', 'a']);
  assert.equal(await f.repo.getSortMode(), 'manual'); f.db.close();
});
test('Backup round-trip includes rules, tags, order and occurrence states', () => {
  const task = makeRepeat('monthly', '2026-01-31');
  const states = [state('r', '2026-02-28')];
  const decoded = Backup.decode(Backup.encode([task], states, 100));
  assert.deepEqual(plain(decoded.tasks), plain([task])); assert.deepEqual(plain(decoded.occurrences), states);
});
test('Backup validation rejects duplicates, unknown rules and orphan or invalid occurrence records', () => {
  const task = makeRepeat('weekly', '2026-10-12');
  for (const [tasks, states] of [
    [[task, task], []], [[{ ...task, repeat: 'yearly' }], []], [[task], [state('missing', '2026-10-12')]],
    [[task], [state('r', '2026-10-13')]], [[task], [state('r', '2026-10-12'), state('r', '2026-10-12')]],
    [[{ ...task, tags: ['a', 'a'] }], []], [[{ ...task, dueAt: 'tomorrow' }], []]
  ]) assert.throws(() => Backup.decode(Backup.encode(tasks, states, 100)));
  assert.throws(() => Backup.decode('{"format":"other","version":3,"tasks":[],"occurrences":[]}'));
});
test('Backup merge preserves existing tasks; importing twice never creates duplicates', async () => {
  const f = repositoryFixture(); await f.repo.load(f.context);
  const existing = S.create(draft({ title: '保留我的修改' }), 'a', 1); await f.repo.save(existing);
  const imported = makeRepeat('daily', '2026-10-10', 'b');
  const doc = Backup.decode(Backup.encode([S.create(draft({ title: '过期备份' }), 'a', 1), imported], [state('b', '2026-10-10')], 100));
  assert.equal(await f.repo.mergeBackup(doc), 1); assert.equal(await f.repo.mergeBackup(doc), 0);
  const tasks = await f.repo.reload(); assert.equal(tasks.length, 2);
  assert.equal(tasks.find(t => t.id === 'a').title, '保留我的修改');
  assert.equal((await f.repo.getOccurrences()).length, 1); f.db.close();
});
test('Failed backup import rolls back every imported task and leaves existing data intact', async () => {
  const f = repositoryFixture(); await f.repo.load(f.context);
  await f.repo.save(S.create(draft(), 'original', 1));
  const task = makeRepeat('daily', '2026-10-10');
  const doc = Backup.decode(Backup.encode([task], [state('r', '2026-10-10')], 100));
  f.fail('INSERT OR REPLACE INTO task_occurrences');
  await assert.rejects(() => f.repo.mergeBackup(doc)); f.fail('');
  assert.deepEqual(plain((await f.repo.reload()).map(t => t.id)), ['original']);
  assert.equal((await f.repo.getOccurrences()).length, 0); f.db.close();
});
test('Deleting a series removes its tags, ordering options and occurrence history', async () => {
  const f = repositoryFixture(); await f.repo.load(f.context);
  await f.repo.save(makeRepeat('daily', '2026-10-10')); await f.repo.setOccurrence(state('r', '2026-10-10'));
  await f.repo.remove('r');
  for (const table of ['tasks', 'task_tags', 'task_options', 'task_occurrences']) {
    assert.equal(f.db.prepare('SELECT COUNT(*) AS n FROM ' + table).get().n, 0);
  }
  f.db.close();
});

test('Next occurrence survives skipping more than a year of monthly occurrences', () => {
  const task = makeRepeat('monthly', '2026-01-31');
  let next = '2026-01-31';
  const states = [];
  for (let i = 0; i < 18; i++) {
    states.push(state('r', next, false, true));
    next = Calendar.nextDate(task, Calendar.shift(next, 1));
  }
  assert.equal(Calendar.project([task], states, 'all', '', date('2026-01-01'))[0].dateKey, '2027-07-31');
});

test('Timed tasks validate minutes and do not cross midnight; deadlines use the interval end', () => {
  const valid = draft({ dueAt: date('2026-10-10'), startMinute: 14 * 60 + 30, durationMinutes: 60 });
  const task = S.create(valid, 'timed', 1);
  assert.equal(S.timeLabel(task), '14:30–15:30');
  assert.equal(new Date(S.deadline(task, task.dueAt)).getHours(), 15);
  assert.equal(S.isOverdue(task, S.deadline(task, task.dueAt) + 1), true);
  assert.equal(S.isOverdue(task, S.deadline(task, task.dueAt) - 1), false);
  assert.equal(S.timeLabel(S.create({ ...valid, startMinute: 1435, durationMinutes: 5 }, 'end', 1)), '23:55–24:00');
  for (const bad of [{ startMinute: -2 }, { startMinute: 1440 }, { startMinute: 1.5 }, { durationMinutes: 0 },
    { durationMinutes: 1441 }, { durationMinutes: 5.5 }, { startMinute: 1439, durationMinutes: 5 }, { dueAt: 0 }]) {
    assert.throws(() => S.create({ ...valid, ...bad }, 'bad', 1));
  }
});

test('Checklist limits and toggles preserve source arrays; edits reset progress only when steps change', () => {
  const task = S.create(draft({ stepsText: ' 整理资料\n\n写初稿 🥰 ' }), 'a', 1);
  assert.deepEqual(plain(task.steps), ['整理资料', '写初稿 🥰']);
  task.doneSteps = S.toggleStep([], 1, 2);
  const next = S.toggleStep(task.doneSteps, 0, 2);
  assert.deepEqual(plain(task.doneSteps), [1]); assert.deepEqual(plain(next), [0, 1]);
  const unchanged = S.edit(task, draft({ title: '新标题', stepsText: task.steps.join('\n') }), 2);
  assert.deepEqual(plain(unchanged.doneSteps), [1]);
  const changed = S.edit(task, draft({ stepsText: '新步骤' }), 3);
  assert.deepEqual(plain(changed.doneSteps), []);
  assert.throws(() => S.parseSteps(Array(21).fill('step').join('\n')));
  assert.throws(() => S.parseSteps('x'.repeat(101)));
  assert.throws(() => S.toggleStep([], 2, 2));
  assert.throws(() => S.validateDone([0, 0], 2));
});

test('Copies created from a draft start with no completion history and leave source untouched', () => {
  const source = S.create(draft({ stepsText: '一步\n二步', startMinute: 600, durationMinutes: 45, dueAt: date('2026-10-10') }), 'a', 1);
  source.completed = true; source.doneSteps = [0, 1];
  const copy = S.create(draft({ title: source.title, note: source.note, stepsText: source.steps.join('\n'),
    dueAt: source.dueAt, startMinute: source.startMinute, durationMinutes: source.durationMinutes }), 'b', 2);
  assert.equal(copy.completed, false); assert.deepEqual(plain(copy.doneSteps), []);
  assert.equal(source.completed, true); assert.deepEqual(plain(source.doneSteps), [0, 1]);
});

test('Quick entry parses explicit clock and duration with a reviewable date', () => {
  const now = new Date(2026, 9, 10, 8).getTime();
  const parsed = Quick.parse('明天 14:30 交报告 用时60分钟 #学习 高优先级', now);
  assert.equal(parsed.title, '交报告'); assert.equal(parsed.startMinute, 870); assert.equal(parsed.durationMinutes, 60);
  assert.equal(Calendar.key(parsed.dueAt), '2026-10-11'); assert.equal(parsed.priority, 2);
  assert.equal(Calendar.key(Quick.parse('09:00 开会', now).dueAt), '2026-10-10');
  assert.throws(() => Quick.parse('明天 25:00 开会', now));
  assert.throws(() => S.create(Quick.parse('明天 23:50 开会 用时60分钟', now), 'x', now));
});

const timed = (id, start, duration = 30, repeat = 'none', day = '2026-10-10') =>
  S.create(draft({ title: id, dueAt: date(day), startMinute: start, durationMinutes: duration, repeat }), id, 1);

test('Conflict checks detect overlap but allow touching intervals and ignore completed or all-day tasks', () => {
  const own = timed('a', 600, 60);
  const candidates = [timed('b', 630), timed('c', 660), timed('d', 570),
    S.withCompletion(timed('done', 610), true, 2), S.create(draft({ dueAt: date('2026-10-10') }), 'all-day', 1), own];
  assert.deepEqual(plain(Calendar.conflicts(own, candidates, [], date('2026-10-10')).map(x => x.title)), ['b']);
});

test('Recurring conflict checks respect individual skipped/completed dates and rule changes', () => {
  const own = timed('a', 600, 30, 'daily');
  const other = timed('b', 610, 30, 'daily');
  const states = [state('b', '2026-10-10', false, true), state('b', '2026-10-11'), state('a', '2026-10-12')];
  const conflicts = Calendar.conflicts(own, [own, other], states, date('2026-10-10'));
  assert.equal(conflicts[0].dateKey, '2026-10-13'); assert.equal(conflicts.length, 5);
  const moved = { ...own, dueAt: date('2026-10-12') };
  assert.equal(Calendar.conflicts(moved, [own, other], states, date('2026-10-10'))[0].dateKey, '2026-10-12');
});

test('Recurring checklist state projects independently on each date', () => {
  const task = S.create(draft({ repeat: 'daily', dueAt: date('2026-10-10'), stepsText: '读\n写' }), 'r', 1);
  const states = [{ ...state('r', '2026-10-10', false), doneSteps: [0] }];
  assert.deepEqual(plain(Calendar.item(task, '2026-10-10', states).doneSteps), [0]);
  assert.deepEqual(plain(Calendar.item(task, '2026-10-11', states).doneSteps), []);
});

test('Old database records acquire safe defaults and rich details survive a new repository instance', async () => {
  const f = repositoryFixture(); await f.repo.load(f.context);
  const old = makeRepeat('daily', '2026-10-10'); delete old.startMinute; delete old.durationMinutes; delete old.steps; delete old.doneSteps;
  await f.repo.save(old); f.db.prepare('DELETE FROM task_details').run();
  let [task] = await f.newRepo().load(f.context);
  assert.equal(task.startMinute, -1); assert.deepEqual(plain(task.steps), []);
  const rich = S.edit(task, draft({ repeat: 'daily', dueAt: task.dueAt, startMinute: 600, durationMinutes: 45, stepsText: '读\n写' }), 2);
  await f.repo.save(rich);
  await f.repo.setOccurrence({ ...state('r', '2026-10-10', false), doneSteps: [1] });
  const repo = f.newRepo(); [task] = await repo.load(f.context);
  assert.equal(task.startMinute, 600); assert.equal(task.durationMinutes, 45); assert.deepEqual(plain(task.steps), ['读', '写']);
  assert.deepEqual(plain((await repo.getOccurrences())[0].doneSteps), [1]); f.db.close();
});

test('Changing checklist template resets dated step progress but preserves completion; time-only edit preserves both', async () => {
  const f = repositoryFixture(); await f.repo.load(f.context);
  let task = S.create(draft({ repeat: 'daily', dueAt: date('2026-10-10'), stepsText: '读\n写' }), 'r', 1);
  await f.repo.save(task); await f.repo.setOccurrence({ ...state('r', '2026-10-10'), doneSteps: [0] });
  task = S.edit(task, draft({ repeat: 'daily', dueAt: task.dueAt, stepsText: '读\n写', startMinute: 600 }), 2);
  await f.repo.save(task); assert.deepEqual(plain((await f.repo.getOccurrences())[0].doneSteps), [0]);
  task = S.edit(task, draft({ repeat: 'daily', dueAt: task.dueAt, stepsText: '新步骤', startMinute: 600 }), 3);
  await f.repo.save(task); const states = await f.repo.getOccurrences();
  assert.equal(states[0].completed, true); assert.deepEqual(plain(states[0].doneSteps), []); f.db.close();
});

test('Occurrence and checklist writes roll back together on a disk error', async () => {
  const f = repositoryFixture(); await f.repo.load(f.context);
  await f.repo.save(S.create(draft({ repeat: 'daily', dueAt: date('2026-10-10'), stepsText: '读' }), 'r', 1));
  await f.repo.setOccurrence({ ...state('r', '2026-10-10', false), doneSteps: [] });
  f.fail('INSERT OR REPLACE INTO task_step_states');
  await assert.rejects(() => f.repo.setOccurrence({ ...state('r', '2026-10-10'), doneSteps: [0] })); f.fail('');
  const [result] = await f.repo.getOccurrences(); assert.equal(result.completed, false); assert.deepEqual(plain(result.doneSteps), []); f.db.close();
});

test('Batch completion preserves checklist progress and affects only selected repeat dates', async () => {
  const f = repositoryFixture(); await f.repo.load(f.context);
  const single = S.create(draft({ stepsText: '写' }), 'a', 1); single.doneSteps = [0];
  const series = S.create(draft({ repeat: 'daily', dueAt: date('2026-10-10'), stepsText: '读' }), 'r', 1);
  await f.repo.save(single); await f.repo.save(series);
  const states = [{ ...state('r', '2026-10-10', false), doneSteps: [0] }];
  await f.repo.setOccurrence(states[0]);
  const items = [Calendar.item(single, '', states), Calendar.item(series, '2026-10-10', states)];
  await f.repo.setCompleted(items, true, 2);
  assert.equal((await f.repo.reload()).find(t => t.id === 'a').completed, true);
  assert.deepEqual(plain((await f.repo.reload()).find(t => t.id === 'a').doneSteps), [0]);
  const updated = await f.repo.getOccurrences(); assert.equal(updated[0].completed, true); assert.deepEqual(plain(updated[0].doneSteps), [0]);
  assert.equal(Calendar.item(series, '2026-10-11', updated).completed, false);
  await f.repo.setCompleted(items, false, 3); assert.equal((await f.repo.getOccurrences())[0].completed, false); f.db.close();
});

test('Batch completion is atomic across ordinary and repeated tasks', async () => {
  const f = repositoryFixture(); await f.repo.load(f.context);
  const a = S.create(draft(), 'a', 1), r = makeRepeat('daily', '2026-10-10');
  await f.repo.save(a); await f.repo.save(r);
  f.fail('INSERT OR REPLACE INTO task_step_states');
  await assert.rejects(() => f.repo.setCompleted([Calendar.item(a, '', []), Calendar.item(r, '2026-10-10', [])], true, 2));
  f.fail(''); assert.equal((await f.repo.reload()).find(t => t.id === 'a').completed, false);
  assert.equal((await f.repo.getOccurrences()).length, 0); f.db.close();
});

test('Version 4 backups preserve time and checklists; version 3 still imports with defaults', async () => {
  const f = repositoryFixture(); await f.repo.load(f.context);
  const task = S.create(draft({ repeat: 'daily', dueAt: date('2026-10-10'), startMinute: 720, stepsText: '读\n写' }), 'r', 1);
  const doc = Backup.decode(Backup.encode([task], [{ ...state('r', '2026-10-10'), doneSteps: [1] }], 100));
  assert.equal(doc.version, 4); await f.repo.mergeBackup(doc);
  assert.equal((await f.repo.reload())[0].startMinute, 720); assert.deepEqual(plain((await f.repo.getOccurrences())[0].doneSteps), [1]);
  const old = { ...makeRepeat('weekly', '2026-10-12', 'old') };
  for (const key of ['startMinute', 'durationMinutes', 'steps', 'doneSteps']) delete old[key];
  await f.repo.mergeBackup(Backup.decode(JSON.stringify({ format: 'TaiPlanHarmony', version: 3, exportedAt: 100, tasks: [old], occurrences: [] })));
  assert.equal((await f.repo.reload()).find(t => t.id === 'old').startMinute, -1); f.db.close();
});

test('Backup rejects malformed time and checklist state instead of storing invalid indices', () => {
  const task = S.create(draft({ repeat: 'daily', dueAt: date('2026-10-10'), stepsText: '读' }), 'r', 1);
  for (const patch of [{ steps: null }, { steps: [''] }, { steps: ['a\nb'] }, { startMinute: null }, { durationMinutes: '30' }, { doneSteps: null }, { doneSteps: [0] }]) {
    assert.throws(() => Backup.encode([{ ...task, ...patch }], [], 100));
  }
  for (const doneSteps of [null, [1], [-1], [0, 0], ['0']]) {
    assert.throws(() => Backup.encode([task], [{ ...state('r', '2026-10-10'), doneSteps }], 100));
  }
});

test('Deleting a rich task removes both new detail tables as well as old records', async () => {
  const f = repositoryFixture(); await f.repo.load(f.context);
  await f.repo.save(S.create(draft({ repeat: 'daily', dueAt: date('2026-10-10'), stepsText: '读' }), 'r', 1));
  await f.repo.setOccurrence({ ...state('r', '2026-10-10'), doneSteps: [0] }); await f.repo.remove('r');
  for (const table of ['tasks', 'task_tags', 'task_options', 'task_occurrences', 'task_details', 'task_step_states']) {
    assert.equal(f.db.prepare('SELECT COUNT(*) AS n FROM ' + table).get().n, 0);
  }
  f.db.close();
});
test('Time sorting orders intervals by start, then all-day tasks, and places undated tasks last', () => {
  const a = timed('early', 540, 120), b = timed('later', 600, 10);
  const c = S.create(draft({ dueAt: date('2026-10-10') }), 'all-day', 3), d = S.create(draft(), 'undated', 4);
  const items = Calendar.project([d, c, b, a], [], 'all', '', date('2026-10-10'));
  assert.deepEqual(plain(Calendar.filter(items, false, '', '', 'time').map(i => i.task.id)), ['early', 'later', 'all-day', 'undated']);
  a.priority = 2;
  assert.equal(Calendar.filter(items, false, '', '', 'priority')[0].task.id, 'early');
});

test('New sorting preferences survive reload and reject unrecognized modes', async () => {
  const f = repositoryFixture(); await f.repo.load(f.context);
  await f.repo.setSortMode('time'); const repo = f.newRepo(); await repo.load(f.context); assert.equal(await repo.getSortMode(), 'time');
  await assert.rejects(() => repo.setSortMode('bad')); assert.equal(await repo.getSortMode(), 'time'); f.db.close();
});
const { IcsService: Ics } = loadModule('services/IcsService.ets');
const ics = events => 'BEGIN:VCALENDAR\r\nVERSION:2.0\r\n' + events.map(lines => 'BEGIN:VEVENT\r\n' + lines.join('\r\n') + '\r\nEND:VEVENT\r\n').join('') + 'END:VCALENDAR\r\n';

test('ICS parses escaped/folded text, floating time and Shanghai/UTC timezone conversion', () => {
  const raw = ics([['UID:calendar-1', 'SUMMARY:中文\\,报告', 'DESCRIPTION:第一行\\n第二行', 'DTSTART;TZID=Asia/Shanghai:20261011T143000', 'DTEND:20261011T073000Z', 'PRIORITY:1'],
    ['UID:calendar-2', 'SUMMARY:Folded ', ' title', 'DTSTART:20261011T100000', 'DTEND:20261011T103000']]);
  const report = Ics.parse(raw, 100); assert.equal(report.document.tasks.length, 2); assert.equal(report.notes.length, 0);
  const a = report.document.tasks[0]; assert.equal(a.title, '中文,报告'); assert.equal(a.note, '第一行\n第二行');
  const local = new Date('2026-10-11T06:30:00Z');
  assert.equal(a.startMinute, local.getHours() * 60 + local.getMinutes()); assert.equal(a.durationMinutes, 60); assert.equal(a.priority, 2);
  assert.equal(report.document.tasks[1].title, 'Folded title');
});

test('ICS reports each unsupported or invalid event and deduplicates UID without silently changing its meaning', () => {
  const base = ['UID:u', 'SUMMARY:任务', 'DTSTART;VALUE=DATE:20261011', 'DTEND;VALUE=DATE:20261012'];
  const report = Ics.parse(ics([base, base, [...base, 'RRULE:FREQ=DAILY'],
    ['UID:z', 'SUMMARY:时区', 'DTSTART;TZID=Unknown/Zone:20261011T100000'],
    ['UID:x', 'SUMMARY:跨日', 'DTSTART:20261011T233000', 'DTEND:20261012T003000'],
    ['UID:s', 'SUMMARY:秒数', 'DTSTART:20261011T100030'], [...base, 'STATUS:CANCELLED']]), 100);
  assert.equal(report.document.tasks.length, 1); assert.equal(report.notes.length, 6);
  assert.match(report.notes.join('\n'), /UID 重复/); assert.match(report.notes.join('\n'), /RRULE/);
  assert.throws(() => Ics.parse('BEGIN:VCALENDAR\nBEGIN:VEVENT\nEND:VCALENDAR', 100));
});

test('ICS export is a bounded snapshot, folds UTF-8 lines and preserves date/time/completion on reimport', () => {
  const now = new Date(2026, 9, 10, 8).getTime();
  const recurring = S.create(draft({ title: '中文🥰'.repeat(18), repeat: 'daily', dueAt: date('2026-10-10'),
    startMinute: 870, durationMinutes: 60, stepsText: '读\n写' }), 'repeat', now);
  const raw = Ics.exportMonth([recurring], [{ ...state('repeat', '2026-10-10'), doneSteps: [0] }, state('repeat', '2026-10-11', false, true)], now);
  for (const line of raw.split('\r\n')) assert.ok(Buffer.byteLength(line) <= 75);
  const report = Ics.parse(raw, now); assert.equal(report.notes.length, 0); assert.equal(report.document.tasks.length, 29);
  const first = report.document.tasks[0]; assert.equal(first.title, recurring.title); assert.equal(first.startMinute, 870);
  assert.equal(first.durationMinutes, 60); assert.equal(first.completed, true); assert.match(first.note, /\[x\] 读/);
  assert.equal(report.document.tasks.at(-1).dueAt, date('2026-11-08'));
});

test('ICS import uses ordinary backup merge and remains idempotent across repeat file selection', async () => {
  const f = repositoryFixture(); await f.repo.load(f.context);
  const doc = Ics.parse(ics([['UID:same', 'SUMMARY:日历事项', 'DTSTART;VALUE=DATE:20261011']]), 100).document;
  assert.equal(await f.repo.mergeBackup(doc), 1); assert.equal(await f.repo.mergeBackup(doc), 0); f.db.close();
});

const { convertRows, transfer } = require('../tools/desktop-transfer.cjs');
const desktopRow = (overrides = {}) => ({ id: 1, title: '桌面任务 🥰', description: '原备注', url: 'https://example.com', date: '2026-10-11',
  time: '09:30', priority: 'urgent', is_completed: 0, created_at: '2026-10-01 10:00:00', updated_at: '2026-10-02 11:00:00',
  is_recurring: 0, recurrence_frequency: null, recurrence_interval: 1, recurrence_end_type: null, recurrence_end_date: null,
  recurrence_stop_before: null, duration_minutes: 60, ...overrides });

test('Desktop transfer retains ordinary fields and creates a valid Harmony backup', () => {
  const result = convertRows([desktopRow({ is_completed: 1 })], [], [], 'my-desktop', 100);
  const task = Backup.decode(JSON.stringify(result.document)).tasks[0];
  assert.equal(task.id, 'desktop:my-desktop:1'); assert.equal(task.startMinute, 570); assert.equal(task.durationMinutes, 60);
  assert.equal(task.completed, true); assert.equal(task.priority, 2); assert.match(task.note, /原备注\n链接：https/);
  assert.equal(result.report.skippedSourceTasks, 0);
});

test('Desktop recurrence completion, cancellations and moved occurrences retain their meaning', () => {
  const row = desktopRow({ is_recurring: 1, recurrence_frequency: 'daily', recurrence_end_type: 'never' });
  const states = [{ task_id: 1, occurrence_key: '2026-10-11T09:30', status: 'completed' },
    { task_id: 1, occurrence_key: '2026-10-12T09:30', status: 'cancelled' }];
  const overrides = [{ task_id: 1, occurrence_key: '2026-10-11T09:30', override_date: '2026-10-13', override_time: '14:00', override_duration_minutes: 45 }];
  const result = convertRows([row], states, overrides, 'desk', 100);
  const doc = Backup.decode(JSON.stringify(result.document));
  assert.equal(doc.tasks.length, 2); assert.equal(doc.tasks[0].repeat, 'daily');
  assert.equal(doc.tasks[1].completed, true); assert.equal(doc.tasks[1].startMinute, 840); assert.equal(doc.tasks[1].durationMinutes, 45);
  assert.equal(doc.tasks[1].dueAt, date('2026-10-13')); assert.equal(doc.occurrences.every(s => s.skipped), true);
});

test('Unsupported desktop series and invalid moved records are reported as a whole, never silently flattened', () => {
  const unsupported = desktopRow({ id: 1, is_recurring: 1, recurrence_frequency: 'weekly', recurrence_interval: 2 });
  const finite = desktopRow({ id: 2, is_recurring: 1, recurrence_frequency: 'daily', recurrence_end_type: 'on_date', recurrence_end_date: '2026-11-01' });
  const invalidMove = desktopRow({ id: 3, is_recurring: 1, recurrence_frequency: 'monthly' });
  const result = convertRows([unsupported, finite, invalidMove], [], [{ task_id: 3, occurrence_key: '2026-10-12T09:30', override_date: '2026-10-14' }], 'desk', 100);
  assert.equal(result.document.tasks.length, 0); assert.equal(result.report.skippedSourceTasks, 3); assert.equal(result.report.notes.length, 3);
});

test('Desktop SQLite conversion works on a copied snapshot, preserves source hash, and refuses overwrites/WAL', () => {
  const dir = fs.mkdtempSync(path.join(__dirname, '.transfer-test-'));
  const input = path.join(dir, 'desktop.db'), output = path.join(dir, 'harmony.json');
  try {
    const db = new DatabaseSync(input);
    db.exec('CREATE TABLE tasks(id INTEGER PRIMARY KEY,title TEXT,description TEXT,url TEXT,date TEXT,time TEXT,priority TEXT,is_completed INTEGER,created_at TEXT,updated_at TEXT,duration_minutes INTEGER)');
    db.prepare('INSERT INTO tasks VALUES (?,?,?,?,?,?,?,?,?,?,?)').run(1, '真实 SQLite 测试', '中文', null, '2026-10-11', '09:30', 'normal', 0, '2026-10-01 10:00:00', '2026-10-01 10:00:00', 45); db.close();
    const original = fs.readFileSync(input);
    const result = transfer(input, output, 'fixture'); assert.equal(result.outputTasks, 1);
    assert.deepEqual(fs.readFileSync(input), original); assert.equal(fs.existsSync(input + '-shm'), false);
    assert.equal(Backup.decode(fs.readFileSync(output, 'utf8')).tasks[0].durationMinutes, 45);
    assert.throws(() => transfer(input, output, 'fixture'), /已存在/);
    fs.writeFileSync(input + '-wal', 'simulated');
    assert.throws(() => transfer(input, path.join(dir, 'other.json'), 'fixture'), /WAL/);
    assert.equal(fs.readdirSync(dir).some(name => name.startsWith('.taiplan-transfer-')), false);
  } finally {
    const real = fs.realpathSync(dir);
    if (path.dirname(real) === fs.realpathSync(__dirname) && path.basename(real).startsWith('.transfer-test-')) fs.rmSync(real, { recursive: true });
  }
});