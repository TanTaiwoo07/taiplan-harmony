import { OccurrenceService } from './OccurrenceService';
import { PlanningService } from './PlanningService';
import { RecurrenceService } from './RecurrenceService';
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
  static occursOn(task: Task, key: string): boolean { return RecurrenceService.matches(task, key); }
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
    const effective = OccurrenceService.effective(task, key);
    return { key: task.id + '@' + key, task: effective, dateKey: key,
      dueAt: effective === task ? ScheduleService.end(key) : effective.dueAt, completed: state?.completed ?? false,
      doneSteps: (state?.doneSteps ?? []).slice() };
  }
  static nextDate(task: Task, start: string): string { return RecurrenceService.next(task, start); }
  static project(tasks: Task[], states: OccurrenceState[], view: string, selected: string, now: number): TaskItem[] {
    const today = ScheduleService.key(now);
    const stateIndex = ScheduleService.indexStates(states);
    const items: TaskItem[] = [];
    for (const task of tasks) {
      if (task.repeat === 'none') {
        const key = task.dueAt > 0 ? ScheduleService.key(task.dueAt) : '';
        const include = view === 'all' || (view === 'inbox' && PlanningService.isInbox(task)) || (view === 'scheduled' && task.dueAt > 0) || (view === 'today' && (key === today || PlanningService.overdue(task, task.dueAt, task.completed, now) || (PlanningService.deadline(task, task.dueAt) > 0 && ScheduleService.key(PlanningService.deadline(task, task.dueAt)) === today)) && (!task.completed || key === today)) ||
          (view === 'future' && key > today && key <= ScheduleService.shift(today, 30)) || (view === 'calendar' && key === selected);
        if (include) {
          const item = ScheduleService.indexedItem(task, key, stateIndex);
          if (item) { items.push(item); }
        }
      } else {
        if (view === 'inbox') { continue; }
        if (view === 'all' || view === 'scheduled') {
          let candidate = ScheduleService.nextDate(task, today);
          while (candidate && (stateIndex.get(`${task.id}@${candidate}`)?.skipped || (task.overrides ?? []).some(entry => entry.originalDate === candidate && ScheduleService.key(entry.draft.dueAt) < today))) {
            candidate = ScheduleService.nextDate(task, ScheduleService.shift(candidate, 1));
          }

          const item = candidate ? ScheduleService.indexedItem(task, candidate, stateIndex) : undefined;
          const moved = (task.overrides ?? []).map(entry => ScheduleService.indexedItem(task, entry.originalDate, stateIndex))
            .filter((entry: TaskItem | undefined) => entry !== undefined && ScheduleService.key(entry.dueAt) >= today) as TaskItem[];
          if (item) { moved.push(item); }
          moved.sort((a: TaskItem, b: TaskItem) => a.dueAt - b.dueAt);
          if (moved.length > 0) { items.push(moved[0]); }
          continue;
        }
        const first = view === 'calendar' ? selected : view === 'future' ? ScheduleService.shift(today, 1) : today;
        const count = view === 'future' ? 30 : 1;
        const candidates = new Set<string>();
        for (let offset = 0; offset < count; offset++) { candidates.add(ScheduleService.shift(first, offset)); }
        for (const entry of task.overrides ?? []) { candidates.add(entry.originalDate); }
        for (const key of candidates) {
          if (!ScheduleService.occursOn(task, key)) { continue; }
          const item = ScheduleService.indexedItem(task, key, stateIndex);
          if (!item) { continue; }
          const actual = ScheduleService.key(item.dueAt);
          if (actual >= first && actual < ScheduleService.shift(first, count)) { items.push(item); }
        }
      }
    }
    return items;
  }
  static startTime(item: TaskItem): number {
    if ((item.task.startMinute ?? -1) < 0) { return item.dueAt; }
    const date = new Date(item.dueAt); date.setHours(0, item.task.startMinute ?? 0, 0, 0); return date.getTime();
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
          const aTime = a.dueAt === 0 ? Number.MAX_SAFE_INTEGER : ScheduleService.startTime(a);
          const bTime = b.dueAt === 0 ? Number.MAX_SAFE_INTEGER : ScheduleService.startTime(b);
          order = aTime - bTime;
        } else { order = b.task.createdAt - a.task.createdAt; }
        return order || b.task.createdAt - a.task.createdAt || a.dueAt - b.dueAt || b.key.localeCompare(a.key);
      });
  }
  static month(tasks: Task[], states: OccurrenceState[], month: string, weekStart: number = 1): CalendarDay[] {
    const stateIndex = ScheduleService.indexStates(states);
    const first = ScheduleService.date(month.slice(0, 7) + '-01');
    const start = ScheduleService.shift(ScheduleService.key(first.getTime()), -((first.getDay() - weekStart + 7) % 7));
    const days: CalendarDay[] = [];
    for (let i = 0; i < 42; i++) {
      const key = ScheduleService.shift(start, i);
      const count = ScheduleService.project(tasks, states, 'calendar', key, 0).length;
      days.push({ key: key, day: ScheduleService.date(key).getDate(), inMonth: key.slice(0, 7) === month.slice(0, 7), count: count });
    }
    return days;
  }
  static repeatLabel(repeat: string): string {
    return repeat === 'daily' ? '每天' : repeat === 'weekly' ? '每周' : repeat === 'monthly' ? '每月' : repeat === 'yearly' ? '每年' : '不重复';
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
    const anchor = ScheduleService.key(candidate.dueAt), today = ScheduleService.key(now);
    const first = candidate.repeat === 'none' || anchor > today ? anchor : today;
    const existing = tasks.find((task: Task) => task.id === candidate.id);
    const keepHistory = existing !== undefined && existing.repeat === candidate.repeat && existing.dueAt === candidate.dueAt;
    const seen = new Set<string>();
    const others = tasks.filter((task: Task) => task.id !== candidate.id);
    for (let day = 0; day < (candidate.repeat === 'none' ? 1 : 30); day++) {
      const key = ScheduleService.shift(first, day);
      const ownItems = ScheduleService.project([candidate], keepHistory ? states : [], 'calendar', key, now);
      for (const own of ownItems) {
        if (own.completed || (own.task.startMinute ?? -1) < 0) { continue; }
        const start = ScheduleService.startTime(own), end = start + (own.task.durationMinutes ?? 30) * 60000;
        for (const offset of [-1, 0, 1]) {
          for (const item of ScheduleService.project(others, states, 'calendar', ScheduleService.shift(key, offset), now)) {
            if (item.completed || (item.task.startMinute ?? -1) < 0 || seen.has(item.key)) { continue; }
            const otherStart = ScheduleService.startTime(item);
            if (start < otherStart + (item.task.durationMinutes ?? 30) * 60000 && end > otherStart) {
              result.push({ title: item.task.title, dateKey: ScheduleService.key(item.dueAt), time: TaskService.timeLabel(item.task) }); seen.add(item.key);
              if (result.length === 5) { return result; }
            }
          }
        }
      }
    }
    return result;
  }
}
