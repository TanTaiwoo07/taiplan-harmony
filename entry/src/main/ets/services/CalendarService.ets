import { Task, TaskItem, OccurrenceState } from '../model/Task';
import { ScheduleService } from './ScheduleService';
import { PlanningService } from './PlanningService';

export interface CalendarBlock {
  key: string;
  item: TaskItem;
  start: number;
  end: number;
  lane: number;
  lanes: number;
  continuesBefore: boolean;
  continuesAfter: boolean;
}
export class CalendarService {
  static days(selected: string, view: string, weekStart: number): string[] {
    if (view !== 'week') { return [selected]; }
    const weekday = ScheduleService.date(selected).getDay();
    const first = ScheduleService.shift(selected, -((weekday - weekStart + 7) % 7));
    return [0, 1, 2, 3, 4, 5, 6].map((offset: number) => ScheduleService.shift(first, offset));
  }
  static blocks(tasks: Task[], states: OccurrenceState[], day: string): CalendarBlock[] {
    const blocks: CalendarBlock[] = [];
    const begin = ScheduleService.date(day); begin.setHours(0, 0, 0, 0);
    const finish = new Date(begin.getTime()); finish.setDate(finish.getDate() + 1);
    for (const key of [ScheduleService.shift(day, -1), day]) {
      for (const item of ScheduleService.project(tasks, states, 'calendar', key, Date.now())) {
        if ((item.task.startMinute ?? -1) < 0) { continue; }
        const start = ScheduleService.date(key); start.setHours(0, item.task.startMinute ?? 0, 0, 0);
        const end = new Date(start.getTime() + (item.task.durationMinutes ?? 30) * 60000);
        if (start.getTime() >= finish.getTime() || end.getTime() <= begin.getTime()) { continue; }
        const startMinute = start.getTime() < begin.getTime() ? 0 : start.getHours() * 60 + start.getMinutes();
        const endMinute = end.getTime() >= finish.getTime() ? 1440 : end.getHours() * 60 + end.getMinutes();
        blocks.push({ key: item.key + ':' + day, item: item, start: startMinute, end: endMinute, lane: 0, lanes: 1,
          continuesBefore: start.getTime() < begin.getTime(), continuesAfter: end.getTime() > finish.getTime() });
      }
    }
    blocks.sort((a: CalendarBlock, b: CalendarBlock) => a.start - b.start || b.end - a.end || a.key.localeCompare(b.key));
    // Assign lanes per connected overlap cluster, not per individual pair.
    let cluster: CalendarBlock[] = []; let clusterEnd = -1; let laneEnds: number[] = [];
    for (const block of blocks) {
      if (block.start >= clusterEnd) {
        for (const previous of cluster) { previous.lanes = laneEnds.length; }
        cluster = []; laneEnds = []; clusterEnd = -1;
      }
      let lane = laneEnds.findIndex((end: number) => end <= block.start);
      if (lane < 0) { lane = laneEnds.length; laneEnds.push(block.end); } else { laneEnds[lane] = block.end; }
      block.lane = lane; cluster.push(block); clusterEnd = Math.max(clusterEnd, block.end);
    }
    for (const block of cluster) { block.lanes = laneEnds.length; }
    return blocks;
  }
  static search(tasks: Task[], query: string): Task[] {
    const keyword = query.trim().toLocaleLowerCase();
    if (!keyword) { return []; }
    return tasks.filter((task: Task) => `${task.title}\n${task.note}\n${task.tags.join(' ')}\n${task.planning?.location ?? ''}\n${task.planning?.listName ?? ''}`.toLocaleLowerCase().includes(keyword))
      .sort((a: Task, b: Task) => b.createdAt - a.createdAt || a.id.localeCompare(b.id));
  }
}
