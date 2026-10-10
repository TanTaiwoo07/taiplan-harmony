import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { BackupDocument, CalendarDay, OccurrenceState, Task, TaskDraft, TaskItem, TimeConflict } from '../model/Task';
import { TaskService } from '../services/TaskService';
import { ScheduleService } from '../services/ScheduleService';
import { QuickEntryService } from '../services/QuickEntryService';
import { BackupService } from '../services/BackupService';
import { IcsService } from '../services/IcsService';
import { DayOverview, FocusService } from '../services/FocusService';
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
  @State private selectedTab: number = 0;
  @State private showFilters: boolean = false;
  @State private showHomeDone: boolean = false;
  @State private undoTitle: string = '';
  @State private view: string = 'all';
  @State private editingId: string = '';
  @State private draftTitle: string = '';
  @State private draftNote: string = '';
  @State private draftPriority: number = 1;
  @State private draftTags: string = '';
  @State private draftDueAt: number = 0;
  @State private draftRepeat: string = 'none';
  @State private draftStart: number = -1;
  @State private draftDuration: string = '30';
  @State private draftSteps: string = '';
  @State private batchRows: TaskItem[] = [];
  @State private batchKeys: string[] = [];
  @State private expandedKeys: string[] = [];
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
  @State private importNotes: string = '';
  private pendingImport: BackupDocument | undefined = undefined;
  private deletedBackup: BackupDocument | undefined = undefined;
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
    this.draftDueAt = task ? task.dueAt : this.selectedTab === 2 ? ScheduleService.end(this.selectedDay) :
      this.selectedTab === 0 ? ScheduleService.end(ScheduleService.key(Date.now())) : 0;
    this.draftRepeat = task ? task.repeat : 'none';
    this.draftStart = task?.startMinute ?? -1;
    this.draftDuration = (task?.durationMinutes ?? 30).toString();
    this.draftSteps = (task?.steps ?? []).join('\n');
    this.changeMode('editor');
  }
  private parseQuick(): void {
    try {
      const draft = QuickEntryService.parse(this.quickText, Date.now());
      TaskService.create(draft, 'preview', Date.now());
      this.openEditor();
      this.draftTitle = draft.title; this.draftNote = draft.note; this.draftPriority = draft.priority;
      this.draftTags = draft.tagsText; this.draftDueAt = draft.dueAt; this.draftRepeat = draft.repeat ?? 'none';
      this.draftStart = draft.startMinute ?? -1; this.draftDuration = (draft.durationMinutes ?? 30).toString();
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
      if (this.selectedTab === 0 && task.dueAt === 0 && task.priority !== 2) { this.selectedTab = 1; }
      this.notice = '任务已保存';
    } catch { this.error = '保存失败，请重试。编辑内容仍然保留。'; }
    finally { this.busy = false; }
  }
  private saveEditor(): void {
    if (this.busy) { return; }
    const draft: TaskDraft = { title: this.draftTitle, note: this.draftNote, priority: this.draftPriority,
      tagsText: this.draftTags, dueAt: this.draftDueAt, repeat: this.draftRepeat,
      startMinute: this.draftStart, durationMinutes: Number(this.draftDuration), stepsText: this.draftSteps };
    try {
      const old = this.tasks.find((task: Task) => task.id === this.editingId);
      if (this.editingId.length > 0 && !old) { this.error = '任务已不存在，请返回列表'; return; }
      const task = old ? TaskService.edit(old, draft, Date.now()) : TaskService.create(draft, util.generateRandomUUID(), Date.now());
      const warnings: string[] = [];
      if (old && (old.repeat !== task.repeat || old.dueAt !== task.dueAt) && this.states.some((state: OccurrenceState) => state.taskId === old.id)) {
        warnings.push('起始日期或重复规则变更将重置这一组的完成、跳过和子任务进度。');
      } else if (old && JSON.stringify(old.steps ?? []) !== JSON.stringify(task.steps ?? []) &&
        ((old.doneSteps ?? []).length > 0 || this.states.some((state: OccurrenceState) => state.taskId === old.id && (state.doneSteps ?? []).length > 0))) {
        warnings.push('子任务清单发生变化，将重置子任务勾选进度，保留任务完成状态。');
      }
      const conflicts = ScheduleService.conflicts(task, this.tasks, this.states, Date.now());
      if (conflicts.length > 0) {
        warnings.push('以下未完成任务时间重叠（重复任务检查起始日或今天起 30 天，最多列出 5 条）：\n' +
          conflicts.map((item: TimeConflict) => `${item.dateKey} ${item.time} ${item.title}`).join('\n'));
      }
      if (warnings.length > 0) {
        this.getUIContext().showAlertDialog({
          title: '保存前确认', message: warnings.join('\n\n'),
          primaryButton: { value: '取消', action: () => {} },
          secondaryButton: { value: '仍然保存', action: () => { this.persistEditor(task); } }
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
        completed: !item.completed, skipped: false, updatedAt: Date.now(), doneSteps: item.doneSteps ?? [] }); }
      await this.refreshData();
    } catch { this.error = '完成状态保存失败，请重试'; }
    finally { this.busy = false; }
  }
  private async skip(item: TaskItem): Promise<void> {
    if (this.busy) { return; }
    this.busy = true;
    try {
      await this.repository.setOccurrence({ taskId: item.task.id, dateKey: item.dateKey, completed: false, skipped: true, updatedAt: Date.now(), doneSteps: item.doneSteps ?? [] });
      await this.refreshData(); this.notice = '已跳过这一次，可在工具中恢复';
    } catch { this.error = '跳过失败，请重试'; }
    finally { this.busy = false; }
  }
  private async restoreOccurrence(state: OccurrenceState): Promise<void> {
    if (this.busy) { return; }
    this.busy = true;
    try {
      await this.repository.setOccurrence({ taskId: state.taskId, dateKey: state.dateKey, completed: false, skipped: false, updatedAt: Date.now(), doneSteps: state.doneSteps ?? [] });
      await this.refreshData(); this.notice = '已恢复这一次任务';
    } catch { this.error = '恢复失败，请重试'; }
    finally { this.busy = false; }
  }
  private async deleteTask(id: string): Promise<void> {
    if (this.busy) { return; }
    this.busy = true;
    let removed = false;
    try {
      const task = this.tasks.find((item: Task) => item.id === id);
      if (!task) { throw new Error('任务已不存在'); }
      const snapshot = BackupService.decode(BackupService.encode([task], this.states.filter((state: OccurrenceState) => state.taskId === id), Date.now()));
      await this.repository.remove(id);
      removed = true;
      this.deletedBackup = snapshot; this.undoTitle = task.title;
      await this.refreshData();
    }
    catch { this.error = removed ? '任务已删除，但列表刷新失败；可撤销或重新启动应用。' : '删除失败，请重试'; }
    finally { this.busy = false; }
  }
  private async undoDelete(): Promise<void> {
    if (this.busy || !this.deletedBackup) { return; }
    this.busy = true; this.error = '';
    try {
      await this.repository.mergeBackup(this.deletedBackup);
      await this.refreshData(); this.deletedBackup = undefined; this.undoTitle = ''; this.notice = '任务及原有进度已恢复';
    } catch { this.error = '撤销失败，可重试'; }
    finally { this.busy = false; }
  }
  private copyTask(task: Task): void {
    this.openEditor(task); this.editingId = '';
    this.draftTitle = (task.title + '（副本）').slice(0, 100);
    this.notice = '已复制为新草稿，完成和子任务进度从头开始。';
  }
  private async toggleStep(item: TaskItem, index: number): Promise<void> {
    if (this.busy) { return; }
    this.busy = true; this.error = '';
    try {
      const done = TaskService.toggleStep(item.doneSteps ?? [], index, (item.task.steps ?? []).length);
      if (item.task.repeat === 'none') {
        const task = TaskService.withCompletion(item.task, item.completed, Date.now());
        task.doneSteps = done;
        await this.repository.save(task);
      } else {
        await this.repository.setOccurrence({ taskId: item.task.id, dateKey: item.dateKey,
          completed: item.completed, skipped: false, updatedAt: Date.now(), doneSteps: done });
      }
      await this.refreshData();
    } catch { this.error = '子任务进度保存失败，请重试'; }
    finally { this.busy = false; }
  }
  private openBatch(): void {
    this.batchRows = this.items(false).concat(this.items(true)); this.batchKeys = [];
    this.changeMode('batch');
  }
  private selectBatch(key: string): void {
    this.batchKeys = this.batchKeys.includes(key) ? this.batchKeys.filter((item: string) => item !== key) : this.batchKeys.concat([key]);
  }
  private async applyBatch(completed: boolean): Promise<void> {
    if (this.busy || this.batchKeys.length === 0) { return; }
    this.busy = true; this.error = '';
    try {
      const rows = this.batchRows.filter((item: TaskItem) => this.batchKeys.includes(item.key));
      await this.repository.setCompleted(rows, completed, Date.now());
      await this.refreshData(); this.changeMode('list');
      this.notice = `已将 ${rows.length} 项标记为${completed ? '完成' : '待办'}`;
    } catch { this.error = '批量更新失败，本次修改已回滚'; }
    finally { this.busy = false; }
  }
  private todaySummary(): string {
    const rows = ScheduleService.project(this.tasks, this.states, 'today', '', this.now);
    const done = rows.filter((item: TaskItem) => item.completed).length;
    const overdue = rows.filter((item: TaskItem) => !item.completed && TaskService.deadline(item.task, item.dueAt) < this.now).length;
    return `今天与逾期事项 ${rows.length} 项 · 已完成 ${done} · 逾期 ${overdue}`;
  }
  private pickTime(): void {
    const selected = new Date();
    selected.setHours(this.draftStart < 0 ? 9 : Math.floor(this.draftStart / 60), this.draftStart < 0 ? 0 : this.draftStart % 60, 0, 0);
    this.getUIContext().showTimePickerDialog({ selected: selected, useMilitaryTime: true,
      onAccept: (value: TimePickerResult) => {
        this.draftStart = value.hour * 60 + value.minute;
        if (this.draftDueAt === 0) { this.draftDueAt = ScheduleService.end(ScheduleService.key(Date.now())); }
      } });
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
  private async selectTheme(next: string): Promise<void> {
    if (this.busy) { return; }
    this.busy = true;
    try { await this.repository.setTheme(this.context(), next); this.theme = next; }
    catch { this.error = '主题保存失败，请重试'; }
    finally { this.busy = false; }
  }
  private async switchSort(): Promise<void> {
    if (this.busy) { return; }
    this.busy = true;
    const modes = ['created', 'time', 'priority', 'manual'];
    const next = modes[(modes.indexOf(this.sortMode) + 1) % modes.length];
    try { await this.repository.setSortMode(next); this.sortMode = next; }
    catch { this.error = '排序设置保存失败'; }
    finally { this.busy = false; }
  }
  private openSort(): void { this.sortDraft = ScheduleService.ordered(this.tasks); this.changeMode('sort'); }
  private sortIndex(id: string): number { return this.sortDraft.findIndex((task: Task) => task.id === id); }
  private shiftSort(id: string, delta: number): void {
    const index = this.sortIndex(id);
    this.sortDraft = ScheduleService.move(this.sortDraft, index, index + delta);
  }
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
    this.busy = true; this.error = ''; this.notice = ''; this.pendingImport = undefined; this.importSummary = ''; this.importNotes = '';
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
  private async chooseCalendar(): Promise<void> {
    if (this.busy) { return; }
    this.busy = true; this.error = ''; this.notice = ''; this.pendingImport = undefined; this.importSummary = ''; this.importNotes = '';
    try {
      const raw = await BackupFiles.importFile(this.context(), 'ics');
      if (raw === undefined) { return; }
      const report = IcsService.parse(raw, Date.now());
      this.pendingImport = BackupService.decode(JSON.stringify(report.document));
      const count = report.document.tasks.filter((task: Task) => !this.tasks.some((current: Task) => current.id === task.id)).length;
      this.importSummary = `日历共 ${report.total} 条事件，可识别 ${report.document.tasks.length} 条，将新增 ${count} 个任务。已有 UID 保留本机版本。`;
      this.importNotes = report.notes.join('\n');
    } catch (error) { this.error = '日历读取失败：' + (error as Error).message; }
    finally { this.busy = false; }
  }
  private async exportCalendar(): Promise<void> {
    if (this.busy) { return; }
    this.busy = true; this.error = ''; this.notice = '';
    try {
      const raw = IcsService.exportMonth(this.tasks, this.states, Date.now());
      if (await BackupFiles.exportFile(this.context(), raw, 'ics')) { this.notice = '已导出今天起 30 天日历快照'; }
    } catch (error) { this.error = '日历导出失败：' + (error as Error).message; }
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
  private items(completed: boolean, page: number = this.selectedTab): TaskItem[] {
    const view = page === 0 ? 'today' : page === 2 ? 'calendar' : this.view;
    return ScheduleService.filter(ScheduleService.project(this.tasks, this.states, view, this.selectedDay, this.now),
      completed, page === 1 ? this.query : '', page === 1 ? this.tagFilter : '', page === 2 ? 'time' : this.sortMode);
  }
  private overview(): DayOverview { return FocusService.overview(this.tasks, this.states, this.now); }
  private tabTitle(page: number): string { return ['今天', '待办', '日历', '设置'][page]; }
  private dateTitle(): string {
    const date = new Date(this.now);
    return `${date.getMonth() + 1}月${date.getDate()}日 · 星期${['日', '一', '二', '三', '四', '五', '六'][date.getDay()]}`;
  }
  private pageTitle(): string {
    return this.mode === 'list' ? this.tabTitle(this.selectedTab) : this.mode === 'editor' ? (this.editingId ? '编辑任务' : '新建任务') :
      this.mode === 'quick' ? '快速添加' : this.mode === 'tools' ? '数据与恢复' : this.mode === 'sort' ? '任务排序' : '批量处理';
  }
  private calendarDays(): CalendarDay[] {
    return ScheduleService.month(this.tasks, this.states, this.month);
  }
  onBackPress(): boolean {
    if (this.mode !== 'list') { if (!this.busy) { this.changeMode('list'); } return true; }
    if (this.selectedTab !== 0) { this.selectedTab = 0; return true; }
    return false;
  }


  private rows(completed: boolean, page: number, group: string): TaskItem[] {
    return group === 'urgent' ? this.overview().urgent : group === 'remaining' ? this.overview().remaining : group === 'done' ? this.overview().done : this.items(completed, page);
  }

  @Builder
  taskRows(completed: boolean, page: number, group: string) {
    ForEach(this.rows(completed, page, group), (item: TaskItem) => {
      TaskCard({ task: item.task, completed: item.completed, displayDueAt: item.dueAt, busy: this.busy, now: this.now,
        expanded: this.expandedKeys.includes(item.key), onExpand: () => {
          this.expandedKeys = this.expandedKeys.includes(item.key) ? this.expandedKeys.filter((key: string) => key !== item.key) : this.expandedKeys.concat([item.key]);
        },
        doneSteps: item.doneSteps ?? [], onStep: (index: number) => this.toggleStep(item, index), onCopy: () => this.copyTask(item.task),
        onToggle: () => this.toggle(item), onEdit: () => this.openEditor(item.task), onRemove: () => this.remove(item) })
    }, (item: TaskItem) => ScheduleService.renderKey(item))
  }

  @Builder
  section(completed: boolean, label: string, page: number) {
    Row() {
      Text(label).fontSize(19).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
      Blank()
      Text(this.items(completed, page).length.toString()).fontSize(13).fontColor($r('app.color.text_secondary'))
    }.width('100%').padding({ top: 14, bottom: 4 })
    if (this.items(completed, page).length === 0) {
      Text(completed ? '完成后的任务会出现在这里' : '没有符合条件的待办')
        .fontSize(13).fontColor($r('app.color.text_secondary')).width('100%').padding({ top: 8, bottom: 12 })
    }
    this.taskRows(completed, page, '')
  }

  @Builder
  filters() {
    Row({ space: 8 }) {
      Search({ value: this.query, placeholder: '搜索任务' }).height(44).layoutWeight(1)
        .onChange((value: string) => { this.query = value; })
        .backgroundColor($r('app.color.card_background')).fontColor($r('app.color.text_primary'))
      Button('筛选').height(44).fontSize(13).padding({ left: 12, right: 12 })
        .backgroundColor($r('app.color.card_background')).fontColor($r('app.color.text_primary'))
        .onClick(() => { this.showFilters = !this.showFilters; })
    }.width('100%')
    if (this.showFilters) {
      Column({ space: 10 }) {
        Row({ space: 8 }) {
          ForEach(['all', 'future'], (view: string) => {
            Button(view === 'all' ? '全部任务' : '未来 30 天').layoutWeight(1).height(40).fontSize(13)
              .backgroundColor(this.view === view ? $r('app.color.accent') : $r('app.color.chip_background'))
              .fontColor(this.view === view ? $r('app.color.on_accent') : $r('app.color.text_secondary'))
              .onClick(() => this.changeView(view))
          })
        }
        Scroll() {
          Row({ space: 8 }) {
            Button('全部标签').height(40).fontSize(12)
              .backgroundColor(this.tagFilter.length === 0 ? $r('app.color.accent') : $r('app.color.chip_background'))
              .fontColor(this.tagFilter.length === 0 ? $r('app.color.on_accent') : $r('app.color.text_secondary'))
              .onClick(() => { this.tagFilter = ''; })
            ForEach(TaskService.allTags(this.tasks), (tag: string) => {
              Button(tag).height(40).fontSize(12)
                .backgroundColor(this.tagFilter === tag ? $r('app.color.accent') : $r('app.color.chip_background'))
                .fontColor(this.tagFilter === tag ? $r('app.color.on_accent') : $r('app.color.text_secondary'))
                .onClick(() => { this.tagFilter = this.tagFilter === tag ? '' : tag; })
            }, (tag: string) => tag)
          }
        }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).align(Alignment.Start)
        Row({ space: 8 }) {
          Button(ScheduleService.sortLabel(this.sortMode)).layoutWeight(1).height(40).fontSize(12).padding(4)
            .backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).onClick(() => this.switchSort())
          Button('拖拽排序').layoutWeight(1).height(40).fontSize(12).padding(4)
            .backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).onClick(() => this.openSort())
          Button('多选').height(40).fontSize(12).padding({ left: 12, right: 12 })
            .backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).onClick(() => this.openBatch())
        }
      }.padding(12).borderRadius(16).backgroundColor($r('app.color.card_background')).width('100%')
    }
    Text((this.view === 'future' ? '未来 30 天' : '全部任务') + (this.tagFilter ? ' · ' + this.tagFilter : '') + ' · ' + ScheduleService.sortLabel(this.sortMode))
      .fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
  }

  @Builder
  homePage() {
    Column({ space: 12 }) {
      Row({ space: 16 }) {
        Column({ space: 6 }) {
          Text('今天已完成').fontSize(13).fontColor($r('app.color.text_secondary'))
          Text(this.overview().completed.toString() + ' / ' + this.overview().planned.toString())
            .fontSize(34).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
          Text(this.overview().planned > 0 && this.overview().completed === this.overview().planned ? '今日计划已全部完成' : '一步一步，完成今天的计划')
            .fontSize(12).fontColor($r('app.color.text_secondary'))
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Column({ space: 6 }) {
          Text(this.overview().overdue.toString()).fontSize(28).fontWeight(FontWeight.Medium)
            .fontColor(this.overview().overdue > 0 ? $r('app.color.danger') : $r('app.color.text_primary'))
          Text('逾期事项').fontSize(12).fontColor($r('app.color.text_secondary'))
        }
      }.width('100%')
      Progress({ value: this.overview().completed, total: Math.max(1, this.overview().planned), type: ProgressType.Linear })
        .color($r('app.color.accent')).backgroundColor($r('app.color.chip_background')).height(4).width('100%')
    }.padding(20).width('100%').borderRadius(20).backgroundColor($r('app.color.card_background'))

    Button('一句话添加  →', { type: ButtonType.Normal }).height(44).width('100%').fontSize(14)
      .borderRadius(14).backgroundColor($r('app.color.card_background')).fontColor($r('app.color.text_primary'))
      .onClick(() => this.changeMode('quick'))

    if (this.overview().urgent.length > 0) {
      Row() {
        Text('优先处理').fontSize(19).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        Blank()
        Text(this.overview().urgent.length.toString()).fontSize(13).fontColor($r('app.color.danger'))
      }.width('100%').padding({ top: 12 })
      Text('逾期与高优先级事项').fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
      this.taskRows(false, 0, 'urgent')
    }
    if (this.overview().remaining.length > 0) {
      Text('今天待办').fontSize(19).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        .width('100%').padding({ top: 12 })
      this.taskRows(false, 0, 'remaining')
    }
    if (this.overview().urgent.length === 0 && this.overview().remaining.length === 0) {
      Column({ space: 8 }) {
        Text('今天暂时没有待办').fontSize(18).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        Text('点右上角 ＋，安排下一件事。\n未安排日期的普通任务在「待办」里。')
          .fontSize(13).lineHeight(21).textAlign(TextAlign.Center).fontColor($r('app.color.text_secondary'))
      }.width('100%').padding({ top: 32, bottom: 24 })
    }
    if (this.overview().done.length > 0) {
      Button((this.showHomeDone ? '收起' : '查看') + '今日已完成 · ' + this.overview().done.length.toString(),
        { type: ButtonType.Normal }).height(44).width('100%').fontSize(13)
        .backgroundColor(Color.Transparent).fontColor($r('app.color.text_secondary'))
        .onClick(() => { this.showHomeDone = !this.showHomeDone; })
      if (this.showHomeDone) { this.taskRows(true, 0, 'done') }
    }
  }

  @Builder
  settingsPage() {
    Text('外观').fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).width('100%')
    Column({ space: 12 }) {
      Text('显示模式').fontSize(15).fontColor($r('app.color.text_primary')).width('100%')
      Row({ space: 8 }) {
        ForEach(['system', 'light', 'dark'], (theme: string) => {
          Button(theme === 'system' ? '跟随系统' : theme === 'light' ? '浅色' : '深色').height(44).layoutWeight(1).fontSize(13).padding(4)
            .backgroundColor(this.theme === theme ? $r('app.color.accent') : $r('app.color.chip_background'))
            .fontColor(this.theme === theme ? $r('app.color.on_accent') : $r('app.color.text_secondary'))
            .onClick(() => this.selectTheme(theme))
        })
      }.width('100%')
      Text('选择跟随系统，可自动使用设备的深浅色设置。')
        .fontSize(12).lineHeight(19).fontColor($r('app.color.text_secondary')).width('100%')
    }.width('100%').padding(16).borderRadius(18).backgroundColor($r('app.color.card_background'))
    Text('数据').fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).width('100%').margin({ top: 12 })
    Button('备份、日历互通与恢复  ›', { type: ButtonType.Normal }).height(56).width('100%').fontSize(15)
      .borderRadius(16).backgroundColor($r('app.color.card_background')).fontColor($r('app.color.text_primary'))
      .onClick(() => this.changeMode('tools'))
    Column({ space: 8 }) {
      Text('TaiPlan 0.5.0').fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
      Text('待办是核心，日历帮助安排时间。\n任务保存在本机，建议定期导出备份。')
        .fontSize(13).lineHeight(21).fontColor($r('app.color.text_secondary'))
    }.alignItems(HorizontalAlign.Start).width('100%').padding({ top: 20, bottom: 16 })
  }

  @Builder
  editor() {
    Column({ space: 14 }) {
      if (this.editingId.length === 0) {
        Button('用一句话快速填写  →', { type: ButtonType.Normal }).height(44).width('100%').fontSize(14)
          .backgroundColor($r('app.color.card_background')).fontColor($r('app.color.text_primary'))
          .borderRadius(14).onClick(() => this.changeMode('quick'))
      }
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
            .fontColor($r('app.color.text_secondary')).onClick(() => { this.draftDueAt = 0; this.draftStart = -1; })
        }
      }
      if (this.draftRepeat === 'monthly') {
        Text('每月按起始日重复，月份没有该日时取当月最后一天。').fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
      }
      Text('时间安排').fontSize(14).fontColor($r('app.color.text_secondary')).width('100%')
      Row({ space: 8 }) {
        Button(this.draftStart < 0 ? '全天 · 点击设置时间' : `开始 ${TaskService.minuteLabel(this.draftStart)}`)
          .layoutWeight(1).height(44).fontSize(13).backgroundColor($r('app.color.card_background'))
          .fontColor($r('app.color.accent')).onClick(() => this.pickTime())
        if (this.draftStart >= 0) {
          Button('改为全天').height(44).fontSize(12).backgroundColor($r('app.color.card_background'))
            .fontColor($r('app.color.text_secondary')).onClick(() => { this.draftStart = -1; })
        }
      }.width('100%')
      if (this.draftStart >= 0) {
        Row({ space: 8 }) {
          Text('时长（分钟）').fontSize(13).fontColor($r('app.color.text_secondary'))
          TextInput({ text: this.draftDuration, placeholder: '例如 30' }).type(InputType.Number).maxLength(4)
            .layoutWeight(1).height(44).backgroundColor($r('app.color.card_background')).fontColor($r('app.color.text_primary'))
            .onChange((value: string) => { this.draftDuration = value; })
        }
        Text('保存时检查时间冲突；时段结束后计为逾期。').fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
      }
      Text('子任务 · 每行一项，最多 20 项').fontSize(14).fontColor($r('app.color.text_secondary')).width('100%')
      TextArea({ text: this.draftSteps, placeholder: '例如：\n整理资料\n完成初稿\n检查并提交' }).height(140).maxLength(2020)
        .backgroundColor($r('app.color.card_background')).fontColor($r('app.color.text_primary'))
        .onChange((value: string) => { this.draftSteps = value; })
      Text('子任务可在卡片展开勾选；任务完成由你单独确认。重复任务每天独立记录子任务进度。')
        .fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
    }.width('100%').padding({ top: 8 }).enabled(!this.busy)
  }

  @Builder
  quickEditor() {
    Column({ space: 16 }) {
      Text('例如：明天 14:30 交报告 用时60分钟 #学习\n或：每周一 复习英语 #学习 高优先级')
        .fontSize(14).fontColor($r('app.color.text_secondary')).width('100%')
      TextArea({ text: this.quickText, placeholder: '输入任务，先识别，再确认保存' }).height(150).maxLength(300)
        .backgroundColor($r('app.color.card_background')).fontColor($r('app.color.text_primary'))
        .onChange((value: string) => { this.quickText = value; })
      Text('支持今天、明天、后天、下周几、YYYY-MM-DD、每天／每周／每月、HH:mm、用时N分钟、#标签及高／低优先级。仅写时间时默认今天，其他文字保留为标题。')
        .fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
      Button('识别并预览').height(46).width('100%').backgroundColor($r('app.color.accent'))
        .fontColor($r('app.color.on_accent')).onClick(() => this.parseQuick())
    }.width('100%')
  }

  @Builder
  toolsPage() {
    Column({ space: 14 }) {
      Button('导出任务备份').width('100%').height(48).backgroundColor($r('app.color.card_background'))
        .fontColor($r('app.color.accent')).onClick(() => this.exportBackup())
      Button('从文件恢复任务').width('100%').height(48).backgroundColor($r('app.color.card_background'))
        .fontColor($r('app.color.accent')).onClick(() => this.chooseBackup())
      Row({ space: 8 }) {
        Button('导入 ICS 日历').layoutWeight(1).height(44).fontSize(13).padding(4)
          .backgroundColor($r('app.color.card_background')).fontColor($r('app.color.accent')).onClick(() => this.chooseCalendar())
        Button('导出 30 天日历').layoutWeight(1).height(44).fontSize(13).padding(4)
          .backgroundColor($r('app.color.card_background')).fontColor($r('app.color.accent')).onClick(() => this.exportCalendar())
      }.width('100%')
      Text('ICS 导出为单次事件快照，包含今天起 30 天的有日期事项；不是完整备份。导入不支持的时区、跨日和重复规则会逐项报告。')
        .fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
      Text('备份包含任务、时间、子任务、标签、顺序和重复完成记录。兼容旧版备份；恢复时只合并新任务，已有同 ID 任务保留。')
        .fontSize(13).fontColor($r('app.color.text_secondary')).width('100%')
      if (this.importSummary.length > 0) {
        Text(this.importSummary).fontSize(14).fontColor($r('app.color.text_primary')).width('100%')
        Button('确认合并导入').height(46).width('100%').backgroundColor($r('app.color.accent'))
          .fontColor($r('app.color.on_accent')).onClick(() => this.confirmImport())
        Button('取消导入').backgroundColor($r('app.color.card_background')).fontColor($r('app.color.text_secondary'))
          .onClick(() => { this.pendingImport = undefined; this.importSummary = ''; })
      }
      if (this.importNotes.length > 0) {
        Text('日历导入报告\n' + this.importNotes).fontSize(12).fontColor($r('app.color.danger')).width('100%')
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
  batchPage() {
    Column({ space: 12 }) {
      Text('基于进入前的视图与筛选；重复任务只影响选中的日期。子任务进度保持不变。')
        .fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
      Row() {
        Text(`已选 ${this.batchKeys.length} / ${this.batchRows.length} 项`).fontSize(14).layoutWeight(1).fontColor($r('app.color.text_primary'))
        Button(this.batchKeys.length === this.batchRows.length && this.batchRows.length > 0 ? '清空选择' : '全选')
          .height(34).fontSize(12).backgroundColor($r('app.color.card_background')).fontColor($r('app.color.accent'))
          .onClick(() => { this.batchKeys = this.batchKeys.length === this.batchRows.length ? [] : this.batchRows.map((item: TaskItem) => item.key); })
      }.width('100%')
      if (this.batchRows.length === 0) { Text('当前视图没有任务').fontColor($r('app.color.text_secondary')) }
      ForEach(this.batchRows, (item: TaskItem) => {
        Row({ space: 10 }) {
          Checkbox({ name: item.key }).select(this.batchKeys.includes(item.key)).selectedColor($r('app.color.accent'))
            .accessibilityText(`选择 ${item.task.title} ${item.dateKey}`)
            .onChange((selected: boolean) => { if (selected !== this.batchKeys.includes(item.key)) { this.selectBatch(item.key); } })
          Column({ space: 6 }) {
            Text(item.task.title).fontSize(16).fontColor($r('app.color.text_primary')).width('100%')
            Text(`${item.completed ? '已完成' : '待办'} · ${item.dateKey || '无日期'} · ${TaskService.timeLabel(item.task)}`)
              .fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
          }.layoutWeight(1)
        }.padding(14).width('100%').borderRadius(16).backgroundColor($r('app.color.card_background'))
      }, (item: TaskItem) => item.key)
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
                .enabled(this.sortIndex(task.id) > 0).onClick(() => this.shiftSort(task.id, -1))
              Button('↓').width(36).height(38).padding(0).fontSize(18).accessibilityText('下移任务')
                .backgroundColor($r('app.color.accent')).fontColor($r('app.color.on_accent')).enabled(this.sortIndex(task.id) < this.sortDraft.length - 1)
                .onClick(() => this.shiftSort(task.id, 1))
            }.padding(14).height(80).width('100%').borderRadius(16).backgroundColor($r('app.color.card_background'))
          }
        }, (task: Task) => task.id).onMove((from: number, to: number) => { this.sortDraft = ScheduleService.move(this.sortDraft, from, to); })
      }.layoutWeight(1).width('100%')
    }.width('100%').height('100%').enabled(!this.busy)
  }


  @Builder
  tabLabel(page: number) {
    Column({ space: 4 }) {
      if (page === 0) { Image($r('app.media.nav_today')).width(23).height(23).opacity(this.selectedTab === page ? 1 : 0.5) }
      else if (page === 1) { Image($r('app.media.nav_tasks')).width(23).height(23).opacity(this.selectedTab === page ? 1 : 0.5) }
      else if (page === 2) { Image($r('app.media.nav_calendar')).width(23).height(23).opacity(this.selectedTab === page ? 1 : 0.5) }
      else { Image($r('app.media.nav_settings')).width(23).height(23).opacity(this.selectedTab === page ? 1 : 0.5) }
      Text(this.tabTitle(page)).fontSize(11).fontWeight(this.selectedTab === page ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.selectedTab === page ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
    }.height(64).width('100%').justifyContent(FlexAlign.Center).accessibilityText(this.tabTitle(page))
  }

  @Builder
  rootPage(page: number) {
    Scroll() {
      Column({ space: 12 }) {
        if (page === 0) { this.homePage() }
        else if (page === 1) {
          this.filters()
          this.section(false, '待办', 1)
          this.section(true, '已完成', 1)
        } else if (page === 2) {
          MonthCalendar({ days: this.calendarDays(), selected: this.selectedDay, month: this.month,
            onSelect: (key: string) => { this.selectedDay = key; },
            onMonth: (delta: number) => this.shiftMonth(delta),
            onToday: () => { this.selectedDay = ScheduleService.key(Date.now()); this.month = this.selectedDay.slice(0, 7) + '-01'; } })
          Text(this.selectedDay + ' · 当日事项').fontSize(13).fontColor($r('app.color.text_secondary')).width('100%')
          this.section(false, '待办', 2)
          this.section(true, '已完成', 2)
        } else { this.settingsPage() }
      }.width('100%').padding({ left: 20, right: 20, top: 8, bottom: 24 })
    }.width('100%').height('100%').align(Alignment.Top).scrollBar(BarState.Off)
  }

  @Builder
  subpageFooter() {
    if (this.mode === 'batch') {
      Row({ space: 8 }) {
        Button('取消').height(48).fontSize(13).padding({ left: 12, right: 12 }).backgroundColor($r('app.color.card_background'))
          .fontColor($r('app.color.text_primary')).onClick(() => this.changeMode('list'))
        Button('设为待办').height(48).fontSize(13).layoutWeight(1).padding(4).backgroundColor($r('app.color.card_background'))
          .fontColor($r('app.color.text_primary')).enabled(this.batchKeys.length > 0).onClick(() => this.applyBatch(false))
        Button('设为完成').height(48).fontSize(13).layoutWeight(1).padding(4).backgroundColor($r('app.color.accent'))
          .fontColor($r('app.color.on_accent')).enabled(this.batchKeys.length > 0).onClick(() => this.applyBatch(true))
      }.width('100%').enabled(!this.busy).padding({ left: 20, right: 20, top: 8, bottom: 12 })
    } else if (this.mode === 'editor' || this.mode === 'sort') {
      Row({ space: 10 }) {
        Button('取消').layoutWeight(1).height(48).backgroundColor($r('app.color.card_background'))
          .fontColor($r('app.color.text_primary')).onClick(() => this.changeMode('list'))
        Button(this.busy ? '保存中…' : this.mode === 'sort' ? '保存顺序' : '保存任务').layoutWeight(1).height(48)
          .backgroundColor($r('app.color.accent')).fontColor($r('app.color.on_accent'))
          .onClick(() => { if (this.mode === 'sort') { this.saveSort(); } else { this.saveEditor(); } })
          .enabled(this.mode === 'sort' || this.draftTitle.trim().length > 0)
      }.width('100%').enabled(!this.busy).padding({ left: 20, right: 20, top: 8, bottom: 12 })
    }
  }

  build() {
    Column() {
      Row({ space: 12 }) {
        if (this.mode !== 'list') {
          Button('‹').width(44).height(44).padding(0).fontSize(30).backgroundColor(Color.Transparent)
            .fontColor($r('app.color.text_primary')).accessibilityText('返回')
            .enabled(!this.busy).onClick(() => this.changeMode('list'))
        }
        Column({ space: 5 }) {
          Text(this.pageTitle()).fontSize(this.mode === 'list' ? 30 : 23).fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
          if (this.mode === 'list') {
            Text(this.selectedTab === 0 ? this.dateTitle() : this.selectedTab === 1 ? '整理任务，安排下一步' :
              this.selectedTab === 2 ? '查看每一天的安排' : '外观与数据管理')
              .fontSize(12).fontColor($r('app.color.text_secondary'))
          }
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        if (this.mode === 'list' && this.selectedTab !== 3) {
          Button('＋').width(44).height(44).padding(0).fontSize(27).backgroundColor($r('app.color.accent'))
            .fontColor($r('app.color.on_accent')).accessibilityText('新建任务').enabled(this.ready && !this.busy)
            .onClick(() => this.openEditor())
        }
      }.width('100%').padding({ left: this.mode === 'list' ? 20 : 8, right: 20, top: 16, bottom: 14 })
      if (this.error.length > 0) {
        Text(this.error).fontSize(13).fontColor($r('app.color.danger')).width('100%').padding({ left: 20, right: 20, bottom: 8 })
      }
      if (this.notice.length > 0) {
        Text(this.notice).fontSize(12).fontColor($r('app.color.text_secondary')).width('100%').padding({ left: 20, right: 20, bottom: 8 })
      }
      if (this.undoTitle.length > 0) {
        Row({ space: 8 }) {
          Text('已删除：' + this.undoTitle).fontSize(12).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1).fontColor($r('app.color.text_primary'))
          Button('撤销').height(40).fontSize(13).padding(8).backgroundColor(Color.Transparent)
            .fontColor($r('app.color.text_primary')).enabled(!this.busy).onClick(() => this.undoDelete())
          Button('×').height(40).width(40).padding(0).backgroundColor(Color.Transparent)
            .fontColor($r('app.color.text_secondary')).accessibilityText('关闭撤销提示')
            .onClick(() => { this.undoTitle = ''; this.deletedBackup = undefined; })
        }.padding({ left: 16, right: 8 }).margin({ left: 20, right: 20, bottom: 8 })
          .borderRadius(12).backgroundColor($r('app.color.card_background'))
      }
      if (!this.ready) {
        Blank()
        Text(this.busy ? '正在读取任务…' : '暂时无法读取任务').fontColor($r('app.color.text_secondary'))
        if (!this.busy) { Button('重新读取').onClick(() => this.load()) }
        Blank()
      } else if (this.mode === 'list') {
        Tabs({ barPosition: BarPosition.End, index: this.selectedTab }) {
          TabContent() { this.rootPage(0) }.tabBar(this.tabLabel(0))
          TabContent() { this.rootPage(1) }.tabBar(this.tabLabel(1))
          TabContent() { this.rootPage(2) }.tabBar(this.tabLabel(2))
          TabContent() { this.rootPage(3) }.tabBar(this.tabLabel(3))
        }.layoutWeight(1).width('100%').barHeight(68).barMode(BarMode.Fixed).scrollable(false)
          .backgroundColor($r('app.color.page_background'))
          .onChange((index: number) => { this.selectedTab = index; this.now = Date.now(); this.error = ''; this.notice = ''; })
      } else {
        if (this.mode === 'sort') {
          Column() { this.sortingPage() }.layoutWeight(1).width('100%').padding({ left: 20, right: 20 })
        } else {
          Scroll(this.scroller) {
            Column({ space: 12 }) {
              if (this.mode === 'editor') { this.editor() }
              else if (this.mode === 'quick') { this.quickEditor() }
              else if (this.mode === 'tools') { this.toolsPage() }
              else if (this.mode === 'batch') { this.batchPage() }
            }.width('100%').padding({ left: 20, right: 20, top: 8, bottom: 24 })
          }.layoutWeight(1).width('100%').align(Alignment.Top)
        }
        this.subpageFooter()
      }
    }.width('100%').height('100%').backgroundColor($r('app.color.page_background'))
  }
}
