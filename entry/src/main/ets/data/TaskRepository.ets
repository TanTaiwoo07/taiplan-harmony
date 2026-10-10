import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { Task, TaskService } from '../model/Task';

export class TaskRepository {
  private store: preferences.Preferences | undefined = undefined;

  async load(context: common.UIAbilityContext): Promise<Task[]> {
    this.store = await preferences.getPreferences(context, { name: 'taiplan_tasks_v1' });
    const value = await this.store.get('document', '');
    if (typeof value !== 'string') {
      throw new Error('任务数据类型错误');
    }
    return value.length === 0 ? [] : TaskService.decode(value);
  }

  async save(tasks: Task[]): Promise<void> {
    const store = this.store;
    if (!store) {
      throw new Error('任务存储尚未就绪');
    }
    await store.put('document', TaskService.encode(tasks));
    // 等磁盘写入成功再更新页面，失败时保留原列表和编辑内容。
    await store.flush();
  }
}
