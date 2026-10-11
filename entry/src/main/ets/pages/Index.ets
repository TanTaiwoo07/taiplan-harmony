import { IconLabel } from '../components/IconLabel';
import { IcsUpdateService } from '../services/IcsUpdateService';
import { MotionService } from '../services/MotionService';
import { AiPlanService, PlanReview } from '../services/AiPlanService';
import { AiPlannerClient } from '../platform/AiPlannerClient';
import { AiSecretStore } from '../platform/AiSecretStore';
import { EditorOptionsService } from '../services/EditorOptionsService';
import { AutoPlanService, PlanReport, PlanSuggestion } from '../services/AutoPlanService';
import { ProductState } from '../model/Product';
import { ProductService } from '../services/ProductService';
import { ProductReminderService } from '../services/ProductReminderService';
import { ProductTools } from '../components/ProductTools';
import { ProductSettings } from '../components/ProductSettings';
import { AiConfigStore } from '../data/AiConfigStore';
import { ClassificationPanel } from '../components/ClassificationPanel';
import { ReminderService } from '../platform/ReminderService';
import { SmartEntry } from '../components/SmartEntry';
import { OccurrenceService } from '../services/OccurrenceService';
import { PlanningService } from '../services/PlanningService';
import { MaterialService } from '../services/MaterialService';
import { CalendarService } from '../services/CalendarService';
import { CalendarWorkspace } from '../components/CalendarWorkspace';
import { PreferencePanel } from '../components/PreferencePanel';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { AppPreferences, TaskPlanning, BackupDocument, CalendarDay, OccurrenceState, Task, TaskDraft, TaskItem, TimeConflict } from '../model/Task';
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
  @State private planEvaluation: string = '';
  @State private planAdvice: string[] = [];
  @State private planAdviceOpen: boolean = false;
  @State private planSource: string = '本地建议';
  @State private planCloudBusy: boolean = false;
  @State private planCloudError: string = '';
  private planner: AiPlannerClient = new AiPlannerClient();
  private planRequest: number = 0;
  private cancelPlanner(): void { this.planRequest++; this.planner.cancel(); this.planCloudBusy = false; }
  private animate(action: () => void): void { this.getUIContext().animateTo(MotionService.options(this.preferences.reduceMotion), action); }
  private setSearch(value: boolean): void { this.animate(() => { this.showSearch = value; this.searchPull = 0; if (!value) { this.query = ''; } }); }
  @State private calendarImport: boolean = false;
  @State private updateCalendarSource: boolean = false;
  @State private calendarEligible: string[] = [];
  private calendarImportSnapshot: string = '';
  @State private searchPull: number = 0;
  @State private productTab: string = '';
  private backModes: string[] = [];
  private pullStartTop: boolean = false;
  private navigateBack(): void {
    this.getUIContext().getFocusController().clearFocus();
    this.cancelPlanner(); this.animate(() => { this.mode = this.backModes.pop() ?? 'list'; }); this.error = ''; this.notice = '';
    this.scroller.scrollTo({ xOffset: 0, yOffset: 0 });
  }
  private openDetail(item: TaskItem): void { this.detail = item; this.changeMode('detail'); }
  @Builder
  detailPage() {
    if (this.detail) {
      Column({ space: 16 }) {
        Text(this.detail.task.title).fontSize(26).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).width('100%')
        Text(TaskService.dateLabel(this.detail.dueAt) + ' · ' + TaskService.timeLabel(this.detail.task)).fontSize(16).fontColor($r('app.color.text_secondary')).width('100%')
        Text(this.detail.task.planning?.kind === 'event' ? '日历事件' : this.detail.completed ? '已完成任务' : '待办任务').fontSize(14).fontColor($r('app.color.text_secondary')).width('100%')
        if (this.detail.task.planning?.location) { Text('地点 · ' + this.detail.task.planning.location).fontSize(15).fontColor($r('app.color.text_primary')).width('100%') }
        if (this.detail.task.planning?.deadlineAt) { Text('截止 · ' + TaskService.dateLabel(this.detail.task.planning.deadlineAt) + (this.detail.task.planning.deadlineMode === 'datetime' ? ' ' + TaskService.minuteLabel(new Date(this.detail.task.planning.deadlineAt).getHours() * 60 + new Date(this.detail.task.planning.deadlineAt).getMinutes()) : '')).fontSize(15).fontColor($r('app.color.text_primary')).width('100%') }
        if (this.detail.task.repeat !== 'none') { Text(EditorOptionsService.repeat(this.detail.task)).fontSize(14).fontColor($r('app.color.text_secondary')).width('100%') }
        if (this.detail.task.note) { Text(this.detail.task.note).fontSize(15).fontColor($r('app.color.text_primary')).width('100%') }
        ForEach(this.detail.task.steps ?? [], (step: string, index: number) => { Text(((this.detail?.doneSteps ?? []).includes(index) ? '✓ ' : '○ ') + step).fontSize(15).fontColor($r('app.color.text_primary')).width('100%') })
        Text(this.reminders.label(this.detail)).fontSize(13).fontColor($r('app.color.text_secondary')).width('100%')
        Button({ type: ButtonType.Capsule }) { IconLabel('编辑这项安排', $r('app.media.glyph_edit_on_accent'), $r('app.color.on_accent')) }.height(52).width('100%').backgroundColor($r('app.color.accent')).fontColor($r('app.color.on_accent')).onClick(() => { if (this.detail) { this.openOccurrence(this.detail); } })
        if (this.detail.task.planning?.kind !== 'event') { Button(this.detail.completed ? '标为待办' : '标为完成').height(48).width('100%').backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).onClick(async () => { if (this.detail) { await this.toggle(this.detail); const next = ScheduleService.item(this.tasks.find((task: Task) => task.id === this.detail?.task.id) ?? this.detail.task, this.detail.dateKey, this.states); if (next) { this.detail = next; } } }) }
      }.width('100%').padding(20).borderRadius(20).backgroundColor($r('app.color.card_background'))
    }
  }
  private openProduct(tab: string): void { this.productTab = tab; this.changeMode('product'); }
  @Builder
  toolEntry(title: string, subtitle: string, icon: Resource, action: () => void) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 14 }) {
        Image(icon).width(28).height(28).margin(10).borderRadius(14).backgroundColor($r('app.color.accent_soft'))
        Column({ space: 4 }) { Text(title).fontSize(17).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).width('100%')
          Text(subtitle).fontSize(12).fontColor($r('app.color.text_secondary')).width('100%') }.layoutWeight(1)
        Image($r('app.media.glyph_next')).width(20).height(20).opacity(0.55).accessibilityLevel('no')
      }.padding(16).width('100%')
    }.width('100%').borderRadius(20).backgroundColor($r('app.color.card_background')).onClick(action)
      .transition(MotionService.entrance(this.preferences.reduceMotion))
  }
  @Builder
  workbenchPage() {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 14 }) {
        Row({ space: 14 }) { Image($r('app.media.glyph_schedule')).width(34).height(34)
          Text('智能安排').fontSize(25).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')) }.width('100%')
        Text('让每件事，找到合适的时间').fontSize(16).fontColor($r('app.color.text_primary')).width('100%')
        Text('本地建议与 AI 优化，都先预览再确认').fontSize(13).fontColor($r('app.color.text_secondary')).width('100%')
        Text('查看安排建议  →').fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.support_accent')).width('100%')
      }.padding(24).width('100%')
    }.width('100%').borderRadius(24).linearGradient({ angle: 135, colors: [[$r('app.color.hero_start'), 0], [$r('app.color.hero_end'), 1]] }).onClick(() => this.proposePlan())
    if (this.product.features.ai) { this.toolEntry('一句话创建', '文字、语音或 AI · 核对后保存', $r('app.media.icon_wand'), () => this.changeMode('quick')) }
    Text('我的工具').fontSize(19).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).width('100%').margin({ top: 12 })
    if (this.product.features.focus) { this.toolEntry('专注', '给一件事留段不被打扰的时间', $r('app.media.icon_focus'), () => { this.productTab = 'focus'; this.changeMode('product'); }) }
    if (this.product.features.habits) { this.toolEntry('习惯', '从小行动，积累日常坚持', $r('app.media.icon_habit'), () => { this.productTab = 'habits'; this.changeMode('product'); }) }
    if (this.product.features.countdowns) { this.toolEntry('倒数日', '记住重要日子与纪念日', $r('app.media.icon_countdown'), () => { this.productTab = 'countdowns'; this.changeMode('product'); }) }
    this.toolEntry('清单与标签', '整理学习、生活与其他事项', $r('app.media.glyph_list_manage'), () => this.changeMode('classification'))
  }
  @State private product: ProductState = ProductService.defaults();
  private productSaving: boolean = false;
  private async renameClassification(kind: string, from: string, to: string): Promise<void> {
    if (this.busy) { throw new Error('正在保存，请稍后再试'); } this.busy = true;
    try { await this.repository.renameClassification(kind, from, to); await this.refreshData(); this.listFilter = ''; }
    finally { this.busy = false; }
  }
  private async saveProduct(value: ProductState): Promise<void> {
    if (this.productSaving || this.busy) { throw new Error('正在保存，请稍后再试'); }
    this.productSaving = true;
    try { await this.repository.saveProduct(value); this.product = value; this.reminderStatus = await this.reminders.sync(this.context(), this.tasks, this.states, ProductReminderService.intents(value, Date.now())); }
    finally { this.productSaving = false; }
  }
  @StorageLink('taiplanReminderTarget') @Watch('followReminder') private reminderTarget: string = '';
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
  @State private view: string = 'inbox';
  @State private preferences: AppPreferences = PlanningService.defaults();
  @State private calendarView: string = 'month';
  @State private showCapture: boolean = false;
  @State private capturedId: string = '';
  @State private showTaskDone: boolean = false;
  @State private listFilter: string = '';
  @State private draftKind: string = 'task';
  @State private draftLocation: string = '';
  @State private draftList: string = '';
  @State private draftDeadline: number = 0;
  @State private draftDeadlineMode: string = 'none';
  @State private draftInterval: string = '1';
  @State private draftWeekdays: number[] = [];
  @State private draftUntil: string = '';
  @State private draftCount: string = '';
  @State private advanced: boolean = false;
  @State private locationOpen: boolean = false;
  @State private notesOpen: boolean = false;
  @State private customLead: boolean = false;
  @State private leadDays: string = '0';
  @State private leadHours: string = '0';
  @State private leadMinutes: string = '0';
  @State private repeatOpen: boolean = false;
  @State private showSearch: boolean = false;
  @State private detail: TaskItem | undefined = undefined;
  private rootOffsets: number[] = [0, 0, 0, 0];
  @State private editingId: string = '';
  @State private occurrenceDate: string = '';
  @State private editScope: string = 'all';
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
  private reminders: ReminderService = new ReminderService();
  @State private reminderStatus: string = '系统提醒未启用';
  @State private draftReminder: string = 'none';
  @State private draftLead: number = 10;
  private repository: TaskRepository = new TaskRepository();
  private scroller: Scroller = new Scroller();
  private clockId: number = -1;
  private calendarUndo: Task | undefined = undefined;
  private calendarUndoRevision: number = 0;
  @State private calendarUndoLabel: string = '';
  @State private planReport: PlanReport = { suggestions: [], unscheduled: [] };
  private planSnapshot: string = '';
  private planUndo: Task[] = [];
  @State private hasPlanUndo: boolean = false;
  private editorInitial: string = '';
  private overviewTasks: Task[] | undefined = undefined;
  private overviewStates: OccurrenceState[] | undefined = undefined;
  private overviewNow: number = -1;
  private overviewCache: DayOverview | undefined = undefined;

  aboutToAppear(): void {
    this.load();
    this.clockId = setInterval(() => { this.now = Date.now(); }, 60000);
  }
  aboutToDisappear(): void { this.cancelPlanner(); if (this.clockId !== -1) { clearInterval(this.clockId); } }
  onPageShow(): void { this.now = Date.now(); }
  private context(): common.UIAbilityContext { return this.getUIContext().getHostContext() as common.UIAbilityContext; }

  private editorPlanning(): TaskPlanning {
    const plan = PlanningService.create(this.draftDueAt, this.draftStart, Number(this.draftDuration), this.draftKind);
    const old = this.tasks.find((task: Task) => task.id === this.editingId);
    plan.legacyTimeSemantics = old?.planning?.legacyTimeSemantics ?? false;
    plan.sourceType = old?.planning?.sourceType ?? 'manual';
    plan.reminder = { mode: this.draftReminder, leadMinutes: this.draftLead, at: 0 };
    plan.location = this.draftLocation.trim(); plan.listName = this.draftList.trim();
    plan.deadlineMode = this.draftDeadlineMode; plan.deadlineAt = this.draftDeadline;
    plan.rule = this.draftRepeat === 'none' ? PlanningService.emptyRule() : {
      interval: Number(this.draftInterval), weekdays: this.draftWeekdays.slice(), untilDate: this.draftUntil.trim(), count: Number(this.draftCount || '0') };
    return plan;
  }
  private editorFingerprint(): string {
    return JSON.stringify([this.draftTitle, this.draftNote, this.draftPriority.toString(), this.draftTags,
      this.draftDueAt.toString(), this.draftStart.toString(), this.draftDuration, this.draftKind, this.draftLocation,
      this.draftList, this.draftReminder, this.draftLead.toString(), this.draftDeadline.toString(), this.draftDeadlineMode, this.draftRepeat, this.draftInterval,
      this.draftWeekdays.join(','), this.draftUntil, this.draftCount, this.draftSteps]);
  }
  private closeSubpage(): void {
    if (this.busy) { return; }
    if (this.mode === 'editor' && this.editorFingerprint() !== this.editorInitial) {
      this.getUIContext().showAlertDialog({ systemMaterial: MaterialService.surface(this.preferences.useMaterial), title: '保留正在编辑的内容？', message: '这些修改还未保存。',
        primaryButton: { value: '继续编辑', action: () => {} },
        secondaryButton: { value: '放弃修改', action: () => this.navigateBack() } });
    } else { this.navigateBack(); }
  }
  private pickDeadline(): void {
    const selected = new Date(this.draftDeadline || Date.now());
    this.getUIContext().showDatePickerDialog({ systemMaterial: MaterialService.surface(this.preferences.useMaterial), start: new Date(2000, 0, 1), end: new Date(2100, 11, 31), selected: selected,
      onAccept: (value: DatePickerResult) => {
        this.draftDeadline = TaskService.endOfDay(value.year ?? selected.getFullYear(), value.month ?? selected.getMonth(), value.day ?? selected.getDate());
        this.draftDeadlineMode = 'date';
      } });
  }
  private pickDeadlineTime(): void {
    this.getUIContext().showTimePickerDialog({ systemMaterial: MaterialService.surface(this.preferences.useMaterial), selected: new Date(this.draftDeadline), useMilitaryTime: true,
      onAccept: (value: TimePickerResult) => { const date = new Date(this.draftDeadline); date.setHours(value.hour, value.minute, 0, 0);
        this.draftDeadline = date.getTime(); this.draftDeadlineMode = 'datetime'; } });
  }
  private async capture(): Promise<void> {
    if (this.busy) { return; }
    this.busy = true; this.error = '';
    try {
      const task = TaskService.create({ title: this.quickText, note: '', priority: 1, tagsText: '', dueAt: 0,
        planning: PlanningService.create(0, -1, 30) }, util.generateRandomUUID(), Date.now());
      await this.repository.save(task); await this.refreshData();
      this.capturedId = task.id; this.quickText = ''; this.showCapture = false;
      this.notice = '已记到收集箱';
    } catch (error) { this.error = (error as Error).message; }
    finally { this.busy = false; }
  }
  private arrangeCaptured(): void {
    const task = this.tasks.find((item: Task) => item.id === this.capturedId);
    if (!task) { this.capturedId = ''; return; }
    this.openEditor(task); this.draftDueAt = ScheduleService.end(ScheduleService.key(Date.now())); this.capturedId = '';
  }
  private async savePreferences(value: AppPreferences): Promise<void> {
    if (this.busy) { return; }
    this.busy = true;
    try { await this.repository.setPreferences(value); this.preferences = value; this.showTaskDone = value.showCompleted; }
    catch (error) { this.error = '偏好保存失败：' + (error as Error).message; }
    finally { this.busy = false; }
  }
  private listNames(): string[] {
    return Array.from(new Set<string>(this.tasks.map((task: Task) => task.planning?.listName ?? '').filter((name: string) => name.length > 0))).sort();
  }
  @Builder
  captureSheet() {
    Column({ space: 16 }) {
      Text('记一件事').fontSize(22).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).width('100%')
      Text('先记下来，稍后再安排时间。').fontSize(13).fontColor($r('app.color.text_secondary')).width('100%')
      Row({ space: 8 }) {
      TextInput({ text: this.quickText, placeholder: '突然想到什么？' }).height(52).maxLength(100).layoutWeight(1)
        .backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary'))
        .enterKeyType(EnterKeyType.Done).onSubmit(() => this.capture())
        .onChange((value: string) => { this.quickText = value; })
      Button(this.busy ? '保存中' : '收集').width(76).height(52).fontSize(14).backgroundColor($r('app.color.accent'))
        .accessibilityText('记到收集箱')
        .fontColor($r('app.color.on_accent')).enabled(!this.busy && this.quickText.trim().length > 0).onClick(() => this.capture())
      }.width('100%')
      if (this.error) { Text(this.error).fontSize(12).fontColor($r('app.color.danger')).width('100%') }
      Row({ space: 8 }) {
        Button({ type: ButtonType.Capsule }) { IconLabel('更多设置', $r('app.media.glyph_preferences'), $r('app.color.text_primary')) }.height(48).layoutWeight(1).fontSize(13).backgroundColor(Color.Transparent).fontColor($r('app.color.text_primary'))
          .onClick(() => { this.showCapture = false; this.openEditor(); this.draftTitle = this.quickText; })
        if (this.product.features.ai) {
        Button({ type: ButtonType.Capsule }) { IconLabel('一句话识别', $r('app.media.glyph_smart_input'), $r('app.color.text_primary')) }.height(48).layoutWeight(1).fontSize(13).backgroundColor(Color.Transparent).fontColor($r('app.color.text_primary'))
          .onClick(() => { this.showCapture = false; this.changeMode('quick'); })
        }
      }
    }.padding(24).width('100%').enabled(!this.busy)
  }
  @Builder
  preferenceSettings() {
    PreferencePanel({ settings: this.preferences, onChange: (value: AppPreferences) => this.savePreferences(value) })
  }
  @Builder
  listChips() {
    if (this.listNames().length > 0) {
      Scroll() {
        Row({ space: 8 }) {
          ForEach([''].concat(this.listNames()), (name: string) => {
            Button(name || '全部清单').height(44).fontSize(12)
              .backgroundColor(this.listFilter === name ? $r('app.color.accent') : $r('app.color.card_background'))
              .fontColor(this.listFilter === name ? $r('app.color.on_accent') : $r('app.color.text_primary')).onClick(() => { this.listFilter = name; })
          })
        }
      }.scrollable(ScrollDirection.Horizontal).width('100%').scrollBar(BarState.Off)
    }
  }
  @Builder
  searchPage() {
    Search({ value: this.query, placeholder: '标题、备注、标签、地点或清单' }).searchIcon({ src: $r('app.media.glyph_search'), size: 20 }).cancelButton({ style: CancelButtonStyle.INPUT, icon: { src: $r('app.media.glyph_close'), size: 18 } }).height(48)
      .backgroundColor($r('app.color.card_background')).fontColor($r('app.color.text_primary')).onChange((value: string) => { this.query = value; })
    Text(this.query.trim() ? '找到 ' + CalendarService.search(this.tasks, this.query).length.toString() + ' 项（重复系列显示一次）' : '搜索包括已完成和未安排的事项')
      .fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
    ForEach(CalendarService.search(this.tasks, this.query), (task: Task) => {
      Button({ type: ButtonType.Normal }) {
        Column({ space: 6 }) {
          Text(task.title).fontSize(16).fontColor($r('app.color.text_primary')).width('100%')
          Text((task.completed ? '已完成 · ' : '') + TaskService.dateLabel(task.dueAt) + ' · ' + (task.planning?.listName || '未分清单'))
            .fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
        }.padding(16).width('100%')
      }.width('100%').borderRadius(16).backgroundColor($r('app.color.card_background')).onClick(() => this.openEditor(task))
    }, (task: Task) => JSON.stringify(task))
  }

  private async load(): Promise<void> {
    this.busy = true; this.error = '';
    try {
      this.tasks = await this.repository.load(this.context());
      this.states = await this.repository.getOccurrences();
      this.product = await this.repository.getProduct();
      this.theme = await this.repository.getTheme();
      this.sortMode = await this.repository.getSortMode();
      this.preferences = await this.repository.getPreferences();
      this.selectedTab = this.preferences.startPage; this.calendarView = this.preferences.calendarView;
      this.showTaskDone = this.preferences.showCompleted;
      this.ready = true;
      this.followReminder();
      this.reminderStatus = await this.reminders.sync(this.context(), this.tasks, this.states, ProductReminderService.intents(this.product, Date.now()));
    } catch { this.error = '读取或迁移失败，请重试。已有数据仍保留。'; }
    finally { this.busy = false; }
  }
  private async refreshData(): Promise<void> {
    this.tasks = await this.repository.reload();
    this.states = await this.repository.getOccurrences();
    this.reminderStatus = await this.reminders.sync(this.context(), this.tasks, this.states, ProductReminderService.intents(this.product, Date.now()));
    if (this.tagFilter.length > 0 && !TaskService.allTags(this.tasks).includes(this.tagFilter)) { this.tagFilter = ''; }
  }
  private followReminder(): void {
    if (!this.ready || !this.reminderTarget) { return; }
    try {
      const target = JSON.parse(this.reminderTarget) as string[]; this.reminderTarget = '';
      if (target[0]?.startsWith('tool:')) {
        this.selectedTab = 3; this.changeMode('list'); this.notice = '工具提醒：请从「功能与工具」打开；隐藏的工具可重新启用。'; return;
      }
      const task = this.tasks.find((entry: Task) => entry.id === target[0]);
      if (!task) { this.notice = '提醒对应的事项已删除'; return; }
      if (task.repeat !== 'none' && ScheduleService.validKey(target[1])) {
        if (!ScheduleService.occursOn(task, target[1])) { this.notice = '此提醒的原始发生项已失效'; return; }
        const item = ScheduleService.item(task, target[1], this.states);
        if (!item) { this.notice = '这一次事项已跳过'; return; }
        this.selectedDay = ScheduleService.key(item.dueAt); this.selectedTab = 2; this.calendarView = 'day'; this.changeMode('list');
        this.notice = '提醒事项：' + item.task.title;
      } else { this.openEditor(task); }
    } catch { this.reminderTarget = ''; this.notice = '无法定位此提醒，请在搜索中查找'; }
  }
  private changeMode(mode: string): void {
    if (mode === 'list') { this.backModes = []; }
    else if (mode !== this.mode) { this.backModes.push(this.mode); }
    this.getUIContext().getFocusController().clearFocus();
    if (this.mode !== mode) { this.cancelPlanner(); } this.animate(() => { this.mode = mode; }); this.error = ''; this.notice = '';
    this.scroller.scrollTo({ xOffset: 0, yOffset: 0 });
  }
  private changeView(view: string): void {
    this.view = view; this.now = Date.now(); this.notice = '';
    this.scroller.scrollTo({ xOffset: 0, yOffset: 0 });
  }
  private openEditor(task?: Task): void {
    this.occurrenceDate = ''; this.editScope = 'all';
    this.editingId = task ? task.id : '';
    this.draftTitle = task ? task.title : '';
    this.draftNote = task ? task.note : '';
    this.draftPriority = task ? task.priority : 1;
    this.draftTags = task ? task.tags.join('，') : '';
    this.draftDueAt = task ? task.dueAt : 0;
    this.draftRepeat = task ? task.repeat : 'none';
    this.draftStart = task?.startMinute ?? -1;
    this.draftDuration = (task?.durationMinutes ?? 30).toString();
    this.draftSteps = (task?.steps ?? []).join('\n');
    const plan = task ? PlanningService.forTask(task) : PlanningService.create(0, -1, 30);
    this.draftReminder = plan.reminder?.mode ?? 'none'; this.draftLead = plan.reminder?.leadMinutes ?? 10;
    this.draftKind = plan.kind; this.draftLocation = plan.location; this.draftList = plan.listName;
    this.draftDeadline = plan.deadlineAt; this.draftDeadlineMode = plan.deadlineMode;
    this.draftInterval = plan.rule.interval.toString(); this.draftWeekdays = plan.rule.weekdays.slice();
    this.draftUntil = plan.rule.untilDate; this.draftCount = plan.rule.count > 0 ? plan.rule.count.toString() : '';
    this.advanced = false; this.repeatOpen = false; this.customLead = false;
    this.locationOpen = this.draftLocation.length > 0; this.notesOpen = this.draftNote.length > 0 || this.draftSteps.length > 0;
    this.editorInitial = this.editorFingerprint();
    this.changeMode('editor');
  }
  private adjustCalendar(item: TaskItem, days: number, minutes: number, resize: boolean): void {
    if (this.busy || (days === 0 && minutes === 0)) { return; }
    const original = this.tasks.find((task: Task) => task.id === item.task.id); if (!original) { return; }
    const draft = OccurrenceService.draft(item.task); draft.dueAt = item.dueAt;
    const date = ScheduleService.date(ScheduleService.key(item.dueAt));
    if (resize) { draft.durationMinutes = Math.max(5, Math.min(1440, (draft.durationMinutes ?? 30) + minutes)); }
    else { date.setDate(date.getDate() + days); date.setHours(0, (draft.startMinute ?? 0) + minutes, 0, 0);
      draft.dueAt = ScheduleService.end(ScheduleService.key(date.getTime())); draft.startMinute = date.getHours() * 60 + date.getMinutes(); }
    const plan = PlanningService.create(draft.dueAt, draft.startMinute ?? 0, draft.durationMinutes ?? 30, draft.planning?.kind ?? 'task');
    if (draft.planning) { plan.location = draft.planning.location; plan.listName = draft.planning.listName; plan.deadlineMode = draft.planning.deadlineMode; plan.deadlineAt = draft.planning.deadlineAt; plan.reminder = draft.planning.reminder; }
    draft.planning = plan; draft.repeat = 'none';
    try {
      const next = original.repeat === 'none' ? TaskService.edit(original, draft, Date.now()) : OccurrenceService.change(original, item.dateKey, draft, Date.now());
      const collision = ScheduleService.conflicts(TaskService.create(draft, original.id, Date.now()), this.tasks, this.states, Date.now());
        if (original.repeat !== 'none') {
          this.getUIContext().showAlertDialog({ systemMaterial: MaterialService.surface(this.preferences.useMaterial), title: '调整重复日程', message: draft.title + '\n目标：' + TaskService.dateLabel(draft.dueAt) + ' ' + TaskService.timeLabel(TaskService.create(draft, 'preview', 0)) + '\n仅这一次：其他日期不变，可直接撤销。\n这次及以后：在编辑器核对新系列，历史记录保留。\n整个系列：在编辑器核对整体规则，已有单次例外保留。' + (collision.length ? '\n注意：与其他安排重叠。' : ''),
            buttons: [
              { value: '取消', action: () => {} },
              { value: '仅这一次', action: () => this.saveCalendarAdjustment(original, next) },
              { value: '这次及以后', action: () => this.reviewCalendarSeries(original, item, draft, 'future', days, minutes, resize) },
              { value: '整个系列', action: () => this.reviewCalendarSeries(original, item, draft, 'all', days, minutes, resize) }
            ] }); return;
        }
      this.getUIContext().showAlertDialog({ systemMaterial: MaterialService.surface(this.preferences.useMaterial), title: resize ? '调整时长？' : '调整安排？',
        message: draft.title + '\n' + TaskService.dateLabel(draft.dueAt) + ' ' + TaskService.timeLabel(TaskService.create(draft, 'preview', 0)) +
          (original.repeat !== 'none' ? '\n只修改这一次。' : '') + (collision.length ? '\n注意：与其他安排重叠。' : ''),
        primaryButton: { value: '取消', action: () => {} }, secondaryButton: { value: '确认', action: () => this.saveCalendarAdjustment(original, next) } });
    } catch (error) { this.error = (error as Error).message; }
  }
  private reviewCalendarSeries(original: Task, item: TaskItem, draft: TaskDraft, scope: string, days: number, minutes: number, resize: boolean): void {
    this.openEditor(original); this.editScope = scope;
    if (scope === 'future') { this.occurrenceDate = item.dateKey; this.draftDueAt = draft.dueAt; }
    else if (!resize) {
      const date = ScheduleService.date(ScheduleService.key(original.dueAt)); date.setDate(date.getDate() + days);
      date.setHours(0, (original.startMinute ?? 0) + minutes, 0, 0); this.draftDueAt = ScheduleService.end(ScheduleService.key(date.getTime())); this.draftStart = date.getHours() * 60 + date.getMinutes();
    }
    if (scope === 'future') { this.draftStart = draft.startMinute ?? -1; } this.draftDuration = (draft.durationMinutes ?? 30).toString();
    this.notice = scope === 'future' ? '请核对新系列的日期、次数和提醒后保存；未来已有进度或例外时会停止保存。' : '整体移动后请核对重复规则和结束日期；已有单次例外保留，尚未保存。';
    this.editorInitial = this.editorFingerprint();
  }
  private async saveCalendarAdjustment(original: Task, next: Task): Promise<void> {
    if (this.busy) { return; } this.busy = true;
    try { const live = (await this.repository.reload()).find((task: Task) => task.id === original.id);
      if (!live || live.updatedAt !== original.updatedAt) { throw new Error('任务已变化，请重新调整'); }
      await this.repository.save(next); this.calendarUndo = original; this.calendarUndoRevision = next.updatedAt;
      this.calendarUndoLabel = original.title; await this.refreshData();
    } catch (error) { this.error = (error as Error).message; } finally { this.busy = false; }
  }
  private async undoCalendarAdjustment(): Promise<void> {
    if (this.busy || !this.calendarUndo) { return; } this.busy = true;
    try { const live = (await this.repository.reload()).find((task: Task) => task.id === this.calendarUndo?.id);
      if (!live || live.updatedAt !== this.calendarUndoRevision) { throw new Error('任务已有后续修改，不能覆盖撤销'); }
      await this.repository.save(this.calendarUndo); this.calendarUndo = undefined; this.calendarUndoLabel = ''; await this.refreshData();
    } catch (error) { this.error = (error as Error).message; } finally { this.busy = false; }
  }
  private openOccurrence(item: TaskItem): void {
    if (item.task.repeat === 'none') { this.openEditor(item.task); return; }
    const original = this.tasks.find((task: Task) => task.id === item.task.id);
    if (!original) { return; }
    this.getUIContext().showAlertDialog({ systemMaterial: MaterialService.surface(this.preferences.useMaterial), title: '修改重复日程', message: item.task.title + '\n原始日期：' + item.dateKey + '\n仅这一次：其他日期不变。\n这次及以后：以前保留，当前和后续一起修改。\n整个系列：修改整体规则，完成历史和已有单次例外保留。',
      buttons: [
        { value: '仅这一次', action: () => { this.openEditor(item.task); this.occurrenceDate = item.dateKey; this.editScope = 'one';
          this.draftDueAt = item.dueAt; this.draftRepeat = 'none'; this.draftCount = ''; this.draftUntil = ''; this.draftWeekdays = []; this.draftInterval = '1';
          this.notice = '只影响原始日期 ' + item.dateKey + '，完成记录保持关联。'; this.editorInitial = this.editorFingerprint(); } },
        { value: '这次及以后', action: () => { this.openEditor(original); this.occurrenceDate = item.dateKey; this.editScope = 'future';
          this.draftDueAt = item.dueAt; this.notice = '拆分新系列；如果未来已有进度或单次调整，将停止保存以保护记录。'; this.editorInitial = this.editorFingerprint(); } },
        { value: '整个系列', action: () => { this.openEditor(original); this.notice = '已有单次例外保留独立内容。'; } }
      ] });
  }
  private proposePlan(): void {
    this.cancelPlanner(); this.hasPlanUndo = false; this.planUndo = []; this.planCloudError = ''; this.planAdviceOpen = false;
    try {
    const now = Date.now();
    this.planReport = AutoPlanService.suggest(this.tasks, this.states, now, this.product.workStart ?? 9, this.product.workEnd ?? 21, this.preferences.snapMinutes);
    const review = AiPlanService.local(AiPlanService.input(this.tasks, this.states, now, this.product.workStart ?? 9, this.product.workEnd ?? 21, this.preferences.snapMinutes), this.planReport);
    this.planEvaluation = review.evaluation; this.planAdvice = review.advice; this.planSource = '本地建议';
    this.planSnapshot = JSON.stringify([this.tasks, this.states]); if (this.mode !== 'plan') { this.changeMode('plan'); }
    } catch (error) { this.error = (error as Error).message; }
  }
  private confirmAiPlan(): void {
    if (this.planCloudBusy || this.busy) { return; }
    try {
      const input = AiPlanService.input(this.tasks, this.states, Date.now(), this.product.workStart ?? 9, this.product.workEnd ?? 21, this.preferences.snapMinutes);
      if (!input.candidates.length) { this.planCloudError = '收集箱没有待安排事项，现有日程不会被 AI 移动。'; return; }
      this.getUIContext().showAlertDialog({ systemMaterial: MaterialService.surface(this.preferences.useMaterial), title: '发送给 AI 优化？', message: '将发送本次最多20个收集箱任务的标题、优先级、预计时长和截止，以及未来7天的忙碌时间段。不会发送备注、地点、子任务、已完成记录或固定日程标题。\nAI返回评价和建议，只有你确认采用才会保存。',
        primaryButton: { value: '取消', action: () => {} }, secondaryButton: { value: '发送并预览', action: () => this.generateAiPlan() } });
    } catch (error) { this.planCloudError = (error as Error).message; }
  }
  private async generateAiPlan(): Promise<void> {
    this.cancelPlanner(); const request = this.planRequest; this.planCloudBusy = true; this.planCloudError = '';
    try {
      const now = Date.now(); const input = AiPlanService.input(this.tasks, this.states, now, this.product.workStart ?? 9, this.product.workEnd ?? 21, this.preferences.snapMinutes);
      const snapshot = JSON.stringify([this.tasks, this.states]); const config = await AiConfigStore.load(this.context());
      if (request !== this.planRequest || this.mode !== 'plan') { return; }
      const key = await AiSecretStore.read(); if (!key) { throw new Error('请先到 AI 服务设置保存密钥；本地建议仍可使用。'); }
      if (request !== this.planRequest || this.mode !== 'plan') { return; }
      const result = await this.planner.generate(config.endpoint, config.model, key, input, this.tasks, this.states);
      if (request !== this.planRequest || this.mode !== 'plan') { return; }
      const current = await this.repository.reload(); const states = await this.repository.getOccurrences();
      if (snapshot !== JSON.stringify([current, states])) { throw new Error('生成期间数据已变化，请重新规划；没有保存。'); }
      this.animate(() => { this.planReport = result.report; this.planEvaluation = result.evaluation; this.planAdvice = result.advice; this.planAdviceOpen = false; this.planSource = 'AI 优化建议'; });
      this.planSnapshot = snapshot; this.hasPlanUndo = false;
    } catch (error) { if (request === this.planRequest) { this.planCloudError = (error as Error).message; } }
    finally { if (request === this.planRequest) { this.planCloudBusy = false; } }
  }
  private async applyPlan(undo: boolean, id: string = ''): Promise<void> {
    if (this.busy || this.planCloudBusy) { return; } this.busy = true;
    try {
      const current = await this.repository.reload(), states = await this.repository.getOccurrences();
      if (JSON.stringify([current, states]) !== this.planSnapshot) { throw new Error('数据已变化，请重新生成建议'); }
      const chosen = this.planReport.suggestions.filter((item: PlanSuggestion) => !id || item.before.id === id);
      if (!undo && chosen.some((item: PlanSuggestion) => (item.after.planning?.startAt ?? 0) <= Date.now())) { throw new Error('建议时间已经过去，请重新生成；没有保存'); }
      const replacement = undo ? this.planUndo : chosen.map(item => item.after);
      await this.repository.saveBatch(replacement);
      this.planUndo = undo ? [] : chosen.map(item => item.before); this.hasPlanUndo = !undo;
      await this.refreshData(); this.planSnapshot = JSON.stringify([this.tasks, this.states]);
      this.planReport = { suggestions: undo ? [] : this.planReport.suggestions.filter((item: PlanSuggestion) => !chosen.some((selected: PlanSuggestion) => selected.before.id === item.before.id)), unscheduled: this.planReport.unscheduled };
      this.notice = undo ? '已撤销本次排程' : '已采用，原有日历事件未移动';
    } catch (error) { this.error = (error as Error).message; } finally { this.busy = false; }
  }
  @Builder
  planPage() {
    Column({ space: 10 }) {
      Text(this.planSource).fontSize(22).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).width('100%')
      Text(this.planEvaluation).fontSize(15).fontColor($r('app.color.text_primary')).width('100%')
      ForEach(this.planAdviceOpen ? this.planAdvice : this.planAdvice.slice(0, 2), (text: string) => { Text('· ' + text).fontSize(13).lineHeight(20).fontColor($r('app.color.text_secondary')).width('100%').transition(MotionService.entrance(this.preferences.reduceMotion)) })
      if (this.planAdvice.length > 2) { Button(this.planAdviceOpen ? '收起建议' : '展开其余 ' + (this.planAdvice.length - 2).toString() + ' 条建议').height(44).fontSize(13).backgroundColor(Color.Transparent).fontColor($r('app.color.support_accent')).onClick(() => this.animate(() => { this.planAdviceOpen = !this.planAdviceOpen; })) }
    }.padding(20).width('100%').borderRadius(22).linearGradient({ angle: 135, colors: [[$r('app.color.hero_start'), 0], [$r('app.color.hero_end'), 1]] })
    Text('未来7天 · ' + (this.product.workStart ?? 9).toString() + ':00–' + (this.product.workEnd ?? 21).toString() + ':00 · ' + this.preferences.snapMinutes.toString() + '分钟网格。下方安排尚未保存，固定日程保持不变。').fontSize(13).fontColor($r('app.color.text_secondary'))
    if (this.product.features.ai) {
      if (this.planCloudBusy) {
        Row({ space: 12 }) { LoadingProgress().width(26).height(26).color($r('app.color.support_accent')); Text('AI 正在优化，原有安排未改变').fontSize(14).fontColor($r('app.color.text_secondary')).layoutWeight(1) }
        Button({ type: ButtonType.Capsule }) { IconLabel('取消 AI 优化', $r('app.media.glyph_close'), $r('app.color.text_primary')) }.height(48).onClick(() => this.cancelPlanner())
      } else { Button({ type: ButtonType.Capsule }) { IconLabel('让 AI 优化并给出建议', $r('app.media.glyph_ai_service'), $r('app.color.text_primary')) }.height(52).width('100%').backgroundColor($r('app.color.accent_soft')).fontColor($r('app.color.support_accent')).onClick(() => this.confirmAiPlan()) }
      if (this.planCloudError) { Text(this.planCloudError).fontSize(13).fontColor($r('app.color.danger')); Button({ type: ButtonType.Capsule }) { IconLabel('AI 服务设置', $r('app.media.glyph_ai_service'), $r('app.color.text_primary')) }.height(48).onClick(() => this.changeMode('aiConfig')) }
    }
    ForEach(this.planReport.suggestions, (item: PlanSuggestion) => {
      Column({ space: 8 }) {
        Text(item.after.title).fontSize(17).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).width('100%')
        Text('原来 · 收集箱，尚未安排').fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
        Text('建议 · ' + TaskService.dateLabel(item.after.dueAt) + ' ' + TaskService.timeLabel(item.after)).fontSize(15).fontColor($r('app.color.support_accent')).width('100%')
        Text(item.reason).fontSize(13).fontColor($r('app.color.text_secondary')).width('100%')
        Button({ type: ButtonType.Capsule }) { IconLabel('只采用这一项', $r('app.media.glyph_check'), $r('app.color.text_primary')) }.height(48).width('100%').backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).enabled(!this.busy && !this.planCloudBusy).onClick(() => this.applyPlan(false, item.before.id))
      }.padding(18).width('100%').borderRadius(20).backgroundColor($r('app.color.card_background')).transition(MotionService.entrance(this.preferences.reduceMotion))
    })
    ForEach(this.planReport.unscheduled, (reason: string) => { Text(reason).fontSize(13).fontColor($r('app.color.text_secondary')) })
    Button({ type: ButtonType.Capsule }) { IconLabel('重新生成本地建议', $r('app.media.glyph_refresh'), $r('app.color.text_primary')) }.height(48).width('100%').backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).onClick(() => this.proposePlan())
    if (this.planReport.suggestions.length > 0) { Button({ type: ButtonType.Capsule }) { IconLabel('确认采用这些安排', $r('app.media.glyph_check_on_accent'), $r('app.color.on_accent')) }.height(52).width('100%').backgroundColor($r('app.color.accent')).fontColor($r('app.color.on_accent')).enabled(!this.busy && !this.planCloudBusy).onClick(() => this.applyPlan(false)) }
    if (this.hasPlanUndo) { Button({ type: ButtonType.Capsule }) { IconLabel('撤销上次排程', $r('app.media.glyph_undo'), $r('app.color.text_primary')) }.height(48).width('100%').onClick(() => this.applyPlan(true)) }
  }
  private editSmartDraft(draft: TaskDraft): void {
    this.openEditor(); this.draftTitle = draft.title; this.draftNote = draft.note; this.draftPriority = draft.priority;
    this.draftTags = draft.tagsText; this.draftDueAt = draft.dueAt; this.draftRepeat = draft.repeat ?? 'none';
    this.draftStart = draft.startMinute ?? -1; this.draftDuration = (draft.durationMinutes ?? 30).toString();
    this.draftLocation = draft.planning?.location ?? ''; this.locationOpen = !!this.draftLocation; this.notesOpen = !!this.draftNote; this.notice = '正在编辑这一条；原文保留在一句话输入中。请核对后保存。';
    this.draftKind = draft.planning?.kind ?? 'task'; this.draftList = draft.planning?.listName ?? '';
    this.draftDeadline = draft.planning?.deadlineAt ?? 0; this.draftDeadlineMode = draft.planning?.deadlineMode ?? 'none';
    this.draftInterval = (draft.planning?.rule.interval ?? 1).toString(); this.draftWeekdays = draft.planning?.rule.weekdays ?? [];
    this.draftUntil = draft.planning?.rule.untilDate ?? ''; this.draftCount = (draft.planning?.rule.count ?? 0).toString();
    this.draftReminder = draft.planning?.reminder?.mode ?? 'none'; this.draftLead = draft.planning?.reminder?.leadMinutes ?? 0;
    this.editorInitial = this.editorFingerprint();
  }
  private async saveSmartDrafts(drafts: TaskDraft[]): Promise<void> {
    if (this.busy || !drafts.length) { return; } this.busy = true; this.error = '';
    try { const now = Date.now(); const tasks = drafts.map((draft: TaskDraft) => TaskService.create(draft, util.generateRandomUUID(), now));
      await this.repository.mergeBackup(BackupService.decode(BackupService.encode(tasks, [], now)));
      await this.refreshData(); this.quickText = ''; this.changeMode('list'); this.selectedTab = 1; this.view = 'all';
      this.notice = '已保存 ' + tasks.length.toString() + ' 条草稿';
    } catch (error) { this.error = '保存失败，草稿仍保留：' + (error as Error).message; } finally { this.busy = false; }
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
      if (this.editScope === 'future') { await this.repository.splitSeries(this.editingId, this.occurrenceDate, task, util.generateRandomUUID()); }
      else { await this.repository.save(task); }
      await this.refreshData();
      this.query = ''; this.tagFilter = '';
      this.changeMode('list'); this.view = task.dueAt === 0 ? 'inbox' : 'scheduled';
      if (this.selectedTab === 3) { this.selectedTab = 1; }
      if (this.selectedTab === 0 && task.dueAt === 0 && task.priority !== 2) { this.selectedTab = 1; }
      this.notice = PlanningService.isEvent(task) ? '事件已保存' : '任务已保存';
    } catch (error) { this.error = '保存失败：' + (error as Error).message + '。编辑内容仍保留。'; }
    finally { this.busy = false; }
  }
  private saveEditor(): void {
    if (this.busy) { return; }
    const draft: TaskDraft = { title: this.draftTitle, note: this.draftNote, priority: this.draftPriority,
      tagsText: this.draftTags, dueAt: this.draftDueAt, repeat: this.draftRepeat,
      startMinute: this.draftStart, durationMinutes: Number(this.draftDuration), stepsText: this.draftSteps, planning: this.editorPlanning() };
    try {
      const old = this.tasks.find((task: Task) => task.id === this.editingId);
      if (this.editingId.length > 0 && !old) { this.error = '任务已不存在，请返回列表'; return; }
      const task = old && this.editScope === 'one' ? OccurrenceService.change(old, this.occurrenceDate, draft, Date.now()) :
        old ? TaskService.edit(old, draft, Date.now()) : TaskService.create(draft, util.generateRandomUUID(), Date.now());
      const warnings: string[] = [];
      if (this.editScope === 'all' && old && (old.repeat !== task.repeat || old.dueAt !== task.dueAt) && this.states.some((state: OccurrenceState) => state.taskId === old.id)) {
        warnings.push('已有历史的重复系列暂不支持更换起始日期或规则；请复制为新系列，原历史会保留。');
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
        this.getUIContext().showAlertDialog({ systemMaterial: MaterialService.surface(this.preferences.useMaterial),
          title: '保存前确认', message: warnings.join('\n\n'),
          primaryButton: { value: '取消', action: () => {} },
          secondaryButton: { value: '仍然保存', action: () => { this.persistEditor(task); } }
        });
      } else { this.persistEditor(task); }
    } catch (error) { this.error = (error as Error).message; }
  }
  private async toggle(item: TaskItem): Promise<void> {
    if (this.busy || PlanningService.isEvent(item.task)) { return; }
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
    this.batchRows = this.items(false).concat(this.items(true)).filter((item: TaskItem) => !PlanningService.isEvent(item.task)); this.batchKeys = [];
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
    this.getUIContext().showTimePickerDialog({ systemMaterial: MaterialService.surface(this.preferences.useMaterial), selected: selected, useMilitaryTime: true,
      onAccept: (value: TimePickerResult) => {
        this.draftStart = value.hour * 60 + value.minute;
        if (this.draftDueAt === 0) { this.draftDueAt = ScheduleService.end(ScheduleService.key(Date.now())); }
      } });
  }
  private remove(item: TaskItem): void {
    if (item.task.repeat === 'none') {
      this.getUIContext().showAlertDialog({ systemMaterial: MaterialService.surface(this.preferences.useMaterial), title: '删除任务？', message: item.task.title,
        primaryButton: { value: '取消', action: () => {} },
        secondaryButton: { value: '删除', action: () => { this.deleteTask(item.task.id); } } });
    } else {
      this.getUIContext().showAlertDialog({ systemMaterial: MaterialService.surface(this.preferences.useMaterial), title: '处理重复任务', message: `${item.task.title}\n本次日期：${item.dateKey}`,
        buttons: [
          { value: '取消', action: () => {} },
          { value: '仅跳过这次', action: () => { this.skip(item); } },
          { value: '删除整组', action: () => {
            this.getUIContext().showAlertDialog({ systemMaterial: MaterialService.surface(this.preferences.useMaterial), title: '删除整组？', message: '此规则和所有完成记录都将删除。',
              primaryButton: { value: '取消', action: () => {} },
              secondaryButton: { value: '删除整组', action: () => { this.deleteTask(item.task.id); } } });
          } }
        ] });
    }
  }
  private pickDate(): void {
    const selected = this.draftDueAt > 0 ? new Date(this.draftDueAt) : new Date();
    this.getUIContext().showDatePickerDialog({ systemMaterial: MaterialService.surface(this.preferences.useMaterial),
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
      const settings = await this.repository.backupSettings();
      const ai = await AiConfigStore.load(this.context());
      settings.ai = { endpoint: ai.endpoint, model: ai.model };
      const content = BackupService.encode(this.tasks, this.states, Date.now(), this.product, settings);
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
      this.calendarImport = false; this.updateCalendarSource = false; this.calendarEligible = [];
      const doc = BackupService.decode(raw);
      const count = doc.tasks.filter((task: Task) => !this.tasks.some((current: Task) => current.id === task.id)).length;
      this.pendingImport = doc;
      this.importSummary = `文件中共 ${doc.tasks.length} 个任务，将新增 ${count} 个。已有的 ${doc.tasks.length - count} 个同 ID 任务保持现状。`;
      if (doc.product) { this.importSummary += ` 工具包含 ${doc.product.habits.length} 个习惯、${doc.product.countdowns.length} 个倒数日和 ${doc.product.sessions.length} 段计时。合并新 ID 并恢复功能开关；已有同 ID 数据保留，导入中的进行计时改为暂停或结束。`; }
      if (doc.settings) { this.importSummary += ' 将恢复显示、排序及非敏感 AI 配置，密钥和系统提醒登记不迁移。'; }
    } catch (error) { this.error = '无法导入：' + (error as Error).message; }
    finally { this.busy = false; }
  }
  private async chooseCalendar(): Promise<void> {
    if (this.busy) { return; }
    this.busy = true; this.error = ''; this.notice = ''; this.pendingImport = undefined; this.importSummary = ''; this.importNotes = '';
    try {
      const raw = await BackupFiles.importFile(this.context(), 'ics');
      if (raw === undefined) { return; }
      const report = IcsService.parse(raw, Date.now()); this.calendarImport = true; this.updateCalendarSource = false;
      this.calendarImportSnapshot = JSON.stringify([this.tasks, this.states]);
      const update = IcsUpdateService.preview(report.document, this.tasks, this.states); this.calendarEligible = update.eligible;
      this.pendingImport = BackupService.decode(JSON.stringify(report.document));
      const count = report.document.tasks.filter((task: Task) => !this.tasks.some((current: Task) => current.id === task.id)).length;
      this.importSummary = `日历共 ${report.total} 条事件，可识别 ${report.document.tasks.length} 条，将新增 ${count} 个任务。同 UID 默认保留本机版本；${update.eligible.length} 条可选择更新，${update.blocked.length} 条受完成记录保护。`;
      report.notes.push(...update.blocked);
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
    let committed = false;
    try {
      const count = this.calendarImport ? await this.repository.importCalendar(this.pendingImport, this.updateCalendarSource ? this.calendarEligible : [], this.calendarImportSnapshot) : await this.repository.mergeBackup(this.pendingImport);
      committed = true;
      this.pendingImport = undefined; this.importSummary = '';
      this.product = await this.repository.getProduct();
      await this.refreshData();
      this.preferences = await this.repository.getPreferences(); this.sortMode = await this.repository.getSortMode();
      this.theme = await this.repository.getTheme(); await this.repository.setTheme(this.context(), this.theme);
      this.notice = `已导入 ${count} 个任务`;
    } catch { this.error = committed ? '数据已导入，界面刷新失败，请重新打开应用；无需再次导入' : '导入失败，数据已回滚，请重试'; }
    finally { this.busy = false; }
  }
  private items(completed: boolean, page: number = this.selectedTab): TaskItem[] {
    const view = page === 0 ? 'today' : page === 2 ? 'calendar' : this.view;
    return ScheduleService.filter(ScheduleService.project(this.tasks, this.states, view, this.selectedDay, this.now).filter((item: TaskItem) => page !== 1 || !this.listFilter || item.task.planning?.listName === this.listFilter),
      completed, page === 1 ? this.query : '', page === 1 ? this.tagFilter : '', page === 2 ? 'time' : this.sortMode);
  }
  private overview(): DayOverview {
    if (!this.overviewCache || this.overviewTasks !== this.tasks || this.overviewStates !== this.states || this.overviewNow !== this.now) {
      this.overviewCache = FocusService.overview(this.tasks, this.states, this.now);
      this.overviewTasks = this.tasks; this.overviewStates = this.states; this.overviewNow = this.now;
    }
    return this.overviewCache;
  }
  private tabTitle(page: number): string { return ['今天', '待办', '日历', '工作台'][page]; }
  private dateTitle(): string {
    const date = new Date(this.now);
    return `${date.getMonth() + 1}月${date.getDate()}日 · 星期${['日', '一', '二', '三', '四', '五', '六'][date.getDay()]}`;
  }
  private pageTitle(): string {
    return this.mode === 'list' ? this.tabTitle(this.selectedTab) : this.mode === 'editor' ? (this.editingId ? '编辑任务' : '新建任务') :
      this.mode === 'settings' ? '设置' : this.mode === 'appearance' ? '外观与动效' : this.mode === 'preferences' ? '操作偏好' : this.mode === 'features' ? '功能与工具' : this.mode === 'notifications' ? '提醒与权限' : this.mode === 'about' ? '关于 TaiPlan' : this.mode === 'aiConfig' ? 'AI 服务设置' : this.mode === 'detail' ? '事项详情' : this.mode === 'classification' ? '清单与标签' : this.mode === 'product' ? '我的工具' : this.mode === 'plan' ? '辅助排程' : this.mode === 'search' ? '搜索全部内容' : this.mode === 'quick' ? '一句话识别' : this.mode === 'tools' ? '数据与恢复' : this.mode === 'sort' ? '任务排序' : '批量处理';
  }
  private calendarDays(): CalendarDay[] {
    return ScheduleService.month(this.tasks, this.states, this.month);
  }
  onBackPress(): boolean {
    if (this.mode !== 'list') { if (!this.busy) { this.closeSubpage(); } return true; }
    if (this.selectedTab !== 0) { this.selectedTab = 0; return true; }
    return false;
  }


  private rows(completed: boolean, page: number, group: string): TaskItem[] {
    return group === 'urgent' ? this.overview().urgent : group === 'remaining' ? this.overview().remaining : group === 'done' ? this.overview().done : group === 'events' ? this.overview().events : this.items(completed, page);
  }

  @Builder
  taskRows(completed: boolean, page: number, group: string) {
    ForEach(this.rows(completed, page, group), (item: TaskItem) => {
      TaskCard({ useMaterial: this.preferences.useMaterial, task: item.task, completed: item.completed, displayDueAt: item.dueAt, busy: this.busy, now: this.now,
        reminderLabel: this.reminderStatus ? this.reminders.label(item) : '',
        expanded: this.expandedKeys.includes(item.key), onExpand: () => {
          this.expandedKeys = this.expandedKeys.includes(item.key) ? this.expandedKeys.filter((key: string) => key !== item.key) : this.expandedKeys.concat([item.key]);
        },
        doneSteps: item.doneSteps ?? [], onStep: (index: number) => this.toggleStep(item, index), onCopy: () => this.copyTask(item.task),
        onToggle: () => this.toggle(item), onEdit: () => { if (page === 2) { this.openDetail(item); } else { this.openOccurrence(item); } }, onRemove: () => this.remove(item) })
    }, (item: TaskItem) => ScheduleService.renderKey(item))
  }

  @Builder
  section(completed: boolean, label: string, page: number) {
    Row() {
      Text(page === 1 && !completed ? (this.view === 'inbox' ? '还没安排' : '待办') : label).fontSize(19).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
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
      Search({ value: this.query, placeholder: '在当前列表查找' }).searchIcon({ src: $r('app.media.glyph_search'), size: 20 }).cancelButton({ style: CancelButtonStyle.INPUT, icon: { src: $r('app.media.glyph_close'), size: 18 } }).height(44).layoutWeight(1)
        .onChange((value: string) => { this.query = value; })
        .backgroundColor($r('app.color.card_background')).fontColor($r('app.color.text_primary'))
      Button({ type: ButtonType.Capsule }) { IconLabel('筛选', $r('app.media.glyph_filter'), $r('app.color.text_primary')) }.height(44).fontSize(13).padding({ left: 12, right: 12 })
        .backgroundColor($r('app.color.card_background')).fontColor($r('app.color.text_primary'))
        .onClick(() => { this.showFilters = !this.showFilters; })
    }.width('100%')
    Row({ space: 8 }) {
      ForEach(['inbox', 'scheduled', 'all'], (view: string) => {
        Button(view === 'inbox' ? '收集箱' : view === 'scheduled' ? '已安排' : '全部').layoutWeight(1).height(44).fontSize(13)
          .backgroundColor(this.view === view ? $r('app.color.accent') : $r('app.color.card_background'))
          .fontColor(this.view === view ? $r('app.color.on_accent') : $r('app.color.text_primary')).onClick(() => this.changeView(view))
      })
    }.width('100%')
    if (this.showFilters) {
      Column({ space: 10 }) {
        Row({ space: 8 }) {
          ForEach(['inbox', 'scheduled', 'all', 'future'], (view: string) => {
            Button(view === 'inbox' ? '收集箱' : view === 'scheduled' ? '已安排' : view === 'all' ? '全部' : '近期').layoutWeight(1).height(40).fontSize(13)
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
          Button({ type: ButtonType.Capsule }) { IconLabel('拖拽排序', $r('app.media.glyph_drag'), $r('app.color.text_primary')) }.layoutWeight(1).height(40).fontSize(12).padding(4)
            .backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).onClick(() => this.openSort())
          Button({ type: ButtonType.Capsule }) { IconLabel('多选', $r('app.media.glyph_multi_select'), $r('app.color.text_primary')) }.height(40).fontSize(12).padding({ left: 12, right: 12 })
            .backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).onClick(() => this.openBatch())
        }
      }.padding(12).borderRadius(16).backgroundColor($r('app.color.card_background')).width('100%')
    }
    Text((this.view === 'inbox' ? '先记下来，想好再安排' : this.view === 'scheduled' ? '有日期的任务与事件' : this.view === 'future' ? '未来 30 天' : '全部任务') + (this.tagFilter ? ' · ' + this.tagFilter : '') + ' · ' + ScheduleService.sortLabel(this.sortMode))
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



    if (this.overview().urgent.length > 0) {
      Row() {
        Text('优先处理').fontSize(19).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        Text(' · ' + this.overview().urgent.length.toString() + ' 项').fontSize(13).fontColor($r('app.color.text_secondary')).margin({ left: 6 })
      }.width('100%').padding({ top: 12 })
      Text('逾期、1 小时内截止与高优先级事项').fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
      this.taskRows(false, 0, 'urgent')
    }
    if (this.overview().events.length > 0) {
      Text('今天的日程 · ' + this.overview().events.length.toString()).fontSize(19).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).width('100%')
      this.taskRows(false, 0, 'events')
    }
    if (this.overview().remaining.length > 0) {
      Text('今天待办').fontSize(19).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        .width('100%').padding({ top: 12 })
      this.taskRows(false, 0, 'remaining')
    }
    if (this.overview().urgent.length === 0 && this.overview().remaining.length === 0) {
      Column({ space: 8 }) {
        Text('今天暂时没有待办').fontSize(18).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        Text('点下方「记一件事」，先留下想法。\n未安排的任务在「待办 → 收集箱」里。')
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
    this.toolEntry('外观与动效', '深浅色、玻璃材质与减少动画', $r('app.media.glyph_appearance'), () => this.changeMode('appearance'))
    this.toolEntry('操作偏好', '启动页面、日历尺度与时间吸附', $r('app.media.glyph_preferences'), () => this.changeMode('preferences'))
    this.toolEntry('功能与工具', '按自己的习惯，选择需要的功能', $r('app.media.nav_workbench'), () => this.changeMode('features'))
    this.toolEntry('提醒与权限', '通知授权、登记状态与取消提醒', $r('app.media.glyph_reminder_perm'), () => this.changeMode('notifications'))
    if (this.product.features.ai) { this.toolEntry('AI 服务', '服务地址、密钥与连接诊断', $r('app.media.glyph_ai_service'), () => this.changeMode('aiConfig')) }
    this.toolEntry('备份与日历互通', '备份恢复、课表和 ICS 导入导出', $r('app.media.icon_data'), () => this.changeMode('tools'))
    this.toolEntry('关于 TaiPlan', '版本、作者与项目仓库', $r('app.media.icon_about'), () => this.changeMode('about'))
    Text('TaiPlan 1.0.1').fontSize(12).fontColor($r('app.color.text_secondary')).width('100%').textAlign(TextAlign.Center).margin({ top: 12, bottom: 12 })
  }
  @Builder
  appearancePage() {
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
    PreferencePanel({ appearanceOnly: true, settings: this.preferences, onChange: (value: AppPreferences) => this.savePreferences(value) })
  }
  @Builder
  notificationsPage() {
    Column({ space: 8 }) {
      Text('系统提醒').fontSize(17).fontColor($r('app.color.text_primary')).width('100%')
      Text(this.reminderStatus).fontSize(13).fontColor($r('app.color.text_secondary')).width('100%')
      Text('只预约未来 7 天、最多 50 条；每次打开或修改任务时补齐。长期不打开不会自动续约。日期任务默认 09:00；不会绕过勿扰。').fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
      Button({ type: ButtonType.Capsule }) { IconLabel('启用授权 / 重试同步', $r('app.media.glyph_refresh'), $r('app.color.text_primary')) }.height(44).onClick(async () => {
        try { await this.reminders.enable(this.context()); this.reminderStatus = await this.reminders.sync(this.context(), this.tasks, this.states, ProductReminderService.intents(this.product, Date.now())); }
        catch (error) { this.reminderStatus = '启用失败：' + (error as Error).message; }
      })
      Button({ type: ButtonType.Capsule }) { IconLabel('关闭并取消已登记提醒', $r('app.media.glyph_reminder_perm'), $r('app.color.text_primary')) }.height(44).onClick(async () => {
        try { await this.reminders.disable(this.context()); this.reminderStatus = '已关闭并取消提醒'; }
        catch { this.reminderStatus = '取消未完成，请稍后重试；不能保证旧提醒已取消'; }
      })
    }.padding(16).width('100%').borderRadius(18).backgroundColor($r('app.color.card_background'))
  }
  @Builder
  aboutPage() {
    Column({ space: 16 }) {
      Image($r('app.media.glyph_app_icon')).width(64).height(64).borderRadius(16)
      Text('TaiPlan').fontSize(30).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
      Text('1.0.1 · HarmonyOS').fontSize(14).fontColor($r('app.color.text_secondary'))
      Text('把想到的事记下来，把重要的事安排好。').fontSize(16).fontColor($r('app.color.text_primary'))
      Text('作者：TaiWoo_Chen').fontSize(14).fontColor($r('app.color.text_primary'))
      Text('使用 ArkTS、ArkUI 和 SQLite 构建。任务保存在本机，可通过备份迁移；AI 请求仅在你主动确认后发送。').fontSize(13).fontColor($r('app.color.text_secondary'))
      Text('https://github.com/TanTaiwoo07/taiplan-harmony').fontSize(13).fontColor($r('app.color.support_accent')).copyOption(CopyOptions.LocalDevice)
      Button({ type: ButtonType.Capsule }) { IconLabel('查看项目仓库', $r('app.media.glyph_repo'), $r('app.color.text_primary')) }.height(48).width('100%').backgroundColor($r('app.color.accent_soft')).fontColor($r('app.color.support_accent')).onClick(async () => {
        try { await this.context().startAbility({ action: 'ohos.want.action.viewData', uri: 'https://github.com/TanTaiwoo07/taiplan-harmony' }); }
        catch { this.notice = '无法打开浏览器，可长按上方地址复制；私有仓库需要访问权限。'; }
      })
      Text('私有项目仓库，访问需要相应权限。\n© 2026 TaiWoo_Chen').fontSize(12).fontColor($r('app.color.text_secondary'))
    }.width('100%').padding(22).borderRadius(24).backgroundColor($r('app.color.card_background'))
  }
  @Builder
  floatingDock() {
    Row() {
      ForEach([0, 1, 2, 3], (page: number) => {
        Button({ type: ButtonType.Normal }) { this.tabLabel(page) }.layoutWeight(1).height(60).borderRadius(24)
          .backgroundColor(this.selectedTab === page ? $r('app.color.accent_soft') : Color.Transparent)
          .animation(MotionService.options(this.preferences.reduceMotion)).accessibilityText(this.tabTitle(page))
          .onClick(() => { this.animate(() => { this.selectedTab = page; }); this.now = Date.now(); this.error = ''; this.notice = ''; })
      })
    }.padding(6).width('92%').height(72).margin({ top: 8, bottom: 12 }).borderRadius(30)
      .backgroundColor(this.preferences.useMaterial ? $r('app.color.glass_surface') : $r('app.color.card_background'))
      .backgroundEffect(this.preferences.useMaterial ? { radius: 24, saturation: 1.1, brightness: 1 } : undefined)
      .border({ width: 0.8, color: $r('app.color.glass_line') }).shadow({ radius: 18, color: $r('app.color.glass_shadow'), offsetY: 4 })
  }

  private pickLead(): void {
    const values = [0, 5, 10, 15, 30, 60, 1440];
    this.getUIContext().showTextPickerDialog({ systemMaterial: MaterialService.surface(this.preferences.useMaterial), range: values.map((value: number) => EditorOptionsService.leadLabel(value)).concat(['自定义…']),
      selected: Math.max(0, values.indexOf(this.draftLead)), canLoop: false,
      onAccept: (result: TextPickerResult) => {
        const index = result.index as number;
        if (index === values.length) { this.customLead = true; this.leadDays = Math.floor(this.draftLead / 1440).toString(); this.leadHours = Math.floor(this.draftLead % 1440 / 60).toString(); this.leadMinutes = (this.draftLead % 60).toString(); }
        else { this.draftLead = values[index]; this.customLead = false; }
      } });
  }
  private pickRepeat(): void {
    this.getUIContext().showTextPickerDialog({ systemMaterial: MaterialService.surface(this.preferences.useMaterial), range: ['不重复', '每天', '工作日（周一至周五）', '每周', '每月', '每年', '自定义…'], canLoop: false,
      selected: this.draftRepeat === 'none' ? 0 : this.draftRepeat === 'daily' ? 1 : this.draftRepeat === 'weekly' ? (this.draftWeekdays.join(',') === '1,2,3,4,5' ? 2 : 3) : this.draftRepeat === 'monthly' ? 4 : 5, onAccept: (result: TextPickerResult) => {
        const index = result.index as number;
        if (index === 6) { if (this.draftRepeat === 'none') { this.draftRepeat = 'daily'; } this.repeatOpen = true; return; }
        this.draftRepeat = ['none', 'daily', 'weekly', 'weekly', 'monthly', 'yearly'][index];
        this.draftInterval = '1'; this.draftWeekdays = index === 2 ? [1, 2, 3, 4, 5] : []; this.draftUntil = ''; this.draftCount = ''; this.repeatOpen = false;
      } });
  }
  private repeatSummary(): string {
    if (this.draftRepeat === 'none') { return '不重复'; }
    try { const task = TaskService.create({ title: this.draftTitle || '预览', note: '', priority: 1, tagsText: '', dueAt: this.draftDueAt,
      startMinute: this.draftStart, durationMinutes: Number(this.draftDuration), repeat: this.draftRepeat, planning: this.editorPlanning() }, 'preview', 0);
      return EditorOptionsService.repeat(task);
    } catch { return '请补齐重复规则'; }
  }
  private endLabel(): string {
    const end = this.draftStart + Number(this.draftDuration);
    return TaskService.minuteLabel(end % 1440) + (end >= 1440 ? '（次日）' : '');
  }
  private pickEnd(): void {
    const selected = new Date(); selected.setHours(0, this.draftStart + Number(this.draftDuration), 0, 0);
    this.getUIContext().showTimePickerDialog({ systemMaterial: MaterialService.surface(this.preferences.useMaterial), selected: selected, useMilitaryTime: true, onAccept: (value: TimePickerResult) => {
      const end = value.hour * 60 + value.minute; this.draftDuration = ((end - this.draftStart + 1440) % 1440 || 1440).toString();
    } });
  }
  private fieldIcon(label: string): Resource {
    if (label === '安排日期') { return $r('app.media.glyph_plan_date'); }
    if (label === '精确时间') { return $r('app.media.glyph_time_range'); }
    if (label.includes('截止')) { return $r('app.media.glyph_deadline'); }
    if (label.includes('提醒')) { return $r('app.media.glyph_reminder'); }
    if (label.includes('备注')) { return $r('app.media.glyph_note'); }
    if (label.includes('子任务')) { return $r('app.media.glyph_subtask'); }
    if (label.includes('地点')) { return $r('app.media.glyph_location'); }
    return $r('app.media.glyph_preferences');
  }
  @Builder
  fieldSwitch(label: string, on: boolean, action: (value: boolean) => void, enabled: boolean = true) {
    Row({ space: 10 }) { Image(this.fieldIcon(label)).width(20).height(20).accessibilityLevel('no')
      Text(label).fontSize(16).fontColor($r('app.color.text_primary')).layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: on }).selectedColor($r('app.color.accent')).enabled(enabled).onChange((value: boolean) => this.animate(() => action(value)))
    }.width('100%').height(52)
  }
  @Builder
  editor() {
    Column({ space: 12 }) {
      TextInput({ placeholder: '准备做什么？', text: this.draftTitle }).maxLength(100).height(54)
        .onChange((value: string) => { this.draftTitle = value; }).backgroundColor($r('app.color.card_background')).fontColor($r('app.color.text_primary'))
      Row({ space: 8 }) {
        ForEach(['task', 'event'], (kind: string) => {
          Button({ type: ButtonType.Capsule }) { IconLabel(kind === 'task' ? '待办任务' : '日历事件', kind === 'task' ? (this.draftKind === kind ? $r('app.media.glyph_todo_on_accent') : $r('app.media.glyph_todo')) : (this.draftKind === kind ? $r('app.media.glyph_calendar_on_accent') : $r('app.media.glyph_calendar')), this.draftKind === kind ? $r('app.color.on_accent') : $r('app.color.text_primary')) }.height(48).layoutWeight(1).fontSize(14)
            .backgroundColor(this.draftKind === kind ? $r('app.color.accent') : $r('app.color.card_background'))
            .fontColor(this.draftKind === kind ? $r('app.color.on_accent') : $r('app.color.text_primary'))
            .onClick(() => { this.draftKind = kind; if (kind === 'event') { this.draftDeadline = 0; this.draftDeadlineMode = 'none'; if (!this.draftDueAt) { this.draftDueAt = ScheduleService.end(ScheduleService.key(Date.now())); } if (this.draftReminder === 'deadline') { this.draftReminder = 'start'; } } })
        })
      }.width('100%')
      if (this.product.features.ai && !this.editingId) { Button({ type: ButtonType.Capsule }) { IconLabel('用一句话填写', $r('app.media.glyph_smart_input')) }.height(48).width('100%').backgroundColor(Color.Transparent).fontColor($r('app.color.text_secondary')).onClick(() => this.changeMode('quick')) }
      if (this.occurrenceDate) { Text('修改范围：' + (this.editScope === 'one' ? '仅这一次' : '这次及以后') + ' · 原日期 ' + this.occurrenceDate).fontSize(13).fontColor($r('app.color.text_secondary')).width('100%') }
      Column({ space: 8 }) {
        this.fieldSwitch('安排日期', this.draftDueAt > 0, (value: boolean) => {
          if (value) { this.draftDueAt = ScheduleService.end(ScheduleService.key(Date.now())); this.pickDate(); }
          else { if (this.draftKind === 'event') { this.error = '日历事件必须有日期；无日期事项请选待办任务'; this.draftDueAt = this.draftDueAt; return; }
            this.draftDueAt = 0; this.draftStart = -1; this.draftRepeat = 'none'; if (this.draftReminder === 'start') { this.draftReminder = 'none'; } this.notice = '已关闭日期，同时移除时间和重复规则；保存后生效。'; }
        }, this.draftKind !== 'event')
        if (this.draftDueAt > 0) {
          Button({ type: ButtonType.Capsule }) { IconLabel(TaskService.dateLabel(this.draftDueAt), $r('app.media.glyph_plan_date')) }.height(48).width('100%').backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).onClick(() => this.pickDate())
          this.fieldSwitch('指定时间', this.draftStart >= 0, (value: boolean) => { this.draftStart = value ? 9 * 60 : -1; if (value) { this.pickTime(); } })
          if (this.draftStart >= 0) {
            Row({ space: 8 }) {
              Button({ type: ButtonType.Capsule }) { IconLabel('开始 ' + TaskService.minuteLabel(this.draftStart), $r('app.media.glyph_time_range')) }.height(48).layoutWeight(1).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).onClick(() => this.pickTime())
              Button({ type: ButtonType.Capsule }) { IconLabel('结束 ' + this.endLabel(), $r('app.media.glyph_time_range')) }.height(48).layoutWeight(1).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).onClick(() => this.pickEnd())
            }
          } else { Text('当天要做，不占用具体时间段').fontSize(12).fontColor($r('app.color.text_secondary')).width('100%') }
        } else { Text('先记进收集箱，之后再安排').fontSize(12).fontColor($r('app.color.text_secondary')).width('100%') }
        this.fieldSwitch('地点', this.locationOpen, (value: boolean) => { this.locationOpen = value; if (!value) { this.draftLocation = ''; } })
        if (this.locationOpen) { TextInput({ text: this.draftLocation, placeholder: '在哪里？' }).height(48).maxLength(200).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).onChange((value: string) => { this.draftLocation = value; }) }
        if (this.draftKind === 'task') {
          this.fieldSwitch('截止期限', this.draftDeadline > 0, (value: boolean) => { if (value) { this.draftDeadline = ScheduleService.end(ScheduleService.key(Date.now())); this.draftDeadlineMode = 'date'; this.pickDeadline(); } else { this.draftDeadline = 0; this.draftDeadlineMode = 'none'; if (this.draftReminder === 'deadline') { this.draftReminder = 'none'; } } })
          if (this.draftDeadline > 0) {
            Button({ type: ButtonType.Capsule }) { IconLabel(TaskService.dateLabel(this.draftDeadline), $r('app.media.glyph_deadline')) }.height(48).width('100%').backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).onClick(() => this.pickDeadline())
            this.fieldSwitch('精确到时间', this.draftDeadlineMode === 'datetime', (value: boolean) => { if (value) { this.draftDeadlineMode = 'datetime'; this.pickDeadlineTime(); } else { this.draftDeadline = ScheduleService.end(ScheduleService.key(this.draftDeadline)); this.draftDeadlineMode = 'date'; } })
            if (this.draftDeadlineMode === 'datetime') { Button(TaskService.minuteLabel(new Date(this.draftDeadline).getHours() * 60 + new Date(this.draftDeadline).getMinutes())).height(48).width('100%').backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).onClick(() => this.pickDeadlineTime()) }
            Text('截止与安排独立，表示最晚何时完成').fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
          }
        }
        this.fieldSwitch('提醒', this.draftReminder !== 'none', (value: boolean) => { if (!value) { this.draftReminder = 'none'; this.customLead = false; } else if (!this.draftDueAt && !this.draftDeadline) { this.error = '请先设置安排日期或截止期限'; } else { this.draftReminder = this.draftDeadline ? 'deadline' : 'start'; } }, this.draftDueAt > 0 || this.draftDeadline > 0)
        if (this.draftReminder !== 'none') {
          if (this.draftDueAt && this.draftDeadline) {
            Button({ type: ButtonType.Capsule }) { IconLabel(this.draftReminder === 'start' ? '依据：安排时间' : '依据：截止期限', $r('app.media.glyph_reminder')) }.height(48).width('100%').backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary'))
              .onClick(() => this.getUIContext().showTextPickerDialog({ systemMaterial: MaterialService.surface(this.preferences.useMaterial), range: ['安排时间', '截止期限'], selected: this.draftReminder === 'start' ? 0 : 1, canLoop: false, onAccept: (value: TextPickerResult) => { this.draftReminder = value.index === 0 ? 'start' : 'deadline'; } }))
          }
          Button({ type: ButtonType.Capsule }) { IconLabel(EditorOptionsService.leadLabel(this.draftLead), $r('app.media.glyph_duration')) }.height(48).width('100%').backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).onClick(() => this.pickLead())
          if (this.customLead) {
            Row({ space: 6 }) {
              TextInput({ text: this.leadDays, placeholder: '天' }).type(InputType.Number).maxLength(1).height(48).layoutWeight(1).onChange((value: string) => { this.leadDays = value; })
              Text('天').fontColor($r('app.color.text_secondary'))
              TextInput({ text: this.leadHours, placeholder: '小时' }).type(InputType.Number).maxLength(2).height(48).layoutWeight(1).onChange((value: string) => { this.leadHours = value; })
              Text('小时').fontColor($r('app.color.text_secondary'))
              TextInput({ text: this.leadMinutes, placeholder: '分钟' }).type(InputType.Number).maxLength(2).height(48).layoutWeight(1).onChange((value: string) => { this.leadMinutes = value; })
              Text('分').fontColor($r('app.color.text_secondary'))
            }
            Button('应用自定义提前量').height(48).width('100%').backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).onClick(() => { try { this.draftLead = EditorOptionsService.lead(this.leadDays, this.leadHours, this.leadMinutes); this.customLead = false; this.error = ''; } catch (error) { this.error = (error as Error).message; } })
          }
        }
        if (this.draftDueAt > 0 && this.editScope !== 'one') {
          Button({ type: ButtonType.Capsule }) { IconLabel('重复 · ' + this.repeatSummary(), $r('app.media.glyph_repeat')) }.height(52).width('100%').fontSize(14).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).onClick(() => this.pickRepeat())
          if (this.draftRepeat !== 'none') { Button(this.repeatOpen ? '收起自定义规则' : '自定义间隔与结束条件').height(48).width('100%').backgroundColor(Color.Transparent).fontColor($r('app.color.text_secondary')).onClick(() => { this.repeatOpen = !this.repeatOpen; }) }
          if (this.repeatOpen && this.draftRepeat !== 'none') {
            Button('周期：' + ScheduleService.repeatLabel(this.draftRepeat)).height(48).width('100%').onClick(() => this.getUIContext().showTextPickerDialog({ systemMaterial: MaterialService.surface(this.preferences.useMaterial), range: ['天', '周', '月', '年'], selected: 0, canLoop: false, onAccept: (value: TextPickerResult) => { this.draftRepeat = ['daily', 'weekly', 'monthly', 'yearly'][value.index as number]; if (this.draftRepeat !== 'weekly') { this.draftWeekdays = []; } } }))
            TextInput({ text: this.draftInterval, placeholder: '每隔几个周期' }).type(InputType.Number).maxLength(3).height(48).onChange((value: string) => { this.draftInterval = value; })
            if (this.draftRepeat === 'weekly') { Flex({ wrap: FlexWrap.Wrap }) { ForEach([1, 2, 3, 4, 5, 6, 7], (day: number) => {
              Button('周' + ['一', '二', '三', '四', '五', '六', '日'][day - 1]).height(48).fontSize(13).margin(3).backgroundColor(this.draftWeekdays.includes(day) ? $r('app.color.accent') : $r('app.color.chip_background')).fontColor(this.draftWeekdays.includes(day) ? $r('app.color.on_accent') : $r('app.color.text_primary')).onClick(() => { this.draftWeekdays = this.draftWeekdays.includes(day) ? this.draftWeekdays.filter((value: number) => value !== day) : this.draftWeekdays.concat([day]); })
            }) } }
            Button(this.draftUntil ? '结束于 ' + this.draftUntil : this.draftCount ? '共 ' + this.draftCount + ' 次' : '结束条件：不设结束').height(48).width('100%').onClick(() => this.getUIContext().showTextPickerDialog({ systemMaterial: MaterialService.surface(this.preferences.useMaterial), range: ['不设结束', '结束日期', '重复次数'], selected: 0, canLoop: false, onAccept: (value: TextPickerResult) => {
              if (value.index === 0) { this.draftUntil = ''; this.draftCount = ''; }
              else if (value.index === 1) { this.getUIContext().showDatePickerDialog({ systemMaterial: MaterialService.surface(this.preferences.useMaterial), selected: new Date(this.draftDueAt), onAccept: (date: DatePickerResult) => { this.draftUntil = ScheduleService.key(new Date(date.year ?? new Date(this.draftDueAt).getFullYear(), date.month ?? new Date(this.draftDueAt).getMonth(), date.day ?? new Date(this.draftDueAt).getDate(), 12).getTime()); this.draftCount = ''; } }); }
              else { this.draftUntil = ''; this.draftCount = '10'; }
            } }))
            if (this.draftCount) { TextInput({ text: this.draftCount, placeholder: '总次数' }).type(InputType.Number).maxLength(5).height(48).onChange((value: string) => { this.draftCount = value; }) }
            Text('未选星期则跟随起始日；工作日不包含节假日调休。').fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
          }
        }
        this.fieldSwitch('子任务/备注', this.notesOpen, (value: boolean) => { this.notesOpen = value; if (!value) { this.draftNote = ''; this.draftSteps = ''; this.notice = '已移除草稿中的子任务和备注，保存后生效；取消可保留原内容。'; } })
        if (this.notesOpen) {
          Text('备注').fontSize(13).fontColor($r('app.color.text_secondary')).width('100%')
          TextArea({ text: this.draftNote, placeholder: '补充说明，不参与勾选' }).height(90).maxLength(1000).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).onChange((value: string) => { this.draftNote = value; })
          Text('子任务 · 每行一项').fontSize(13).fontColor($r('app.color.text_secondary')).width('100%')
          TextArea({ text: this.draftSteps, placeholder: '整理资料\n完成初稿' }).height(120).maxLength(2020).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).onChange((value: string) => { this.draftSteps = value; })
        }
      }.padding(16).borderRadius(18).backgroundColor($r('app.color.card_background')).width('100%')
      Button({ type: ButtonType.Capsule }) { IconLabel(this.advanced ? '收起分类与优先级' : '清单、标签与优先级', $r('app.media.glyph_tag')) }.height(48).width('100%').backgroundColor(Color.Transparent).fontColor($r('app.color.text_secondary')).onClick(() => { this.advanced = !this.advanced; })
      if (this.advanced) {
        TextInput({ text: this.draftList, placeholder: '清单，例如学习、生活' }).height(48).maxLength(12).onChange((value: string) => { this.draftList = value; })
        TextInput({ text: this.draftTags, placeholder: '标签，逗号分隔' }).height(48).maxLength(80).onChange((value: string) => { this.draftTags = value; })
        Row({ space: 8 }) { ForEach([0, 1, 2], (priority: number) => {
          Button(TaskService.priorityLabel(priority) + '优先级').height(48).layoutWeight(1).fontSize(13).backgroundColor(this.draftPriority === priority ? $r('app.color.accent') : $r('app.color.card_background')).fontColor(this.draftPriority === priority ? $r('app.color.on_accent') : $r('app.color.text_primary')).onClick(() => { this.draftPriority = priority; })
        }) }
      }
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
      Button({ type: ButtonType.Capsule }) { IconLabel('识别并预览', $r('app.media.glyph_smart_input_on_accent'), $r('app.color.on_accent')) }.height(46).width('100%').backgroundColor($r('app.color.accent'))
        .fontColor($r('app.color.on_accent')).onClick(() => this.parseQuick())
    }.width('100%')
  }

  @Builder
  toolsPage() {
    Column({ space: 14 }) {
      Button({ type: ButtonType.Capsule }) { IconLabel('导出任务备份', $r('app.media.glyph_backup'), $r('app.color.text_primary')) }.width('100%').height(48).backgroundColor($r('app.color.card_background'))
        .fontColor($r('app.color.accent')).onClick(() => this.exportBackup())
      Button({ type: ButtonType.Capsule }) { IconLabel('从文件恢复任务', $r('app.media.glyph_import'), $r('app.color.text_primary')) }.width('100%').height(48).backgroundColor($r('app.color.card_background'))
        .fontColor($r('app.color.accent')).onClick(() => this.chooseBackup())
      Row({ space: 8 }) {
        Button({ type: ButtonType.Capsule }) { IconLabel('导入 ICS 日历', $r('app.media.glyph_import'), $r('app.color.text_primary')) }.layoutWeight(1).height(44).fontSize(13).padding(4)
          .backgroundColor($r('app.color.card_background')).fontColor($r('app.color.accent')).onClick(() => this.chooseCalendar())
        Button({ type: ButtonType.Capsule }) { IconLabel('导出 30 天日历', $r('app.media.glyph_export'), $r('app.color.text_primary')) }.layoutWeight(1).height(44).fontSize(13).padding(4)
          .backgroundColor($r('app.color.card_background')).fontColor($r('app.color.accent')).onClick(() => this.exportCalendar())
      }.width('100%')
      Text('ICS 导出为未来 30 天单次快照；导入支持常见重复、RDATE、单次调课及 IANA 时区。同 UID 默认保留，可预览后更新无历史的来源事项；不支持的组合单独报告。')
        .fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
      Text('备份包含任务、时间、子任务、标签、顺序和重复完成记录。兼容旧版备份；恢复时只合并新任务，已有同 ID 任务保留。')
        .fontSize(13).fontColor($r('app.color.text_secondary')).width('100%')
      if (this.importSummary.length > 0) {
        Text(this.importSummary).fontSize(14).fontColor($r('app.color.text_primary')).width('100%')
        if (this.calendarImport && this.calendarEligible.length > 0) {
          Row({ space: 12 }) {
            Text('更新同来源日程（' + this.calendarEligible.length.toString() + ' 项）').layoutWeight(1).fontSize(14).fontColor($r('app.color.text_primary'))
            Toggle({ type: ToggleType.Switch, isOn: this.updateCalendarSource }).onChange((value: boolean) => { this.updateCalendarSource = value; })
          }.width('100%')
          Text('默认保留原日程；开启后仅更新没有完成记录或单次修改的日历来源事项。').fontSize(12).fontColor($r('app.color.text_secondary'))
        }
        Button({ type: ButtonType.Capsule }) { IconLabel('确认合并导入', $r('app.media.glyph_check_on_accent'), $r('app.color.on_accent')) }.height(46).width('100%').backgroundColor($r('app.color.accent'))
          .fontColor($r('app.color.on_accent')).onClick(() => this.confirmImport())
        Button({ type: ButtonType.Capsule }) { IconLabel('取消导入', $r('app.media.glyph_close'), $r('app.color.text_primary')) }.backgroundColor($r('app.color.card_background')).fontColor($r('app.color.text_secondary'))
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
          Button({ type: ButtonType.Capsule }) { IconLabel('恢复', $r('app.media.glyph_undo_on_accent'), $r('app.color.on_accent')) }.fontSize(12).height(36).backgroundColor($r('app.color.accent'))
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
              Image($r('app.media.glyph_drag')).width(22).height(22).accessibilityLevel('no')
              Text(task.title).fontSize(15).layoutWeight(1).maxLines(2).fontColor($r('app.color.text_primary'))
              Button({ type: ButtonType.Normal }) { Image($r('app.media.glyph_collapse_on_accent')).width(22).height(22).accessibilityLevel('no') }.width(36).height(38).padding(0).fontSize(18).accessibilityText('上移任务')
                .backgroundColor($r('app.color.accent')).fontColor($r('app.color.on_accent'))
                .enabled(this.sortIndex(task.id) > 0).onClick(() => this.shiftSort(task.id, -1))
              Button({ type: ButtonType.Normal }) { Image($r('app.media.glyph_expand_on_accent')).width(22).height(22).accessibilityLevel('no') }.width(36).height(38).padding(0).fontSize(18).accessibilityText('下移任务')
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
      if (page === 0) { Image(this.selectedTab === 0 ? $r('app.media.glyph_today_selected') : $r('app.media.glyph_today')).width(24).height(24).opacity(this.selectedTab === 0 ? 1 : 0.7) }
      else if (page === 1) { Image(this.selectedTab === 1 ? $r('app.media.glyph_todo_selected') : $r('app.media.glyph_todo')).width(24).height(24).opacity(this.selectedTab === 1 ? 1 : 0.7) }
      else if (page === 2) { Image(this.selectedTab === 2 ? $r('app.media.glyph_calendar_selected') : $r('app.media.glyph_calendar')).width(24).height(24).opacity(this.selectedTab === 2 ? 1 : 0.7) }
      else { Image(this.selectedTab === 3 ? $r('app.media.glyph_workbench_selected') : $r('app.media.glyph_workbench')).width(24).height(24).opacity(this.selectedTab === 3 ? 1 : 0.7) }
      Text(this.tabTitle(page)).fontSize(11).fontWeight(this.selectedTab === page ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.selectedTab === page ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
    }.height(60).width('100%').justifyContent(FlexAlign.Center).borderRadius(24)
      .backgroundColor(this.selectedTab === page ? $r('app.color.accent_soft') : Color.Transparent).accessibilityText(this.tabTitle(page))
  }

  @Builder
  rootPage(page: number) {
    Column() {
    if (this.showSearch) {
      Row() { Search({ value: this.query, placeholder: '搜索标题、备注、标签或地点' }).searchIcon({ src: $r('app.media.glyph_search'), size: 20 }).cancelButton({ style: CancelButtonStyle.INPUT, icon: { src: $r('app.media.glyph_close'), size: 18 } }).height(48).layoutWeight(1).id('globalSearch').onAppear(() => { this.getUIContext().getFocusController().requestFocus('globalSearch'); }).onChange((value: string) => { this.query = value; }).onSubmit(() => this.changeMode('search'))
        Button({ type: ButtonType.Capsule }) { IconLabel('搜索', $r('app.media.glyph_search_on_accent'), $r('app.color.on_accent')) }.height(48).backgroundColor($r('app.color.accent')).fontColor($r('app.color.on_accent')).onClick(() => this.changeMode('search'))
        Button({ type: ButtonType.Capsule }) { IconLabel('收起', $r('app.media.glyph_collapse'), $r('app.color.text_primary')) }.height(48).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).onClick(() => { this.setSearch(false); }) }.padding({ left: 20, right: 20 }).width('100%').transition(MotionService.entrance(this.preferences.reduceMotion))
    }
    Scroll() {
      Column({ space: 12 }) {
        if (this.searchPull > 0 && !this.showSearch) {
          Text(this.searchPull >= 28 ? '松开搜索' : '下拉搜索').fontSize(12).height(this.searchPull)
            .opacity(Math.min(1, this.searchPull / 28)).fontColor($r('app.color.text_secondary')).width('100%')
        }
        if (page === 0) { this.homePage() }
        else if (page === 1) {
          this.filters()
          this.listChips()
          this.section(false, this.view === 'inbox' ? '还没安排' : '待办', 1)
          Button((this.showTaskDone ? '收起' : '查看') + '已完成').height(48).width('100%').fontSize(13)
            .backgroundColor(Color.Transparent).fontColor($r('app.color.text_secondary')).onClick(() => { this.showTaskDone = !this.showTaskDone; if (this.view === 'inbox') { this.view = 'all'; } })
          if (this.showTaskDone) { this.section(true, '已完成', 1) }
        } else if (page === 2) {
          if (this.calendarUndoLabel) {
            Button('撤销时间调整 · ' + this.calendarUndoLabel).height(44).width('100%').onClick(() => this.undoCalendarAdjustment())
          }
          CalendarWorkspace({ reduceMotion: this.preferences.reduceMotion ?? false, tasks: this.tasks, states: this.states, selected: this.selectedDay, view: this.calendarView,
            weekStart: this.preferences.weekStart, snapMinutes: this.preferences.snapMinutes, now: this.now,
            onSelect: (day: string) => { this.selectedDay = day; this.month = day.slice(0, 7) + '-01'; },
            onAdjust: (item: TaskItem, days: number, minutes: number, resize: boolean) => this.adjustCalendar(item, days, minutes, resize),
            onView: (view: string) => { this.calendarView = view; }, onEdit: (item: TaskItem) => this.openDetail(item),
            onCreate: (day: string, minute: number) => { this.openEditor(); this.draftDueAt = ScheduleService.end(day); this.draftStart = minute; } })
            if (this.calendarView !== 'week' && this.calendarView !== 'day') {
            Text(this.selectedDay + ' · 当日事项').fontSize(13).fontColor($r('app.color.text_secondary')).width('100%')
            this.section(false, '待办', 2)
            this.section(true, '已完成', 2)
            }
        } else { this.workbenchPage() }
      }.width('100%').padding({ left: 20, right: 20, top: 8, bottom: 24 })
    }.width('100%').layoutWeight(1).align(Alignment.Top).scrollBar(BarState.Off)
      .onDidScroll((x: number, y: number) => { this.rootOffsets[page] = Math.max(0, this.rootOffsets[page] + y); })
      .parallelGesture(PanGesture({ direction: PanDirection.Vertical }).onActionStart(() => { this.pullStartTop = this.rootOffsets[page] <= 1 && !(page === 2 && (this.calendarView === 'day' || this.calendarView === 'week')); }).onActionUpdate((event: GestureEvent) => { if (this.pullStartTop && !this.showSearch) { this.searchPull = Math.max(0, Math.min(40, event.offsetY * 0.4)); } }).onActionEnd((event: GestureEvent) => { if (this.pullStartTop && event.offsetY > 70) { this.setSearch(true); } else { this.animate(() => { this.searchPull = 0; }); } }).onActionCancel(() => this.animate(() => { this.searchPull = 0; })))
    if (page !== 3) {
      Button({ type: ButtonType.Capsule }) { IconLabel('记一件事', $r('app.media.glyph_plus_on_accent'), $r('app.color.on_accent'), 16) }.height(52).width('90%').fontSize(16).fontWeight(FontWeight.Medium)
        .backgroundColor($r('app.color.accent')).fontColor($r('app.color.on_accent')).margin({ top: 8, bottom: 8 })
        .enabled(!this.busy).onClick(() => { this.showCapture = true; })
    }
    }.width('100%').height('100%').padding({ bottom: MaterialService.nativeDock(this.preferences.useMaterial) ? 92 : 0 })
  }

  @Builder
  subpageFooter() {
    if (this.mode === 'batch') {
      Row({ space: 8 }) {
        Button({ type: ButtonType.Capsule }) { IconLabel('取消', $r('app.media.glyph_close'), $r('app.color.text_primary')) }.height(48).fontSize(13).padding({ left: 12, right: 12 }).backgroundColor($r('app.color.card_background'))
          .fontColor($r('app.color.text_primary')).onClick(() => this.closeSubpage())
        Button({ type: ButtonType.Capsule }) { IconLabel('设为待办', $r('app.media.glyph_task_open'), $r('app.color.text_primary')) }.height(48).fontSize(13).layoutWeight(1).padding(4).backgroundColor($r('app.color.card_background'))
          .fontColor($r('app.color.text_primary')).enabled(this.batchKeys.length > 0).onClick(() => this.applyBatch(false))
        Button({ type: ButtonType.Capsule }) { IconLabel('设为完成', $r('app.media.glyph_task_done_on_accent'), $r('app.color.on_accent')) }.height(48).fontSize(13).layoutWeight(1).padding(4).backgroundColor($r('app.color.accent'))
          .fontColor($r('app.color.on_accent')).enabled(this.batchKeys.length > 0).onClick(() => this.applyBatch(true))
      }.width('100%').enabled(!this.busy).padding({ left: 20, right: 20, top: 8, bottom: 12 })
    } else if (this.mode === 'editor' || this.mode === 'sort') {
      Row({ space: 10 }) {
        Button({ type: ButtonType.Capsule }) { IconLabel('取消', $r('app.media.glyph_close'), $r('app.color.text_primary')) }.layoutWeight(1).height(48).backgroundColor($r('app.color.card_background'))
          .fontColor($r('app.color.text_primary')).onClick(() => this.closeSubpage())
        Button({ type: ButtonType.Capsule }) { IconLabel(this.busy ? '保存中…' : this.mode === 'sort' ? '保存顺序' : '保存任务', $r('app.media.glyph_check_on_accent'), $r('app.color.on_accent')) }.layoutWeight(1).height(48)
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
          Button({ type: ButtonType.Normal }) { Image($r('app.media.glyph_back')).width(22).height(22).accessibilityLevel('no') }.width(44).height(44).padding(0).fontSize(30).backgroundColor(Color.Transparent)
            .fontColor($r('app.color.text_primary')).accessibilityText('返回')
            .enabled(!this.busy).onClick(() => this.closeSubpage())
        }
        Column({ space: 5 }) {
          Text(this.pageTitle()).fontSize(this.mode === 'list' ? 30 : 23).fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
          if (this.mode === 'list') {
            Text(this.selectedTab === 0 ? this.dateTitle() : this.selectedTab === 1 ? '整理任务，安排下一步' :
              this.selectedTab === 2 ? '查看每一天的安排' : '智能安排与个人工具')
              .fontSize(12).fontColor($r('app.color.text_secondary'))
          }
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        if (this.mode === 'list') {
          Button({ type: ButtonType.Normal }) { Image($r('app.media.icon_settings')).width(24).height(24) }
            .width(48).height(48).borderRadius(24).backgroundColor($r('app.color.card_background')).accessibilityText('设置').onClick(() => this.changeMode('settings'))
        }
      }.width('100%').padding({ left: this.mode === 'list' ? 20 : 8, right: 20, top: 16, bottom: 14 }).parallelGesture(PanGesture({ direction: PanDirection.Vertical }).onActionUpdate((event: GestureEvent) => { if (this.mode === 'list' && !this.showSearch) { this.searchPull = Math.max(0, Math.min(40, event.offsetY * 0.4)); } }).onActionEnd((event: GestureEvent) => { if (this.mode === 'list' && event.offsetY > 60) { this.setSearch(true); } else { this.animate(() => { this.searchPull = 0; }); } }).onActionCancel(() => this.animate(() => { this.searchPull = 0; })))
      if (this.error.length > 0) {
        Text(this.error).fontSize(13).fontColor($r('app.color.danger')).width('100%').padding({ left: 20, right: 20, bottom: 8 })
      }
      if (this.notice.length > 0) {
        Text(this.notice).fontSize(12).fontColor($r('app.color.text_secondary')).width('100%').padding({ left: 20, right: 20, bottom: 8 })
      }
      if (this.capturedId.length > 0 && this.mode === 'list') {
        Button({ type: ButtonType.Capsule }) { IconLabel('刚记下的任务 · 安排今天', $r('app.media.glyph_plan_date')) }.height(48).fontSize(13).backgroundColor($r('app.color.card_background')).fontColor($r('app.color.text_primary'))
          .onClick(() => this.arrangeCaptured())
      }
      if (this.undoTitle.length > 0) {
        Row({ space: 8 }) {
          Text('已删除：' + this.undoTitle).fontSize(12).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1).fontColor($r('app.color.text_primary'))
          Button({ type: ButtonType.Capsule }) { IconLabel('撤销', $r('app.media.glyph_undo'), $r('app.color.text_primary')) }.height(40).fontSize(13).padding(8).backgroundColor(Color.Transparent)
            .fontColor($r('app.color.text_primary')).enabled(!this.busy).onClick(() => this.undoDelete())
          Button({ type: ButtonType.Normal }) { Image($r('app.media.glyph_close')).width(22).height(22).accessibilityLevel('no') }.height(40).width(40).padding(0).backgroundColor(Color.Transparent)
            .fontColor($r('app.color.text_secondary')).accessibilityText('关闭撤销提示')
            .onClick(() => { this.undoTitle = ''; this.deletedBackup = undefined; })
        }.padding({ left: 16, right: 8 }).margin({ left: 20, right: 20, bottom: 8 })
          .borderRadius(12).backgroundColor($r('app.color.card_background'))
      }
      if (!this.ready) {
        Blank()
        Text(this.busy ? '正在读取任务…' : '暂时无法读取任务').fontColor($r('app.color.text_secondary'))
        if (!this.busy) { Button({ type: ButtonType.Capsule }) { IconLabel('重新读取', $r('app.media.glyph_refresh'), $r('app.color.text_primary')) }.onClick(() => this.load()) }
        Blank()
      } else if (this.mode === 'list') {
        Tabs({ barPosition: BarPosition.End, index: this.selectedTab }) {
          TabContent() { this.rootPage(0) }.tabBar(this.tabLabel(0))
          TabContent() { this.rootPage(1) }.tabBar(this.tabLabel(1))
          TabContent() { this.rootPage(2) }.tabBar(this.tabLabel(2))
          TabContent() { this.rootPage(3) }.tabBar(this.tabLabel(3))
        }.layoutWeight(1).width('100%').barHeight(MaterialService.nativeDock(this.preferences.useMaterial) ? 72 : 0)
          .barOverlap(MaterialService.nativeDock(this.preferences.useMaterial))
          .barBackgroundColor(Color.Transparent)
          .barFloatingStyle(MaterialService.nativeDock(this.preferences.useMaterial) ? { barSideMargin: 16, barBottomMargin: 12,
            systemMaterial: MaterialService.dock(this.preferences.useMaterial, MotionService.reduced(this.preferences.reduceMotion)),
            maskColor: $r('app.color.page_background'), maskHeight: 24 } : undefined)
          .animationDuration(MotionService.reduced(this.preferences.reduceMotion) ? 0 : 260).barMode(BarMode.Fixed).scrollable(false)
          .backgroundColor($r('app.color.page_background'))
          .onChange((index: number) => { this.animate(() => { this.selectedTab = index; }); this.now = Date.now(); this.error = ''; this.notice = ''; })
        if (!MaterialService.nativeDock(this.preferences.useMaterial)) { this.floatingDock() }
      } else {
        if (this.mode === 'sort') {
          Column() { this.sortingPage() }.layoutWeight(1).width('100%').padding({ left: 20, right: 20 })
        } else {
          Scroll(this.scroller) {
            Column({ space: 12 }) {
              if (this.mode === 'editor') { Column({ space: 12 }) { this.editor() }.width('100%').transition(MotionService.entrance(this.preferences.reduceMotion)) }
              else if (this.mode === 'plan') { Column({ space: 12 }) { this.planPage() }.width('100%').transition(MotionService.entrance(this.preferences.reduceMotion)) }
              else if (this.mode === 'settings') { Column({ space: 12 }) { this.settingsPage() }.width('100%').transition(MotionService.entrance(this.preferences.reduceMotion)) }
              else if (this.mode === 'appearance') { Column({ space: 12 }) { this.appearancePage() }.width('100%').transition(MotionService.entrance(this.preferences.reduceMotion)) }
              else if (this.mode === 'preferences') { Column({ space: 12 }) { this.preferenceSettings() }.width('100%').transition(MotionService.entrance(this.preferences.reduceMotion)) }
              else if (this.mode === 'notifications') { Column({ space: 12 }) { this.notificationsPage() }.width('100%').transition(MotionService.entrance(this.preferences.reduceMotion)) }
              else if (this.mode === 'features') { Column({ space: 12 }) { ProductSettings({ state: this.product, onSave: (value: ProductState) => this.saveProduct(value), onOpen: () => this.changeMode('product') }) }.width('100%').transition(MotionService.entrance(this.preferences.reduceMotion)) }
              else if (this.mode === 'about') { Column({ space: 12 }) { this.aboutPage() }.width('100%').transition(MotionService.entrance(this.preferences.reduceMotion)) }
              else if (this.mode === 'detail') { Column({ space: 12 }) { this.detailPage() }.width('100%').transition(MotionService.entrance(this.preferences.reduceMotion)) }
              else if (this.mode === 'aiConfig') { Column({ space: 12 }) { SmartEntry({ useMaterial: this.preferences.useMaterial, configOnly: true }) }.width('100%').transition(MotionService.entrance(this.preferences.reduceMotion)) }
              else if (this.mode === 'product') { Column({ space: 12 }) { ProductTools({ useMaterial: this.preferences.useMaterial, initialTab: this.productTab, state: this.product, tasks: this.tasks, reminderStatus: this.reminderStatus, onSave: (value: ProductState) => this.saveProduct(value) }) }.width('100%').transition(MotionService.entrance(this.preferences.reduceMotion)) }
              else if (this.mode === 'classification') { Column({ space: 12 }) { ClassificationPanel({ useMaterial: this.preferences.useMaterial, tasks: this.tasks, onRename: (kind: string, from: string, to: string) => this.renameClassification(kind, from, to) }) }.width('100%').transition(MotionService.entrance(this.preferences.reduceMotion)) }
              else if (this.mode === 'quick') { Column({ space: 12 }) { SmartEntry({ useMaterial: this.preferences.useMaterial, initialText: this.quickText, saving: this.busy, onOpenConfig: () => this.changeMode('aiConfig'), onTextChange: (value: string) => { this.quickText = value; }, onEdit: (draft: TaskDraft) => this.editSmartDraft(draft), onSave: (drafts: TaskDraft[]) => this.saveSmartDrafts(drafts) }) }.width('100%').transition(MotionService.entrance(this.preferences.reduceMotion)) }
              else if (this.mode === 'search') { Column({ space: 12 }) { this.searchPage() }.width('100%').transition(MotionService.entrance(this.preferences.reduceMotion)) }
              else if (this.mode === 'tools') { Column({ space: 12 }) { this.toolsPage() }.width('100%').transition(MotionService.entrance(this.preferences.reduceMotion)) }
              else if (this.mode === 'batch') { Column({ space: 12 }) { this.batchPage() }.width('100%').transition(MotionService.entrance(this.preferences.reduceMotion)) }
            }.width('100%').padding({ left: 20, right: 20, top: 8, bottom: 24 })
          }.layoutWeight(1).width('100%').align(Alignment.Top).transition(MotionService.entrance(this.preferences.reduceMotion))
        }
        this.subpageFooter()
      }
    }.width('100%').height('100%').backgroundColor($r('app.color.page_background'))
      .bindSheet($$this.showCapture, this.captureSheet(), { height: 380, showClose: true, keyboardAvoidMode: SheetKeyboardAvoidMode.TRANSLATE_AND_RESIZE,
        backgroundColor: $r('app.color.card_background'), systemMaterial: MaterialService.surface(this.preferences.useMaterial) })
  }
}
