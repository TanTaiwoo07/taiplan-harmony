import { Task, TaskItem } from '../model/Task';
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

  build() {
    Row({ space: 10 }) {
      Checkbox({ name: this.task.id }).select(this.completed)
        .selectedColor($r('app.color.accent'))
        .accessibilityText(`${this.completed ? '取消完成' : '标记完成'}：${this.task.title}`)
        .onChange((selected: boolean) => { if (selected !== this.completed) { this.onToggle(this.task); } })
      Column({ space: 8 }) {
        Text(this.task.title).fontSize(17).fontWeight(FontWeight.Medium).width('100%')
          .fontColor(this.completed ? $r('app.color.text_secondary') : $r('app.color.text_primary'))
          .decoration({ type: this.completed ? TextDecorationType.LineThrough : TextDecorationType.None })
        if (this.task.note.length > 0) {
          Text(this.task.note).fontSize(13).fontColor($r('app.color.text_secondary')).maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        }
        Row({ space: 8 }) {
          Text(`${TaskService.priorityLabel(this.task.priority)}优先级`).fontSize(12)
            .fontColor(this.task.priority === 2 ? $r('app.color.danger') : $r('app.color.accent'))
          if (this.displayDueAt > 0) {
            Text(`${(!this.completed && TaskService.deadline(this.task, this.displayDueAt) < this.now) ? '已逾期 · ' : ''}${TaskService.dateLabel(this.displayDueAt)}`)
              .fontSize(12).layoutWeight(1)
              .fontColor((!this.completed && TaskService.deadline(this.task, this.displayDueAt) < this.now) ? $r('app.color.danger') : $r('app.color.text_secondary'))
          }
        }.width('100%')
        if ((this.task.startMinute ?? -1) >= 0) {
          Text(`${TaskService.timeLabel(this.task)} · ${this.task.durationMinutes ?? 30} 分钟`).fontSize(13)
            .fontColor($r('app.color.accent')).width('100%')
        }
        if (this.task.repeat !== 'none') {
          Text(ScheduleService.repeatLabel(this.task.repeat) + '重复 · 勾选仅完成本次').fontSize(11).fontColor($r('app.color.accent')).width('100%')
        }
        if (this.task.tags.length > 0) {
          Text(this.task.tags.map((tag: string) => `#${tag}`).join('  ')).fontSize(12)
            .fontColor($r('app.color.accent')).width('100%')
        }
        if ((this.task.steps ?? []).length > 0) {
          Button(`${this.expanded ? '收起' : '展开'}子任务 · ${this.doneSteps.length}/${(this.task.steps ?? []).length}`)
            .height(32).fontSize(12).padding({ left: 0, right: 8 }).backgroundColor(Color.Transparent)
            .fontColor($r('app.color.accent')).onClick(() => this.onExpand())
          if (this.expanded) {
            ForEach(this.task.steps ?? [], (step: string, index: number) => {
              Row({ space: 6 }) {
                Checkbox({ name: `${this.task.id}-step-${index}` }).select(this.doneSteps.includes(index))
                  .width(18).height(18).selectedColor($r('app.color.accent')).accessibilityText(step)
                  .onChange((selected: boolean) => { if (selected !== this.doneSteps.includes(index)) { this.onStep(index); } })
                Text(step).fontSize(13).layoutWeight(1).fontColor($r('app.color.text_primary'))
                  .decoration({ type: this.doneSteps.includes(index) ? TextDecorationType.LineThrough : TextDecorationType.None })
              }.width('100%').padding({ top: 4, bottom: 4 })
            }, (step: string, index: number) => `${index}:${step}`)
          }
        }
        Row({ space: 10 }) {
          Button('编辑', { type: ButtonType.Normal }).fontSize(13).height(36)
            .backgroundColor(Color.Transparent).fontColor($r('app.color.accent')).onClick(() => this.onEdit(this.task))
          Button('删除', { type: ButtonType.Normal }).fontSize(13).height(36)
            .backgroundColor(Color.Transparent).fontColor($r('app.color.text_secondary')).onClick(() => this.onRemove(this.task))
          Button('复制', { type: ButtonType.Normal }).fontSize(13).height(36)
            .backgroundColor(Color.Transparent).fontColor($r('app.color.accent')).onClick(() => this.onCopy())
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
    }.padding(16).width('100%').borderRadius(18).backgroundColor($r('app.color.card_background')).enabled(!this.busy)
  }
}
