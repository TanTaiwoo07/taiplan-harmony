import { ProductState, FocusSession, Habit, Countdown } from '../model/Product';
import { Task } from '../model/Task';
import { ProductService } from '../services/ProductService';
import { PlanningService } from '../services/PlanningService';
import { util } from '@kit.ArkTS';

@Component
export struct ProductTools {
  @Prop state: ProductState = ProductService.defaults();
  @Prop tasks: Task[] = [];
  @Prop reminderStatus: string = '';
  onSave: (state: ProductState) => Promise<void> = async () => {};
  @State private tab: string = 'focus';
  @State private now: number = Date.now();
  @State private busy: boolean = false;
  @State private error: string = '';
  @State private title: string = '';
  @State private editing: string = '';
  @State private weekdays: number[] = [1, 2, 3, 4, 5, 6, 7];
  @State private weeklyTarget: number = 0;
  @State private dailyTarget: number = 1;
  @State private selectedDate: string = PlanningService.key(Date.now());
  @State private annual: boolean = false;
  @State private category: string = '';
  @State private related: string = '';
  @State private deleted: Countdown | undefined = undefined;
  private timer: number = -1;

  aboutToAppear(): void {
    this.tab = this.state.features.focus ? 'focus' : this.state.features.habits ? 'habits' : 'countdowns';
    this.timer = setInterval(() => { this.now = Date.now(); }, 1000);
  }
  aboutToDisappear(): void { if (this.timer !== -1) { clearInterval(this.timer); } }
  private async commit(next: ProductState): Promise<void> {
    if (this.busy) { return; } this.busy = true; this.error = '';
    try { ProductService.validate(next); await this.onSave(next); }
    catch (error) { this.error = (error as Error).message; throw error as Error; }
    finally { this.busy = false; }
  }
  private active(): FocusSession | undefined { return ProductService.active(this.state); }
  private async action(action: string): Promise<void> {
    try { await this.commit(ProductService.transition(this.state, action, Date.now())); } catch (error) { this.error = (error as Error).message; }
  }
  private async start(phase: string): Promise<void> {
    const task = this.tasks.find((item: Task) => item.id === this.related);
    try { await this.commit(ProductService.start(this.state, util.generateRandomUUID(), task?.title ?? (phase === 'work' ? '自由专注' : '休息'),
      task?.id ?? '', phase, Date.now())); } catch (error) { this.error = (error as Error).message; }
  }
  private remaining(): string {
    const session = this.active(); if (!session) { return this.state.focusOptions.work.toString() + ':00'; }
    const seconds = session.targetSeconds - ProductService.elapsed(session, this.now);
    return Math.floor(seconds / 60).toString().padStart(2, '0') + ':' + (seconds % 60).toString().padStart(2, '0');
  }
  private breakPhase(): string {
    const finished = this.state.sessions.filter((item: FocusSession) => item.phase === 'work' && item.status === 'finished').length;
    return finished > 0 && finished % this.state.focusOptions.cycles === 0 ? 'long' : 'short';
  }
  private minutes(): number {
    return Math.floor(this.state.sessions.filter((item: FocusSession) => item.phase === 'work').reduce((sum: number, item: FocusSession) => sum + ProductService.elapsed(item, this.now), 0) / 60);
  }
  private taskOptions(): SelectOption[] {
    const options: SelectOption[] = [{ value: '不关联任务' }];
    return options.concat(this.tasks.filter((task: Task) => !task.completed && task.planning?.kind !== 'event').map((task: Task): SelectOption => { return { value: task.title }; }));
  }
  private pickDate(): void {
    const selected = PlanningService.date(this.selectedDate);
    this.getUIContext().showDatePickerDialog({ start: new Date(2000, 0, 1), end: new Date(2100, 11, 31), selected: selected,
      onAccept: (result: DatePickerResult) => { this.selectedDate = PlanningService.key(new Date(result.year ?? selected.getFullYear(), result.month ?? selected.getMonth(), result.day ?? selected.getDate(), 12).getTime()); } });
  }
  private async saveHabit(): Promise<void> {
    try {
      const next = ProductService.clone(this.state);
      // Rules are immutable once created, keeping historical streaks meaningful.
      next.habits.push({ id: util.generateRandomUUID(), title: this.title.trim(), createdDate: this.selectedDate, weekdays: this.weekdays.slice(),
        weeklyTarget: this.weeklyTarget, dailyTarget: this.dailyTarget, checks: [] });
      if (this.selectedDate > PlanningService.key(this.now)) { throw new Error('习惯开始日期不能晚于今天'); }
      await this.commit(next); this.title = '';
    } catch (error) { this.error = (error as Error).message; }
  }
  private async check(habit: Habit, add: boolean): Promise<void> {
    try { await this.commit(ProductService.check(this.state, habit.id, this.selectedDate, add, Date.now())); }
    catch (error) { this.error = (error as Error).message; }
  }
  private async saveCountdown(): Promise<void> {
    try {
      const next = ProductService.clone(this.state); const old = next.countdowns.find((item: Countdown) => item.id === this.editing);
      const item: Countdown = { id: old?.id ?? util.generateRandomUUID(), title: this.title.trim(), date: this.selectedDate,
        annual: this.annual, pinned: old?.pinned ?? false, category: this.category.trim(), reminderDays: old?.reminderDays ?? -1 };
      next.countdowns = next.countdowns.filter((entry: Countdown) => entry.id !== item.id).concat([item]);
      await this.commit(next); this.title = ''; this.editing = '';
    } catch (error) { this.error = (error as Error).message; }
  }
  private async pin(item: Countdown): Promise<void> {
    const next = ProductService.clone(this.state); const target = next.countdowns.find((entry: Countdown) => entry.id === item.id);
    if (target) { target.pinned = !target.pinned; }
    try { await this.commit(next); } catch {}
  }
  private async reminder(id: string, habit: boolean): Promise<void> {
    const next = ProductService.clone(this.state);
    if (habit) { const target = next.habits.find((item: Habit) => item.id === id);
      if (target) { target.reminderMinute = target.reminderMinute === 480 ? 720 : target.reminderMinute === 720 ? 1200 : target.reminderMinute === 1200 ? -1 : 480; } }
    else { const target = next.countdowns.find((item: Countdown) => item.id === id);
      if (target) { target.reminderDays = target.reminderDays === 0 ? 1 : target.reminderDays === 1 ? 3 : target.reminderDays === 3 ? 7 : target.reminderDays === 7 ? -1 : 0; } }
    try { await this.commit(next); } catch {}
  }
  private remove(id: string, habit: boolean): void {
    this.getUIContext().showAlertDialog({ title: habit ? '删除习惯和打卡记录？' : '删除倒数日？', message: habit ? '请先备份需要保留的历史。' : '删除后可撤销最近一次操作。',
      primaryButton: { value: '取消', action: () => {} }, secondaryButton: { value: '删除', action: async () => {
        const next = ProductService.clone(this.state); const removed = next.countdowns.find((entry: Countdown) => entry.id === id);
        if (habit) { next.habits = next.habits.filter((item: Habit) => item.id !== id); }
        else { next.countdowns = next.countdowns.filter((item: Countdown) => item.id !== id); }
        try { await this.commit(next); if (!habit) { this.deleted = removed; } } catch {}
      } } });
  }
  private async undo(): Promise<void> {
    if (!this.deleted || this.state.countdowns.some((item: Countdown) => item.id === this.deleted?.id)) { return; }
    const next = ProductService.clone(this.state); next.countdowns.push(this.deleted);
    try { await this.commit(next); this.deleted = undefined; } catch {}
  }
  private async removeSession(id: string): Promise<void> {
    const next = ProductService.clone(this.state);
    if (ProductService.active(next)?.id === id) { return; }
    next.sessions = next.sessions.filter((item: FocusSession) => item.id !== id);
    try { await this.commit(next); } catch {}
  }
  private countdowns(): Countdown[] {
    return this.state.countdowns.slice().sort((a: Countdown, b: Countdown) => Number(b.pinned) - Number(a.pinned) ||
      ProductService.nextDate(a, PlanningService.key(this.now)).localeCompare(ProductService.nextDate(b, PlanningService.key(this.now))));
  }
  private dayLabel(item: Countdown): string {
    const days = ProductService.days(item, PlanningService.key(this.now));
    return days === 0 ? '就是今天' : days > 0 ? '还有 ' + days.toString() + ' 天' : '已经 ' + Math.abs(days).toString() + ' 天';
  }
  @Builder
  focusPage() {
    Text(this.active()?.title ?? '给一件事留一段时间').fontSize(19).fontColor($r('app.color.text_primary')).width('100%')
    Text(this.remaining()).fontSize(56).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).width('100%').textAlign(TextAlign.Center)
    if (this.active()) {
      Text((this.active()?.phase === 'work' ? '专注' : '休息') + ' · ' + (this.active()?.status === 'paused' ? '已暂停' : this.remaining() === '00:00' ? '时间到，请结束本次' : '进行中'))
        .fontColor($r('app.color.text_secondary'))
      Row({ space: 8 }) {
        Button(this.remaining() === '00:00' ? '完成本次' : this.active()?.status === 'paused' ? '继续' : '暂停').height(48).fontSize(14).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).layoutWeight(1)
          .onClick(() => this.action(this.remaining() === '00:00' ? 'finish' : this.active()?.status === 'paused' ? 'resume' : 'pause'))
        Button('结束并保留记录').height(48).fontSize(14).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).layoutWeight(1).onClick(() => this.action('abandon'))
      }
    } else {
      Select(this.taskOptions())
        .value(this.tasks.find((task: Task) => task.id === this.related)?.title ?? '不关联任务')
        .onSelect((index: number) => { this.related = index === 0 ? '' : this.tasks.filter((task: Task) => !task.completed && task.planning?.kind !== 'event')[index - 1].id; })
      Row({ space: 8 }) {
        Button('开始专注').height(48).fontSize(14).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).layoutWeight(1).onClick(() => this.start('work'))
        Button(this.breakPhase() === 'long' ? '长休息' : '短休息').height(48).fontSize(14).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).layoutWeight(1).onClick(() => this.start(this.breakPhase()))
      }
    }
    Text('累计有效专注 ' + this.minutes().toString() + ' 分钟 · 不会自动完成关联任务').fontSize(13).fontColor($r('app.color.text_secondary'))
    Text('计时可在退出后恢复。系统提醒需在设置中成功登记；未登记时请勿依赖后台响铃。修改系统时间会影响墙上时钟计时，倒退期间不累计新增时长。').fontSize(12).fontColor($r('app.color.text_secondary'))
    ForEach(this.state.sessions.slice().reverse().slice(0, 20), (session: FocusSession) => {
      Row({ space: 6 }) {
      Text(session.title + ' · ' + (session.phase === 'work' ? '专注' : '休息') + ' ' + Math.floor(ProductService.elapsed(session, this.now) / 60).toString() + ' 分钟 · ' +
        (session.status === 'finished' ? '完成' : session.status === 'abandoned' ? '提前结束' : session.status === 'paused' ? '暂停' : '进行中'))
        .fontSize(13).fontColor($r('app.color.text_secondary')).layoutWeight(1).padding(10)
      if (session.status === 'finished' || session.status === 'abandoned') {
        Button('删除记录').height(48).fontSize(12).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_secondary')).onClick(() => {
          this.getUIContext().showAlertDialog({ title: '删除这条专注记录？', message: session.title + '，删除后不能撤销。',
            primaryButton: { value: '取消', action: () => {} }, secondaryButton: { value: '删除', action: () => this.removeSession(session.id) } });
        })
      }
      }.width('100%')
    }, (session: FocusSession) => session.id + session.status)
  }
  @Builder
  habitPage() {
    Text('打卡日期 · ' + this.selectedDate).fontSize(15).fontColor($r('app.color.text_primary'))
    Button('选择日期 / 补打').height(48).fontSize(14).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).onClick(() => this.pickDate())
    ForEach(this.state.habits, (habit: Habit) => {
      Column({ space: 8 }) {
        Text(habit.title).fontSize(18).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).width('100%')
        Button((habit.reminderMinute ?? -1) < 0 ? '提醒：关闭' : '提醒：' + Math.floor((habit.reminderMinute ?? 0) / 60).toString() + ':00').height(44).fontSize(13).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).onClick(() => this.reminder(habit.id, true))
        Text(habit.weeklyTarget > 0 ? '本周完成 ' + ProductService.weekCount(habit, PlanningService.key(this.now)).toString() + ' / ' + habit.weeklyTarget.toString() + ' 天' :
          '连续 ' + ProductService.streak(habit, PlanningService.key(this.now)).toString() + ' 个应打卡日 · 周' + habit.weekdays.join('、'))
          .fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
        Row({ space: 8 }) {
          Button('打卡 ' + ProductService.count(habit, this.selectedDate).toString() + '/' + habit.dailyTarget.toString()).height(48).fontSize(14).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary'))
            .enabled(ProductService.scheduled(habit, this.selectedDate) && ProductService.count(habit, this.selectedDate) < habit.dailyTarget && this.selectedDate <= PlanningService.key(this.now))
            .onClick(() => this.check(habit, true))
          Button('撤销一次').height(48).fontSize(14).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).enabled(ProductService.count(habit, this.selectedDate) > 0).onClick(() => this.check(habit, false))
          Button('删除').height(48).fontSize(14).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).onClick(() => this.remove(habit.id, true))
        }
        Text('近期记录：' + habit.checks.slice().sort((a, b) => b.date.localeCompare(a.date)).slice(0, 7).map((check) => check.date + ' ×' + check.count.toString()).join(' · '))
          .fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
      }.padding(16).borderRadius(16).backgroundColor($r('app.color.card_background')).width('100%')
    }, (habit: Habit) => JSON.stringify(habit))
    Text('新建习惯 · 以所选日期开始').fontSize(17).fontColor($r('app.color.text_primary'))
    TextInput({ text: this.title, placeholder: '例如：每天读书' }).maxLength(100).height(48).fontSize(14).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).onChange((value: string) => { this.title = value; })
    Button(this.weeklyTarget === 0 ? '指定星期' : '每周 ' + this.weeklyTarget.toString() + ' 天').height(48).fontSize(14).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary'))
      .onClick(() => { this.weeklyTarget = (this.weeklyTarget + 1) % 8; })
    if (this.weeklyTarget === 0) {
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach([1, 2, 3, 4, 5, 6, 7], (day: number) => {
          Button((this.weekdays.includes(day) ? '✓ ' : '') + '周' + day.toString()).height(44).fontSize(13).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).margin(3)
            .onClick(() => { this.weekdays = this.weekdays.includes(day) ? this.weekdays.filter((entry: number) => entry !== day) : this.weekdays.concat([day]); })
        })
      }
    }
    Button('每天目标 ' + this.dailyTarget.toString() + ' 次').height(48).fontSize(14).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).onClick(() => { this.dailyTarget = this.dailyTarget % 10 + 1; })
    Button('创建习惯').height(48).fontSize(14).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).enabled(this.title.trim().length > 0).onClick(() => this.saveHabit())
    Text('规则创建后固定，避免改写历史统计；需要变更时可新建习惯。打卡日期可选过去日期，不能选未来。').fontSize(12).fontColor($r('app.color.text_secondary'))
  }
  @Builder
  countdownPage() {
    ForEach(this.countdowns(), (item: Countdown) => {
      Column({ space: 10 }) {
        Text((item.pinned ? '置顶 · ' : '') + item.title).fontSize(18).fontColor($r('app.color.text_primary')).width('100%')
        Text(this.dayLabel(item)).fontSize(28).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).width('100%')
        Button((item.reminderDays ?? -1) < 0 ? '提醒：关闭' : '提前 ' + item.reminderDays?.toString() + ' 天 09:00 提醒').height(44).fontSize(13).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).onClick(() => this.reminder(item.id, false))
        Text(ProductService.nextDate(item, PlanningService.key(this.now)) + (item.annual ? ' · 每年' : '') + (item.category ? ' · ' + item.category : ''))
          .fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
        Row({ space: 8 }) {
          Button('编辑').height(48).fontSize(14).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).onClick(() => { this.editing = item.id; this.title = item.title; this.selectedDate = item.date; this.annual = item.annual; this.category = item.category; })
          Button(item.pinned ? '取消置顶' : '置顶').height(48).fontSize(14).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).onClick(() => this.pin(item))
          Button('删除').height(48).fontSize(14).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).onClick(() => this.remove(item.id, false))
        }
      }.padding(16).borderRadius(16).backgroundColor($r('app.color.card_background')).width('100%')
    }, (item: Countdown) => JSON.stringify(item))
    if (this.deleted) { Button('撤销删除：' + this.deleted.title).height(48).fontSize(14).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).onClick(() => this.undo()) }
    Text(this.editing ? '编辑倒数日' : '新建倒数日').fontSize(18).fontColor($r('app.color.text_primary'))
    TextInput({ text: this.title, placeholder: '名称' }).maxLength(100).height(48).fontSize(14).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).onChange((value: string) => { this.title = value; })
    TextInput({ text: this.category, placeholder: '分类（可选）' }).maxLength(30).height(48).fontSize(14).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).onChange((value: string) => { this.category = value; })
    Button('日期 · ' + this.selectedDate).height(48).fontSize(14).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).onClick(() => this.pickDate())
    Button(this.annual ? '每年纪念日' : '单次日期').height(48).fontSize(14).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).onClick(() => { this.annual = !this.annual; })
    Button(this.editing ? '保存修改' : '添加倒数日').height(48).fontSize(14).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).enabled(this.title.trim().length > 0).onClick(() => this.saveCountdown())
    if (this.editing) { Button('取消编辑').height(48).fontSize(14).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).onClick(() => { this.editing = ''; this.title = ''; }) }
    Text('公历日期差，今天为 0 天；2 月 29 日纪念日在平年按 2 月 28 日显示。').fontSize(12).fontColor($r('app.color.text_secondary'))
  }
  build() {
    Column({ space: 12 }) {
      Row({ space: 6 }) {
        if (this.state.features.focus) { Button('专注').height(48).fontSize(14).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).layoutWeight(1).onClick(() => { this.tab = 'focus'; this.title = ''; }) }
        if (this.state.features.habits) { Button('习惯').height(48).fontSize(14).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).layoutWeight(1).onClick(() => { this.tab = 'habits'; this.title = ''; this.selectedDate = PlanningService.key(this.now); }) }
        if (this.state.features.countdowns) { Button('倒数日').height(48).fontSize(14).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).layoutWeight(1).onClick(() => { this.tab = 'countdowns'; this.title = ''; this.editing = ''; }) }
      }.width('100%')
      if (this.error) { Text(this.error).fontColor($r('app.color.danger')).fontSize(13).width('100%') }
      Text(this.reminderStatus + '。逻辑提醒开关不等于系统已登记，失败请到设置重试。').fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
      if (this.tab === 'focus' && this.state.features.focus) { this.focusPage() }
      else if (this.tab === 'habits' && this.state.features.habits) { this.habitPage() }
      else if (this.tab === 'countdowns' && this.state.features.countdowns) { this.countdownPage() }
    }.width('100%').enabled(!this.busy)
  }
}
