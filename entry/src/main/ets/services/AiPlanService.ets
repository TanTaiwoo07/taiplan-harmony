import { Task, OccurrenceState, TaskPlanning } from '../model/Task';
import { PlanReport } from './AutoPlanService';
import { TaskService } from './TaskService';
import { ScheduleService } from './ScheduleService';
import { PlanningService } from './PlanningService';
import { CalendarService } from './CalendarService';
import { OccurrenceService } from './OccurrenceService';

export interface PlanCandidate { id: string; title: string; priority: number; priorityLabel: string; duration: number; deadline: number; }
export interface BusySpan { date: string; start: number; end: number; }
export interface FreeSlot { date: string; start: string; end: string; }
export interface PlanInput { today: string; now: number; nowLocal: string; timeZone: string; startHour: number; endHour: number; snap: number; candidates: PlanCandidate[]; busy: BusySpan[]; free: FreeSlot[]; }
interface Assignment { id: string; date: string; time: string; reason: string; }
interface Unscheduled { id: string; reason: string; }
interface PlanResponse { evaluation: string; advice: string[]; assignments: Assignment[]; unscheduled: Unscheduled[]; }
export interface PlanReview { report: PlanReport; evaluation: string; advice: string[]; }

export class AiPlanService {
  static input(tasks: Task[], states: OccurrenceState[], now: number, startHour: number, endHour: number, snap: number): PlanInput {
    if (!Number.isInteger(startHour) || !Number.isInteger(endHour) || startHour < 0 || endHour > 24 || startHour >= endHour || ![5, 15, 30].includes(snap)) { throw new Error('可用时段或时间网格无效'); }
    const candidates = tasks.filter((task: Task) => PlanningService.isInbox(task)).sort((a: Task, b: Task) => b.priority - a.priority || a.createdAt - b.createdAt).slice(0, 20);
    const busy: BusySpan[] = [];
    const today = ScheduleService.key(now);
    for (let day = 0; day < 7; day++) {
      const date = ScheduleService.shift(today, day);
      const blocks = CalendarService.blocks(tasks, states, date).slice().sort((a, b) => a.start - b.start);
      for (const block of blocks) {
        if (block.item.completed) { continue; }
        const last = busy[busy.length - 1];
        if (last && last.date === date && block.start <= last.end) { last.end = Math.max(last.end, block.end); }
        else { busy.push({ date: date, start: block.start, end: block.end }); }
      }
    }
    if (busy.length > 500) { throw new Error('日历过于密集，请先缩小安排范围'); }
    const free: FreeSlot[] = []; const clock = new Date(now);
    for (let day = 0; day < 7; day++) {
      const date = ScheduleService.shift(today, day); let cursor = day === 0 ? Math.max(startHour * 60, Math.ceil((clock.getHours() * 60 + clock.getMinutes() + 1) / snap) * snap) : startHour * 60;
      const finish = endHour * 60;
      for (const span of busy.filter((item: BusySpan) => item.date === date)) {
        if (span.end <= cursor || span.start >= finish) { continue; }
        if (span.start > cursor) { free.push({ date: date, start: TaskService.minuteLabel(cursor), end: TaskService.minuteLabel(Math.min(finish, span.start)) }); }
        cursor = Math.max(cursor, Math.ceil(span.end / snap) * snap);
      }
      if (cursor < finish) { free.push({ date: date, start: TaskService.minuteLabel(cursor), end: TaskService.minuteLabel(finish) }); }
    }
    return { today: today, now: now, nowLocal: today + 'T' + TaskService.minuteLabel(clock.getHours() * 60 + clock.getMinutes()), timeZone: Intl.DateTimeFormat().resolvedOptions().timeZone, startHour: startHour, endHour: endHour, snap: snap,
      candidates: candidates.map((task: Task): PlanCandidate => { return { id: task.id, title: task.title, priority: task.priority, priorityLabel: task.priority === 2 ? '高' : task.priority === 0 ? '低' : '中', duration: task.durationMinutes ?? 30, deadline: PlanningService.deadline(task, task.dueAt) }; }), busy: busy, free: free };
  }
  static local(input: PlanInput, report: PlanReport): PlanReview {
    const urgent = input.candidates.filter((item: PlanCandidate) => item.priority === 2).length;
    return { report: report, evaluation: '收集箱本次规划 ' + input.candidates.length.toString() + ' 项，其中高优先级 ' + urgent.toString() + ' 项；可安排 ' + report.suggestions.length.toString() + ' 项。已有日程保持原位。',
      advice: ['先核对预计时长，未填写的任务按30分钟处理。', '为临时事项和休息留出空白，不必填满全天。'].concat(report.unscheduled.length ? ['有事项未排入，请检查截止期限或扩大可用时段。'] : []) };
  }
  private static text(value: string, limit: number): boolean { return typeof value === 'string' && value.trim().length > 0 && value.length <= limit; }
  static decode(raw: string, input: PlanInput, tasks: Task[], states: OccurrenceState[]): PlanReview {
    if (raw.length > 60000) { throw new Error('AI规划响应过长'); }
    let doc: PlanResponse;
    try { doc = JSON.parse(raw.trim().replace(/^```(?:json)?\s*/i, '').replace(/\s*```$/, '')) as PlanResponse; }
    catch { throw new Error('AI规划不是有效 JSON，请重新生成'); }
    if (!doc || !AiPlanService.text(doc.evaluation, 2000) || !Array.isArray(doc.advice) || doc.advice.length > 8 || doc.advice.some((text: string) => !AiPlanService.text(text, 300)) ||
      !Array.isArray(doc.assignments) || !Array.isArray(doc.unscheduled) || doc.assignments.length + doc.unscheduled.length !== input.candidates.length) { throw new Error('AI规划结构不完整，请重新生成'); }
    const seen = new Set<string>(); const report: PlanReport = { suggestions: [], unscheduled: [] }; const occupied = input.busy.slice();
    for (const row of doc.assignments) {
      if (!row) { throw new Error('AI安排结构无效'); }
      const candidate = input.candidates.find((item: PlanCandidate) => item.id === row.id);
      const task = tasks.find((item: Task) => item.id === row.id);
      if (!candidate || !task || seen.has(row.id) || !AiPlanService.text(row.reason, 300) || !ScheduleService.validKey(row.date) || row.date < input.today || row.date > ScheduleService.shift(input.today, 6) || !/^([01]\d|2[0-3]):[0-5]\d$/.test(row.time)) { throw new Error('AI包含未知事项、重复事项或无效日期时间'); }
      const minute = Number(row.time.slice(0, 2)) * 60 + Number(row.time.slice(3)); const end = minute + candidate.duration;
      const start = ScheduleService.date(row.date); start.setHours(0, minute, 0, 0);
      if (minute % input.snap || minute < input.startHour * 60 || end > input.endHour * 60 || start.getTime() <= input.now ||
        (candidate.deadline > 0 && start.getTime() + candidate.duration * 60000 > candidate.deadline) || occupied.some((span: BusySpan) => span.date === row.date && minute < span.end && end > span.start)) { throw new Error('AI建议与日历冲突、超过截止或不符合可用时段；没有保存'); }
      const draft = OccurrenceService.draft(task); draft.dueAt = ScheduleService.end(row.date); draft.startMinute = minute;
      const old = PlanningService.forTask(task); const plan = JSON.parse(JSON.stringify(old)) as TaskPlanning;
      const schedule = PlanningService.create(draft.dueAt, minute, candidate.duration);
      plan.scheduleMode = schedule.scheduleMode; plan.plannedDate = schedule.plannedDate; plan.startAt = schedule.startAt; plan.endAt = schedule.endAt;
      draft.planning = plan;
      report.suggestions.push({ before: task, after: TaskService.edit(task, draft, input.now), reason: row.reason.trim() });
      occupied.push({ date: row.date, start: minute, end: end }); seen.add(row.id);
    }
    for (const row of doc.unscheduled) {
      if (!row) { throw new Error('AI未安排结构无效'); }
      const task = input.candidates.find((item: PlanCandidate) => item.id === row.id);
      if (!task || seen.has(row.id) || !AiPlanService.text(row.reason, 300)) { throw new Error('AI未安排事项不完整'); }
      seen.add(row.id); report.unscheduled.push(task.title + '：' + row.reason.trim());
    }
    return { report: report, evaluation: doc.evaluation.trim(), advice: doc.advice.map((text: string) => text.trim()) };
  }
}
