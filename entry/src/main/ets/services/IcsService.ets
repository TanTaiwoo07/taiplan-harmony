import { TimeZoneService } from './TimeZoneService';
import { PlanningService } from './PlanningService';
import { OccurrenceService } from './OccurrenceService';
import { BackupDocument, OccurrenceState, Task } from '../model/Task';
import { TaskService } from './TaskService';
import { ScheduleService } from './ScheduleService';

export interface IcsReport { document: BackupDocument; notes: string[]; total: number; }
interface IcsProperty { name: string; head: string; value: string; }
interface IcsDate { timestamp: number; allDay: boolean; }

// VEVENT 导入：额外日期和跨时区系列可展开；无法保持含义的事件逐组报告。
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
    if (/;VALUE=DATE-TIME(?:;|$)/i.test(prop.head) && allDay) { throw new Error('日期时间属性不能使用全天日期'); }
    if (/;VALUE=DATE(?:;|$)/i.test(prop.head) && !allDay) { throw new Error('全天事件的日期格式无效'); }
    const zoneMatch = prop.head.match(/;TZID=(?:"([^"]+)"|([^;]+))/i);
    const zone = zoneMatch ? zoneMatch[1] || zoneMatch[2] : '';
    if (zone && match[7]) { throw new Error('UTC 时间不能同时指定 TZID'); }
    if (allDay) { if (zone) { throw new Error('全天日期不能指定 TZID'); } return { timestamp: ScheduleService.date(key).getTime(), allDay: true }; }
    const hour = Number(match[4]), minute = Number(match[5]), second = Number(match[6]);
    if (hour > 23 || minute > 59 || second !== 0) { throw new Error('时间无效或精度不是整分钟'); }
    let date: Date;
    if (match[7] || zone.length > 0) {
      date = new Date(match[7] ? Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3]), hour, minute) : TimeZoneService.timestamp(Number(match[1]), Number(match[2]), Number(match[3]), hour, minute, zone));
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
      if (['RECURRENCE-ID', 'DURATION'].includes(prop.name)) { throw new Error(`${prop.name} 暂不支持，请先导出展开后的单次事件`); }
      if (prop.name === 'EXDATE' || prop.name === 'RDATE') { continue; }
      if (values.has(prop.name)) { throw new Error(`重复属性 ${prop.name}`); }
      values.set(prop.name, prop);
    }
    if (values.get('STATUS')?.value.toUpperCase() === 'CANCELLED') { throw new Error('已取消的事件'); }
    const uid = IcsService.unescape(values.get('UID')?.value ?? '').trim();
    if (uid.length === 0 || uid.length > 1024 || /[\r\n]/.test(uid)) { throw new Error('缺少 UID 或 UID 超过 1024 字'); }
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
      if (plan.rule.weekdays.length > 0 && !plan.rule.weekdays.includes(date.getDay() || 7)) { throw new Error('DTSTART 与 BYDAY 不一致，无法完整保留首个发生项'); }
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
  private static exceptionDay(task: Task, prop: IcsProperty): string {
    const date = IcsService.date(prop); const day = ScheduleService.key(date.timestamp);
    const minute = task.startMinute ?? -1;
    if (date.allDay !== (minute < 0) || (!date.allDay && new Date(date.timestamp).getHours() * 60 + new Date(date.timestamp).getMinutes() !== minute)) {
      throw new Error('例外必须匹配原始开始时间和日期类型');
    }
    return day;
  }
  private static dates(lines: string[], name: string): IcsProperty[] {
    const result: IcsProperty[] = [];
    for (const line of lines.filter((value: string) => new RegExp('^' + name + '[;:]').test(value))) {
      const prop = IcsService.property(line);
      for (const value of prop.value.split(',')) { result.push({ name: prop.name, head: prop.head, value: value }); }
    }
    return result;
  }
  private static member(lines: string[], start: IcsDate, duration: number, now: number): Task {
    const values = lines.filter((line: string) => !/^(DTSTART|DTEND|RRULE|RDATE|EXDATE|RECURRENCE-ID)[;:]/.test(line));
    if (start.allDay) { const date = ScheduleService.key(start.timestamp); values.push('DTSTART;VALUE=DATE:' + date.replace(/-/g, ''), 'DTEND;VALUE=DATE:' + ScheduleService.shift(date, 1).replace(/-/g, '')); }
    else { values.push('DTSTART:' + IcsService.stamp(start.timestamp), 'DTEND:' + IcsService.stamp(start.timestamp + duration * 60000)); }
    return IcsService.event(values, now);
  }
  private static extraDates(lines: string[], task: Task, now: number): Task[] {
    const starts = new Set<number>(); const result: Task[] = [];
    const excluded = IcsService.dates(lines, 'EXDATE').map((prop: IcsProperty) => IcsService.date(prop).timestamp);
    for (const prop of IcsService.dates(lines, 'RDATE')) {
      const period = /;VALUE=PERIOD(?:;|$)/i.test(prop.head); const pieces = prop.value.split('/');
      if (period !== (pieces.length === 2)) { throw new Error('RDATE PERIOD 格式无效'); }
      const head = prop.head.replace(/;VALUE=PERIOD/i, '');
      const start = IcsService.date({ name: 'DTSTART', head: head, value: pieces[0] });
      if (start.allDay !== ((task.startMinute ?? -1) < 0)) { throw new Error('RDATE 日期类型与主事件不一致'); }
      let duration = task.durationMinutes ?? 30;
      if (period) {
        if (/^P/.test(pieces[1])) { throw new Error('RDATE PERIOD 时长表达式暂不支持，请使用明确结束时间'); }
        const end = IcsService.date({ name: 'DTEND', head: head, value: pieces[1] });
        if (end.allDay || start.allDay || end.timestamp <= start.timestamp) { throw new Error('RDATE PERIOD 起止无效'); }
        duration = (end.timestamp - start.timestamp) / 60000;
      }
      const date = new Date(start.timestamp); const minute = start.allDay ? -1 : date.getHours() * 60 + date.getMinutes();
      const key = ScheduleService.key(start.timestamp);
      if (ScheduleService.occursOn(task, key) && minute === (task.startMinute ?? -1) && duration !== (task.durationMinutes ?? 30)) { throw new Error('RDATE PERIOD 与规则发生项重叠且时长不同，请先展开导出'); }
      if (starts.has(start.timestamp) || excluded.includes(start.timestamp) || (ScheduleService.occursOn(task, key) && minute === (task.startMinute ?? -1))) { continue; }
      const member = IcsService.member(lines, start, duration, now); member.id = task.id + ':rdate:' + start.timestamp.toString();
      result.push(member); starts.add(start.timestamp);
      if (result.length > 5000) { throw new Error('RDATE 展开超过5000条'); }
    }
    return result;
  }
  private static zonedSeries(entries: string[][], now: number, notes: string[]): Task[] | undefined {
    const master = entries.find((entry: string[]) => !entry.some((line: string) => /^RECURRENCE-ID[;:]/.test(line)));
    if (!master) { return undefined; }
    const startLine = master.find((line: string) => /^DTSTART[;:]/.test(line)); const ruleLine = master.find((line: string) => /^RRULE:/.test(line));
    if (!startLine || !ruleLine) { return undefined; }
    const startProp = IcsService.property(startLine); const zoneMatch = startProp.head.match(/;TZID=(?:"([^"]+)"|([^;]+))/i);
    const localZone = Intl.DateTimeFormat().resolvedOptions().timeZone;
    const sourceZone = zoneMatch ? zoneMatch[1] || zoneMatch[2] : startProp.value.endsWith('Z') ? 'UTC' : localZone;
    const fixedZones = ['Asia/Shanghai', 'UTC', 'Etc/UTC'];
    // Even fixed offsets can cross midnight and change BYDAY/month boundaries.
    if (sourceZone === localZone && fixedZones.includes(localZone)) { return undefined; }
    const first = IcsService.event(master.filter((line: string) => !/^RRULE:/.test(line)), now);
    if ((first.startMinute ?? -1) < 0) { return undefined; }
    const fields = ruleLine.slice(6).split(';'); const countPart = fields.find((value: string) => value.startsWith('COUNT=')); const untilPart = fields.find((value: string) => value.startsWith('UNTIL='));
    const count = countPart ? Number(countPart.slice(6)) : 0;
    if ((countPart && (!Number.isInteger(count) || count < 1 || count > 5000)) || (countPart && untilPart)) { throw new Error('时区系列次数或结束条件无效'); }
    if (untilPart && !/Z$/.test(untilPart)) { throw new Error('跨时区重复的 UNTIL 必须使用 UTC 日期时间'); }
    const until = untilPart ? IcsService.date({ name: 'UNTIL', head: 'UNTIL', value: untilPart.slice(6) }).timestamp : 0;
    const firstKey = startProp.value.slice(0, 4) + '-' + startProp.value.slice(4, 6) + '-' + startProp.value.slice(6, 8);
    const hour = Number(startProp.value.slice(9, 11)), minute = Number(startProp.value.slice(11, 13));
    const dummyLines = master.filter((line: string) => !/^(DTSTART|DTEND|RRULE)[;:]/.test(line));
    dummyLines.push('DTSTART:' + startProp.value.replace(/Z$/, ''), 'RRULE:' + fields.filter((value: string) => !/^(COUNT|UNTIL)=/.test(value)).join(';'));
    const pattern = IcsService.event(dummyLines, now);
    const extras = IcsService.extraDates(master, first, now);
    const excluded = IcsService.dates(master, 'EXDATE').map((prop: IcsProperty) => IcsService.date(prop).timestamp);
    const overrides = new Map<number, string[]>();
    for (const entry of entries.filter((lines: string[]) => lines.some((line: string) => /^RECURRENCE-ID[;:]/.test(line)))) {
      const prop = IcsService.property(entry.find((line: string) => /^RECURRENCE-ID[;:]/.test(line)) ?? '');
      if (/RANGE=/i.test(prop.head)) { throw new Error('时区系列 RANGE 暂不支持'); }
      const at = IcsService.date(prop).timestamp; if (overrides.has(at)) { throw new Error('重复时区例外'); } overrides.set(at, entry);
    }
    const result: Task[] = []; const generated = new Set<number>(); let valid = 0; let finished = false;
    const horizon = ScheduleService.shift(ScheduleService.key(now), 366);
    for (let offset = 0; offset <= 37000; offset++) {
      const day = ScheduleService.shift(firstKey, offset);
      if (day > '2100-12-31') { break; }
      if (!count && !until && day > horizon) { finished = true; break; }
      if (!ScheduleService.occursOn(pattern, day)) { continue; }
      const parts = day.split('-').map((value: string) => Number(value)); let at = 0;
      try { at = TimeZoneService.timestamp(parts[0], parts[1], parts[2], hour, minute, sourceZone); }
      catch (error) { if ((error as Error).message.includes('时刻不存在')) { continue; } throw error as Error; }
      if (until && at > until) { finished = true; break; }
      valid++; generated.add(at);
      if (!excluded.includes(at)) {
        const replacement = overrides.get(at);
        if (!replacement?.includes('STATUS:CANCELLED')) {
          const task = replacement ? IcsService.event(replacement.filter((line: string) => !/^RECURRENCE-ID[;:]/.test(line)), now) : IcsService.member(master, { timestamp: at, allDay: false }, first.durationMinutes ?? 30, now);
          task.id = first.id + ':at:' + at.toString(); result.push(task);
        }
      }
      if (count && valid >= count) { finished = true; break; }
      if (valid + extras.length > 5000) { throw new Error('跨时区系列展开超过5000项，请缩小源文件范围'); }
    }
    if (!finished) { throw new Error('时区系列不能在支持年份内完整展开'); }
    for (const at of overrides.keys()) { if (!generated.has(at) && !extras.some((item: Task) => item.planning?.startAt === at)) { throw new Error('时区例外不属于已展开范围'); } }
    for (const item of extras) { const at = item.planning?.startAt ?? 0; if (!generated.has(at)) { const replacement = overrides.get(at); if (replacement?.includes('STATUS:CANCELLED')) { continue; }
      const next = replacement ? IcsService.event(replacement.filter((line: string) => !/^RECURRENCE-ID[;:]/.test(line)), now) : item; next.id = first.id + ':at:' + at.toString(); result.push(next); } }
    notes.push(first.title + '：为保持 ' + sourceZone + ' 源时区日期与时刻，展开为 ' + result.length.toString() + ' 条单次日程' + (!count && !until ? '；无结束规则仅展开至 ' + horizon + '，之后需再次导入。' : '。'));
    return result;
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
        const zoned = IcsService.zonedSeries(entries, now, notes); if (zoned) { if (masters.length > 1) { notes.push('UID 重复，保留首个时区主事件'); } tasks.push(...zoned); continue; }
        let task = IcsService.event(masters[0], now);
        const extras = IcsService.extraDates(masters[0], task, now);
        for (let i = 1; i < masters.length; i++) { try { IcsService.event(masters[i], now); notes.push(task.title + '：UID 重复，保留首个主事件'); } catch (error) { notes.push(task.title + '：' + (error as Error).message); } }
        const exceptions: OccurrenceState[] = []; const keys = new Set<string>(); let excludedMaster = false;
        for (const line of masters[0].filter((value: string) => /^EXDATE[;:]/.test(value))) {
          const prop = IcsService.property(line);
          for (const value of prop.value.split(',')) {
            const exclusion = IcsService.date({ name: prop.name, head: prop.head, value: value });
            const exclusionDay = ScheduleService.key(exclusion.timestamp);
            const rdateMatch = IcsService.dates(masters[0], 'RDATE').some((extra: IcsProperty) => IcsService.date({ name: extra.name, head: extra.head.replace(/;VALUE=PERIOD/i, ''), value: extra.value.split('/')[0] }).timestamp === exclusion.timestamp);
            if (rdateMatch && (!ScheduleService.occursOn(task, exclusionDay) || (!exclusion.allDay && new Date(exclusion.timestamp).getHours() * 60 + new Date(exclusion.timestamp).getMinutes() !== (task.startMinute ?? -1)))) { continue; }
            const day = IcsService.exceptionDay(task, { name: prop.name, head: prop.head, value: value });
            if (!ScheduleService.occursOn(task, day)) {
              const isExtra = IcsService.dates(masters[0], 'RDATE').some((extra: IcsProperty) => IcsService.date({ name: extra.name, head: extra.head.replace(/;VALUE=PERIOD/i, ''), value: extra.value.split('/')[0] }).timestamp === IcsService.date({ name: prop.name, head: prop.head, value: value }).timestamp);
              if (isExtra) { continue; } throw new Error('EXDATE 不属于此系列');
            }
            if (task.repeat === 'none') { excludedMaster = true; continue; }
            if (!keys.has(day)) { exceptions.push({ taskId: task.id, dateKey: day, completed: false, skipped: true, updatedAt: now }); keys.add(day); }
          }
        }
        for (const entry of entries.filter((row: string[]) => row.some((line: string) => /^RECURRENCE-ID[;:]/.test(line)))) {
          const prop = IcsService.property(entry.find((line: string) => /^RECURRENCE-ID[;:]/.test(line)) ?? '');
          if (/RANGE=/i.test(prop.head)) { throw new Error('RECURRENCE-ID RANGE 暂不支持'); }
          const extraAt = IcsService.date(prop).timestamp; const extraIndex = extras.findIndex((extra: Task) => (extra.planning?.startAt || ScheduleService.date(ScheduleService.key(extra.dueAt)).getTime()) === extraAt);
          if (extraIndex >= 0) {
            if (entry.includes('STATUS:CANCELLED')) { extras.splice(extraIndex, 1); }
            else { const replacement = IcsService.event(entry.filter((line: string) => !/^RECURRENCE-ID[;:]/.test(line)), now); replacement.id = extras[extraIndex].id; extras[extraIndex] = replacement; }
            continue;
          }
          const day = IcsService.exceptionDay(task, prop);
          if (task.repeat === 'none' && ScheduleService.occursOn(task, day)) {
            if (excludedMaster) { continue; }
            if (keys.has(day)) { throw new Error('重复例外冲突'); } keys.add(day);
            if (entry.includes('STATUS:CANCELLED')) { excludedMaster = true; }
            else { const replacement = IcsService.event(entry.filter((line: string) => !/^RECURRENCE-ID[;:]/.test(line)), now); replacement.id = task.id; task = replacement; }
            continue;
          }
          if (keys.has(day) || !ScheduleService.occursOn(task, day)) { throw new Error('重复例外冲突或日期无效'); } keys.add(day);
          if (entry.includes('STATUS:CANCELLED')) { exceptions.push({ taskId: task.id, dateKey: day, completed: false, skipped: true, updatedAt: now }); continue; }
          const replacement = IcsService.event(entry.filter((line: string) => !/^RECURRENCE-ID[;:]/.test(line)), now);
          task = OccurrenceService.change(task, day, OccurrenceService.draft(replacement), now);
        }
        if (!excludedMaster) { tasks.push(task); } tasks.push(...extras); occurrences.push(...exceptions);
      } catch (error) { notes.push((entries[0].find((line: string) => line.startsWith('UID:')) ?? '事件') + '：整组未导入，' + (error as Error).message); }
    }
    if (tasks.length > 5000) { throw new Error('展开后的日历超过5000条，请缩小范围'); }
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
    const lines = ['BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//TaiPlan//Harmony 1.0//ZH', 'CALSCALE:GREGORIAN'];
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
        if (task.planning?.location) { lines.push('LOCATION:' + IcsService.escape(task.planning.location)); }
        lines.push(`SUMMARY:${IcsService.escape(task.title)}`, `DESCRIPTION:${IcsService.escape([task.note, steps].filter((s: string) => s.length > 0).join('\n'))}`,
          `PRIORITY:${task.priority === 2 ? 1 : task.priority === 0 ? 9 : 5}`, `X-TAIPLAN-COMPLETED:${item.completed ? 'TRUE' : 'FALSE'}`, 'END:VEVENT');
      }
    }
    lines.push('END:VCALENDAR');
    return lines.map((line: string) => IcsService.fold(line)).join('\r\n') + '\r\n';
  }
}
