import { Task } from '../model/Task';
import { PlanningService } from './PlanningService';
import { TaskService } from './TaskService';
export class ClassificationService {
  static rename(tasks: Task[], kind: string, from: string, to: string, now: number): Task[] {
    if (!['list', 'tag'].includes(kind) || !from || to.length > (kind === 'tag' ? 12 : 30) || /[,，、\n]/.test(to)) { throw new Error('名称无效'); }
    const result: Task[] = [];
    for (const source of tasks) {
      const task = JSON.parse(JSON.stringify(source)) as Task; let changed = false;
      if (kind === 'list') {
        if ((task.planning?.listName ?? '') === from) { task.planning = PlanningService.forTask(task); task.planning.listName = to; changed = true; }
        for (const override of task.overrides ?? []) {
          if (override.draft.planning?.listName === from) { override.draft.planning.listName = to; override.updatedAt = now; changed = true; }
        }
      } else {
        if (task.tags.includes(from)) { task.tags = Array.from(new Set<string>(task.tags.map((tag: string) => tag === from ? to : tag).filter((tag: string) => tag.length > 0))); changed = true; }
        for (const override of task.overrides ?? []) {
          const tags = TaskService.parseTags(override.draft.tagsText);
          if (tags.includes(from)) { override.draft.tagsText = Array.from(new Set<string>(tags.map((tag: string) => tag === from ? to : tag).filter((tag: string) => tag.length > 0))).join(','); override.updatedAt = now; changed = true; }
        }
      }
      if (changed) { task.updatedAt = now; result.push(task); }
    }
    return result;
  }
}
