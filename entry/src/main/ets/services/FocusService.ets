import { OccurrenceState, Task, TaskItem } from '../model/Task';
import { ScheduleService } from './ScheduleService';
import { TaskService } from './TaskService';

export interface DayOverview {
  planned: number;
  completed: number;
  overdue: number;
  urgent: TaskItem[];
  remaining: TaskItem[];
  done: TaskItem[];
}

export class FocusService {
  static overview(tasks: Task[], states: OccurrenceState[], now: number): DayOverview {
    const today = ScheduleService.key(now);
    const scheduled = ScheduleService.project(tasks, states, 'calendar', today, now);
    const rows = ScheduleService.project(tasks, states, 'today', today, now);
    // 未安排日期的高优先级任务也要可见；未来事项仍留在待办和日历。
    const unplanned = ScheduleService.project(tasks, states, 'all', today, now)
      .filter((item: TaskItem) => !item.completed && item.dueAt === 0 && item.task.priority === 2);
    const pending = rows.filter((item: TaskItem) => !item.completed).concat(unplanned);
    const isOverdue = (item: TaskItem): boolean => item.dueAt > 0 && TaskService.deadline(item.task, item.dueAt) < now;
    const urgent = pending.filter((item: TaskItem) => item.task.priority === 2 || isOverdue(item))
      .sort((a: TaskItem, b: TaskItem) => Number(isOverdue(b)) - Number(isOverdue(a)) ||
        b.task.priority - a.task.priority || b.task.createdAt - a.task.createdAt);
    const keys = new Set<string>(urgent.map((item: TaskItem) => item.key));
    return { planned: scheduled.length, completed: scheduled.filter((item: TaskItem) => item.completed).length,
      overdue: pending.filter(isOverdue).length, urgent: urgent,
      remaining: ScheduleService.filter(pending.filter((item: TaskItem) => !keys.has(item.key)), false, '', '', 'time'),
      done: ScheduleService.filter(scheduled, true, '', '', 'created') };
  }
}
