import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { BackupDocument, CalendarDay, OccurrenceState, Task, TaskDraft, TaskItem } from '../model/Task';
import { TaskService } from '../services/TaskService';
import { ScheduleService } from '../services/ScheduleService';
import { QuickEntryService } from '../services/QuickEntryService';
import { BackupService } from '../services/BackupService';
import { TaskRepository } from '../data/TaskRepository';
import { BackupFiles } from '../data/BackupFiles';
import { TaskCard } from '../components/TaskCard';
import { MonthCalendar } from '../components/MonthCalendar';

@Entry
@Component
struct Index {
  @State private tasks: Task[] = [];
  @State private states: OccurrenceState[] = [];
  @State private ready: boolean = false;
  @State private busy: boolean = false;
  @State private error: string = '';
  @State private notice: string = '';
  @State private mode: string = 'list';
  @State private view: string = 'all';
  @State private editingId: string = '';
  @State private draftTitle: string = '';
  @State private draftNote: string = '';
  @State private draftPriority: number = 1;
  @State private draftTags: string = '';
  @State private draftDueAt: number = 0;
  @State private draftRepeat: string = 'none';
  @State private quickText: string = '';
  @State private query: string = '';
  @State private tagFilter: string = '';
  @State private theme: string = 'system';
  @State private sortMode: string = 'created';
  @State private sortDraft: Task[] = [];
  @State private selectedDay: string = ScheduleService.key(Date.now());
  @State private month: string = ScheduleService.key(Date.now()).slice(0, 7) + '-01';
  @State private now: number = Date.now();
  @State private importSummary: string = '';
  private pendingImport: BackupDocument | undefined = undefined;
  private repository: TaskRepository = new TaskRepository();
  private scroller: Scroller = new Scroller();
  private clockId: number = -1;

  aboutToAppear(): void {
    this.load();
    this.clockId = setInterval(() => { this.now = Date.now(); }, 60000);
  }
  aboutToDisappear(): void { if (this.clockId !== -1) { clearInterval(this.clockId); } }
  onPageShow(): void { this.now = Date.now(); }
  private context(): common.UIAbilityContext { return this.getUIContext().getHostContext() as common.UIAbilityContext; }

