import { Task, TaskItem, OccurrenceState } from '../model/Task';
import { CalendarBlock, CalendarService } from '../services/CalendarService';
import { ScheduleService } from '../services/ScheduleService';
import { TaskService } from '../services/TaskService';

@Component
export struct TimeTable {
  @Prop tasks: Task[] = [];
  @Prop states: OccurrenceState[] = [];
  @Prop days: string[] = [];
  @Prop selected: string = '';
  @State private verticalOffset: number = 420;
  @Prop now: number = Date.now();
  @Prop snapMinutes: number = 15;
  onEdit: (item: TaskItem) => void = () => {};
  onAdjust: (item: TaskItem, days: number, minutes: number, resize: boolean) => void = () => {};
  onCreate: (day: string, minute: number) => void = () => {};
  onSelect: (day: string) => void = () => {};
  private scroller: Scroller = new Scroller();
  private horizontal: Scroller = new Scroller();
  private hours: number[] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23];
  private columnWidth(): number { return this.days.length === 1 ? 280 : 144; }
  private blocks(day: string): CalendarBlock[] { return CalendarService.blocks(this.tasks, this.states, day); }
  aboutToAppear(): void { setTimeout((): void => {
    this.scroller.scrollTo({ xOffset: 0, yOffset: 7 * 60 });
    this.horizontal.scrollTo({ xOffset: Math.max(0, this.days.indexOf(this.selected)) * this.columnWidth(), yOffset: 0 });
  }, 150); }
  build() {
    Column({ space: 8 }) {
      Text(this.days.length > 1 ? '左右滑动查看整周 · 点日期切换无时间事项' : '长按区块拖动 · 拖底部调整时长 · 长按空白添加').fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
      Stack({ alignContent: Alignment.TopStart }) {
      Scroll(this.horizontal) {
        Column({ space: 0 }) {
          Row() {
            Text('时间').width(44).fontSize(11).fontColor($r('app.color.text_secondary'))
            ForEach(this.days, (day: string) => {
              Text(day.slice(5) + ' 周' + ['日', '一', '二', '三', '四', '五', '六'][ScheduleService.date(day).getDay()])
                .width(this.columnWidth()).height(40).textAlign(TextAlign.Center).fontSize(13).fontColor($r('app.color.text_primary'))
                .fontWeight(day === this.selected ? FontWeight.Bold : FontWeight.Normal).onClick(() => this.onSelect(day))
            }, (day: string) => day)
          }
          Scroll(this.scroller) {
            Row() {
              Column({ space: 0 }) {
                ForEach(this.hours, (hour: number) => {
                  Text(hour.toString().padStart(2, '0') + ':00').height(60).width(44).fontSize(10)
                    .fontColor($r('app.color.text_secondary')).textAlign(TextAlign.Start).align(Alignment.TopStart)
                })
              }.height(1440)
              ForEach(this.days, (day: string) => {
                Stack({ alignContent: Alignment.TopStart }) {
                  Column({ space: 0 }) {
                    ForEach(this.hours, (hour: number) => {
                      Row().height(60).width(this.columnWidth()).border({ width: { top: 0.5, left: 0.5 }, color: $r('app.color.chip_background') })
                        .accessibilityText(day + ' ' + hour.toString() + '点，长按添加')
                        .gesture(LongPressGesture().onAction(() => this.onCreate(day, hour * 60)))
                    })
                  }
                  ForEach(this.blocks(day), (block: CalendarBlock) => {
                    Column({ space: 3 }) {
                      Text((block.item.task.priority === 2 && !block.item.completed ? '！' : '') + block.item.task.title).fontSize(12).fontWeight(FontWeight.Medium).maxLines(block.end - block.start >= 70 ? 2 : 1)
                        .fontColor(block.item.task.priority === 2 && !block.item.completed ? $r('app.color.danger') : $r('app.color.text_primary')).width('100%')
                      if (block.end - block.start >= 70) {
                        Text((block.continuesBefore ? '续 · ' : '') + TaskService.timeLabel(block.item.task))
                          .fontSize(10).fontColor($r('app.color.text_secondary')).width('100%')
                      }
                      if (block.end - block.start >= 30) {
                      Text('━').fontSize(10).width('100%').height(18).fontColor($r('app.color.text_secondary'))
                        .position({ x: 0, y: Math.max(0, block.end - block.start - 22) })
                        .accessibilityText('拖动调整时长')
                        .gesture(PanGesture({ direction: PanDirection.Vertical }).onActionEnd((event: GestureEvent) => {
                          this.onAdjust(block.item, 0, Math.round(event.offsetY / this.snapMinutes) * this.snapMinutes, true);
                        }))
                      }
                    }.padding(5).width((this.columnWidth() - 6) / block.lanes - 2).height(Math.max(18, block.end - block.start - 2))
                      .borderRadius(8).clip(true).backgroundColor($r('app.color.chip_background'))
                      .opacity(block.item.completed ? 0.55 : 1)
                      .position({ x: 3 + block.lane * (this.columnWidth() - 6) / block.lanes, y: block.start })
                      .accessibilityText(block.item.task.title + ' ' + TaskService.timeLabel(block.item.task))
                      .onClick(() => this.onEdit(block.item))
                      .gesture(GestureGroup(GestureMode.Sequence, LongPressGesture({ duration: 500 }),
                        PanGesture().onActionEnd((event: GestureEvent) => {
                          this.onAdjust(block.item, this.days.length > 1 ? Math.round(event.offsetX / this.columnWidth()) : 0,
                            Math.round(event.offsetY / this.snapMinutes) * this.snapMinutes, false);
                        })))
                  }, (block: CalendarBlock) => JSON.stringify(block))
                  if (day === ScheduleService.key(this.now)) {
                    Row().height(1).width(this.columnWidth()).backgroundColor($r('app.color.danger'))
                      .position({ x: 0, y: new Date(this.now).getHours() * 60 + new Date(this.now).getMinutes() })
                  }
                }.width(this.columnWidth()).height(1440)
              }, (day: string) => day)
            }.alignItems(VerticalAlign.Top)
          }.height(440).width(44 + this.columnWidth() * this.days.length).scrollBar(BarState.On)
            .onDidScroll(() => { this.verticalOffset = this.scroller.currentOffset().yOffset; })
        }
      }.scrollable(ScrollDirection.Horizontal).width('100%').scrollBar(BarState.On)
      Column({ space: 0 }) {
        Text('时间').width(44).height(40).fontSize(11).fontColor($r('app.color.text_secondary'))
          .backgroundColor($r('app.color.card_background'))
        Stack({ alignContent: Alignment.TopStart }) {
          Column({ space: 0 }) {
            ForEach(this.hours, (hour: number) => {
              Text(hour.toString().padStart(2, '0') + ':00').height(60).width(44).fontSize(10)
                .fontColor($r('app.color.text_secondary')).align(Alignment.TopStart)
            })
          }.height(1440).position({ x: 0, y: -this.verticalOffset })
        }.height(440).width(44).clip(true).backgroundColor($r('app.color.card_background'))
      }.width(44).hitTestBehavior(HitTestMode.None)
      }.width('100%')
    }.padding(10).borderRadius(18).backgroundColor($r('app.color.card_background')).width('100%')
  }
}
