import { Task, TaskDraft, OccurrenceOverride } from '../model/Task';
import { TaskService } from './TaskService';
import { PlanningService } from './PlanningService';
import { RecurrenceService } from './RecurrenceService';

// Identity is always series id + ORIGINAL civil date, even after moving to another day.
export class OccurrenceService {
  static draft(task: Task): TaskDraft {
    return { title: task.title, note: task.note, priority: task.priority, tagsText: task.tags.join(','),
      dueAt: task.dueAt, repeat: task.repeat, startMinute: task.startMinute, durationMinutes: task.durationMinutes,
      stepsText: (task.steps ?? []).join('\n'), planning: PlanningService.forTask(task) };
  }
  static validate(task: Task): void {
    if (task.overrides === undefined) { return; }
    if (!Array.isArray(task.overrides) || task.overrides.length > 5000 || (task.repeat === 'none' && task.overrides.length > 0)) { throw new Error('重复例外格式无效'); }
    const keys = new Set<string>();
    for (const entry of task.overrides) {
      if (!entry || typeof entry.originalDate !== 'string' || !RecurrenceService.matches(task, entry.originalDate) ||
        keys.has(entry.originalDate) || !Number.isSafeInteger(entry.updatedAt) || entry.updatedAt < 0 || !entry.draft ||
        entry.draft.repeat !== 'none' || entry.draft.dueAt <= 0) { throw new Error('重复例外的原日期或内容无效'); }
      TaskService.create(entry.draft, task.id, task.createdAt); keys.add(entry.originalDate);
    }
  }
  static effective(task: Task, originalDate: string): Task {
    const entry = task.overrides?.find((item: OccurrenceOverride) => item.originalDate === originalDate);
    if (!entry) { return task; }
    const effective = TaskService.create(entry.draft, task.id, task.createdAt);
    effective.repeat = task.repeat; effective.sortOrder = task.sortOrder; effective.updatedAt = entry.updatedAt;
    return effective;
  }
  static change(task: Task, originalDate: string, draft: TaskDraft, now: number): Task {
    if (task.repeat === 'none' || !RecurrenceService.matches(task, originalDate)) { throw new Error('原始重复日期不存在'); }
    const replacement: TaskDraft = JSON.parse(JSON.stringify(draft)) as TaskDraft;
    replacement.repeat = 'none';
    if (replacement.planning) { replacement.planning.rule = PlanningService.emptyRule(); }
    if (replacement.dueAt <= 0) { throw new Error('单次重复事项必须保留计划日期'); }
    TaskService.create(replacement, task.id, now);
    const next = TaskService.withCompletion(task, false, now);
    next.overrides = (task.overrides ?? []).filter((item: OccurrenceOverride) => item.originalDate !== originalDate)
      .concat([{ originalDate: originalDate, draft: replacement, updatedAt: now }]);
    OccurrenceService.validate(next); return next;
  }
}
