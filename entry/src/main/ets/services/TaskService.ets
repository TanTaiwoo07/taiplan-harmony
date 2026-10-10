import { LegacyDocument, LegacyTask, Task, TaskDraft } from '../model/Task';

// 纯业务函数不依赖 ArkUI 或数据库，跨平台可用相同案例验证。
export class TaskService {
  static parseTags(text: string): string[] {
    const tags: string[] = [];
    for (const part of text.split(/[,，、\n]/)) {
      const tag = part.trim();
      if (tag.length === 0 || tags.includes(tag)) { continue; }
      if (tag.length > 12) { throw new Error('每个标签最多 12 字'); }
      tags.push(tag);
    }
    if (tags.length > 5) { throw new Error('每个任务最多添加 5 个标签'); }
    return tags;
  }
  static create(draft: TaskDraft, id: string, now: number): Task {
    const title = draft.title.trim();
    if (title.length === 0 || title.length > 100) { throw new Error('请输入 1～100 字的任务标题'); }
    if (draft.note.length > 1000) { throw new Error('备注最多 1000 字'); }
    if (![0, 1, 2].includes(draft.priority)) { throw new Error('请选择有效的优先级'); }
    if (!Number.isFinite(draft.dueAt) || draft.dueAt < 0) { throw new Error('截止日期无效'); }
    return { id: id, title: title, note: draft.note.trim(), completed: false,
      createdAt: now, updatedAt: now, priority: draft.priority,
      tags: TaskService.parseTags(draft.tagsText), dueAt: draft.dueAt };
  }
  static edit(task: Task, draft: TaskDraft, now: number): Task {
    const next = TaskService.create(draft, task.id, task.createdAt);
    next.completed = task.completed;
    next.updatedAt = now;
    return next;
  }
  static toggle(task: Task, now: number): Task {
    return { id: task.id, title: task.title, note: task.note, completed: !task.completed,
      createdAt: task.createdAt, updatedAt: now, priority: task.priority,
      tags: task.tags.slice(), dueAt: task.dueAt };
  }
  static section(tasks: Task[], completed: boolean, query: string = '', tag: string = ''): Task[] {
    const keyword = query.trim().toLocaleLowerCase();
    return tasks.filter((task: Task) => task.completed === completed &&
      (tag.length === 0 || task.tags.includes(tag)) &&
      (keyword.length === 0 || `${task.title}\n${task.note}\n${task.tags.join(' ')}`.toLocaleLowerCase().includes(keyword)))
      .sort((a: Task, b: Task) => b.createdAt - a.createdAt || b.id.localeCompare(a.id));
  }
  static allTags(tasks: Task[]): string[] {
    const tags: string[] = [];
    for (const task of tasks) {
      for (const tag of task.tags) { if (!tags.includes(tag)) { tags.push(tag); } }
    }
    return tags.sort((a: string, b: string) => a.localeCompare(b));
  }
  static priorityLabel(priority: number): string { return ['低', '中', '高'][priority]; }
  static dateLabel(dueAt: number): string {
    if (dueAt === 0) { return '不设置截止日期'; }
    const date = new Date(dueAt);
    return `${date.getFullYear()}/${date.getMonth() + 1}/${date.getDate()}`;
  }
  static endOfDay(year: number, month: number, day: number): number {
    return new Date(year, month, day, 23, 59, 59, 999).getTime();
  }
  static isOverdue(task: Task, now: number): boolean {
    return !task.completed && task.dueAt > 0 && task.dueAt < now;
  }
  static migrateLegacy(raw: string): Task[] {
    if (raw.length === 0) { return []; }
    const document = JSON.parse(raw) as LegacyDocument;
    if (!document || document.version !== 1 || !Array.isArray(document.tasks)) {
      throw new Error('旧版任务数据格式不兼容');
    }
    const ids: string[] = [];
    const result: Task[] = [];
    for (const task of document.tasks) {
      TaskService.validateLegacy(task, ids);
      ids.push(task.id);
      result.push({ id: task.id, title: task.title, note: task.note, completed: task.completed,
        createdAt: task.createdAt, updatedAt: task.updatedAt, priority: 1, tags: [], dueAt: 0 });
    }
    return result;
  }
  private static validateLegacy(task: LegacyTask, ids: string[]): void {
    if (!task || typeof task.id !== 'string' || task.id.length === 0 || ids.includes(task.id) ||
      typeof task.title !== 'string' || task.title.trim().length === 0 || task.title.length > 100 ||
      typeof task.note !== 'string' || task.note.length > 1000 || typeof task.completed !== 'boolean' ||
      typeof task.createdAt !== 'number' || !Number.isFinite(task.createdAt) ||
      typeof task.updatedAt !== 'number' || !Number.isFinite(task.updatedAt)) {
      throw new Error('旧版任务数据损坏，迁移已停止');
    }
  }
}
