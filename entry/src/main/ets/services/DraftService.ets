import { TaskDraft } from '../model/Task';
import { TaskService } from './TaskService';
import { PlanningService } from './PlanningService';
import { QuickEntryService } from './QuickEntryService';
import { ScheduleService } from './ScheduleService';

export interface DraftProposal { draft: TaskDraft; explanation: string; selected: boolean; }
interface AiDraft { title: string; date: string; time: string; duration: number; priority: number; location: string; note: string; explanation: string; }
interface AiDraftResponse { drafts: AiDraft[]; }
export class DraftService {
  static local(input: string, now: number): DraftProposal[] {
    if (!input.trim() || input.length > 4000) { throw new Error('请输入 1～4000 字'); }
    const lines = input.split(/[\n；;。]+|另外/).map((line: string) => line.trim()).filter((line: string) => line.length > 0);
    if (lines.length > 20) { throw new Error('一次最多识别 20 件事'); }
    return lines.map((line: string): DraftProposal => {
      let text = line;
      text = text.replace(/(\d{1,2})[:：](\d{2})/g, (_match: string, hour: string, minute: string): string => {
        if (Number(hour) > 23 || Number(minute) > 59) { throw new Error('时间无效'); }
        return ' ' + hour.padStart(2, '0') + ':' + minute + ' ';
      });
      const clock = text.match(/(凌晨|早上|上午|中午|下午|晚上)?([零一二两三四五六七八九十\d]+)[点时](半|[零一二两三四五六七八九十\d]+分)?/);
      if (clock) {
        let hour = DraftService.number(clock[2]);
        if (hour > 23) { throw new Error('时间无效：' + clock[0]); }
        if (['下午', '晚上'].includes(clock[1]) && hour < 12) { hour += 12; }
        if (clock[1] === '凌晨' && hour === 12) { hour = 0; }
        const minute = clock[3] === '半' ? 30 : clock[3] ? DraftService.number(clock[3].replace('分', '')) : 0;
        if (minute > 59) { throw new Error('分钟无效'); }
        text = text.replace(clock[0], ' ' + hour.toString().padStart(2, '0') + ':' + minute.toString().padStart(2, '0') + ' ');
      }
      text = text.replace(/一个小时|一小时/g, '持续60分钟').replace(/半小时/g, '持续30分钟');
      const draft = QuickEntryService.parse(text, now);
      draft.title = draft.title.replace(/^[，,\s]+|[，,\s]+$/g, '');
      draft.planning = PlanningService.create(draft.dueAt, draft.startMinute ?? -1, draft.durationMinutes ?? 30);
      TaskService.create(draft, 'preview', now);
      return { draft: draft, explanation: '离线规则识别；未明确提取的地点、截止和提醒保留在标题中，请核对。', selected: true };
    });
  }
  private static number(value: string): number {
    if (/^\d+$/.test(value)) { return Number(value); }
    const digits = '零一二三四五六七八九'; const clean = value.replace('两', '二');
    if (clean.includes('十')) { const parts = clean.split('十'); return (parts[0] ? digits.indexOf(parts[0]) : 1) * 10 + (parts[1] ? digits.indexOf(parts[1]) : 0); }
    const result = digits.indexOf(clean); if (result < 0) { throw new Error('不能识别时间数字'); } return result;
  }
  static decode(raw: string, now: number): DraftProposal[] {
    if (raw.length > 64000) { throw new Error('AI 返回过长'); }
    const parsed = JSON.parse(raw.replace(/^\s*```(?:json)?\s*/i, '').replace(/\s*```\s*$/, '')) as AiDraftResponse;
    if (!parsed || !Array.isArray(parsed.drafts) || parsed.drafts.length < 1 || parsed.drafts.length > 20) { throw new Error('AI 必须返回 1～20 条结构化草稿'); }
    return parsed.drafts.map((row: AiDraft): DraftProposal => {
      if (!row || typeof row.title !== 'string' || typeof row.date !== 'string' || typeof row.time !== 'string' ||
        typeof row.note !== 'string' || typeof row.location !== 'string' || typeof row.explanation !== 'string' ||
        row.location.length > 200 || row.explanation.length > 1000 || !Number.isInteger(row.duration) || ![0, 1, 2].includes(row.priority)) { throw new Error('AI 草稿字段无效'); }
      if (row.date && !PlanningService.validDate(row.date)) { throw new Error('AI 返回不存在的日期'); }
      if (row.time && (!/^([01]\d|2[0-3]):[0-5]\d$/.test(row.time) || !row.date)) { throw new Error('AI 返回无效时间'); }
      const minute = row.time ? Number(row.time.slice(0, 2)) * 60 + Number(row.time.slice(3)) : -1;
      const due = row.date ? ScheduleService.end(row.date) : 0;
      const plan = PlanningService.create(due, minute, row.duration); plan.location = row.location;
      const draft: TaskDraft = { title: row.title, note: row.note, priority: row.priority, tagsText: '', dueAt: due,
        startMinute: minute, durationMinutes: row.duration, repeat: 'none', planning: plan };
      TaskService.create(draft, 'preview', now);
      return { draft: draft, explanation: row.explanation, selected: true };
    });
  }
}
