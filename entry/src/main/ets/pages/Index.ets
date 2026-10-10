import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { Task, TaskService } from '../model/Task';
import { TaskRepository } from '../data/TaskRepository';

@Entry
@Component
struct Index {
  @State private tasks: Task[] = [];
  @State private ready: boolean = false;
  @State private busy: boolean = false;
  @State private error: string = '';
  @State private editing: boolean = false;
  @State private editingId: string = '';
  @State private draftTitle: string = '';
  @State private draftNote: string = '';
  private repository: TaskRepository = new TaskRepository();

  aboutToAppear(): void {
    this.load();
  }

  private async load(): Promise<void> {
    this.busy = true;
    this.error = '';
    try {
      this.tasks = await this.repository.load(this.getUIContext().getHostContext() as common.UIAbilityContext);
      this.ready = true;
    } catch {
      this.error = '读取任务失败，请重试。现有数据未被覆盖。';
    } finally {
      this.busy = false;
    }
  }

  private openEditor(task?: Task): void {
    this.editingId = task ? task.id : '';
    this.draftTitle = task ? task.title : '';
    this.draftNote = task ? task.note : '';
    this.error = '';
    this.editing = true;
  }

  private async commit(next: Task[]): Promise<boolean> {
    if (this.busy || !this.ready) { return false; }
    this.busy = true;
    this.error = '';
    try {
      await this.repository.save(next);
      this.tasks = next;
      return true;
    } catch {
      this.error = '保存失败，请重试。修改尚未保存。';
      return false;
    } finally {
      this.busy = false;
    }
  }

  private async saveEditor(): Promise<void> {
    if (this.busy) { return; }
    try {
      const now = Date.now();
      let next: Task[];
      if (this.editingId.length === 0) {
        const task = TaskService.create(this.draftTitle, this.draftNote, util.generateRandomUUID(), now);
        next = this.tasks.concat([task]);
      } else {
        next = this.tasks.map((task: Task) => task.id === this.editingId ?
          TaskService.edit(task, this.draftTitle, this.draftNote, now) : task);
      }
      if (await this.commit(next)) { this.editing = false; }
    } catch {
      this.error = '请输入 1～100 字的标题，备注最多 1000 字';
    }
  }

  private toggle(task: Task): void {
    this.commit(this.tasks.map((item: Task) => item.id === task.id ? TaskService.toggle(item, Date.now()) : item));
  }

  private remove(task: Task): void {
    this.getUIContext().showAlertDialog({
      title: '删除任务？', message: task.title,
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: { value: '删除', action: () => {
        this.commit(this.tasks.filter((item: Task) => item.id !== task.id));
      } }
    });
  }

  onBackPress(): boolean {
    if (this.editing) {
      if (!this.busy) { this.editing = false; }
      return true;
    }
    return false;
  }

