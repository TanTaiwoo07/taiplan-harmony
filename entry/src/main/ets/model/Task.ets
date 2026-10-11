import { ProductState } from './Product';
export interface LegacyTask {
  id: string;
  title: string;
  note: string;
  completed: boolean;
  createdAt: number;
  updatedAt: number;
}
export interface Task extends LegacyTask {
  priority: number; // 0 = 低，1 = 中，2 = 高
  tags: string[];
  dueAt: number; // 本地截止日期的当天末尾；0 表示未设置
  repeat: string; // none / daily / weekly / monthly
  sortOrder: number;
  startMinute?: number; // -1 全天，否则本地 00:00 起的分钟数
  durationMinutes?: number;
  steps?: string[];
  doneSteps?: number[]; // 普通任务的步骤进度；重复任务使用日期状态
  planning?: TaskPlanning; // v5: dueAt/startMinute remain a compatibility projection, not a deadline.
  overrides?: OccurrenceOverride[];
}
export interface OccurrenceOverride { originalDate: string; draft: TaskDraft; updatedAt: number; }
export interface LegacyDocument { version: number; tasks: LegacyTask[]; }
export interface TaskDraft {
  title: string;
  note: string;
  priority: number;
  tagsText: string;
  dueAt: number;
  repeat?: string;
  startMinute?: number;
  durationMinutes?: number;
  stepsText?: string;
  planning?: TaskPlanning;
}

export interface RecurrenceRule {
  interval: number;
  weekdays: number[]; // ISO Monday=1, Sunday=7
  untilDate: string;
  count: number; // 0 means no count limit
}
export interface TaskPlanning {
  reminder?: ReminderRule;
  kind: string;
  scheduleMode: string;
  plannedDate: string;
  startAt: number;
  endAt: number;
  timeZone: string;
  deadlineMode: string;
  deadlineAt: number;
  location: string;
  listName: string;
  sourceType: string;
  legacyTimeSemantics: boolean;
  rule: RecurrenceRule;
}
export interface ReminderRule { mode: string; leadMinutes: number; at: number; }

export interface AppPreferences {
  startPage: number;
  calendarView: string;
  weekStart: number;
  snapMinutes: number;
  showCompleted: boolean;
  useMaterial: boolean;
  reduceMotion?: boolean;
}

export interface OccurrenceState {
  taskId: string;
  dateKey: string;
  completed: boolean;
  skipped: boolean;
  updatedAt: number;
  doneSteps?: number[];
}

export interface TaskItem {
  key: string;
  task: Task;
  dateKey: string;
  dueAt: number;
  completed: boolean;
  doneSteps?: number[];
}

export interface TimeConflict { title: string; dateKey: string; time: string; }

export interface CalendarDay {
  key: string;
  day: number;
  inMonth: boolean;
  count: number;
}

export interface BackupDocument {
  settings?: BackupSettings;
  product?: ProductState;
  format: string;
  version: number;
  exportedAt: number;
  tasks: Task[];
  occurrences: OccurrenceState[];
}
export interface BackupAiConfig { endpoint: string; model: string; }
export interface BackupSettings { display: AppPreferences; theme: string; sort: string; ai?: BackupAiConfig; }
