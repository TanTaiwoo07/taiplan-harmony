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
}
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
  format: string;
  version: number;
  exportedAt: number;
  tasks: Task[];
  occurrences: OccurrenceState[];
}
