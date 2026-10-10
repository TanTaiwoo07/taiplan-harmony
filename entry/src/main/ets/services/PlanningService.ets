import { AppPreferences, RecurrenceRule, Task, TaskPlanning } from '../model/Task';

// Central time contract. Plain civil dates never acquire an implicit deadline.
export class PlanningService {
  static key(value: number): string {
    const date = new Date(value);
    return `${date.getFullYear()}-${(date.getMonth() + 1).toString().padStart(2, '0')}-${date.getDate().toString().padStart(2, '0')}`;
  }
  static date(key: string): Date {
    const parts = key.split('-').map((part: string) => Number(part));
    return new Date(parts[0], parts[1] - 1, parts[2], 12);
  }
  static validDate(key: string): boolean {
    return /^\d{4}-\d{2}-\d{2}$/.test(key) && key >= '2000-01-01' && key <= '2100-12-31' && PlanningService.key(PlanningService.date(key).getTime()) === key;
  }
  static emptyRule(): RecurrenceRule { return { interval: 1, weekdays: [], untilDate: '', count: 0 }; }
  static create(day: number, minute: number, duration: number, kind: string = 'task'): TaskPlanning {
    let start = 0;
    if (day > 0 && minute >= 0) { const date = new Date(day); date.setHours(0, minute, 0, 0); start = date.getTime(); }
    return { kind: kind, scheduleMode: day === 0 ? 'unscheduled' : minute >= 0 ? 'timed' : kind === 'event' ? 'allDay' : 'date',
      plannedDate: day > 0 ? PlanningService.key(day) : '', startAt: start, endAt: start > 0 ? start + duration * 60000 : 0,
      timeZone: Intl.DateTimeFormat().resolvedOptions().timeZone, deadlineMode: 'none', deadlineAt: 0,
      location: '', listName: '', sourceType: 'manual', legacyTimeSemantics: false, rule: PlanningService.emptyRule() };
  }
  static forTask(task: Task): TaskPlanning {
    if (task.planning) { return JSON.parse(JSON.stringify(task.planning)) as TaskPlanning; }
    const plan = PlanningService.create(task.dueAt, task.startMinute ?? -1, task.durationMinutes ?? 30);
    plan.legacyTimeSemantics = true;
    plan.sourceType = 'legacy';
    if (task.dueAt > 0) {
      plan.deadlineMode = (task.startMinute ?? -1) >= 0 ? 'datetime' : 'date';
      plan.deadlineAt = (task.startMinute ?? -1) >= 0 ? plan.endAt : task.dueAt;
    }
    return plan;
  }
  static validate(plan: TaskPlanning, day: number, minute: number, duration: number, repeat: string): void {
    if (!plan || !['task', 'event'].includes(plan.kind) || !['unscheduled', 'date', 'timed', 'allDay'].includes(plan.scheduleMode) ||
      !['none', 'date', 'datetime'].includes(plan.deadlineMode) || typeof plan.location !== 'string' || plan.location.length > 200 ||
      typeof plan.listName !== 'string' || plan.listName.length > 30 || typeof plan.timeZone !== 'string' || plan.timeZone.length > 100 ||
      typeof plan.sourceType !== 'string' || plan.sourceType.length > 40 || typeof plan.legacyTimeSemantics !== 'boolean') { throw new Error('任务安排字段无效'); }
    const expected = PlanningService.create(day, minute, duration, plan.kind);
    if (plan.scheduleMode !== expected.scheduleMode || plan.plannedDate !== expected.plannedDate ||
      plan.startAt !== expected.startAt || plan.endAt !== expected.endAt || (day > 0 && !PlanningService.validDate(plan.plannedDate))) {
      throw new Error('计划日期与时间不一致');
    }
    if (plan.kind === 'event' && (day === 0 || plan.deadlineMode !== 'none')) { throw new Error('事件需要安排日期，不使用任务截止期限'); }
    if (!Number.isSafeInteger(plan.deadlineAt) || plan.deadlineAt < 0 || plan.deadlineAt > 4133980799999 ||
      (plan.deadlineMode === 'none' ? plan.deadlineAt !== 0 : plan.deadlineAt === 0)) { throw new Error('截止期限无效'); }
    if (plan.deadlineMode === 'date') { const d = new Date(plan.deadlineAt); if (d.getHours() !== 23 || d.getMinutes() !== 59 || d.getSeconds() !== 59 || d.getMilliseconds() !== 999) { throw new Error('按日期截止需使用当天结束'); } }
    const rule = plan.rule;
    if (!rule || !Number.isInteger(rule.interval) || rule.interval < 1 || rule.interval > 366 ||
      !Array.isArray(rule.weekdays) || rule.weekdays.some((day: number) => !Number.isInteger(day) || day < 1 || day > 7) ||
      new Set<number>(rule.weekdays).size !== rule.weekdays.length || typeof rule.untilDate !== 'string' ||
      (rule.untilDate !== '' && (!PlanningService.validDate(rule.untilDate) || rule.untilDate < plan.plannedDate)) ||
      !Number.isInteger(rule.count) || rule.count < 0 || rule.count > 10000 || (rule.count > 0 && rule.untilDate !== '') ||
      (repeat !== 'weekly' && rule.weekdays.length > 0)) { throw new Error('重复间隔、星期或结束条件无效'); }
  }
  static deadline(task: Task, occurrenceDay: number): number {
    const plan = PlanningService.forTask(task);
    if (plan.kind === 'event' || plan.deadlineMode === 'none') { return 0; }
    if (task.repeat === 'none' || task.dueAt === 0 || occurrenceDay === 0) { return plan.deadlineAt; }
    // Keep a repeated deadline at the same civil-day offset and clock time; DST is not 24h arithmetic.
    const result = new Date(plan.deadlineAt);
    const origin = new Date(task.dueAt); const selected = new Date(occurrenceDay);
    const days = (Date.UTC(selected.getFullYear(), selected.getMonth(), selected.getDate()) - Date.UTC(origin.getFullYear(), origin.getMonth(), origin.getDate())) / 86400000;
    result.setDate(result.getDate() + days); return result.getTime();
  }
  static overdue(task: Task, day: number, completed: boolean, now: number): boolean {
    const deadline = PlanningService.deadline(task, day);
    return !completed && deadline > 0 && deadline < now;
  }
  static isEvent(task: Task): boolean { return task.planning?.kind === 'event'; }
  static isInbox(task: Task): boolean { return !PlanningService.isEvent(task) && task.dueAt === 0 && !task.completed; }
  static defaults(): AppPreferences { return { startPage: 0, calendarView: 'month', weekStart: 1, snapMinutes: 15, showCompleted: false, useMaterial: true }; }
  static validatePreferences(value: AppPreferences): void {
    if (!value || ![0, 1, 2].includes(value.startPage) || !['year', 'month', 'week', 'day'].includes(value.calendarView) ||
      ![0, 1].includes(value.weekStart) || ![5, 15, 30].includes(value.snapMinutes) || typeof value.showCompleted !== 'boolean' || typeof value.useMaterial !== 'boolean') { throw new Error('显示偏好无效'); }
  }
}
