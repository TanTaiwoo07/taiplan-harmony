import { Task, OccurrenceState, BackupDocument } from '../model/Task';
export interface IcsUpdatePreview { eligible: string[]; blocked: string[]; additions: number; }
export class IcsUpdateService {
  static preview(document: BackupDocument, existing: Task[], states: OccurrenceState[]): IcsUpdatePreview {
    const result: IcsUpdatePreview = { eligible: [], blocked: [], additions: 0 };
    for (const task of document.tasks) {
      const old = existing.find((item: Task) => item.id === task.id);
      if (!old) { result.additions++; continue; }
      if (old.planning?.sourceType !== 'ics' || old.completed || (old.doneSteps ?? []).length || (old.overrides ?? []).length || states.some((state: OccurrenceState) => state.taskId === old.id)) {
        result.blocked.push(old.title + '：有本地完成记录、单次例外或不是日历来源，保留本机版本');
      } else { result.eligible.push(old.id); }
    }
    return result;
  }
}
