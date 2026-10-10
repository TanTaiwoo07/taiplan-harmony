import { OccurrenceService } from './OccurrenceService';
import { BackupDocument, OccurrenceState, Task } from '../model/Task';
import { TaskService } from './TaskService';
import { ScheduleService } from './ScheduleService';

export class BackupService {
  static encode(tasks: Task[], occurrences: OccurrenceState[], now: number): string {
    const doc: BackupDocument = { format: 'TaiPlanHarmony', version: 6, exportedAt: now, tasks: tasks, occurrences: occurrences };
    const raw = JSON.stringify(doc, null, 2);
    BackupService.decode(raw);
    return raw;
  }
  static decode(raw: string): BackupDocument {
    if (raw.length > 4 * 1024 * 1024) { throw new Error('备份超过 4 MB，请选择较小的文件'); }
    const doc = JSON.parse(raw) as BackupDocument;
    if (!doc || doc.format !== 'TaiPlanHarmony' || ![3, 4, 5, 6].includes(doc.version) || !Array.isArray(doc.tasks) ||
      !Array.isArray(doc.occurrences) || doc.tasks.length > 5000 || doc.occurrences.length > 50000) { throw new Error('不是受支持的 TaiPlan 备份'); }
    const ids = new Set<string>();
    const byId = new Map<string, Task>();
    for (const task of doc.tasks) {
      if (!task || typeof task.id !== 'string' || task.id.length === 0 || task.id.length > 128 || ids.has(task.id) ||
        typeof task.title !== 'string' || typeof task.note !== 'string' || typeof task.completed !== 'boolean' ||
        typeof task.createdAt !== 'number' || !Number.isSafeInteger(task.createdAt) || task.createdAt < 0 ||
        typeof task.updatedAt !== 'number' || !Number.isSafeInteger(task.updatedAt) || task.updatedAt < 0 ||
        typeof task.sortOrder !== 'number' || !Number.isSafeInteger(task.sortOrder) ||
        !Array.isArray(task.tags) || task.tags.some((tag: string) => typeof tag !== 'string' || tag.trim() !== tag || /[,，、\n]/.test(tag)) ||
        typeof task.repeat !== 'string') { throw new Error('备份中的任务数据无效'); }
      if (task.steps !== undefined && (!Array.isArray(task.steps) || task.steps.some((step: string) => typeof step !== 'string' ||
        step.trim() !== step || step.length === 0 || /[\r\n]/.test(step)))) { throw new Error('备份中的子任务无效'); }
      if ((task.startMinute !== undefined && typeof task.startMinute !== 'number') ||
        (task.durationMinutes !== undefined && typeof task.durationMinutes !== 'number') ||
        (task.doneSteps !== undefined && !Array.isArray(task.doneSteps))) { throw new Error('备份中的时间或子任务进度无效'); }
      const clean = TaskService.create({ title: task.title, note: task.note, priority: task.priority,
        tagsText: task.tags.join(','), dueAt: task.dueAt, repeat: task.repeat, startMinute: task.startMinute,
        durationMinutes: task.durationMinutes, planning: task.planning, stepsText: (task.steps ?? []).join('\n') }, task.id, task.createdAt);
      if (task.planning?.kind === 'event' && task.completed) { throw new Error('事件不使用任务完成状态'); }
      TaskService.validateDone(task.doneSteps ?? [], (task.steps ?? []).length);
      if (task.repeat !== 'none' && (task.doneSteps ?? []).length > 0) { throw new Error('重复任务的子任务进度必须按日期保存'); }
      if (clean.tags.length !== task.tags.length || (task.repeat !== 'none' && task.completed)) { throw new Error('备份中的重复任务或标签无效'); }
      OccurrenceService.validate(task);
      ids.add(task.id);
      byId.set(task.id, task);
    }
    const stateKeys = new Set<string>();
    for (const state of doc.occurrences) {
      if (!state || typeof state.taskId !== 'string' || !ids.has(state.taskId) || typeof state.dateKey !== 'string' ||
        !ScheduleService.validKey(state.dateKey) || typeof state.completed !== 'boolean' || typeof state.skipped !== 'boolean' ||
        typeof state.updatedAt !== 'number' || !Number.isSafeInteger(state.updatedAt) || state.updatedAt < 0 || (state.completed && state.skipped)) {
        throw new Error('备份中的完成记录无效');
      }
      const task = byId.get(state.taskId);
      const key = `${state.taskId}@${state.dateKey}`;
      if (!task || task.repeat === 'none' || !ScheduleService.occursOn(task, state.dateKey) || stateKeys.has(key)) { throw new Error('备份中的重复日期无效'); }
      if (state.doneSteps !== undefined && !Array.isArray(state.doneSteps)) { throw new Error('备份中的子任务进度无效'); }
      TaskService.validateDone(state.doneSteps ?? [], (OccurrenceService.effective(task, state.dateKey).steps ?? []).length);
      stateKeys.add(key);
    }
    return doc;
  }
}
