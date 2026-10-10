import { PlanningService } from './PlanningService';
import { LegacyDocument, LegacyTask, Task, TaskDraft } from '../model/Task';

// 纯业务函数不依赖 ArkUI 或数据库，跨平台可用相同案例验证。
export class TaskService {
  static parseSteps(text: string): string[] {
    const steps = text.split('\n').map((line: string) => line.trim()).filter((line: string) => line.length > 0);
    if (steps.length > 20 || steps.some((line: string) => line.length > 100)) { throw new Error('子任务最多 20 项，每项最多 100 字'); }
    return steps;
  }
  static minuteLabel(minute: number): string {
    return `${Math.floor(minute / 60).toString().padStart(2, '0')}:${(minute % 60).toString().padStart(2, '0')}`;
  }
  static timeLabel(task: Task): string {
    const start = task.startMinute ?? -1;
    return start < 0 ? (task.planning?.kind === 'event' ? '全天' : '未指定时间') : `${TaskService.minuteLabel(start)}–${((start + (task.durationMinutes ?? 30)) >= 1440 ? '次日 ' : '') + TaskService.minuteLabel((start + (task.durationMinutes ?? 30)) % 1440)}`;
  }
  static deadline(task: Task, day: number): number {
    if (task.planning) { return PlanningService.deadline(task, day); }
    if (day === 0 || (task.startMinute ?? -1) < 0) { return day; }
    const date = new Date(day);
    date.setHours(0, (task.startMinute ?? 0) + (task.durationMinutes ?? 30), 0, 0);
    return date.getTime();
  }
  static toggleStep(done: number[], index: number, count: number): number[] {
    if (!Number.isInteger(index) || index < 0 || index >= count) { throw new Error('子任务不存在'); }
    return done.includes(index) ? done.filter((value: number) => value !== index) : done.concat([index]).sort((a: number, b: number) => a - b);
  }
  static validateDone(done: number[], count: number): void {
    if (!Array.isArray(done) || done.some((index: number) => !Number.isInteger(index) || index < 0 || index >= count) ||
      new Set<number>(done).size !== done.length) { throw new Error('子任务进度无效'); }
  }
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
    if (!Number.isFinite(draft.dueAt) || draft.dueAt < 0 || draft.dueAt > 4133980799999) { throw new Error('截止日期无效'); }
    const repeat = draft.repeat ?? 'none';
    if (!['none', 'daily', 'weekly', 'monthly', 'yearly'].includes(repeat)) { throw new Error('重复规则无效'); }
    if (repeat !== 'none' && draft.dueAt === 0) { throw new Error('请先选择重复任务的起始日期'); }
    const start = draft.startMinute ?? -1;
    const duration = draft.durationMinutes ?? 30;
    if (!Number.isInteger(start) || start < -1 || start > 1439 || !Number.isInteger(duration) || duration < 5 || duration > 1440) {
      throw new Error('开始时间无效，时长需为 5～1440 分钟');
    }
    if (start >= 0 && (draft.dueAt === 0 || (!draft.planning && start + duration > 1440))) { throw new Error('请先选择日期，且时间安排不能跨过当天 24:00'); }
    if (draft.planning !== undefined) { PlanningService.validate(draft.planning, draft.dueAt, start, duration, repeat); }
    const result: Task = { id: id, title: title, note: draft.note.trim(), completed: false,
      createdAt: now, updatedAt: now, priority: draft.priority,
      tags: TaskService.parseTags(draft.tagsText), dueAt: draft.dueAt, repeat: repeat, sortOrder: -now,
      startMinute: start, durationMinutes: duration, steps: TaskService.parseSteps(draft.stepsText ?? ''), doneSteps: [] };
    if (draft.planning) { result.planning = JSON.parse(JSON.stringify(draft.planning)); }
    return result;
  }
  static edit(task: Task, draft: TaskDraft, now: number): Task {
    const effective: TaskDraft = { title: draft.title, note: draft.note, priority: draft.priority,
      tagsText: draft.tagsText, dueAt: draft.dueAt, repeat: draft.repeat, startMinute: draft.startMinute,
      durationMinutes: draft.durationMinutes, stepsText: draft.stepsText, planning: draft.planning };
    if (task.planning && draft.planning === undefined) {
      const plan = PlanningService.forTask(task);
      const updated = PlanningService.create(draft.dueAt, draft.startMinute ?? -1, draft.durationMinutes ?? 30, plan.kind);
      plan.scheduleMode = updated.scheduleMode; plan.plannedDate = updated.plannedDate;
      plan.startAt = updated.startAt; plan.endAt = updated.endAt;
      if ((draft.repeat ?? 'none') === 'none') { plan.rule = PlanningService.emptyRule(); }
      effective.planning = plan;
    }
    const next = TaskService.create(effective, task.id, task.createdAt);
    next.completed = PlanningService.isEvent(next) ? false : task.completed;
    next.updatedAt = now;
    next.sortOrder = task.sortOrder;
    if (task.overrides) { next.overrides = JSON.parse(JSON.stringify(task.overrides)); }
    if (JSON.stringify(next.steps) === JSON.stringify(task.steps ?? [])) { next.doneSteps = (task.doneSteps ?? []).slice(); }
    if (next.repeat !== 'none') { next.completed = false; next.doneSteps = []; }
    return next;
  }
  static toggle(task: Task, now: number): Task {
    return TaskService.withCompletion(task, !task.completed, now);
  }
  static withCompletion(task: Task, completed: boolean, now: number): Task {
    const result: Task = { id: task.id, title: task.title, note: task.note, completed: completed,
      createdAt: task.createdAt, updatedAt: now, priority: task.priority,
      tags: task.tags.slice(), dueAt: task.dueAt, repeat: task.repeat, sortOrder: task.sortOrder,
      startMinute: task.startMinute ?? -1, durationMinutes: task.durationMinutes ?? 30,
      steps: (task.steps ?? []).slice(), doneSteps: (task.doneSteps ?? []).slice() };
    if (task.planning) { result.planning = PlanningService.forTask(task); }
    if (task.overrides) { result.overrides = JSON.parse(JSON.stringify(task.overrides)); }
    return result;
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
    if (dueAt === 0) { return '未安排日期'; }
    const date = new Date(dueAt);
    return `${date.getFullYear()}/${date.getMonth() + 1}/${date.getDate()}`;
  }
  static endOfDay(year: number, month: number, day: number): number {
    return new Date(year, month, day, 23, 59, 59, 999).getTime();
  }
  static isOverdue(task: Task, now: number): boolean {
    return PlanningService.overdue(task, task.dueAt, task.completed, now);
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
        createdAt: task.createdAt, updatedAt: task.updatedAt, priority: 1, tags: [], dueAt: 0,
        repeat: 'none', sortOrder: -task.createdAt });
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
