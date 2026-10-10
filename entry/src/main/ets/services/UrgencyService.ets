import { Task } from '../model/Task';
import { PlanningService } from './PlanningService';
import { ScheduleService } from './ScheduleService';

export class UrgencyService {
  static duration(milliseconds: number): string {
    const minutes = Math.max(1, Math.ceil(Math.abs(milliseconds) / 60000));
    return minutes < 60 ? minutes.toString() + ' 分钟' : minutes < 1440 ?
      Math.floor(minutes / 60).toString() + ' 小时' + (minutes % 60 ? ' ' + (minutes % 60).toString() + ' 分钟' : '') :
      Math.floor(minutes / 1440).toString() + ' 天';
  }
  static label(task: Task, day: number, completed: boolean, now: number): string {
    if (completed) { return ''; }
    const deadline = PlanningService.deadline(task, day);
    if (deadline > 0 && deadline < now) { return '已逾期 ' + UrgencyService.duration(now - deadline); }
    if (deadline > 0 && deadline - now <= 3600000) { return '即将截止 · 剩余 ' + UrgencyService.duration(deadline - now); }
    if (task.priority === 2) { return '！紧急 · 高优先级'; }
    return '';
  }
  static clock(at: number): string {
    const date = new Date(at);
    return date.getHours().toString().padStart(2, '0') + ':' + date.getMinutes().toString().padStart(2, '0');
  }
  static deadlineText(task: Task, day: number): string {
    const at = PlanningService.deadline(task, day);
    return at === 0 ? '' : '截止 · ' + ScheduleService.key(at) + (PlanningService.forTask(task).deadlineMode === 'date' ? ' 当天结束' : ' ' + UrgencyService.clock(at));
  }
}
