import { CalendarDay, OccurrenceState, Task, TaskItem, TimeConflict } from '../model/Task';
import { TaskService } from './TaskService';

export class ScheduleService {
  // ArkUI V1 ForEach 保留相同 key 的构建闭包；投影对象改变时需重建该卡片。
  static renderKey(item: TaskItem): string { return JSON.stringify(item); }
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
        dueAt: task.dueAt, completed: task.completed, doneSteps: (task.doneSteps ?? []).slice() };
    }
    const state = states.get(`${task.id}@${key}`);
    if (state?.skipped) { return undefined; }
    return { key: `${task.id}@${key}`, task: task, dateKey: key,
      dueAt: ScheduleService.end(key), completed: state?.completed ?? false, doneSteps: (state?.doneSteps ?? []).slice() };
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
  static sortLabel(mode: string): string {
    return mode === 'manual' ? '手动顺序' : mode === 'time' ? '时间先后' : mode === 'priority' ? '优先级' : '创建倒序';
  }
  static filter(items: TaskItem[], completed: boolean, query: string, tag: string, mode: string): TaskItem[] {
    const keyword = query.trim().toLocaleLowerCase();
    return items.filter((item: TaskItem) => item.completed === completed &&
      (tag.length === 0 || item.task.tags.includes(tag)) &&
      (keyword.length === 0 || `${item.task.title}\n${item.task.note}\n${item.task.tags.join(' ')}`.toLocaleLowerCase().includes(keyword)))
      .sort((a: TaskItem, b: TaskItem) => {
        let order = 0;
        if (mode === 'manual') { order = a.task.sortOrder - b.task.sortOrder; }
        else if (mode === 'priority') { order = b.task.priority - a.task.priority; }
        else if (mode === 'time') {
          const aTime = a.dueAt === 0 ? Number.MAX_SAFE_INTEGER : TaskService.deadline(a.task, a.dueAt) -
            ((a.task.startMinute ?? -1) >= 0 ? (a.task.durationMinutes ?? 30) * 60000 : 0);
          const bTime = b.dueAt === 0 ? Number.MAX_SAFE_INTEGER : TaskService.deadline(b.task, b.dueAt) -
            ((b.task.startMinute ?? -1) >= 0 ? (b.task.durationMinutes ?? 30) * 60000 : 0);
          order = aTime - bTime;
        } else { order = b.task.createdAt - a.task.createdAt; }
        return order || b.task.createdAt - a.task.createdAt || a.dueAt - b.dueAt || b.key.localeCompare(a.key);
      });
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
  static conflicts(candidate: Task, tasks: Task[], states: OccurrenceState[], now: number): TimeConflict[] {
    const result: TimeConflict[] = [];
    if ((candidate.startMinute ?? -1) < 0 || candidate.dueAt === 0 || candidate.completed) { return result; }
    const anchor = ScheduleService.key(candidate.dueAt);
    const today = ScheduleService.key(now);
    const first = candidate.repeat === 'none' || anchor > today ? anchor : today;
    const start = candidate.startMinute ?? 0;
    const end = start + (candidate.durationMinutes ?? 30);
    const index = ScheduleService.indexStates(states);
    const existing = tasks.find((task: Task) => task.id === candidate.id);
    const keepHistory = existing !== undefined && existing.repeat === candidate.repeat && existing.dueAt === candidate.dueAt;
    for (let day = 0; day < (candidate.repeat === 'none' ? 1 : 30); day++) {
      const key = ScheduleService.shift(first, day);
      if (!ScheduleService.occursOn(candidate, key)) { continue; }
      if (keepHistory) {
        const own = ScheduleService.indexedItem(candidate, key, index);
        if (!own || own.completed) { continue; }
      }
      for (const task of tasks) {
        if (task.id === candidate.id || (task.startMinute ?? -1) < 0 || !ScheduleService.occursOn(task, key)) { continue; }
        const item = ScheduleService.indexedItem(task, key, index);
        if (!item || item.completed) { continue; }
        const otherStart = task.startMinute ?? 0;
        if (start < otherStart + (task.durationMinutes ?? 30) && end > otherStart) {
          result.push({ title: task.title, dateKey: key, time: TaskService.timeLabel(task) });
          if (result.length === 5) { return result; }
        }
      }
    }
    return result;
  }
}
