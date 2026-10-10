import { ProductState } from '../model/Product';
import { ProductService } from './ProductService';
import { PlanningService } from './PlanningService';
import { ReminderIntent } from './ReminderPlanService';
export class ProductReminderService {
  static intents(state: ProductState, now: number): ReminderIntent[] {
    const result: ReminderIntent[] = []; const today = PlanningService.key(now);
    const active = ProductService.active(state);
    if (active?.status === 'running') {
      const at = Math.ceil((active.resumedAt + (active.targetSeconds - active.elapsedSeconds) * 1000) / 60000) * 60000;
      if (at > now) { result.push({ key: 'focus:' + active.id, taskId: 'tool:focus', originalDate: '', at: at, title: '专注计时结束', content: active.title + ' · 打开查看记录' }); }
    }
    for (let offset = 0; offset < 8; offset++) {
      const day = ProductService.shift(today, offset);
      for (const habit of state.habits) {
        if ((habit.reminderMinute ?? -1) < 0 || !ProductService.scheduled(habit, day) || ProductService.count(habit, day) >= habit.dailyTarget ||
          (habit.weeklyTarget > 0 && ProductService.weekCount(habit, day) >= habit.weeklyTarget)) { continue; }
        const date = PlanningService.date(day); date.setHours(0, habit.reminderMinute, 0, 0);
        if (date.getTime() > now && date.getTime() <= now + 7 * 86400000) {
          result.push({ key: 'habit:' + habit.id + '@' + day, taskId: 'tool:habits', originalDate: day, at: date.getTime(), title: '习惯打卡 · ' + habit.title, content: '今天的习惯还未完成' });
        }
      }
    }
    for (const item of state.countdowns) {
      if ((item.reminderDays ?? -1) < 0) { continue; }
      const target = ProductService.nextDate(item, today);
      const date = PlanningService.date(ProductService.shift(target, -(item.reminderDays ?? 0))); date.setHours(9, 0, 0, 0);
      if (date.getTime() > now && date.getTime() <= now + 7 * 86400000) {
        result.push({ key: 'countdown:' + item.id + '@' + target, taskId: 'tool:countdowns', originalDate: target, at: date.getTime(),
          title: '纪念日提醒 · ' + item.title, content: target + ' · ' + (item.reminderDays === 0 ? '就是今天' : '提前 ' + item.reminderDays?.toString() + ' 天') });
      }
    }
    return result.sort((a: ReminderIntent, b: ReminderIntent) => a.at - b.at || a.key.localeCompare(b.key));
  }
}
