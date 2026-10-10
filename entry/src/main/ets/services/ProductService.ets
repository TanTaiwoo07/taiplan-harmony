import { ProductState, FocusSession, Habit, Countdown } from '../model/Product';
import { PlanningService } from './PlanningService';

// These modules share an atomic SQLite document; no timer tick is needed to preserve elapsed time.
export class ProductService {
  static defaults(): ProductState {
    return { version: 1, features: { focus: false, habits: false, countdowns: false, ai: true },
      focusOptions: { work: 25, shortBreak: 5, longBreak: 15, cycles: 4 }, sessions: [], habits: [], countdowns: [] };
  }
  static clone(value: ProductState): ProductState { return JSON.parse(JSON.stringify(value)) as ProductState; }
  static integer(value: number, min: number, max: number): boolean { return Number.isSafeInteger(value) && value >= min && value <= max; }
  static text(value: string, max: number): boolean { return typeof value === 'string' && value.trim().length > 0 && value.length <= max; }
  static validate(value: ProductState): void {
    if (value && (!ProductService.integer(value.workStart ?? 9, 0, 23) || !ProductService.integer(value.workEnd ?? 21, 1, 24) || (value.workStart ?? 9) >= (value.workEnd ?? 21))) { throw new Error('可用时段无效'); }
    if (!value || value.version !== 1 || !value.features || !value.focusOptions ||
      typeof value.features.focus !== 'boolean' || typeof value.features.habits !== 'boolean' ||
      typeof value.features.countdowns !== 'boolean' || typeof value.features.ai !== 'boolean' ||
      !ProductService.integer(value.focusOptions.work, 1, 180) || !ProductService.integer(value.focusOptions.shortBreak, 1, 60) ||
      !ProductService.integer(value.focusOptions.longBreak, 1, 120) || !ProductService.integer(value.focusOptions.cycles, 1, 12) ||
      !Array.isArray(value.sessions) || value.sessions.length > 10000 || !Array.isArray(value.habits) || value.habits.length > 500 ||
      !Array.isArray(value.countdowns) || value.countdowns.length > 1000) { throw new Error('工具数据或功能偏好无效'); }
    const ids = new Set<string>();
    let active = 0;
    for (const session of value.sessions) {
      ProductService.id(session.id, ids);
      if (!ProductService.text(session.title, 100) || typeof session.taskId !== 'string' || session.taskId.length > 128 ||
        !['work', 'short', 'long'].includes(session.phase) || !['running', 'paused', 'finished', 'abandoned'].includes(session.status) ||
        !ProductService.integer(session.startedAt, 1, 4133980799999) || !ProductService.integer(session.resumedAt, 1, 4133980799999) ||
        !ProductService.integer(session.targetSeconds, 60, 10800) || !ProductService.integer(session.elapsedSeconds, 0, session.targetSeconds) ||
        !ProductService.integer(session.finishedAt, 0, 4133980799999)) { throw new Error('专注记录无效'); }
      if (session.status === 'running' || session.status === 'paused') { active++; }
    }
    if (active > 1) { throw new Error('只能有一个进行中的计时'); }
    for (const habit of value.habits) {
      ProductService.id(habit.id, ids);
      if (habit.reminderMinute !== undefined && !ProductService.integer(habit.reminderMinute, -1, 1439)) { throw new Error('习惯提醒时间无效'); }
      if (!ProductService.text(habit.title, 100) || !PlanningService.validDate(habit.createdDate) ||
        !Array.isArray(habit.weekdays) || !habit.weekdays.length || habit.weekdays.some((day: number) => !ProductService.integer(day, 1, 7)) ||
        new Set<number>(habit.weekdays).size !== habit.weekdays.length || !ProductService.integer(habit.weeklyTarget, 0, 7) ||
        !ProductService.integer(habit.dailyTarget, 1, 10) || !Array.isArray(habit.checks) || habit.checks.length > 37000) { throw new Error('习惯规则无效'); }
      const days = new Set<string>();
      for (const check of habit.checks) {
        if (!PlanningService.validDate(check.date) || check.date < habit.createdDate || days.has(check.date) ||
          !ProductService.integer(check.count, 1, habit.dailyTarget) || !ProductService.integer(check.updatedAt, 0, 4133980799999)) { throw new Error('习惯打卡记录无效'); }
        days.add(check.date);
      }
    }
    for (const day of value.countdowns) {
      ProductService.id(day.id, ids);
      if (day.reminderDays !== undefined && !ProductService.integer(day.reminderDays, -1, 365)) { throw new Error('倒数日提前提醒无效'); }
      if (!ProductService.text(day.title, 100) || !PlanningService.validDate(day.date) || typeof day.annual !== 'boolean' ||
        typeof day.pinned !== 'boolean' || typeof day.category !== 'string' || day.category.length > 30) { throw new Error('倒数日无效'); }
    }
  }
  private static id(id: string, ids: Set<string>): void {
    if (!ProductService.text(id, 128) || ids.has(id)) { throw new Error('工具记录 ID 无效或重复'); } ids.add(id);
  }
  static elapsed(session: FocusSession, now: number): number {
    return Math.min(session.targetSeconds, session.elapsedSeconds + (session.status === 'running' ? Math.max(0, Math.floor((now - session.resumedAt) / 1000)) : 0));
  }
  static active(state: ProductState): FocusSession | undefined {
    return state.sessions.find((session: FocusSession) => session.status === 'running' || session.status === 'paused');
  }
  static start(state: ProductState, id: string, title: string, taskId: string, phase: string, now: number): ProductState {
    const next = ProductService.clone(state);
    if (ProductService.active(next)) { throw new Error('请先结束当前计时'); }
    const minutes = phase === 'work' ? next.focusOptions.work : phase === 'short' ? next.focusOptions.shortBreak : next.focusOptions.longBreak;
    next.sessions.push({ id: id, title: title, taskId: taskId, phase: phase, status: 'running', startedAt: now, resumedAt: now,
      targetSeconds: minutes * 60, elapsedSeconds: 0, finishedAt: 0 });
    ProductService.validate(next); return next;
  }
  static transition(state: ProductState, action: string, now: number): ProductState {
    const next = ProductService.clone(state); const session = ProductService.active(next);
    if (!session) { throw new Error('当前没有计时'); }
    if (!['pause', 'resume', 'finish', 'abandon'].includes(action)) { throw new Error('计时操作无效'); }
    if (action === 'finish' && ProductService.elapsed(session, now) < session.targetSeconds) { throw new Error('计时尚未结束'); }
    session.elapsedSeconds = ProductService.elapsed(session, now);
    session.resumedAt = Math.max(now, session.resumedAt);
    session.status = action === 'resume' ? 'running' : action === 'pause' ? 'paused' : action === 'finish' ? 'finished' : 'abandoned';
    if (action === 'finish' || action === 'abandon') { session.finishedAt = now; }
    ProductService.validate(next); return next;
  }
  static shift(day: string, offset: number): string {
    const date = PlanningService.date(day); date.setDate(date.getDate() + offset); return PlanningService.key(date.getTime());
  }
  static scheduled(habit: Habit, day: string): boolean {
    return day >= habit.createdDate && (habit.weeklyTarget > 0 || habit.weekdays.includes(PlanningService.date(day).getDay() || 7));
  }
  static check(state: ProductState, id: string, day: string, add: boolean, now: number): ProductState {
    const next = ProductService.clone(state); const habit = next.habits.find((item: Habit) => item.id === id);
    if (!habit || !PlanningService.validDate(day) || day > PlanningService.key(now) || !ProductService.scheduled(habit, day)) { throw new Error('只能在已开始、应打卡的日期打卡或补打'); }
    const old = habit.checks.find((item) => item.date === day);
    const count = Math.min(habit.dailyTarget, Math.max(0, (old?.count ?? 0) + (add ? 1 : -1)));
    habit.checks = habit.checks.filter((item) => item.date !== day);
    if (count > 0) { habit.checks.push({ date: day, count: count, updatedAt: now }); }
    ProductService.validate(next); return next;
  }
  static count(habit: Habit, day: string): number { return habit.checks.find((item) => item.date === day)?.count ?? 0; }
  static weekCount(habit: Habit, day: string): number {
    const monday = ProductService.shift(day, -((PlanningService.date(day).getDay() + 6) % 7));
    return habit.checks.filter((check) => check.date >= monday && check.date <= day && check.count >= habit.dailyTarget).length;
  }
  static streak(habit: Habit, today: string): number {
    let count = 0; let day = today;
    // Today may still be in progress. Non-required days never break a streak.
    if (ProductService.count(habit, today) < habit.dailyTarget) { day = ProductService.shift(day, -1); }
    while (day >= habit.createdDate) {
      if (ProductService.scheduled(habit, day)) {
        if (ProductService.count(habit, day) < habit.dailyTarget) { break; } count++;
      }
      day = ProductService.shift(day, -1);
    }
    return count;
  }
  static nextDate(item: Countdown, today: string): string {
    if (!item.annual) { return item.date; }
    const origin = PlanningService.date(item.date); let year = PlanningService.date(today).getFullYear();
    const inYear = (value: number): string => {
      const last = new Date(value, origin.getMonth() + 1, 0).getDate();
      return PlanningService.key(new Date(value, origin.getMonth(), Math.min(origin.getDate(), last), 12).getTime());
    };
    return inYear(year) >= today ? inYear(year) : inYear(year + 1);
  }
  static days(item: Countdown, today: string): number {
    const target = PlanningService.date(ProductService.nextDate(item, today)); const base = PlanningService.date(today);
    return Math.round((Date.UTC(target.getFullYear(), target.getMonth(), target.getDate()) - Date.UTC(base.getFullYear(), base.getMonth(), base.getDate())) / 86400000);
  }
  static merge(current: ProductState, incoming: ProductState): ProductState {
    ProductService.validate(incoming); const next = ProductService.clone(current);
    next.features = incoming.features; next.focusOptions = incoming.focusOptions;
    next.workStart = incoming.workStart ?? 9; next.workEnd = incoming.workEnd ?? 21;
    for (const habit of incoming.habits) { if (!next.habits.some((item: Habit) => item.id === habit.id)) { next.habits.push(habit); } }
    for (const day of incoming.countdowns) { if (!next.countdowns.some((item: Countdown) => item.id === day.id)) { next.countdowns.push(day); } }
    for (const source of incoming.sessions) {
      if (next.sessions.some((item: FocusSession) => item.id === source.id)) { continue; }
      const session: FocusSession = JSON.parse(JSON.stringify(source)) as FocusSession;
      // Restore ongoing sessions as paused; never silently start a timer from another device.
      if (session.status === 'running' || session.status === 'paused') {
        session.status = ProductService.active(next) ? 'abandoned' : 'paused';
      }
      next.sessions.push(session);
    }
    ProductService.validate(next); return next;
  }
}
