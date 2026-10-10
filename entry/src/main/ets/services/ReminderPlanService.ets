import { Task, OccurrenceState, TaskItem } from '../model/Task';
import { ScheduleService } from './ScheduleService';
import { PlanningService } from './PlanningService';
export interface ReminderIntent { key: string; taskId: string; originalDate: string; title: string; at: number; content?: string; }
export class ReminderPlanService {
  static intents(tasks: Task[], states: OccurrenceState[], now: number): ReminderIntent[] {
    const result: ReminderIntent[] = []; const seen = new Set<string>(); const today = ScheduleService.key(now);
    const candidates: TaskItem[] = [];
    for (let offset = 0; offset < 8; offset++) { candidates.push(...ScheduleService.project(tasks, states, 'calendar', ScheduleService.shift(today, offset), now)); }
    candidates.push(...ScheduleService.project(tasks.filter((task: Task) => task.repeat === 'none'), states, 'all', '', now));
    for (const item of candidates) {
      const rule = item.task.planning?.reminder;
      if (!rule || rule.mode === 'none' || item.completed || seen.has(item.key)) { continue; } seen.add(item.key);
      let at = rule.at;
      if (rule.mode === 'start') {
        if (!item.dueAt) { continue; }
        const date = ScheduleService.date(ScheduleService.key(item.dueAt)); date.setHours(0, (item.task.startMinute ?? -1) >= 0 ? item.task.startMinute : 9 * 60, 0, 0);
        at = date.getTime() - rule.leadMinutes * 60000;
      } else if (rule.mode === 'deadline') { const deadline = PlanningService.deadline(item.task, item.dueAt); if (!deadline) { continue; } at = deadline - rule.leadMinutes * 60000; }
      at = Math.ceil(at / 60000) * 60000;
      if (at > now && at <= now + 7 * 86400000) { result.push({ key: item.key, taskId: item.task.id, originalDate: item.dateKey,
        title: (item.task.priority === 2 ? '【紧急】' : '') + item.task.title, at: at,
        content: (rule.mode === 'deadline' ? '截止提醒' : rule.mode === 'start' ? '日程开始提醒' : '指定时间提醒') +
          (rule.mode !== 'absolute' && rule.leadMinutes > 0 ? ' · 提前 ' + rule.leadMinutes.toString() + ' 分钟' : '') +
          (item.task.planning?.location ? ' · ' + item.task.planning.location : '') }); }
    }
    return result.sort((a: ReminderIntent, b: ReminderIntent) => a.at - b.at || a.key.localeCompare(b.key));
  }
}
