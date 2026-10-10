import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { Task, TaskDraft } from '../model/Task';
import { TaskService } from '../services/TaskService';
import { TaskRepository } from '../data/TaskRepository';
import { TaskCard } from '../components/TaskCard';

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
  @State private draftPriority: number = 1;
  @State private draftTags: string = '';
  @State private draftDueAt: number = 0;
  @State private query: string = '';
  @State private tagFilter: string = '';
  @State private theme: string = 'system';
  private repository: TaskRepository = new TaskRepository();
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void { this.load(); }

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private async load(): Promise<void> {
    this.busy = true;
    this.error = '';
    try {
      this.tasks = await this.repository.load(this.context());
      this.theme = await this.repository.getTheme();
      this.ready = true;
    } catch {
      this.error = '读取或迁移任务失败，请重试。旧版数据已保留。';
    } finally { this.busy = false; }
  }

  private openEditor(task?: Task): void {
    this.editingId = task ? task.id : '';
    this.draftTitle = task ? task.title : '';
    this.draftNote = task ? task.note : '';
    this.draftPriority = task ? task.priority : 1;
    this.draftTags = task ? task.tags.join('，') : '';
    this.draftDueAt = task ? task.dueAt : 0;
    this.error = '';
    this.editing = true;
    this.scroller.scrollTo({ xOffset: 0, yOffset: 0 });
  }

  private reconcileFilter(): void {
    if (this.tagFilter.length > 0 && !TaskService.allTags(this.tasks).includes(this.tagFilter)) {
      this.tagFilter = '';
    }
  }

  private async saveTask(task: Task): Promise<boolean> {
    if (this.busy || !this.ready) { return false; }
    this.busy = true;
    this.error = '';
    try {
      await this.repository.save(task);
      this.tasks = this.tasks.filter((item: Task) => item.id !== task.id).concat([task]);
      this.reconcileFilter();
      return true;
    } catch {
      this.error = '保存失败，请重试。编辑内容仍然保留。';
      return false;
    } finally { this.busy = false; }
  }

  private async saveEditor(): Promise<void> {
    if (this.busy) { return; }
    const draft: TaskDraft = { title: this.draftTitle, note: this.draftNote,
      priority: this.draftPriority, tagsText: this.draftTags, dueAt: this.draftDueAt };
    let task: Task;
    try {
      if (this.editingId.length === 0) {
        task = TaskService.create(draft, util.generateRandomUUID(), Date.now());
      } else {
        const old = this.tasks.find((item: Task) => item.id === this.editingId);
        if (!old) { this.error = '任务已不存在，请返回列表'; return; }
        task = TaskService.edit(old, draft, Date.now());
      }
    } catch (error) {
      this.error = (error as Error).message;
      return;
    }
    if (await this.saveTask(task)) {
      this.editing = false;
      this.scroller.scrollTo({ xOffset: 0, yOffset: 0 });
    }
  }

  private toggle(task: Task): void { this.saveTask(TaskService.toggle(task, Date.now())); }

  private async deleteTask(id: string): Promise<void> {
    if (this.busy) { return; }
    this.busy = true;
    this.error = '';
    try {
      await this.repository.remove(id);
      this.tasks = this.tasks.filter((item: Task) => item.id !== id);
      this.reconcileFilter();
    } catch { this.error = '删除失败，请重试'; }
    finally { this.busy = false; }
  }

  private remove(task: Task): void {
    this.getUIContext().showAlertDialog({
      title: '删除任务？', message: task.title,
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: { value: '删除', action: () => { this.deleteTask(task.id); } }
    });
  }

  private pickDate(): void {
    const selected = this.draftDueAt > 0 ? new Date(this.draftDueAt) : new Date();
    this.getUIContext().showDatePickerDialog({
      start: new Date(2000, 0, 1), end: new Date(2100, 11, 31), selected: selected,
      onAccept: (value: DatePickerResult) => {
        this.draftDueAt = TaskService.endOfDay(value.year ?? selected.getFullYear(),
          value.month ?? selected.getMonth(), value.day ?? selected.getDate());
      }
    });
  }

  private async switchTheme(): Promise<void> {
    if (this.busy) { return; }
    const next = this.theme === 'system' ? 'light' : this.theme === 'light' ? 'dark' : 'system';
    this.busy = true;
    try { await this.repository.setTheme(this.context(), next); this.theme = next; }
    catch { this.error = '主题保存失败，请重试'; }
    finally { this.busy = false; }
  }

  onBackPress(): boolean {
    if (this.editing) {
      if (!this.busy) { this.editing = false; this.error = ''; }
      return true;
    }
    return false;
  }

  @Builder
  section(completed: boolean, label: string) {
    Row() {
      Text(label).fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
      Blank()
      Text(`${TaskService.section(this.tasks, completed, this.query, this.tagFilter).length}`)
        .fontSize(14).fontColor($r('app.color.text_secondary'))
    }.width('100%').padding({ top: 16, bottom: 4 })
    if (TaskService.section(this.tasks, completed, this.query, this.tagFilter).length === 0) {
      Text(this.query.trim().length > 0 || this.tagFilter.length > 0 ? '没有符合条件的任务' :
        completed ? '完成的任务会出现在这里' : '留一点空间，开始今天的第一件事。')
        .fontSize(14).fontColor($r('app.color.text_secondary')).width('100%').padding({ top: 12, bottom: 18 })
    }
    ForEach(TaskService.section(this.tasks, completed, this.query, this.tagFilter), (task: Task) => {
      TaskCard({ task: task, busy: this.busy,
        onToggle: (item: Task) => this.toggle(item),
        onEdit: (item: Task) => this.openEditor(item),
        onRemove: (item: Task) => this.remove(item) })
    }, (task: Task) => task.id)
  }

  @Builder
  filters() {
    Search({ value: this.query, placeholder: '搜索标题、备注或标签' })
      .height(46).onChange((value: string) => { this.query = value; })
      .backgroundColor($r('app.color.card_background')).fontColor($r('app.color.text_primary'))
    Scroll() {
      Row({ space: 8 }) {
        Button('全部标签').height(34).fontSize(13)
          .backgroundColor(this.tagFilter.length === 0 ? $r('app.color.accent') : $r('app.color.card_background'))
          .fontColor(this.tagFilter.length === 0 ? $r('app.color.on_accent') : $r('app.color.text_secondary'))
          .onClick(() => { this.tagFilter = ''; })
        ForEach(TaskService.allTags(this.tasks), (tag: string) => {
          Button(tag).height(34).fontSize(13)
            .backgroundColor(this.tagFilter === tag ? $r('app.color.accent') : $r('app.color.card_background'))
            .fontColor(this.tagFilter === tag ? $r('app.color.on_accent') : $r('app.color.text_secondary'))
            .onClick(() => { this.tagFilter = this.tagFilter === tag ? '' : tag; })
        }, (tag: string) => tag)
      }
    }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
    Row() {
      Text(`共 ${this.tasks.length} 件 · 待办 ${TaskService.section(this.tasks, false).length} 件`)
        .fontSize(13).fontColor($r('app.color.text_secondary'))
      Blank()
      Text('创建时间倒序').fontSize(12).fontColor($r('app.color.text_secondary'))
    }.width('100%')
  }

  @Builder
  editor() {
    Column({ space: 14 }) {
      Text(this.editingId.length > 0 ? '编辑任务' : '记下一件事').fontSize(24).fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary')).width('100%')
      TextInput({ placeholder: '准备做什么？（必填）', text: this.draftTitle }).maxLength(100).height(52)
        .onChange((value: string) => { this.draftTitle = value; })
        .backgroundColor($r('app.color.card_background')).fontColor($r('app.color.text_primary'))
      TextArea({ placeholder: '添加备注（可选）', text: this.draftNote }).maxLength(1000).height(100)
        .onChange((value: string) => { this.draftNote = value; })
        .backgroundColor($r('app.color.card_background')).fontColor($r('app.color.text_primary'))
      Text('优先级').fontSize(14).fontColor($r('app.color.text_secondary')).width('100%')
      Row({ space: 10 }) {
        ForEach([0, 1, 2], (priority: number) => {
          Button(TaskService.priorityLabel(priority)).layoutWeight(1).height(38)
            .backgroundColor(this.draftPriority === priority ? $r('app.color.accent') : $r('app.color.card_background'))
            .fontColor(this.draftPriority === priority ? $r('app.color.on_accent') : $r('app.color.text_primary'))
            .onClick(() => { this.draftPriority = priority; })
        }, (priority: number) => priority.toString())
      }.width('100%')
      Text('标签 · 用逗号分隔，最多 5 个').fontSize(14).fontColor($r('app.color.text_secondary')).width('100%')
      TextInput({ placeholder: '例如：学习，生活', text: this.draftTags }).maxLength(80).height(48)
        .onChange((value: string) => { this.draftTags = value; })
        .backgroundColor($r('app.color.card_background')).fontColor($r('app.color.text_primary'))
      Text('截止日期（可选）').fontSize(14).fontColor($r('app.color.text_secondary')).width('100%')
      Row({ space: 8 }) {
        Button(TaskService.dateLabel(this.draftDueAt)).layoutWeight(1).height(44)
          .backgroundColor($r('app.color.card_background')).fontColor($r('app.color.accent'))
          .onClick(() => this.pickDate())
        if (this.draftDueAt > 0) {
          Button('清除').height(44).fontSize(13)
            .backgroundColor($r('app.color.card_background')).fontColor($r('app.color.text_secondary'))
            .onClick(() => { this.draftDueAt = 0; })
        }
      }.width('100%')
    }.width('100%').padding({ top: 8 }).enabled(!this.busy)
  }

  build() {
    Column({ space: 12 }) {
      Row() {
        Column({ space: 4 }) {
          Text('TaiPlan').fontSize(29).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
          Text('把想做的事，变成完成的事。').fontSize(12).fontColor($r('app.color.text_secondary'))
        }.alignItems(HorizontalAlign.Start)
        Blank()
        Button(this.theme === 'dark' ? '深色' : this.theme === 'light' ? '浅色' : '跟随系统')
          .height(36).fontSize(12).padding({ left: 12, right: 12 })
          .backgroundColor($r('app.color.card_background')).fontColor($r('app.color.accent'))
          .accessibilityText('切换主题：跟随系统、浅色、深色')
          .enabled(this.ready && !this.busy).onClick(() => this.switchTheme())
      }.width('100%').padding({ top: 12, bottom: 4 })
      if (this.error.length > 0) {
        Text(this.error).fontSize(13).fontColor($r('app.color.danger')).width('100%')
      }
      if (!this.ready) {
        Blank()
        Text(this.busy ? '正在读取任务…' : '暂时无法读取任务').fontColor($r('app.color.text_secondary'))
        if (!this.busy) { Button('重新读取').onClick(() => this.load()) }
        Blank()
      } else {
        if (!this.editing) { this.filters() }
        Scroll(this.scroller) {
          Column({ space: 12 }) {
            if (this.editing) { this.editor() }
            else { this.section(false, '待办'); this.section(true, '已完成') }
          }.width('100%').padding({ bottom: 20 })
        }.layoutWeight(1).width('100%').align(Alignment.Top)
        if (this.editing) {
          Row({ space: 12 }) {
            Button('取消').layoutWeight(1).height(48).backgroundColor($r('app.color.card_background'))
              .fontColor($r('app.color.text_primary')).onClick(() => { this.editing = false; this.error = ''; })
            Button(this.busy ? '保存中…' : '保存任务').layoutWeight(1).height(48)
              .backgroundColor($r('app.color.accent')).fontColor($r('app.color.on_accent'))
              .onClick(() => this.saveEditor()).enabled(this.draftTitle.trim().length > 0)
          }.enabled(!this.busy)
        } else {
          Button('＋  新建任务').height(50).width('100%').backgroundColor($r('app.color.accent'))
            .fontColor($r('app.color.on_accent')).enabled(!this.busy).onClick(() => this.openEditor())
        }
      }
    }.padding({ left: 20, right: 20, bottom: 16 }).width('100%').height('100%')
      .backgroundColor($r('app.color.page_background'))
  }
}
