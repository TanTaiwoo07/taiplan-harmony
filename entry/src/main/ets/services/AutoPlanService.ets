import { Task, OccurrenceState } from '../model/Task';
import { TaskService } from './TaskService';
import { PlanningService } from './PlanningService';
import { ScheduleService } from './ScheduleService';
import { CalendarService } from './CalendarService';
import { OccurrenceService } from './OccurrenceService';
export interface PlanSuggestion { before: Task; after: Task; reason: string; }
export interface PlanReport { suggestions: PlanSuggestion[]; unscheduled: string[]; }
export class AutoPlanService {
  static suggest(tasks: Task[], states: OccurrenceState[], now: number, startHour: number = 9, endHour: number = 21, snap: number = 15): PlanReport {
    if (!Number.isInteger(startHour) || !Number.isInteger(endHour) || startHour < 0 || endHour > 24 || startHour >= endHour || ![5, 15, 30].includes(snap)) { throw new Error('可用时段或时间网格无效'); }
    const suggestions: PlanSuggestion[] = []; const unscheduled: string[] = [];
    const inbox = tasks.filter((task: Task) => PlanningService.isInbox(task)).sort((a: Task, b: Task) => b.priority - a.priority || a.createdAt - b.createdAt);
    const working = tasks.slice(); const today = ScheduleService.key(now);
    for (const task of inbox.slice(0, 20)) {
      let assigned = false; const duration = task.durationMinutes ?? 30;
      for (let offset = 0; offset < 7 && !assigned; offset++) {
        const day = ScheduleService.shift(today, offset); const blocks = CalendarService.blocks(working, states, day);
        for (let minute = startHour * 60; minute + duration <= endHour * 60; minute += snap) {
          const clock = ScheduleService.date(day); clock.setHours(0, minute, 0, 0); const start = clock.getTime();
          if (start <= now || blocks.some(block => minute < block.end && minute + duration > block.start)) { continue; }
          const deadline = PlanningService.deadline(task, task.dueAt); if (deadline > 0 && start + duration * 60000 > deadline) { continue; }
          const draft = OccurrenceService.draft(task); draft.dueAt = ScheduleService.end(day); draft.startMinute = minute;
          const plan = PlanningService.create(draft.dueAt, minute, duration); const old = PlanningService.forTask(task);
          plan.location = old.location; plan.listName = old.listName; plan.deadlineAt = old.deadlineAt; plan.deadlineMode = old.deadlineMode; plan.reminder = old.reminder;
          draft.planning = plan; const next = TaskService.edit(task, draft, now);
          suggestions.push({ before: task, after: next, reason: '按明确优先级与创建顺序；使用已有预计时长 ' + duration.toString() + ' 分钟' });
          working.push(next); assigned = true; break;
        }
      }
      if (!assigned) { unscheduled.push(task.title + '：未来 7 天所选时段没有满足时长和截止的空档'); }
    }
    if (inbox.length > 20) { unscheduled.push('每次最多规划 20 项，其余保留收集箱'); }
    return { suggestions: suggestions, unscheduled: unscheduled };
  }
}
