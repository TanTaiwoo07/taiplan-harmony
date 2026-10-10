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
}
export interface LegacyDocument { version: number; tasks: LegacyTask[]; }
export interface TaskDraft {
  title: string;
  note: string;
  priority: number;
  tagsText: string;
  dueAt: number;
}
