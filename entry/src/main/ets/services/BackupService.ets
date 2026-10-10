import { BackupDocument, OccurrenceState, Task } from '../model/Task';
import { TaskService } from './TaskService';
import { ScheduleService } from './ScheduleService';

export class BackupService {
  static encode(tasks: Task[], occurrences: OccurrenceState[], now: number): string {
    const doc: BackupDocument = { format: 'TaiPlanHarmony', version: 3, exportedAt: now, tasks: tasks, occurrences: occurrences };
    const raw = JSON.stringify(doc, null, 2);
    BackupService.decode(raw);
    return raw;
  }
  static decode(raw: string): BackupDocument {
    if (raw.length > 4 * 1024 * 1024) { throw new Error('备份超过 4 MB，请选择较小的文件'); }
    const doc = JSON.parse(raw) as BackupDocument;
    if (!doc || doc.format !== 'TaiPlanHarmony' || doc.version !== 3 || !Array.isArray(doc.tasks) ||
      !Array.isArray(doc.occurrences) || doc.tasks.length > 5000 || doc.occurrences.length > 50000) { throw new Error('不是受支持的 TaiPlan 备份'); }
    const ids = new Set<string>();
    for (const task of doc.tasks) {
      if (!task || typeof task.id !== 'string' || task.id.length === 0 || task.id.length > 128 || ids.has(task.id) ||
        typeof task.title !== 'string' || typeof task.note !== 'string' || typeof task.completed !== 'boolean' ||
        typeof task.createdAt !== 'number' || !Number.isSafeInteger(task.createdAt) || task.createdAt < 0 ||
        typeof task.updatedAt !== 'number' || !Number.isSafeInteger(task.updatedAt) || task.updatedAt < 0 ||
        typeof task.sortOrder !== 'number' || !Number.isSafeInteger(task.sortOrder) ||
        !Array.isArray(task.tags) || task.tags.some((tag: string) => typeof tag !== 'string' || tag.trim() !== tag || /[,，、\n]/.test(tag)) ||
        typeof task.repeat !== 'string') { throw new Error('备份中的任务数据无效'); }
      const clean = TaskService.create({ title: task.title, note: task.note, priority: task.priority,
        tagsText: task.tags.join(','), dueAt: task.dueAt, repeat: task.repeat }, task.id, task.createdAt);
      if (clean.tags.length !== task.tags.length || (task.repeat !== 'none' && task.completed)) { throw new Error('备份中的重复任务或标签无效'); }
      ids.add(task.id);
    }
    const stateKeys = new Set<string>();
    for (const state of doc.occurrences) {
      if (!state || typeof state.taskId !== 'string' || !ids.has(state.taskId) || typeof state.dateKey !== 'string' ||
        !ScheduleService.validKey(state.dateKey) || typeof state.completed !== 'boolean' || typeof state.skipped !== 'boolean' ||
        typeof state.updatedAt !== 'number' || !Number.isSafeInteger(state.updatedAt) || state.updatedAt < 0 || (state.completed && state.skipped)) {
        throw new Error('备份中的完成记录无效');
      }
      const task = doc.tasks.find((task: Task) => task.id === state.taskId);
      const key = `${state.taskId}@${state.dateKey}`;
      if (!task || task.repeat === 'none' || !ScheduleService.occursOn(task, state.dateKey) || stateKeys.has(key)) { throw new Error('备份中的重复日期无效'); }
      stateKeys.add(key);
    }
    return doc;
  }
}
