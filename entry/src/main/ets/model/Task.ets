export interface Task {
  id: string;
  title: string;
  note: string;
  completed: boolean;
  createdAt: number;
  updatedAt: number;
}

export interface TaskDocument {
  version: number;
  tasks: Task[];
}

// 业务规则独立于界面和存储，后续扩展标签、优先级时集中在这里处理。
export class TaskService {
  static create(title: string, note: string, id: string, now: number): Task {
    const cleanTitle = title.trim();
    if (cleanTitle.length === 0 || cleanTitle.length > 100 || note.length > 1000) {
      throw new Error('请输入 1～100 字的标题，备注最多 1000 字');
    }
    return { id: id, title: cleanTitle, note: note.trim(), completed: false, createdAt: now, updatedAt: now };
  }

  static edit(task: Task, title: string, note: string, now: number): Task {
    const edited = TaskService.create(title, note, task.id, task.createdAt);
    edited.completed = task.completed;
    edited.updatedAt = now;
    return edited;
  }

  static toggle(task: Task, now: number): Task {
    return { id: task.id, title: task.title, note: task.note, completed: !task.completed,
      createdAt: task.createdAt, updatedAt: now };
  }

  static section(tasks: Task[], completed: boolean): Task[] {
    return tasks.filter((task: Task) => task.completed === completed)
      .sort((a: Task, b: Task) => b.createdAt - a.createdAt || b.id.localeCompare(a.id));
  }

  static decode(raw: string): Task[] {
    const document = JSON.parse(raw) as TaskDocument;
    if (!document || document.version !== 1 || !Array.isArray(document.tasks)) {
      throw new Error('任务数据格式不兼容');
    }
    const ids: string[] = [];
    for (const task of document.tasks) {
      if (!task || typeof task.id !== 'string' || task.id.length === 0 || ids.includes(task.id) ||
        typeof task.title !== 'string' || task.title.trim().length === 0 || task.title.length > 100 ||
        typeof task.note !== 'string' || task.note.length > 1000 || typeof task.completed !== 'boolean' ||
        typeof task.createdAt !== 'number' || !Number.isFinite(task.createdAt) ||
        typeof task.updatedAt !== 'number' || !Number.isFinite(task.updatedAt)) {
        throw new Error('任务数据损坏');
      }
      ids.push(task.id);
    }
    return document.tasks;
  }

  static encode(tasks: Task[]): string {
    const document: TaskDocument = { version: 1, tasks: tasks };
    return JSON.stringify(document);
  }
}
