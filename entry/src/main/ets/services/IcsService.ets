import { PlanningService } from './PlanningService';
import { OccurrenceService } from './OccurrenceService';
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
      if (['RDATE', 'RECURRENCE-ID', 'DURATION'].includes(prop.name)) { throw new Error(`${prop.name} 暂不支持，请先导出展开后的单次事件`); }
      if (prop.name === 'EXDATE') { continue; }
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
    const minute = start.allDay ? -1 : date.getHours() * 60 + date.getMinutes();
    const plan = PlanningService.create(ScheduleService.end(key), minute, duration, values.has('X-TAIPLAN-COMPLETED') ? 'task' : 'event');
    plan.location = IcsService.unescape(values.get('LOCATION')?.value ?? ''); plan.sourceType = 'ics';
    let repeat = 'none';
    const rule = values.get('RRULE');
    if (rule) {
      const parts = new Map<string, string>();
      for (const field of rule.value.split(';')) { const pair = field.split('=');
        if (pair.length !== 2 || parts.has(pair[0]) || !['FREQ', 'INTERVAL', 'BYDAY', 'COUNT', 'UNTIL', 'WKST'].includes(pair[0])) { throw new Error('RRULE 包含不支持的字段'); } parts.set(pair[0], pair[1]); }
      repeat = (parts.get('FREQ') ?? '').toLowerCase();
      if (!['daily', 'weekly', 'monthly', 'yearly'].includes(repeat) || (parts.has('WKST') && parts.get('WKST') !== 'MO')) { throw new Error('RRULE 频率或周起始不支持'); }
      if ((repeat === 'monthly' && date.getDate() > 28) || (repeat === 'yearly' && date.getMonth() === 1 && date.getDate() === 29)) { throw new Error('RRULE 月末或闰日跳过语义暂不支持'); }
      plan.rule.interval = Number(parts.get('INTERVAL') ?? 1); plan.rule.count = Number(parts.get('COUNT') ?? 0);
      if (parts.has('BYDAY')) { if (repeat !== 'weekly') { throw new Error('RRULE BYDAY 仅支持每周'); }
        plan.rule.weekdays = (parts.get('BYDAY') ?? '').split(',').map((day: string) => ['MO','TU','WE','TH','FR','SA','SU'].indexOf(day) + 1); }
      if (parts.has('UNTIL')) { const until = IcsService.date({ name: 'UNTIL', head: 'UNTIL', value: parts.get('UNTIL') ?? '' });
        plan.rule.untilDate = ScheduleService.key(until.timestamp);
        if (!until.allDay) { const boundary = new Date(until.timestamp); if (boundary.getHours() * 60 + boundary.getMinutes() < minute) { plan.rule.untilDate = ScheduleService.shift(plan.rule.untilDate, -1); } }
      }
    }
    const task = TaskService.create({ title: IcsService.unescape(values.get('SUMMARY')?.value ?? ''), note: note,
      priority: priority >= 1 && priority <= 4 ? 2 : priority >= 6 && priority <= 9 ? 0 : 1,
      tagsText: '日历导入', dueAt: ScheduleService.end(key), repeat: repeat, planning: plan,
      startMinute: start.allDay ? -1 : date.getHours() * 60 + date.getMinutes(), durationMinutes: duration }, `ics:${uid}`, now);
    task.completed = values.get('X-TAIPLAN-COMPLETED')?.value === 'TRUE';
    return task;
  }
  static parse(raw: string, now: number): IcsReport {
    if (raw.length > 4 * 1024 * 1024) { throw new Error('日历文件超过 4 MB'); }
    const lines = raw.replace(/^\uFEFF/, '').replace(/\r\n/g, '\n').replace(/\r/g, '\n').replace(/\n[ \t]/g, '').split('\n');
    if (!lines.includes('BEGIN:VCALENDAR') || !lines.includes('END:VCALENDAR')) { throw new Error('不是完整的 iCalendar 文件'); }
    const tasks: Task[] = [], notes: string[] = [], event: string[] = [];
    const occurrences: OccurrenceState[] = []; const groups = new Map<string, string[][]>();
    let active = false, total = 0;
    for (const line of lines) {
      if (line === 'BEGIN:VEVENT') { if (active) { throw new Error('日历事件嵌套错误'); } active = true; event.length = 0; continue; }
      if (line === 'END:VEVENT') {
        if (!active) { throw new Error('日历事件结构错误'); } active = false; total++;
        if (total > 5000) { throw new Error('最多导入 5000 条事件'); }
        const uid = event.find((value: string) => value.startsWith('UID:')) ?? 'missing:' + total.toString();
        const entries = groups.get(uid) ?? []; entries.push(event.slice()); groups.set(uid, entries);
      } else if (active && line.length > 0) { event.push(line); }
    }
    if (active) { throw new Error('日历事件未结束'); }
    for (const entries of groups.values()) {
      const masters = entries.filter((entry: string[]) => !entry.some((line: string) => /^RECURRENCE-ID[;:]/.test(line)));
      try {
        if (!masters.length) { throw new Error('缺少重复系列主事件'); }
        let task = IcsService.event(masters[0], now);
        for (let i = 1; i < masters.length; i++) { try { IcsService.event(masters[i], now); notes.push(task.title + '：UID 重复，保留首个主事件'); } catch (error) { notes.push(task.title + '：' + (error as Error).message); } }
        const exceptions: OccurrenceState[] = []; const keys = new Set<string>();
        for (const line of masters[0].filter((value: string) => /^EXDATE[;:]/.test(value))) {
          const prop = IcsService.property(line);
          for (const value of prop.value.split(',')) {
            const day = ScheduleService.key(IcsService.date({ name: prop.name, head: prop.head, value: value }).timestamp);
            if (!ScheduleService.occursOn(task, day) || task.repeat === 'none') { throw new Error('EXDATE 不属于此系列'); }
            if (!keys.has(day)) { exceptions.push({ taskId: task.id, dateKey: day, completed: false, skipped: true, updatedAt: now }); keys.add(day); }
          }
        }
        for (const entry of entries.filter((row: string[]) => row.some((line: string) => /^RECURRENCE-ID[;:]/.test(line)))) {
          const prop = IcsService.property(entry.find((line: string) => /^RECURRENCE-ID[;:]/.test(line)) ?? '');
          if (/RANGE=/i.test(prop.head)) { throw new Error('RECURRENCE-ID RANGE 暂不支持'); }
          const day = ScheduleService.key(IcsService.date(prop).timestamp);
          if (keys.has(day) || !ScheduleService.occursOn(task, day)) { throw new Error('重复例外冲突或日期无效'); } keys.add(day);
          if (entry.includes('STATUS:CANCELLED')) { exceptions.push({ taskId: task.id, dateKey: day, completed: false, skipped: true, updatedAt: now }); continue; }
          const replacement = IcsService.event(entry.filter((line: string) => !/^RECURRENCE-ID[;:]/.test(line)), now);
          task = OccurrenceService.change(task, day, OccurrenceService.draft(replacement), now);
        }
        tasks.push(task); occurrences.push(...exceptions);
      } catch (error) { notes.push((entries[0].find((line: string) => line.startsWith('UID:')) ?? '事件') + '：整组未导入，' + (error as Error).message); }
    }
    return { document: { format: 'TaiPlanHarmony', version: 6, exportedAt: now, tasks: tasks, occurrences: occurrences }, notes: notes, total: total };
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
          const end = ScheduleService.startTime(item) + (task.durationMinutes ?? 30) * 60000;
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
