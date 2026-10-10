import { TaskDraft } from '../model/Task';
import { ScheduleService } from './ScheduleService';

export class QuickEntryService {
  static parse(input: string, now: number): TaskDraft {
    let title = input.trim();
    if (title.length === 0) { throw new Error('先输入一句想做的事'); }
    let priority = 1;
    if (/高优先级|!高/.test(title)) { priority = 2; }
    else if (/低优先级|!低/.test(title)) { priority = 0; }
    title = title.replace(/高优先级|中优先级|低优先级|!高|!中|!低/g, ' ');
    const tags = title.match(/#[^\s#，,]+/g) ?? [];
    title = title.replace(/#[^\s#，,]+/g, ' ');
    const today = ScheduleService.key(now);
    let key = '';
    let repeat = 'none';
    let startMinute = -1;
    let durationMinutes = 30;
    const clock = title.match(/(?:^|\s)(\d{1,2})[:：](\d{2})(?=\s|$)/);
    if (clock) {
      const hour = Number(clock[1]); const minute = Number(clock[2]);
      if (hour > 23 || minute > 59) { throw new Error('时间无效，请使用 00:00～23:59'); }
      startMinute = hour * 60 + minute; title = title.replace(clock[0], ' ');
    }
    const duration = title.match(/(?:用时|持续)\s*(\d+)\s*分钟/);
    if (duration) { durationMinutes = Number(duration[1]); title = title.replace(duration[0], ' '); }
    const weekly = title.match(/每周([一二三四五六日天])?/);
    if (/每天|每日/.test(title)) { repeat = 'daily'; key = today; title = title.replace(/每天|每日/, ' '); }
    else if (weekly) {
      repeat = 'weekly'; key = today;
      if (weekly[1]) {
        const target = '日一二三四五六'.indexOf(weekly[1] === '天' ? '日' : weekly[1]);
        key = ScheduleService.shift(today, (target - new Date(now).getDay() + 7) % 7);
      }
      title = title.replace(weekly[0], ' ');
    } else if (/每月/.test(title)) { repeat = 'monthly'; key = today; title = title.replace('每月', ' '); }
    const explicit = title.match(/(\d{4})[-/](\d{1,2})[-/](\d{1,2})/);
    if (explicit) {
      key = `${explicit[1]}-${explicit[2].padStart(2, '0')}-${explicit[3].padStart(2, '0')}`;
      if (!ScheduleService.validKey(key)) { throw new Error('这一天不存在，请检查日期'); }
      title = title.replace(explicit[0], ' ');
    } else if (/后天/.test(title)) { key = ScheduleService.shift(today, 2); title = title.replace('后天', ' '); }
    else if (/明天/.test(title)) { key = ScheduleService.shift(today, 1); title = title.replace('明天', ' '); }
    else if (/今天/.test(title)) { key = today; title = title.replace('今天', ' '); }
    else {
      const nextWeek = title.match(/下周([一二三四五六日天])/);
      if (nextWeek) {
        const target = '一二三四五六日'.indexOf(nextWeek[1] === '天' ? '日' : nextWeek[1]);
        key = ScheduleService.shift(today, 7 - (new Date(now).getDay() + 6) % 7 + target);
        title = title.replace(nextWeek[0], ' ');
      }
    }
    title = title.replace(/\s+/g, ' ').trim();
    if (startMinute >= 0 && key.length === 0) { key = today; }
    if (title.length === 0) { throw new Error('还需要输入任务内容，例如：明天交报告 #学习'); }
    return { title: title, note: '', priority: priority, tagsText: tags.map((tag: string) => tag.slice(1)).join(','),
      dueAt: key.length > 0 ? ScheduleService.end(key) : 0, repeat: repeat, startMinute: startMinute, durationMinutes: durationMinutes };
  }
}
