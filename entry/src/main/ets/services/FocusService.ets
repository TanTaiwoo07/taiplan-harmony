import { OccurrenceState, Task, TaskItem } from '../model/Task';
import { ScheduleService } from './ScheduleService';
import { PlanningService } from './PlanningService';
import { TaskService } from './TaskService';
import { UrgencyService } from './UrgencyService';

export interface DayOverview {
  planned: number;
  completed: number;
  overdue: number;
  events: TaskItem[];
  urgent: TaskItem[];
  remaining: TaskItem[];
  done: TaskItem[];
}

export class FocusService {
  static overview(tasks: Task[], states: OccurrenceState[], now: number): DayOverview {
    const today = ScheduleService.key(now);
    const dayItems = ScheduleService.project(tasks, states, 'calendar', today, now);
    const scheduled = dayItems.filter((item: TaskItem) => !PlanningService.isEvent(item.task));
    const rows = ScheduleService.project(tasks, states, 'today', today, now).filter((item: TaskItem) => !PlanningService.isEvent(item.task));
    // 未安排日期的高优先级任务也要可见；未来事项仍留在待办和日历。
    const unplanned = ScheduleService.project(tasks, states, 'all', today, now)
      .filter((item: TaskItem) => !item.completed && item.dueAt === 0 && item.task.priority === 2);
    const pending = rows.filter((item: TaskItem) => !item.completed).concat(unplanned.filter((item: TaskItem) => !rows.some((row: TaskItem) => row.key === item.key)));
    const isOverdue = (item: TaskItem): boolean => PlanningService.overdue(item.task, item.dueAt, item.completed, now);
    const urgent = pending.filter((item: TaskItem) => UrgencyService.label(item.task, item.dueAt, item.completed, now).length > 0)
      .concat(dayItems.filter((item: TaskItem) => PlanningService.isEvent(item.task) && item.task.priority === 2))
      .sort((a: TaskItem, b: TaskItem) => Number(isOverdue(b)) - Number(isOverdue(a)) ||
        b.task.priority - a.task.priority || b.task.createdAt - a.task.createdAt);
    const keys = new Set<string>(urgent.map((item: TaskItem) => item.key));
    return { events: dayItems.filter((item: TaskItem) => PlanningService.isEvent(item.task) && !keys.has(item.key)), planned: scheduled.length, completed: scheduled.filter((item: TaskItem) => item.completed).length,
      overdue: pending.filter(isOverdue).length, urgent: urgent,
      remaining: ScheduleService.filter(pending.filter((item: TaskItem) => !keys.has(item.key)), false, '', '', 'time'),
      done: ScheduleService.filter(scheduled, true, '', '', 'created') };
  }
}
