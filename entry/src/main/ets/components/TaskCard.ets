import { Task } from '../model/Task';
import { TaskService } from '../services/TaskService';

@Component
export struct TaskCard {
  @Prop task: Task = { id: '', title: '', note: '', completed: false, createdAt: 0,
    updatedAt: 0, priority: 1, tags: [], dueAt: 0 };
  @Prop busy: boolean = false;
  onToggle: (task: Task) => void = () => {};
  onEdit: (task: Task) => void = () => {};
  onRemove: (task: Task) => void = () => {};

  build() {
    Row({ space: 10 }) {
      Checkbox({ name: this.task.id }).select(this.task.completed)
        .selectedColor($r('app.color.accent'))
        .accessibilityText(`${this.task.completed ? '取消完成' : '标记完成'}：${this.task.title}`)
        .onChange((selected: boolean) => { if (selected !== this.task.completed) { this.onToggle(this.task); } })
      Column({ space: 8 }) {
        Text(this.task.title).fontSize(17).fontWeight(FontWeight.Medium).width('100%')
          .fontColor(this.task.completed ? $r('app.color.text_secondary') : $r('app.color.text_primary'))
          .decoration({ type: this.task.completed ? TextDecorationType.LineThrough : TextDecorationType.None })
        if (this.task.note.length > 0) {
          Text(this.task.note).fontSize(13).fontColor($r('app.color.text_secondary')).maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        }
        Row({ space: 8 }) {
          Text(`${TaskService.priorityLabel(this.task.priority)}优先级`).fontSize(12)
            .fontColor(this.task.priority === 2 ? $r('app.color.danger') : $r('app.color.accent'))
          if (this.task.dueAt > 0) {
            Text(`${TaskService.isOverdue(this.task, Date.now()) ? '已逾期 · ' : '截止 '}${TaskService.dateLabel(this.task.dueAt)}`)
              .fontSize(12).layoutWeight(1)
              .fontColor(TaskService.isOverdue(this.task, Date.now()) ? $r('app.color.danger') : $r('app.color.text_secondary'))
          }
        }.width('100%')
        if (this.task.tags.length > 0) {
          Text(this.task.tags.map((tag: string) => `#${tag}`).join('  ')).fontSize(12)
            .fontColor($r('app.color.accent')).width('100%')
        }
        Row({ space: 10 }) {
          Button('编辑', { type: ButtonType.Normal }).fontSize(13).height(36)
            .backgroundColor(Color.Transparent).fontColor($r('app.color.accent')).onClick(() => this.onEdit(this.task))
          Button('删除', { type: ButtonType.Normal }).fontSize(13).height(36)
            .backgroundColor(Color.Transparent).fontColor($r('app.color.text_secondary')).onClick(() => this.onRemove(this.task))
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
    }.padding(16).width('100%').borderRadius(18).backgroundColor($r('app.color.card_background')).enabled(!this.busy)
  }
}
