import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { preferences, relationalStore } from '@kit.ArkData';
import { Task } from '../model/Task';
import { TaskService } from '../services/TaskService';

export class TaskRepository {
  private store: relationalStore.RdbStore | undefined = undefined;
  private settings: preferences.Preferences | undefined = undefined;

  async load(context: common.UIAbilityContext): Promise<Task[]> {
    this.settings = await preferences.getPreferences(context, { name: 'taiplan_settings' });
    const theme = await this.settings.get('theme', 'system');
    TaskRepository.applyTheme(context, typeof theme === 'string' ? theme : 'system');
    const db = await relationalStore.getRdbStore(context, {
      name: 'taiplan.db', securityLevel: relationalStore.SecurityLevel.S1
    });
    this.store = db;
    await db.executeSql('CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
    await db.executeSql('CREATE TABLE IF NOT EXISTS tasks (id TEXT PRIMARY KEY, title TEXT NOT NULL, note TEXT NOT NULL, completed INTEGER NOT NULL CHECK(completed IN (0,1)), created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, priority INTEGER NOT NULL CHECK(priority IN (0,1,2)), due_at INTEGER NOT NULL DEFAULT 0)');
    await db.executeSql('CREATE TABLE IF NOT EXISTS task_tags (task_id TEXT NOT NULL, tag TEXT NOT NULL, PRIMARY KEY(task_id, tag))');
    await db.executeSql('CREATE INDEX IF NOT EXISTS idx_tasks_created ON tasks(created_at DESC)');
    await this.migrate(context, db);
    return this.readTasks(db);
  }

  private async migrate(context: common.UIAbilityContext, db: relationalStore.RdbStore): Promise<void> {
    const meta = await db.querySql("SELECT value FROM metadata WHERE key = 'legacy_import'");
    let migrated = false;
    try { migrated = meta.rowCount > 0; } finally { meta.close(); }
    if (migrated) { return; }
    const legacy = await preferences.getPreferences(context, { name: 'taiplan_tasks_v1' });
    const raw = await legacy.get('document', '');
    if (typeof raw !== 'string') { throw new Error('旧版任务格式错误'); }
    const tasks = TaskService.migrateLegacy(raw);
    db.beginTransaction();
    try {
      for (const task of tasks) { await this.writeTask(db, task); }
      await db.executeSql("INSERT INTO metadata(key,value) VALUES ('legacy_import','1')");
      db.commit();
    } catch (error) {
      db.rollBack();
      throw error as Error;
    }
    // 保留旧版 Preferences；迁移标记和全部数据在同一事务中提交。
  }

  private async readTasks(db: relationalStore.RdbStore): Promise<Task[]> {
    const tasks: Task[] = [];
    const rows = await db.querySql('SELECT * FROM tasks ORDER BY created_at DESC, id DESC');
    try {
      while (rows.goToNextRow()) {
        tasks.push({ id: rows.getString(rows.getColumnIndex('id')),
          title: rows.getString(rows.getColumnIndex('title')), note: rows.getString(rows.getColumnIndex('note')),
          completed: rows.getLong(rows.getColumnIndex('completed')) === 1,
          createdAt: rows.getLong(rows.getColumnIndex('created_at')), updatedAt: rows.getLong(rows.getColumnIndex('updated_at')),
          priority: rows.getLong(rows.getColumnIndex('priority')), dueAt: rows.getLong(rows.getColumnIndex('due_at')), tags: [] });
      }
    } finally { rows.close(); }
    const tagRows = await db.querySql('SELECT task_id, tag FROM task_tags ORDER BY tag');
    try {
      while (tagRows.goToNextRow()) {
        const id = tagRows.getString(0);
        const tag = tagRows.getString(1);
        const task = tasks.find((item: Task) => item.id === id);
        if (task) { task.tags.push(tag); }
      }
    } finally { tagRows.close(); }
    return tasks;
  }

  private async writeTask(db: relationalStore.RdbStore, task: Task): Promise<void> {
    await db.executeSql('INSERT OR REPLACE INTO tasks(id,title,note,completed,created_at,updated_at,priority,due_at) VALUES (?,?,?,?,?,?,?,?)',
      [task.id, task.title, task.note, task.completed ? 1 : 0, task.createdAt, task.updatedAt, task.priority, task.dueAt]);
    await db.executeSql('DELETE FROM task_tags WHERE task_id = ?', [task.id]);
    for (const tag of task.tags) { await db.executeSql('INSERT INTO task_tags(task_id,tag) VALUES (?,?)', [task.id, tag]); }
  }

  async save(task: Task): Promise<void> {
    const db = this.store;
    if (!db) { throw new Error('数据库尚未就绪'); }
    db.beginTransaction();
    try { await this.writeTask(db, task); db.commit(); }
    catch (error) { db.rollBack(); throw error as Error; }
  }

  async remove(id: string): Promise<void> {
    const db = this.store;
    if (!db) { throw new Error('数据库尚未就绪'); }
    db.beginTransaction();
    try {
      await db.executeSql('DELETE FROM task_tags WHERE task_id = ?', [id]);
      await db.executeSql('DELETE FROM tasks WHERE id = ?', [id]);
      db.commit();
    } catch (error) { db.rollBack(); throw error as Error; }
  }

  async getTheme(): Promise<string> {
    const value = await this.settings?.get('theme', 'system');
    return typeof value === 'string' ? value : 'system';
  }

  async setTheme(context: common.UIAbilityContext, theme: string): Promise<void> {
    if (!this.settings) { throw new Error('设置尚未就绪'); }
    await this.settings.put('theme', theme);
    await this.settings.flush();
    TaskRepository.applyTheme(context, theme);
  }

  private static applyTheme(context: common.UIAbilityContext, theme: string): void {
    const mode = theme === 'dark' ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK :
      theme === 'light' ? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT : ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
    context.getApplicationContext().setColorMode(mode);
  }
}