  private async load(): Promise<void> {
    this.busy = true; this.error = '';
    try {
      this.tasks = await this.repository.load(this.context());
      this.states = await this.repository.getOccurrences();
      this.theme = await this.repository.getTheme();
      this.sortMode = await this.repository.getSortMode();
      this.ready = true;
    } catch { this.error = '读取或迁移失败，请重试。已有数据仍保留。'; }
    finally { this.busy = false; }
  }
  private async refreshData(): Promise<void> {
    this.tasks = await this.repository.reload();
    this.states = await this.repository.getOccurrences();
    if (this.tagFilter.length > 0 && !TaskService.allTags(this.tasks).includes(this.tagFilter)) { this.tagFilter = ''; }
  }
  private changeMode(mode: string): void {
    this.mode = mode; this.error = ''; this.notice = '';
    this.scroller.scrollTo({ xOffset: 0, yOffset: 0 });
  }
  private changeView(view: string): void {
    this.view = view; this.now = Date.now(); this.notice = '';
    this.scroller.scrollTo({ xOffset: 0, yOffset: 0 });
  }
  private openEditor(task?: Task): void {
    this.editingId = task ? task.id : '';
    this.draftTitle = task ? task.title : '';
    this.draftNote = task ? task.note : '';
    this.draftPriority = task ? task.priority : 1;
    this.draftTags = task ? task.tags.join('，') : '';
    this.draftDueAt = task ? task.dueAt : this.view === 'calendar' ? ScheduleService.end(this.selectedDay) : 0;
    this.draftRepeat = task ? task.repeat : 'none';
    this.changeMode('editor');
  }
  private parseQuick(): void {
    try {
      const draft = QuickEntryService.parse(this.quickText, Date.now());
      TaskService.create(draft, 'preview', Date.now());
      this.openEditor();
      this.draftTitle = draft.title; this.draftNote = draft.note; this.draftPriority = draft.priority;
      this.draftTags = draft.tagsText; this.draftDueAt = draft.dueAt; this.draftRepeat = draft.repeat ?? 'none';
      this.notice = '已识别为草稿，请核对后保存。';
    } catch (error) { this.error = (error as Error).message; }
  }
  private async persistEditor(task: Task): Promise<void> {
    if (this.busy) { return; }
    this.busy = true; this.error = '';
    try {
      await this.repository.save(task);
      await this.refreshData();
      this.query = ''; this.tagFilter = '';
      this.changeMode('list'); this.view = 'all';
      this.notice = '任务已保存';
    } catch { this.error = '保存失败，请重试。编辑内容仍然保留。'; }
    finally { this.busy = false; }
  }
  private saveEditor(): void {
    if (this.busy) { return; }
    const draft: TaskDraft = { title: this.draftTitle, note: this.draftNote, priority: this.draftPriority,
      tagsText: this.draftTags, dueAt: this.draftDueAt, repeat: this.draftRepeat };
    try {
      const old = this.tasks.find((task: Task) => task.id === this.editingId);
      if (this.editingId.length > 0 && !old) { this.error = '任务已不存在，请返回列表'; return; }
      const task = old ? TaskService.edit(old, draft, Date.now()) : TaskService.create(draft, util.generateRandomUUID(), Date.now());
      if (old && (old.repeat !== task.repeat || old.dueAt !== task.dueAt) && this.states.some((state: OccurrenceState) => state.taskId === old.id)) {
        this.getUIContext().showAlertDialog({
          title: '更新重复规则？', message: '起始日期或规则变更会重置这一组的完成和跳过记录。',
          primaryButton: { value: '取消', action: () => {} },
          secondaryButton: { value: '更新规则', action: () => { this.persistEditor(task); } }
        });
      } else { this.persistEditor(task); }
    } catch (error) { this.error = (error as Error).message; }
  }
  private async toggle(item: TaskItem): Promise<void> {
    if (this.busy) { return; }
    this.busy = true; this.error = '';
    try {
      if (item.task.repeat === 'none') { await this.repository.save(TaskService.toggle(item.task, Date.now())); }
      else { await this.repository.setOccurrence({ taskId: item.task.id, dateKey: item.dateKey,
        completed: !item.completed, skipped: false, updatedAt: Date.now() }); }
      await this.refreshData();
    } catch { this.error = '完成状态保存失败，请重试'; }
    finally { this.busy = false; }
  }
  private async skip(item: TaskItem): Promise<void> {
    if (this.busy) { return; }
    this.busy = true;
    try {
      await this.repository.setOccurrence({ taskId: item.task.id, dateKey: item.dateKey, completed: false, skipped: true, updatedAt: Date.now() });
      await this.refreshData(); this.notice = '已跳过这一次，可在工具中恢复';
    } catch { this.error = '跳过失败，请重试'; }
    finally { this.busy = false; }
  }
  private async restoreOccurrence(state: OccurrenceState): Promise<void> {
    if (this.busy) { return; }
    this.busy = true;
    try {
      await this.repository.setOccurrence({ taskId: state.taskId, dateKey: state.dateKey, completed: false, skipped: false, updatedAt: Date.now() });
      await this.refreshData(); this.notice = '已恢复这一次任务';
    } catch { this.error = '恢复失败，请重试'; }
    finally { this.busy = false; }
  }
  private async deleteTask(id: string): Promise<void> {
    if (this.busy) { return; }
    this.busy = true;
    try { await this.repository.remove(id); await this.refreshData(); }
    catch { this.error = '删除失败，请重试'; }
    finally { this.busy = false; }
  }
  private remove(item: TaskItem): void {
    if (item.task.repeat === 'none') {
      this.getUIContext().showAlertDialog({ title: '删除任务？', message: item.task.title,
        primaryButton: { value: '取消', action: () => {} },
        secondaryButton: { value: '删除', action: () => { this.deleteTask(item.task.id); } } });
    } else {
      this.getUIContext().showAlertDialog({ title: '处理重复任务', message: `${item.task.title}\n本次日期：${item.dateKey}`,
        buttons: [
          { value: '取消', action: () => {} },
          { value: '仅跳过这次', action: () => { this.skip(item); } },
          { value: '删除整组', action: () => {
            this.getUIContext().showAlertDialog({ title: '删除整组？', message: '此规则和所有完成记录都将删除。',
              primaryButton: { value: '取消', action: () => {} },
              secondaryButton: { value: '删除整组', action: () => { this.deleteTask(item.task.id); } } });
          } }
        ] });
    }
  }
  private pickDate(): void {
    const selected = this.draftDueAt > 0 ? new Date(this.draftDueAt) : new Date();
    this.getUIContext().showDatePickerDialog({
      start: new Date(2000, 0, 1), end: new Date(2100, 11, 31), selected: selected,
      onAccept: (value: DatePickerResult) => {
        this.draftDueAt = TaskService.endOfDay(value.year ?? selected.getFullYear(), value.month ?? selected.getMonth(), value.day ?? selected.getDate());
      }
    });
  }
  private shiftMonth(delta: number): void {
    const date = ScheduleService.date(this.month);
    date.setMonth(date.getMonth() + delta);
    if (date.getFullYear() < 2000 || date.getFullYear() > 2100) { return; }
    this.month = ScheduleService.key(date.getTime()); this.selectedDay = this.month;
  }
  private async switchTheme(): Promise<void> {
    if (this.busy) { return; }
    const next = this.theme === 'system' ? 'light' : this.theme === 'light' ? 'dark' : 'system';
    this.busy = true;
    try { await this.repository.setTheme(this.context(), next); this.theme = next; }
    catch { this.error = '主题保存失败，请重试'; }
    finally { this.busy = false; }
  }
  private async switchSort(): Promise<void> {
    if (this.busy) { return; }
    this.busy = true;
    const next = this.sortMode === 'manual' ? 'created' : 'manual';
    try { await this.repository.setSortMode(next); this.sortMode = next; }
    catch { this.error = '排序设置保存失败'; }
    finally { this.busy = false; }
  }
  private openSort(): void { this.sortDraft = ScheduleService.ordered(this.tasks); this.changeMode('sort'); }
  private async saveSort(): Promise<void> {
    if (this.busy) { return; }
    this.busy = true;
    try {
      await this.repository.saveOrder(this.sortDraft); await this.repository.setSortMode('manual');
      await this.refreshData(); this.sortMode = 'manual'; this.changeMode('list'); this.notice = '手动顺序已保存';
    } catch { this.error = '顺序保存失败，请重试'; }
    finally { this.busy = false; }
  }
  private async exportBackup(): Promise<void> {
    if (this.busy) { return; }
    this.busy = true; this.error = '';
    try {
      const content = BackupService.encode(this.tasks, this.states, Date.now());
      if (await BackupFiles.exportFile(this.context(), content)) { this.notice = '任务备份已保存'; }
    } catch (error) { this.error = '导出失败：' + (error as Error).message; }
    finally { this.busy = false; }
  }
  private async chooseBackup(): Promise<void> {
    if (this.busy) { return; }
    this.busy = true; this.error = ''; this.notice = ''; this.pendingImport = undefined; this.importSummary = '';
    try {
      const raw = await BackupFiles.importFile(this.context());
      if (raw === undefined) { return; }
      const doc = BackupService.decode(raw);
      const count = doc.tasks.filter((task: Task) => !this.tasks.some((current: Task) => current.id === task.id)).length;
      this.pendingImport = doc;
      this.importSummary = `文件中共 ${doc.tasks.length} 个任务，将新增 ${count} 个。已有的 ${doc.tasks.length - count} 个同 ID 任务保持现状。`;
    } catch (error) { this.error = '无法导入：' + (error as Error).message; }
    finally { this.busy = false; }
  }
  private async confirmImport(): Promise<void> {
    if (this.busy || !this.pendingImport) { return; }
    this.busy = true;
    try {
      const count = await this.repository.mergeBackup(this.pendingImport);
      await this.refreshData(); this.pendingImport = undefined; this.importSummary = '';
      this.notice = `已导入 ${count} 个任务`;
    } catch { this.error = '导入失败，数据已回滚，请重试'; }
    finally { this.busy = false; }
  }
  private items(completed: boolean): TaskItem[] {
    return ScheduleService.filter(ScheduleService.project(this.tasks, this.states, this.view, this.selectedDay, this.now),
      completed, this.query, this.tagFilter, this.sortMode === 'manual');
  }
  private calendarDays(): CalendarDay[] {
    const keyword = this.query.trim().toLocaleLowerCase();
    const tasks = this.tasks.filter((task: Task) => (this.tagFilter.length === 0 || task.tags.includes(this.tagFilter)) &&
      (keyword.length === 0 || `${task.title} ${task.note} ${task.tags.join(' ')}`.toLocaleLowerCase().includes(keyword)));
    return ScheduleService.month(tasks, this.states, this.month);
  }
  onBackPress(): boolean {
    if (this.mode !== 'list') { if (!this.busy) { this.changeMode('list'); } return true; }
    return false;
  }

