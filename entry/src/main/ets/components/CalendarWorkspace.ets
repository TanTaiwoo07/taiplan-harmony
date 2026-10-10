import { Task, TaskItem, OccurrenceState } from '../model/Task';
import { ScheduleService } from '../services/ScheduleService';
import { CalendarService } from '../services/CalendarService';
import { MonthCalendar } from './MonthCalendar';
import { TimeTable } from './TimeTable';

@Component
export struct CalendarWorkspace {
  @Prop tasks: Task[] = [];
  @Prop states: OccurrenceState[] = [];
  @Prop selected: string = '';
  @Prop view: string = 'month';
  @Prop weekStart: number = 1;
  @Prop snapMinutes: number = 15;
  @Prop now: number = Date.now();
  onSelect: (day: string) => void = () => {};
  onView: (view: string) => void = () => {};
  onEdit: (item: TaskItem) => void = () => {};
  onAdjust: (item: TaskItem, days: number, minutes: number, resize: boolean) => void = () => {};
  onCreate: (day: string, minute: number) => void = () => {};
  private dateItems(day: string): TaskItem[] {
    return ScheduleService.project(this.tasks, this.states, 'calendar', day, this.now).filter((item: TaskItem) => (item.task.startMinute ?? -1) < 0);
  }
  private shift(delta: number): void {
    const date = ScheduleService.date(this.selected);
    if (this.view === 'year') { date.setFullYear(date.getFullYear() + delta); }
    else if (this.view === 'month') { date.setDate(1); date.setMonth(date.getMonth() + delta); }
    else { date.setDate(date.getDate() + delta * (this.view === 'week' ? 7 : 1)); }
    if (date.getFullYear() >= 2000 && date.getFullYear() <= 2100) { this.onSelect(ScheduleService.key(date.getTime())); }
  }
  build() {
    Column({ space: 12 }) {
      Row({ space: 4 }) {
        ForEach(['year', 'month', 'week', 'day'], (view: string) => {
          Button(view === 'year' ? '年' : view === 'month' ? '月' : view === 'week' ? '周' : '日').height(44).layoutWeight(1)
            .backgroundColor(this.view === view ? $r('app.color.accent') : $r('app.color.card_background'))
            .fontColor(this.view === view ? $r('app.color.on_accent') : $r('app.color.text_primary')).onClick(() => this.onView(view))
        })
      }.width('100%')
      if (this.view !== 'month') {
        Row() {
          Button('‹').width(48).height(48).fontSize(26).padding(0).backgroundColor(Color.Transparent)
            .fontColor($r('app.color.text_primary')).accessibilityText('上一' + this.view).onClick(() => this.shift(-1))
          Text(this.view === 'year' ? this.selected.slice(0, 4) + '年' : this.selected).layoutWeight(1).textAlign(TextAlign.Center)
            .fontSize(17).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
          Button('今天').height(48).fontSize(12).backgroundColor(Color.Transparent).fontColor($r('app.color.text_primary'))
            .onClick(() => this.onSelect(ScheduleService.key(this.now)))
          Button('›').width(48).height(48).fontSize(26).padding(0).backgroundColor(Color.Transparent)
            .fontColor($r('app.color.text_primary')).accessibilityText('下一' + this.view).onClick(() => this.shift(1))
        }.width('100%')
      }
      if (this.view === 'year') {
        Grid() {
          ForEach([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12], (month: number) => {
            GridItem() {
              Button(month.toString() + '月', { type: ButtonType.Normal }).width('100%').height(80).borderRadius(16)
                .fontSize(20).backgroundColor($r('app.color.card_background')).fontColor($r('app.color.text_primary'))
                .onClick(() => { this.onSelect(this.selected.slice(0, 4) + '-' + month.toString().padStart(2, '0') + '-01'); this.onView('month'); })
            }
          })
        }.columnsTemplate('1fr 1fr 1fr').rowsGap(10).columnsGap(10).height(360)
      } else if (this.view === 'month') {
        MonthCalendar({ days: ScheduleService.month(this.tasks, this.states, this.selected, this.weekStart), selected: this.selected,
          month: this.selected.slice(0, 7), weekStart: this.weekStart,
          onSelect: (day: string) => this.onSelect(day), onMonth: (delta: number) => this.shift(delta),
          onToday: () => this.onSelect(ScheduleService.key(this.now)) })
        Button('查看 ' + this.selected.slice(5) + ' 的时间表').height(48).width('100%').fontSize(13)
          .backgroundColor($r('app.color.card_background')).fontColor($r('app.color.text_primary')).onClick(() => this.onView('day'))
      } else {
        ForEach([this.selected], (day: string) => {
          if (this.dateItems(day).length > 0) {
            Column({ space: 6 }) {
              Text(day.slice(5) + ' · 选中日的无时间事项').fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
              ForEach(this.dateItems(day), (item: TaskItem) => {
                Button((item.task.planning?.kind === 'event' ? '全天事件 · ' : '任务 · ') + item.task.title, { type: ButtonType.Normal })
                  .height(48).width('100%').fontSize(13).borderRadius(12).backgroundColor($r('app.color.card_background'))
                  .fontColor($r('app.color.text_primary')).onClick(() => this.onEdit(item))
              }, (item: TaskItem) => ScheduleService.renderKey(item))
            }.width('100%')
          }
        }, (day: string) => day)
        ForEach([this.view], (view: string) => {
          TimeTable({ tasks: this.tasks, states: this.states, snapMinutes: this.snapMinutes, days: CalendarService.days(this.selected, view, this.weekStart),
            selected: this.selected, now: this.now, onEdit: this.onEdit, onCreate: this.onCreate, onAdjust: this.onAdjust, onSelect: this.onSelect })
        }, (view: string) => view)
      }
    }.width('100%')
  }
}
