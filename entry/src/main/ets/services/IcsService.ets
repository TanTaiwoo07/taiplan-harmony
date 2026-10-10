import { BackupDocument, OccurrenceState, Task } from '../model/Task';
import { TaskService } from './TaskService';
import { ScheduleService } from './ScheduleService';

export interface IcsReport { document: BackupDocument; notes: string[]; total: number; }
interface IcsProperty { name: string; head: string; value: string; }
interface IcsDate { timestamp: number; allDay: boolean; }

// 严格的 VEVENT 子集：无法保持含义的事件跳过并逐项报告，不猜测时区或重复规则。
export class IcsService {
  static unescape(value: string): string {
    return value.replace(/\\([nN,;\\])/g, (match: string, char: string) => char === 'n' || char === 'N' ? '\n' : char);
  }
  static escape(value: string): string {
    return value.replace(/\\/g, '\\\\').replace(/\r\n|\r|\n/g, '\\n').replace(/,/g, '\\,').replace(/;/g, '\\;');
  }
  private static property(line: string): IcsProperty {
    let quoted = false;
    for (let i = 0; i < line.length; i++) {
      if (line[i] === '"') { quoted = !quoted; }
      if (line[i] === ':' && !quoted) {
        const head = line.slice(0, i);
        return { name: head.split(';')[0].toUpperCase(), head: head, value: line.slice(i + 1) };
      }
    }
    throw new Error('属性缺少冒号');
  }
  private static date(prop: IcsProperty): IcsDate {
    const value = prop.value.trim();
    const match = value.match(/^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})(Z)?)?$/);
    if (!match) { throw new Error('日期时间格式不支持'); }
    const key = `${match[1]}-${match[2]}-${match[3]}`;
    if (!ScheduleService.validKey(key) || Number(match[1]) < 2000 || Number(match[1]) > 2100) { throw new Error('日期超出 2000～2100 或不存在'); }
    const allDay = !match[4];
    if (/;VALUE=DATE(?:;|$)/i.test(prop.head) && !allDay) { throw new Error('全天事件的日期格式无效'); }
    const zoneMatch = prop.head.match(/;TZID=(?:"([^"]+)"|([^;]+))/i);
    const zone = zoneMatch ? zoneMatch[1] || zoneMatch[2] : '';
    if (zone.length > 0 && zone !== 'Asia/Shanghai' && zone !== 'UTC' && zone !== 'Etc/UTC') { throw new Error(`暂不支持时区 ${zone}`); }
    if (allDay) { return { timestamp: ScheduleService.date(key).getTime(), allDay: true }; }
    const hour = Number(match[4]), minute = Number(match[5]), second = Number(match[6]);
    if (hour > 23 || minute > 59 || second !== 0) { throw new Error('时间无效或精度不是整分钟'); }
    let date: Date;
    if (match[7] || zone.length > 0) {
      const offset = !match[7] && zone === 'Asia/Shanghai' ? 8 * 60 : 0;
      date = new Date(Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3]), hour, minute - offset));
    } else {
      date = ScheduleService.date(key); date.setHours(hour, minute, 0, 0);
      if (date.getHours() !== hour || date.getMinutes() !== minute) { throw new Error('本地时区不存在这个时间'); }
    }
    return { timestamp: date.getTime(), allDay: false };
  }
  private static event(lines: string[], now: number): Task {
    const values = new Map<string, IcsProperty>();
    let nested = 0;
    for (const line of lines) {
      const prop = IcsService.property(line);
      if (prop.name === 'BEGIN') { nested++; continue; }
      if (prop.name === 'END') { nested--; continue; }
      if (nested > 0) { continue; }
      if (['RRULE', 'RDATE', 'EXDATE', 'RECURRENCE-ID', 'DURATION'].includes(prop.name)) { throw new Error(`${prop.name} 暂不支持，请先导出展开后的单次事件`); }
      if (values.has(prop.name)) { throw new Error(`重复属性 ${prop.name}`); }
      values.set(prop.name, prop);
    }
    if (values.get('STATUS')?.value.toUpperCase() === 'CANCELLED') { throw new Error('已取消的事件'); }
    const uid = IcsService.unescape(values.get('UID')?.value ?? '').trim();
    if (uid.length === 0 || uid.length > 120 || /[\r\n]/.test(uid)) { throw new Error('缺少 UID 或 UID 超过 120 字'); }
    const startProp = values.get('DTSTART');
    if (!startProp) { throw new Error('缺少开始日期'); }
    const start = IcsService.date(startProp);
    const endProp = values.get('DTEND');
    const key = ScheduleService.key(start.timestamp);
    let duration = 30;
    if (endProp) {
      const end = IcsService.date(endProp);
      if (start.allDay !== end.allDay || end.timestamp <= start.timestamp) { throw new Error('起止时间不一致'); }
      if (start.allDay) {
        if (ScheduleService.key(end.timestamp) !== ScheduleService.shift(key, 1)) { throw new Error('跨多日的全天事件暂不支持'); }
      } else {
        duration = (end.timestamp - start.timestamp) / 60000;
      }
    }
    const note = [IcsService.unescape(values.get('DESCRIPTION')?.value ?? ''),
      values.has('LOCATION') ? `地点：${IcsService.unescape(values.get('LOCATION')?.value ?? '')}` : '',
      values.get('URL')?.value ?? ''].filter((part: string) => part.length > 0).join('\n');
    const priority = Number(values.get('PRIORITY')?.value ?? 0);
    const date = new Date(start.timestamp);
    const task = TaskService.create({ title: IcsService.unescape(values.get('SUMMARY')?.value ?? ''), note: note,
      priority: priority >= 1 && priority <= 4 ? 2 : priority >= 6 && priority <= 9 ? 0 : 1,
      tagsText: '日历导入', dueAt: ScheduleService.end(key), repeat: 'none',
      startMinute: start.allDay ? -1 : date.getHours() * 60 + date.getMinutes(), durationMinutes: duration }, `ics:${uid}`, now);
    task.completed = values.get('X-TAIPLAN-COMPLETED')?.value === 'TRUE';
    return task;
  }
  static parse(raw: string, now: number): IcsReport {
    if (raw.length > 4 * 1024 * 1024) { throw new Error('日历文件超过 4 MB'); }
    const lines = raw.replace(/^\uFEFF/, '').replace(/\r\n/g, '\n').replace(/\r/g, '\n').replace(/\n[ \t]/g, '').split('\n');
    if (!lines.includes('BEGIN:VCALENDAR') || !lines.includes('END:VCALENDAR')) { throw new Error('不是完整的 iCalendar 文件'); }
    const tasks: Task[] = [], notes: string[] = [], event: string[] = [];
    const ids = new Set<string>();
    let active = false, total = 0;
    for (const line of lines) {
      if (line === 'BEGIN:VEVENT') {
        if (active) { throw new Error('日历事件嵌套错误'); }
        active = true; event.length = 0; continue;
      }
      if (line === 'END:VEVENT') {
        if (!active) { throw new Error('日历事件结构错误'); }
        active = false; total++;
        if (total > 5000) { throw new Error('最多导入 5000 条事件'); }
        try {
          const task = IcsService.event(event, now);
          if (ids.has(task.id)) { throw new Error('文件中 UID 重复'); }
          ids.add(task.id); tasks.push(task);
        } catch (error) { notes.push(`第 ${total} 条：${(error as Error).message}`); }
      } else if (active && line.length > 0) { event.push(line); }
      else if (line === 'BEGIN:VTODO') { notes.push('VTODO 待办组件暂不支持'); }
    }
    if (active) { throw new Error('日历事件未结束'); }
    return { document: { format: 'TaiPlanHarmony', version: 4, exportedAt: now, tasks: tasks, occurrences: [] }, notes: notes, total: total };
  }
  private static stamp(timestamp: number): string {
    return new Date(timestamp).toISOString().replace(/[-:]/g, '').replace(/\.\d{3}Z$/, 'Z');
  }
  private static fold(line: string): string {
    let result = '', width = 0;
    for (const char of line) {
      const code = char.codePointAt(0) ?? 0;
      const size = code < 128 ? 1 : code < 2048 ? 2 : code < 65536 ? 3 : 4;
      if (width + size > 75) { result += '\r\n '; width = 1; }
      result += char; width += size;
    }
    return result;
  }
  static exportMonth(tasks: Task[], states: OccurrenceState[], now: number): string {
    const lines = ['BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//TaiPlan//Harmony 0.4//ZH', 'CALSCALE:GREGORIAN'];
    const today = ScheduleService.key(now);
    let count = 0;
    for (let offset = 0; offset < 30; offset++) {
      const key = ScheduleService.shift(today, offset);
      for (const item of ScheduleService.project(tasks, states, 'calendar', key, now)) {
        count++;
        if (count > 5000) { throw new Error('未来 30 天超过 5000 条事件，暂不能整体导出'); }
        const task = item.task;
        lines.push('BEGIN:VEVENT', `UID:${IcsService.escape(`${task.id}@${key}@taiplan`)}`, `DTSTAMP:${IcsService.stamp(now)}`);
        if ((task.startMinute ?? -1) < 0) {
          lines.push(`DTSTART;VALUE=DATE:${key.replace(/-/g, '')}`, `DTEND;VALUE=DATE:${ScheduleService.shift(key, 1).replace(/-/g, '')}`);
        } else {
          const end = TaskService.deadline(task, item.dueAt);
          lines.push(`DTSTART:${IcsService.stamp(end - (task.durationMinutes ?? 30) * 60000)}`, `DTEND:${IcsService.stamp(end)}`);
        }
        const steps = (task.steps ?? []).map((step: string, index: number) => `${(item.doneSteps ?? []).includes(index) ? '[x]' : '[ ]'} ${step}`).join('\n');
        lines.push(`SUMMARY:${IcsService.escape(task.title)}`, `DESCRIPTION:${IcsService.escape([task.note, steps].filter((s: string) => s.length > 0).join('\n'))}`,
          `PRIORITY:${task.priority === 2 ? 1 : task.priority === 0 ? 9 : 5}`, `X-TAIPLAN-COMPLETED:${item.completed ? 'TRUE' : 'FALSE'}`, 'END:VEVENT');
      }
    }
    lines.push('END:VCALENDAR');
    return lines.map((line: string) => IcsService.fold(line)).join('\r\n') + '\r\n';
  }
}