  @Builder
  section(completed: boolean, label: string) {
    Row() {
      Text(label).fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
      Blank()
      Text(this.items(completed).length.toString()).fontSize(14).fontColor($r('app.color.text_secondary'))
    }.width('100%').padding({ top: 14, bottom: 4 })
    if (this.items(completed).length === 0) {
      Text('当前视图没有符合条件的任务').fontSize(13).fontColor($r('app.color.text_secondary'))
        .width('100%').padding({ top: 10, bottom: 18 })
    }
    ForEach(this.items(completed), (item: TaskItem) => {
      TaskCard({ task: item.task, completed: item.completed, displayDueAt: item.dueAt, busy: this.busy, now: this.now,
        onToggle: () => this.toggle(item), onEdit: () => this.openEditor(item.task), onRemove: () => this.remove(item) })
    }, (item: TaskItem) => item.key)
  }

  @Builder
  filters() {
    Row({ space: 6 }) {
      ForEach(['all', 'today', 'future', 'calendar'], (view: string) => {
        Button(view === 'all' ? '全部' : view === 'today' ? '今天' : view === 'future' ? '未来' : '月历')
          .layoutWeight(1).height(34).fontSize(13)
          .backgroundColor(this.view === view ? $r('app.color.accent') : $r('app.color.card_background'))
          .fontColor(this.view === view ? $r('app.color.on_accent') : $r('app.color.text_secondary'))
          .onClick(() => this.changeView(view))
      })
    }.width('100%')
    Search({ value: this.query, placeholder: '搜索标题、备注或标签' }).height(42)
      .onChange((value: string) => { this.query = value; })
      .backgroundColor($r('app.color.card_background')).fontColor($r('app.color.text_primary'))
    Scroll() {
      Row({ space: 8 }) {
        Button('全部标签').height(30).fontSize(12)
          .backgroundColor(this.tagFilter.length === 0 ? $r('app.color.accent') : $r('app.color.card_background'))
          .fontColor(this.tagFilter.length === 0 ? $r('app.color.on_accent') : $r('app.color.text_secondary')).onClick(() => { this.tagFilter = ''; })
        ForEach(TaskService.allTags(this.tasks), (tag: string) => {
          Button(tag).height(30).fontSize(12)
            .backgroundColor(this.tagFilter === tag ? $r('app.color.accent') : $r('app.color.card_background'))
            .fontColor(this.tagFilter === tag ? $r('app.color.on_accent') : $r('app.color.text_secondary'))
            .onClick(() => { this.tagFilter = this.tagFilter === tag ? '' : tag; })
        }, (tag: string) => tag)
      }
    }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).align(Alignment.Start)
    Row() {
      Text(this.view === 'future' ? '未来 30 天' : this.view === 'today' ? '今日事项 + 未完成的逾期任务' :
        this.view === 'calendar' ? this.selectedDay : '重复任务显示今天或下一次').fontSize(11)
        .fontColor($r('app.color.text_secondary')).layoutWeight(1)
      Button(this.sortMode === 'manual' ? '手动顺序' : '创建倒序').fontSize(11).height(28)
        .padding({ left: 6, right: 6 }).backgroundColor(Color.Transparent).fontColor($r('app.color.accent'))
        .enabled(!this.busy).onClick(() => this.switchSort())
    }.width('100%')
  }

  @Builder
  editor() {
    Column({ space: 14 }) {
      Text(this.editingId.length > 0 ? '编辑任务' : '记下一件事').fontSize(24).fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary')).width('100%')
      if (this.editingId.length > 0 && this.draftRepeat !== 'none') {
        Text('这里修改整个重复系列；勾选完成只影响当天。').fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
      }
      TextInput({ placeholder: '准备做什么？（必填）', text: this.draftTitle }).maxLength(100).height(50)
        .onChange((value: string) => { this.draftTitle = value; })
        .backgroundColor($r('app.color.card_background')).fontColor($r('app.color.text_primary'))
      TextArea({ placeholder: '添加备注（可选）', text: this.draftNote }).maxLength(1000).height(90)
        .onChange((value: string) => { this.draftNote = value; })
        .backgroundColor($r('app.color.card_background')).fontColor($r('app.color.text_primary'))
      Text('优先级').fontSize(14).fontColor($r('app.color.text_secondary')).width('100%')
      Row({ space: 8 }) {
        ForEach([0, 1, 2], (priority: number) => {
          Button(TaskService.priorityLabel(priority)).layoutWeight(1).height(36)
            .backgroundColor(this.draftPriority === priority ? $r('app.color.accent') : $r('app.color.card_background'))
            .fontColor(this.draftPriority === priority ? $r('app.color.on_accent') : $r('app.color.text_primary'))
            .onClick(() => { this.draftPriority = priority; })
        }, (priority: number) => priority.toString())
      }
      Text('标签 · 逗号分隔，最多 5 个').fontSize(14).fontColor($r('app.color.text_secondary')).width('100%')
      TextInput({ placeholder: '例如：学习，生活', text: this.draftTags }).maxLength(80).height(46)
        .onChange((value: string) => { this.draftTags = value; })
        .backgroundColor($r('app.color.card_background')).fontColor($r('app.color.text_primary'))
      Text('重复规则').fontSize(14).fontColor($r('app.color.text_secondary')).width('100%')
      Row({ space: 6 }) {
        ForEach(['none', 'daily', 'weekly', 'monthly'], (repeat: string) => {
          Button(ScheduleService.repeatLabel(repeat)).layoutWeight(1).height(36).fontSize(12)
            .backgroundColor(this.draftRepeat === repeat ? $r('app.color.accent') : $r('app.color.card_background'))
            .fontColor(this.draftRepeat === repeat ? $r('app.color.on_accent') : $r('app.color.text_primary'))
            .onClick(() => { this.draftRepeat = repeat; })
        })
      }
      Text(this.draftRepeat === 'none' ? '截止日期（可选）' : '起始日期（必填）').fontSize(14)
        .fontColor($r('app.color.text_secondary')).width('100%')
      Row({ space: 8 }) {
        Button(TaskService.dateLabel(this.draftDueAt)).layoutWeight(1).height(44)
          .backgroundColor($r('app.color.card_background')).fontColor($r('app.color.accent')).onClick(() => this.pickDate())
        if (this.draftDueAt > 0) {
          Button('清除').height(44).fontSize(12).backgroundColor($r('app.color.card_background'))
            .fontColor($r('app.color.text_secondary')).onClick(() => { this.draftDueAt = 0; })
        }
      }
      if (this.draftRepeat === 'monthly') {
        Text('每月按起始日重复，月份没有该日时取当月最后一天。').fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
      }
    }.width('100%').padding({ top: 8 }).enabled(!this.busy)
  }

  @Builder
  quickEditor() {
    Column({ space: 16 }) {
      Text('一句话记任务').fontSize(24).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).width('100%')
      Text('例如：明天 交报告 #学习 高优先级\n或：每周一 复习英语 #学习')
        .fontSize(14).fontColor($r('app.color.text_secondary')).width('100%')
      TextArea({ text: this.quickText, placeholder: '输入任务，先识别，再确认保存' }).height(150).maxLength(300)
        .backgroundColor($r('app.color.card_background')).fontColor($r('app.color.text_primary'))
        .onChange((value: string) => { this.quickText = value; })
      Text('支持今天、明天、后天、下周几、YYYY-MM-DD、每天／每周／每月、#标签及高／低优先级。日期精确到天，其他文字保留为标题。')
        .fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
      Button('识别并预览').height(46).width('100%').backgroundColor($r('app.color.accent'))
        .fontColor($r('app.color.on_accent')).onClick(() => this.parseQuick())
    }.width('100%')
  }

  @Builder
  toolsPage() {
    Column({ space: 14 }) {
      Text('日程工具').fontSize(24).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).width('100%')
      Button('拖拽调整任务顺序').width('100%').height(48).backgroundColor($r('app.color.card_background'))
        .fontColor($r('app.color.accent')).onClick(() => this.openSort())
      Button('导出任务备份').width('100%').height(48).backgroundColor($r('app.color.card_background'))
        .fontColor($r('app.color.accent')).onClick(() => this.exportBackup())
      Button('从文件恢复任务').width('100%').height(48).backgroundColor($r('app.color.card_background'))
        .fontColor($r('app.color.accent')).onClick(() => this.chooseBackup())
      Text('备份包含任务、标签、顺序和重复完成记录。恢复时只合并新任务，已有同 ID 任务保留。')
        .fontSize(13).fontColor($r('app.color.text_secondary')).width('100%')
      if (this.importSummary.length > 0) {
        Text(this.importSummary).fontSize(14).fontColor($r('app.color.text_primary')).width('100%')
        Button('确认合并导入').height(46).width('100%').backgroundColor($r('app.color.accent'))
          .fontColor($r('app.color.on_accent')).onClick(() => this.confirmImport())
        Button('取消导入').backgroundColor($r('app.color.card_background')).fontColor($r('app.color.text_secondary'))
          .onClick(() => { this.pendingImport = undefined; this.importSummary = ''; })
      }
      Text('已跳过的重复事项').fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).width('100%').margin({ top: 12 })
      if (!this.states.some((state: OccurrenceState) => state.skipped)) {
        Text('还没有跳过的事项').fontSize(13).fontColor($r('app.color.text_secondary')).width('100%')
      }
      ForEach(this.states.filter((state: OccurrenceState) => state.skipped), (state: OccurrenceState) => {
        Row({ space: 8 }) {
          Text(`${this.tasks.find((task: Task) => task.id === state.taskId)?.title ?? ''}\n${state.dateKey}`)
            .fontSize(14).layoutWeight(1).fontColor($r('app.color.text_primary'))
          Button('恢复').fontSize(12).height(36).backgroundColor($r('app.color.accent'))
            .fontColor($r('app.color.on_accent')).onClick(() => this.restoreOccurrence(state))
        }.padding(12).width('100%').borderRadius(14).backgroundColor($r('app.color.card_background'))
      }, (state: OccurrenceState) => `${state.taskId}@${state.dateKey}`)
    }.width('100%').enabled(!this.busy)
  }

  @Builder
  sortingPage() {
    Column({ space: 10 }) {
      Text('长按任务拖动，也可点箭头微调').fontSize(15).fontColor($r('app.color.text_primary')).width('100%')
      Text('保存后启用手动顺序；列表右上角可切回创建倒序。').fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
      List({ space: 10 }) {
        ForEach(this.sortDraft, (task: Task, index: number) => {
          ListItem() {
            Row({ space: 8 }) {
              Text('≡').fontSize(22).fontColor($r('app.color.accent'))
              Text(task.title).fontSize(15).layoutWeight(1).maxLines(2).fontColor($r('app.color.text_primary'))
              Button('↑').width(36).height(38).padding(0).fontSize(18).accessibilityText('上移任务')
                .backgroundColor($r('app.color.accent')).fontColor($r('app.color.on_accent'))
                .enabled(index > 0).onClick(() => { this.sortDraft = ScheduleService.move(this.sortDraft, index, index - 1); })
              Button('↓').width(36).height(38).padding(0).fontSize(18).accessibilityText('下移任务')
                .backgroundColor($r('app.color.accent')).fontColor($r('app.color.on_accent')).enabled(index < this.sortDraft.length - 1)
                .onClick(() => { this.sortDraft = ScheduleService.move(this.sortDraft, index, index + 1); })
            }.padding(14).height(80).width('100%').borderRadius(16).backgroundColor($r('app.color.card_background'))
          }
        }, (task: Task) => task.id).onMove((from: number, to: number) => { this.sortDraft = ScheduleService.move(this.sortDraft, from, to); })
      }.layoutWeight(1).width('100%')
    }.width('100%').height('100%').enabled(!this.busy)
  }

  build() {
    Column({ space: 10 }) {
      Row({ space: 6 }) {
        Column({ space: 3 }) {
          Text('TaiPlan').fontSize(28).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
          Text('把想做的事，变成完成的事。').fontSize(11).fontColor($r('app.color.text_secondary'))
        }.alignItems(HorizontalAlign.Start)
        Blank()
        Button(this.theme === 'dark' ? '深色' : this.theme === 'light' ? '浅色' : '系统')
          .height(34).fontSize(12).padding({ left: 10, right: 10 }).backgroundColor($r('app.color.card_background'))
          .fontColor($r('app.color.accent')).enabled(this.ready && !this.busy).onClick(() => this.switchTheme())
        Button('⋯').width(36).height(34).padding(0).fontSize(22).backgroundColor($r('app.color.card_background'))
          .fontColor($r('app.color.accent')).accessibilityText('打开日程工具').enabled(this.ready && !this.busy)
          .onClick(() => this.changeMode('tools'))
      }.width('100%').padding({ top: 12, bottom: 2 })
      if (this.error.length > 0) { Text(this.error).fontSize(13).fontColor($r('app.color.danger')).width('100%') }
      if (this.notice.length > 0) { Text(this.notice).fontSize(12).fontColor($r('app.color.accent')).width('100%') }
      if (!this.ready) {
        Blank()
        Text(this.busy ? '正在读取任务…' : '暂时无法读取任务').fontColor($r('app.color.text_secondary'))
        if (!this.busy) { Button('重新读取').onClick(() => this.load()) }
        Blank()
      } else {
        if (this.mode === 'list') { this.filters() }
        if (this.mode === 'sort') {
          Column() { this.sortingPage() }.layoutWeight(1).width('100%')
        } else {
          Scroll(this.scroller) {
            Column({ space: 12 }) {
              if (this.mode === 'editor') { this.editor() }
              else if (this.mode === 'quick') { this.quickEditor() }
              else if (this.mode === 'tools') { this.toolsPage() }
              else {
                if (this.view === 'calendar') {
                  MonthCalendar({ days: this.calendarDays(), selected: this.selectedDay, month: this.month,
                    onSelect: (key: string) => { this.selectedDay = key; },
                    onMonth: (delta: number) => this.shiftMonth(delta),
                    onToday: () => { this.selectedDay = ScheduleService.key(Date.now()); this.month = this.selectedDay.slice(0, 7) + '-01'; } })
                }
                this.section(false, '待办')
                this.section(true, '已完成')
              }
            }.width('100%').padding({ bottom: 20 })
          }.layoutWeight(1).width('100%').align(Alignment.Top)
        }
        if (this.mode === 'editor' || this.mode === 'sort') {
          Row({ space: 10 }) {
            Button('取消').layoutWeight(1).height(48).backgroundColor($r('app.color.card_background'))
              .fontColor($r('app.color.text_primary')).onClick(() => this.changeMode('list'))
            Button(this.busy ? '保存中…' : this.mode === 'sort' ? '保存顺序' : '保存任务').layoutWeight(1).height(48)
              .backgroundColor($r('app.color.accent')).fontColor($r('app.color.on_accent'))
              .onClick(() => { if (this.mode === 'sort') { this.saveSort(); } else { this.saveEditor(); } })
              .enabled(this.mode === 'sort' || this.draftTitle.trim().length > 0)
          }.enabled(!this.busy)
        } else if (this.mode === 'list') {
          Row({ space: 10 }) {
            Button('一句话').height(48).fontSize(14).backgroundColor($r('app.color.card_background'))
              .fontColor($r('app.color.accent')).onClick(() => this.changeMode('quick'))
            Button('＋ 新建任务').height(48).layoutWeight(1).backgroundColor($r('app.color.accent'))
              .fontColor($r('app.color.on_accent')).onClick(() => this.openEditor())
          }.enabled(!this.busy)
        } else {
          Button('返回任务列表').height(48).width('100%').backgroundColor($r('app.color.card_background'))
            .fontColor($r('app.color.accent')).enabled(!this.busy).onClick(() => this.changeMode('list'))
        }
      }
    }.padding({ left: 18, right: 18, bottom: 16 }).width('100%').height('100%')
      .backgroundColor($r('app.color.page_background'))
  }
}
