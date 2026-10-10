import { CalendarDay, OccurrenceState, Task, TaskItem } from '../model/Task';
import { TaskService } from './TaskService';

export class ScheduleService {
  static key(value: number): string {
    const date = new Date(value);
    return `${date.getFullYear()}-${(date.getMonth() + 1).toString().padStart(2, '0')}-${date.getDate().toString().padStart(2, '0')}`;
  }
  static date(key: string): Date {
    const parts = key.split('-').map((part: string) => Number(part));
    return new Date(parts[0], parts[1] - 1, parts[2], 12);
  }
  static validKey(key: string): boolean {
    return /^\d{4}-\d{2}-\d{2}$/.test(key) && ScheduleService.key(ScheduleService.date(key).getTime()) === key;
  }
  static end(key: string): number {
    const date = ScheduleService.date(key);
    return TaskService.endOfDay(date.getFullYear(), date.getMonth(), date.getDate());
  }
  static shift(key: string, days: number): string {
    const date = ScheduleService.date(key);
    date.setDate(date.getDate() + days);
    return ScheduleService.key(date.getTime());
  }
  static occursOn(task: Task, key: string): boolean {
    if (task.dueAt === 0) { return false; }
    const anchor = ScheduleService.key(task.dueAt);
    if (key < anchor) { return false; }
    if (task.repeat === 'none') { return key === anchor; }
    if (task.repeat === 'daily') { return true; }
    const date = ScheduleService.date(key);
    const start = ScheduleService.date(anchor);
    if (task.repeat === 'weekly') { return date.getDay() === start.getDay(); }
    const last = new Date(date.getFullYear(), date.getMonth() + 1, 0).getDate();
    return date.getDate() === Math.min(start.getDate(), last);
  }
  static item(task: Task, key: string, states: OccurrenceState[]): TaskItem | undefined {
    return ScheduleService.indexedItem(task, key, ScheduleService.indexStates(states));
  }
  private static indexStates(states: OccurrenceState[]): Map<string, OccurrenceState> {
    const result = new Map<string, OccurrenceState>();
    for (const state of states) { result.set(`${state.taskId}@${state.dateKey}`, state); }
    return result;
  }
  private static indexedItem(task: Task, key: string, states: Map<string, OccurrenceState>): TaskItem | undefined {
    if (task.repeat === 'none') {
      return { key: task.id, task: task, dateKey: task.dueAt > 0 ? ScheduleService.key(task.dueAt) : '',
        dueAt: task.dueAt, completed: task.completed };
    }
    const state = states.get(`${task.id}@${key}`);
    if (state?.skipped) { return undefined; }
    return { key: `${task.id}@${key}`, task: task, dateKey: key,
      dueAt: ScheduleService.end(key), completed: state?.completed ?? false };
  }
  static nextDate(task: Task, start: string): string {
    const anchor = ScheduleService.key(task.dueAt);
    const first = start < anchor ? anchor : start;
    if (task.repeat === 'daily') { return first; }
    const date = ScheduleService.date(first);
    const origin = ScheduleService.date(anchor);
    if (task.repeat === 'weekly') { return ScheduleService.shift(first, (origin.getDay() - date.getDay() + 7) % 7); }
    const last = new Date(date.getFullYear(), date.getMonth() + 1, 0).getDate();
    let candidate = new Date(date.getFullYear(), date.getMonth(), Math.min(origin.getDate(), last), 12);
    if (ScheduleService.key(candidate.getTime()) < first) {
      const nextLast = new Date(date.getFullYear(), date.getMonth() + 2, 0).getDate();
      candidate = new Date(date.getFullYear(), date.getMonth() + 1, Math.min(origin.getDate(), nextLast), 12);
    }
    return ScheduleService.key(candidate.getTime());
  }
  static project(tasks: Task[], states: OccurrenceState[], view: string, selected: string, now: number): TaskItem[] {
    const today = ScheduleService.key(now);
    const stateIndex = ScheduleService.indexStates(states);
    const items: TaskItem[] = [];
    for (const task of tasks) {
      if (task.repeat === 'none') {
        const key = task.dueAt > 0 ? ScheduleService.key(task.dueAt) : '';
        const include = view === 'all' || (view === 'today' && key.length > 0 && key <= today && (!task.completed || key === today)) ||
          (view === 'future' && key > today && key <= ScheduleService.shift(today, 30)) || (view === 'calendar' && key === selected);
        if (include) {
          const item = ScheduleService.indexedItem(task, key, stateIndex);
          if (item) { items.push(item); }
        }
      } else {
        if (view === 'all') {
          let candidate = ScheduleService.nextDate(task, today);
          while (stateIndex.get(`${task.id}@${candidate}`)?.skipped) {
            candidate = ScheduleService.nextDate(task, ScheduleService.shift(candidate, 1));
          }
          const item = ScheduleService.indexedItem(task, candidate, stateIndex);
          if (item) { items.push(item); }
          continue;
        }
        const anchor = ScheduleService.key(task.dueAt);
        const first = view === 'calendar' ? selected : view === 'future' ? ScheduleService.shift(today, 1) :
          view === 'all' && anchor > today ? anchor : today;
        const count = view === 'all' ? 370 : view === 'future' ? 30 : 1;
        for (let offset = 0; offset < count; offset++) {
          const key = ScheduleService.shift(first, offset);
          if (!ScheduleService.occursOn(task, key)) { continue; }
          const item = ScheduleService.indexedItem(task, key, stateIndex);
          if (item) { items.push(item); if (view === 'all') { break; } }
        }
      }
    }
    return items;
  }
  static filter(items: TaskItem[], completed: boolean, query: string, tag: string, manual: boolean): TaskItem[] {
    const keyword = query.trim().toLocaleLowerCase();
    return items.filter((item: TaskItem) => item.completed === completed &&
      (tag.length === 0 || item.task.tags.includes(tag)) &&
      (keyword.length === 0 || `${item.task.title}\n${item.task.note}\n${item.task.tags.join(' ')}`.toLocaleLowerCase().includes(keyword)))
      .sort((a: TaskItem, b: TaskItem) => (manual ? a.task.sortOrder - b.task.sortOrder : b.task.createdAt - a.task.createdAt) ||
        a.dueAt - b.dueAt || b.key.localeCompare(a.key));
  }
  static month(tasks: Task[], states: OccurrenceState[], month: string): CalendarDay[] {
    const stateIndex = ScheduleService.indexStates(states);
    const first = ScheduleService.date(month.slice(0, 7) + '-01');
    const start = ScheduleService.shift(ScheduleService.key(first.getTime()), -(first.getDay() + 6) % 7);
    const days: CalendarDay[] = [];
    for (let i = 0; i < 42; i++) {
      const key = ScheduleService.shift(start, i);
      let count = 0;
      for (const task of tasks) {
        if (ScheduleService.occursOn(task, key) && ScheduleService.indexedItem(task, key, stateIndex)) { count++; }
      }
      days.push({ key: key, day: ScheduleService.date(key).getDate(), inMonth: key.slice(0, 7) === month.slice(0, 7), count: count });
    }
    return days;
  }
  static repeatLabel(repeat: string): string {
    return repeat === 'daily' ? '每天' : repeat === 'weekly' ? '每周' : repeat === 'monthly' ? '每月' : '不重复';
  }
  static ordered(tasks: Task[]): Task[] {
    return tasks.slice().sort((a: Task, b: Task) => a.sortOrder - b.sortOrder || b.createdAt - a.createdAt || b.id.localeCompare(a.id));
  }
  static move(tasks: Task[], from: number, to: number): Task[] {
    const next = tasks.slice();
    if (!Number.isInteger(from) || !Number.isInteger(to) || from < 0 || to < 0 || from >= next.length || to >= next.length) { return next; }
    const item = next.splice(from, 1)[0];
    next.splice(to, 0, item);
    return next;
  }
}
