import { Task } from '../model/Task';
import { PlanningService } from './PlanningService';

export class RecurrenceService {
  private static ordinal(key: string): number { const d = PlanningService.date(key); return Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()) / 86400000; }
  static matches(task: Task, key: string): boolean {
    if (task.dueAt === 0 || !PlanningService.validDate(key)) { return false; }
    const anchor = PlanningService.key(task.dueAt);
    if (key < anchor) { return false; }
    if (task.repeat === 'none') { return key === anchor; }
    const rule = task.planning?.rule ?? PlanningService.emptyRule();
    if (rule.untilDate && key > rule.untilDate) { return false; }
    if (!RecurrenceService.pattern(task, key)) { return false; }
    if (rule.count === 0) { return true; }
    const date = PlanningService.date(key), origin = PlanningService.date(anchor);
    const delta = RecurrenceService.ordinal(key) - RecurrenceService.ordinal(anchor);
    let count = 0;
    if (task.repeat === 'daily') { count = Math.floor(delta / rule.interval) + 1; }
    else if (task.repeat === 'monthly') { count = ((date.getFullYear() - origin.getFullYear()) * 12 + date.getMonth() - origin.getMonth()) / rule.interval + 1; }
    else if (task.repeat === 'yearly') { count = (date.getFullYear() - origin.getFullYear()) / rule.interval + 1; }
    else {
      const originDay = (origin.getDay() + 6) % 7 + 1, day = (date.getDay() + 6) % 7 + 1;
      const days = rule.weekdays.length > 0 ? rule.weekdays : [originDay];
      const week = Math.floor((delta + originDay - 1) / 7);
      count = week === 0 ? days.filter((value: number) => value >= originDay && value <= day).length :
        days.filter((value: number) => value >= originDay).length + (week / rule.interval - 1) * days.length + days.filter((value: number) => value <= day).length;
    }
    return count <= rule.count;
  }
  private static pattern(task: Task, key: string): boolean {
    const origin = new Date(task.dueAt); const date = PlanningService.date(key);
    const rule = task.planning?.rule ?? PlanningService.emptyRule();
    const delta = RecurrenceService.ordinal(key) - RecurrenceService.ordinal(PlanningService.key(task.dueAt));
    if (task.repeat === 'daily') { return delta % rule.interval === 0; }
    if (task.repeat === 'weekly') {
      const weekday = (date.getDay() + 6) % 7 + 1;
      const originWeekday = (origin.getDay() + 6) % 7 + 1;
      return Math.floor((delta + originWeekday - 1) / 7) % rule.interval === 0 &&
        (rule.weekdays.length > 0 ? rule.weekdays.includes(weekday) : weekday === originWeekday);
    }
    const monthDelta = (date.getFullYear() - origin.getFullYear()) * 12 + date.getMonth() - origin.getMonth();
    if (task.repeat === 'yearly' && (date.getMonth() !== origin.getMonth() || (date.getFullYear() - origin.getFullYear()) % rule.interval !== 0)) { return false; }
    if (task.repeat === 'monthly' && monthDelta % rule.interval !== 0) { return false; }
    const last = new Date(date.getFullYear(), date.getMonth() + 1, 0).getDate();
    return date.getDate() === Math.min(origin.getDate(), last);
  }
  static next(task: Task, start: string): string {
    const anchor = PlanningService.key(task.dueAt);
    const date = PlanningService.date(start < anchor ? anchor : start);
    const last = task.planning?.rule.untilDate || '2100-12-31';
    while (PlanningService.key(date.getTime()) <= last) {
      const key = PlanningService.key(date.getTime());
      if (RecurrenceService.matches(task, key)) { return key; }
      // A finite count cannot gain new instances after it has ended.
      if ((task.planning?.rule.count ?? 0) > 0 && RecurrenceService.pattern(task, key)) { return ''; }
      date.setDate(date.getDate() + 1);
    }
    return '';
  }
}
