import { Task } from '../model/Task';
import { PlanningService } from './PlanningService';
export class EditorOptionsService {
  static leadLabel(minutes: number): string {
    if (minutes === 0) { return '准时提醒'; }
    const days = Math.floor(minutes / 1440), hours = Math.floor(minutes % 1440 / 60), rest = minutes % 60;
    return '提前 ' + (days ? days.toString() + ' 天 ' : '') + (hours ? hours.toString() + ' 小时 ' : '') + (rest ? rest.toString() + ' 分钟' : '');
  }
  static lead(days: string, hours: string, minutes: string): number {
    if (![days, hours, minutes].every((part: string) => /^\d{1,3}$/.test(part))) { throw new Error('提前量请填写非负整数'); }
    const total = Number(days) * 1440 + Number(hours) * 60 + Number(minutes);
    if (Number(hours) > 23 || Number(minutes) > 59 || total > 10080) { throw new Error('最多提前 7 天，小时为 0–23，分钟为 0–59'); }
    return total;
  }
  static repeat(task: Task): string {
    if (task.repeat === 'none') { return '不重复'; }
    const rule = PlanningService.forTask(task).rule;
    const unit = task.repeat === 'daily' ? '天' : task.repeat === 'weekly' ? '周' : task.repeat === 'monthly' ? '个月' : '年';
    let label = '每 ' + rule.interval.toString() + ' ' + unit;
    if (task.repeat === 'weekly' && rule.weekdays.length) { label += ' · ' + rule.weekdays.slice().sort((a: number, b: number) => a - b).map((day: number) => '周' + ['一', '二', '三', '四', '五', '六', '日'][day - 1]).join('、'); }
    return label + (rule.untilDate ? '，至 ' + rule.untilDate : rule.count ? '，共 ' + rule.count.toString() + ' 次' : '，不设结束');
  }
}