  @Builder
  taskCard(task: Task) {
    Row({ space: 12 }) {
      Checkbox({ name: task.id }).select(task.completed)
        .selectedColor($r('app.color.accent'))
        .accessibilityText(task.completed ? '取消完成' : '标记完成')
        .onChange((selected: boolean) => { if (selected !== task.completed) { this.toggle(task); } })
      Column({ space: 6 }) {
        Text(task.title).fontSize(17).fontWeight(FontWeight.Medium)
          .fontColor(task.completed ? $r('app.color.text_secondary') : $r('app.color.text_primary'))
          .decoration({ type: task.completed ? TextDecorationType.LineThrough : TextDecorationType.None })
          .width('100%')
        if (task.note.length > 0) {
          Text(task.note).fontSize(13).fontColor($r('app.color.text_secondary')).maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        }
        Row({ space: 12 }) {
          Button('编辑', { type: ButtonType.Normal }).fontSize(12).height(32)
            .backgroundColor(Color.Transparent).fontColor($r('app.color.accent')).onClick(() => this.openEditor(task))
          Button('删除', { type: ButtonType.Normal }).fontSize(12).height(32)
            .backgroundColor(Color.Transparent).fontColor($r('app.color.text_secondary')).onClick(() => this.remove(task))
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
    }.padding(16).width('100%').borderRadius(18).backgroundColor($r('app.color.card_background'))
      .enabled(!this.busy)
  }

  @Builder
  section(completed: boolean, label: string) {
    Row() {
      Text(label).fontSize(19).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
      Blank()
      Text(`${TaskService.section(this.tasks, completed).length}`).fontSize(14).fontColor($r('app.color.text_secondary'))
    }.width('100%').padding({ top: 16, bottom: 4 })
    if (TaskService.section(this.tasks, completed).length === 0) {
      Text(completed ? '完成的任务会出现在这里' : '留一点空间，开始今天的第一件事。')
        .fontSize(14).fontColor($r('app.color.text_secondary')).width('100%').padding({ top: 16, bottom: 20 })
    }
    ForEach(TaskService.section(this.tasks, completed), (task: Task) => {
      this.taskCard(task)
    }, (task: Task) => `${task.id}:${task.updatedAt}:${task.completed}:${task.title}:${task.note}`)
  }

  @Builder
  editor() {
    Column({ space: 16 }) {
      Text(this.editingId.length > 0 ? '编辑任务' : '记下一件事').fontSize(26).fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary')).width('100%')
      TextInput({ placeholder: '准备做什么？', text: this.draftTitle }).maxLength(100).height(56)
        .onChange((value: string) => { this.draftTitle = value; }).enabled(!this.busy)
      TextArea({ placeholder: '添加备注（可选）', text: this.draftNote }).maxLength(1000).height(150)
        .onChange((value: string) => { this.draftNote = value; }).enabled(!this.busy)
      Row({ space: 12 }) {
        Button('取消').layoutWeight(1).height(48).backgroundColor($r('app.color.card_background'))
          .fontColor($r('app.color.text_primary')).onClick(() => { this.editing = false; this.error = ''; })
        Button(this.busy ? '保存中…' : '保存任务').layoutWeight(1).height(48)
          .backgroundColor('#236B59').fontColor(Color.White).onClick(() => this.saveEditor())
          .enabled(this.draftTitle.trim().length > 0)
      }.enabled(!this.busy)
    }.width('100%').padding({ top: 12 })
  }

  build() {
    Column({ space: 12 }) {
      Row() {
        Column({ space: 4 }) {
          Text('TaiPlan').fontSize(30).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
          Text('把想做的事，变成完成的事。').fontSize(13).fontColor($r('app.color.text_secondary'))
        }.alignItems(HorizontalAlign.Start)
        Blank()
        Text('基础版').fontSize(12).fontColor($r('app.color.accent'))
      }.width('100%').padding({ top: 16, bottom: 8 })
      if (this.error.length > 0) {
        Text(this.error).fontSize(14).fontColor('#B34B36').width('100%')
      }
      if (!this.ready) {
        Blank()
        Text(this.busy ? '正在读取任务…' : '暂时无法读取任务').fontColor($r('app.color.text_secondary'))
        if (!this.busy) { Button('重新读取').onClick(() => this.load()) }
        Blank()
      } else {
        Scroll() {
          Column({ space: 12 }) {
            if (this.editing) {
              this.editor()
            } else {
              Row() {
                Text(`待办 ${TaskService.section(this.tasks, false).length} 件`).fontSize(16)
                  .fontColor($r('app.color.text_primary'))
                Blank()
                Text('按创建时间倒序').fontSize(12).fontColor($r('app.color.text_secondary'))
              }.padding(18).width('100%').borderRadius(18).backgroundColor($r('app.color.card_background'))
              this.section(false, '待办')
              this.section(true, '已完成')
            }
          }.width('100%').padding({ bottom: 20 })
        }.layoutWeight(1).width('100%').align(Alignment.Top)
        if (!this.editing) {
          Button('＋  新建任务').height(52).width('100%').backgroundColor('#236B59').fontColor(Color.White)
            .enabled(!this.busy).onClick(() => this.openEditor())
        }
      }
    }.padding({ left: 24, right: 24, bottom: 16 }).width('100%').height('100%')
      .backgroundColor($r('app.color.page_background'))
  }
}
