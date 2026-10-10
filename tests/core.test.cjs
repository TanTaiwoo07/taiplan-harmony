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
  assert.deepEqual(plain(task), { ...legacyTask, priority: 1, tags: [], dueAt: 0 });
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
