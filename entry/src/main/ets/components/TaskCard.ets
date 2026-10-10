import { Task, TaskItem } from '../model/Task';
import { PlanningService } from '../services/PlanningService';
import { TaskService } from '../services/TaskService';
import { ScheduleService } from '../services/ScheduleService';

@Component
export struct TaskCard {
  @Prop task: Task = { id: '', title: '', note: '', completed: false, createdAt: 0,
    updatedAt: 0, priority: 1, tags: [], dueAt: 0, repeat: 'none', sortOrder: 0 };
  @Prop completed: boolean = false;
  @Prop displayDueAt: number = 0;
  @Prop now: number = Date.now();
  @Prop busy: boolean = false;
  @Prop doneSteps: number[] = [];
  @Prop expanded: boolean = false;
  onExpand: () => void = () => {};
  onStep: (index: number) => void = () => {};
  onCopy: () => void = () => {};
  onToggle: (task: Task) => void = () => {};
  onEdit: (task: Task) => void = () => {};
  onRemove: (task: Task) => void = () => {};


  private overdue(): boolean {
    return PlanningService.overdue(this.task, this.displayDueAt, this.completed, this.now);
  }
  build() {
    Row({ space: 12 }) {
      if (!PlanningService.isEvent(this.task)) {
      Checkbox({ name: this.task.id }).select(this.completed).width(22).height(22).margin({ top: 3 })
        .responseRegion({ x: -13, y: -13, width: 48, height: 48 })
        .selectedColor($r('app.color.accent'))
        .accessibilityText((this.completed ? '取消完成：' : '标记完成：') + this.task.title)
        .onChange((selected: boolean) => { if (selected !== this.completed) { this.onToggle(this.task); } })
      } else { Text('▦').width(22).fontSize(22).fontColor($r('app.color.text_secondary')).margin({ top: 12 }) }
      Column({ space: 7 }) {
        Row({ space: 4 }) {
          Text(this.task.title).fontSize(17).fontWeight(FontWeight.Medium).layoutWeight(1).maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .fontColor(this.completed ? $r('app.color.text_secondary') : $r('app.color.text_primary'))
            .decoration({ type: this.completed ? TextDecorationType.LineThrough : TextDecorationType.None })
            .accessibilityText('查看或编辑：' + this.task.title).onClick(() => this.onEdit(this.task))
          Button('⋯', { type: ButtonType.Normal }).width(48).height(48).padding(0).fontSize(22)
            .backgroundColor(Color.Transparent).fontColor($r('app.color.text_secondary'))
            .accessibilityText('任务操作：' + this.task.title)
            .bindMenu([
              { value: '编辑', action: () => this.onEdit(this.task) },
              { value: '复制为新任务', action: () => this.onCopy() },
              { value: this.task.repeat === 'none' ? '删除' : '跳过或删除', action: () => this.onRemove(this.task) }
            ])
        }.width('100%')
        Row({ space: 8 }) {
          if (this.task.priority !== 1 && !PlanningService.isEvent(this.task)) {
          Text(TaskService.priorityLabel(this.task.priority) + '优先级').fontSize(11)
            .fontColor(!this.completed && this.task.priority === 2 ? $r('app.color.danger') : $r('app.color.text_secondary'))
          }
          if (this.displayDueAt > 0) {
            Text('计划 · ' + TaskService.dateLabel(this.displayDueAt)).fontSize(11)
              .layoutWeight(1).fontColor($r('app.color.text_secondary'))
          }
        }.width('100%')
        if (PlanningService.deadline(this.task, this.displayDueAt) > 0) {
          Text((this.overdue() ? '已逾期 · ' : '截止 · ') + TaskService.dateLabel(PlanningService.deadline(this.task, this.displayDueAt)))
            .fontSize(12).fontColor(this.overdue() ? $r('app.color.danger') : $r('app.color.text_secondary')).width('100%')
        }
        if ((this.task.startMinute ?? -1) >= 0 || this.task.repeat !== 'none') {
          Text(((this.task.startMinute ?? -1) >= 0 ? TaskService.timeLabel(this.task) : '全天') +
            (this.task.repeat !== 'none' ? ' · ' + ScheduleService.repeatLabel(this.task.repeat) : ''))
            .fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
        }
        if ((this.task.planning?.location ?? '').length > 0) {
          Text('地点 · ' + this.task.planning?.location).fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
        }
        if ((this.task.planning?.listName ?? '').length > 0) {
          Text(this.task.planning?.listName ?? '').fontSize(11).fontColor($r('app.color.text_secondary'))
        }
        if (this.task.tags.length > 0) {
          Text(this.task.tags.map((tag: string) => '#' + tag).join('  ')).fontSize(11)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).fontColor($r('app.color.text_secondary')).width('100%')
        }
        if (this.task.note.length > 0 && this.expanded) {
          Text(this.task.note).fontSize(13).fontColor($r('app.color.text_secondary')).width('100%')
        }
        if ((this.task.steps ?? []).length > 0) {
          Button((this.expanded ? '收起子任务' : '子任务') + ' · ' + this.doneSteps.length.toString() + '/' + (this.task.steps ?? []).length.toString(),
            { type: ButtonType.Normal }).height(40).fontSize(12).padding({ left: 0, right: 8 })
            .backgroundColor(Color.Transparent).fontColor($r('app.color.text_secondary')).onClick(() => this.onExpand())
          if (this.expanded) {
            ForEach(this.task.steps ?? [], (step: string, index: number) => {
              Row({ space: 8 }) {
                Checkbox({ name: this.task.id + '-step-' + index.toString() }).select(this.doneSteps.includes(index))
                  .responseRegion({ x: -12, y: -12, width: 44, height: 44 })
                  .width(20).height(20).selectedColor($r('app.color.accent')).accessibilityText(step)
                  .onChange((selected: boolean) => { if (selected !== this.doneSteps.includes(index)) { this.onStep(index); } })
                Text(step).fontSize(13).layoutWeight(1).fontColor($r('app.color.text_primary'))
                  .decoration({ type: this.doneSteps.includes(index) ? TextDecorationType.LineThrough : TextDecorationType.None })
              }.width('100%').constraintSize({ minHeight: 44 })
            }, (step: string, index: number) => index.toString() + ':' + step)
          }
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
    }.alignItems(VerticalAlign.Top).padding({ left: 14, right: 10, top: 12, bottom: 14 }).width('100%')
      .borderRadius(16).backgroundColor($r('app.color.card_background'))
      .enabled(!this.busy)
  }
}
