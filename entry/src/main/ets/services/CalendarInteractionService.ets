import { TaskItem } from '../model/Task';
import { ScheduleService } from './ScheduleService';
import { TaskService } from './TaskService';
export class CalendarInteractionService {
  static height(value: number): number { return Math.max(30, Math.min(120, value)); }
  static minutes(offset: number, height: number, snap: number): number {
    if (!Number.isFinite(offset) || !Number.isFinite(height) || height < 30 || height > 120 || ![5, 15, 30].includes(snap)) { throw new Error('时间表刻度无效'); }
    return Math.round(offset / (height / 60) / snap) * snap;
  }
  static anchor(offset: number, center: number, oldHeight: number, newHeight: number, viewport: number): number {
    return Math.max(0, Math.min(24 * newHeight - viewport, (offset + center) / oldHeight * newHeight - center));
  }
  static preview(item: TaskItem, days: number, minutes: number, resize: boolean): string {
    const date = ScheduleService.date(ScheduleService.key(item.dueAt));
    date.setDate(date.getDate() + (resize ? 0 : days));
    date.setHours(0, (item.task.startMinute ?? 0) + (resize ? 0 : minutes), 0, 0);
    const duration = Math.max(5, Math.min(1440, (item.task.durationMinutes ?? 30) + (resize ? minutes : 0)));
    const end = new Date(date.getTime() + duration * 60000);
    return ScheduleService.key(date.getTime()) + ' · ' + TaskService.minuteLabel(date.getHours() * 60 + date.getMinutes()) + '–' +
      TaskService.minuteLabel(end.getHours() * 60 + end.getMinutes()) + (ScheduleService.key(date.getTime()) !== ScheduleService.key(end.getTime()) ? '（次日）' : '');
  }
}
