import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { Task, OccurrenceState } from '../model/Task';
import { ReminderPlanService, ReminderIntent } from '../services/ReminderPlanService';
interface ReminderLink { key: string; at: number; title: string; state: string; systemId: number; }
export class ReminderService {
  private running: boolean = false;
  async enable(context: common.UIAbilityContext): Promise<void> {
    if (!canIUse('SystemCapability.Notification.ReminderAgent')) { throw new Error('此设备不支持代理提醒'); }
    await notificationManager.requestEnableNotification(context);
    if (!await notificationManager.isNotificationEnabled()) { throw new Error('通知未授权'); }
    const store = await preferences.getPreferences(context, { name: 'taiplan_reminders' }); await store.put('enabled', true); await store.flush();
  }
  private request(intent: ReminderIntent, notificationId: number): reminderAgentManager.ReminderRequestCalendar {
    const date = new Date(intent.at);
    return { reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR,
      dateTime: { year: date.getFullYear(), month: date.getMonth() + 1, day: date.getDate(), hour: date.getHours(), minute: date.getMinutes() },
      title: intent.title, content: 'TaiPlan · 到安排时间了', ringDuration: 1, notificationId: notificationId,
      slotType: notificationManager.SlotType.SERVICE_INFORMATION,
      actionButton: [{ title: '关闭', type: reminderAgentManager.ActionButtonType.ACTION_BUTTON_TYPE_CLOSE }],
      wantAgent: { pkgName: 'com.taiwoo.taiplan', abilityName: 'EntryAbility', parameters: { taiplanKey: intent.key, taskId: intent.taskId, originalDate: intent.originalDate, reminderAt: intent.at } } };
  }
  async sync(context: common.UIAbilityContext, tasks: Task[], states: OccurrenceState[]): Promise<string> {
    if (this.running) { return '提醒正在同步'; } this.running = true;
    try {
      const store = await preferences.getPreferences(context, { name: 'taiplan_reminders' });
      if (!await store.get('enabled', false)) { return '系统提醒未启用'; }
      const all = ReminderPlanService.intents(tasks, states, Date.now()); const wanted = all.slice(0, 50);
      const links: ReminderLink[] = wanted.map((item: ReminderIntent): ReminderLink => { return { key: item.key, at: item.at, title: item.title, state: 'pending', systemId: -1 }; });
      await store.put('journal', JSON.stringify(links)); await store.flush();
      const valid = await reminderAgentManager.getAllValidReminders();
      for (const existing of valid) {
        const params = existing.reminderReq.wantAgent?.parameters;
        if (typeof params?.taiplanKey !== 'string') { continue; }
        const link = links.find((item: ReminderLink) => item.key === params.taiplanKey && item.at === params.reminderAt && item.title === existing.reminderReq.title && item.systemId === -1);
        if (link) { link.state = 'registered'; link.systemId = existing.reminderId; }
        else { await reminderAgentManager.cancelReminder(existing.reminderId); }
      }
      let failed = 0; let errorCode = 0;
      for (let i = 0; i < links.length; i++) {
        if (links[i].systemId >= 0) { continue; }
        try {
          const notificationId = (await store.get('nextNotificationId', 1000) as number) + 1;
          await store.put('nextNotificationId', notificationId); await store.flush();
          links[i].systemId = await reminderAgentManager.publishReminder(this.request(wanted[i], notificationId)); links[i].state = 'registered';
        }
        catch (error) { errorCode = (error as BusinessError).code; links[i].state = 'failed:' + errorCode.toString(); failed++; }
        await store.put('journal', JSON.stringify(links)); await store.flush();
      }
      await store.put('journal', JSON.stringify(links)); await store.flush();
      return '未来 7 天已登记 ' + links.filter((link: ReminderLink) => link.state === 'registered').length.toString() + ' 条' +
        (failed ? '；失败 ' + failed.toString() + ' 条（系统代码 ' + errorCode.toString() + '），可重试' : '') + (all.length > 50 ? '；超过 50 条的暂未登记' : '');
    } catch { return '提醒同步失败或未授权；任务已保留，请重试。旧提醒可能尚未取消。'; }
    finally { this.running = false; }
  }
  async disable(context: common.UIAbilityContext): Promise<void> {
    if (this.running) { throw new Error('正在同步，请稍后再关闭'); }
    const valid = await reminderAgentManager.getAllValidReminders();
    for (const item of valid) { if (typeof item.reminderReq.wantAgent?.parameters?.taiplanKey === 'string') { await reminderAgentManager.cancelReminder(item.reminderId); } }
    const store = await preferences.getPreferences(context, { name: 'taiplan_reminders' }); await store.put('enabled', false); await store.put('journal', '[]'); await store.flush();
  }
}
