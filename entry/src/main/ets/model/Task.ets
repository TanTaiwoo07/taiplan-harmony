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
}
export interface LegacyDocument { version: number; tasks: LegacyTask[]; }
export interface TaskDraft {
  title: string;
  note: string;
  priority: number;
  tagsText: string;
  dueAt: number;
  repeat?: string;
}

export interface OccurrenceState {
  taskId: string;
  dateKey: string;
  completed: boolean;
  skipped: boolean;
  updatedAt: number;
}

export interface TaskItem {
  key: string;
  task: Task;
  dateKey: string;
  dueAt: number;
  completed: boolean;
}

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
