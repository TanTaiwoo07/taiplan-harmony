import { MotionService } from '../services/MotionService';
import { CalendarInteractionService } from '../services/CalendarInteractionService';
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
  @State private hourHeight: number = 60;
  @State private dragKey: string = '';
  @State private dragMinutes: number = 0;
  @State private dragDays: number = 0;
  @State private dragResize: boolean = false;
  @State private dragLabel: string = '';
  private dragBlock: CalendarBlock | undefined = undefined;
  private dragStartScroll: number = 0;
  private dragStartHorizontal: number = 0;
  private dragX: number = 0;
  private dragY: number = 0;
  private edgeY: number = 0;
  private edgeX: number = 0;
  private viewportTop: number = 0;
  private viewportLeft: number = 0;
  private viewportWidth: number = 0;
  private pinchHeight: number = 60;
  private ignoreClickUntil: number = 0;
  private autoTimer: number = -1;
  private zoomTimer: number = -1;
  private appearTimer: number = -1;
  private cacheTasks: Task[] | undefined = undefined;
  private cacheStates: OccurrenceState[] | undefined = undefined;
  private blockCache: Map<string, CalendarBlock[]> = new Map();
  @Prop reduceMotion: boolean = false;
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
  private blocks(day: string): CalendarBlock[] {
    if (this.cacheTasks !== this.tasks || this.cacheStates !== this.states) { this.blockCache.clear(); this.cacheTasks = this.tasks; this.cacheStates = this.states; }
    let blocks = this.blockCache.get(day); if (!blocks) { blocks = CalendarService.blocks(this.tasks, this.states, day); this.blockCache.set(day, blocks); } return blocks;
  }
  private px(minutes: number): number { return minutes * this.hourHeight / 60; }
  private zoom(height: number, center: number = 220, live: boolean = false): void {
    if (this.dragKey) { return; }
    const next = CalendarInteractionService.height(height), offset = CalendarInteractionService.anchor(this.scroller.currentOffset().yOffset, center, this.hourHeight, next, 440);
    const duration = live || MotionService.reduced(this.reduceMotion) ? 0 : 280;
    if (duration === 0) { this.hourHeight = next; }
    else { this.getUIContext().animateTo(MotionService.options(this.reduceMotion), () => { this.hourHeight = next; }); }
    this.scroller.scrollTo({ xOffset: 0, yOffset: offset, animation: { duration: duration, curve: Curve.EaseOut } });
    if (this.zoomTimer !== -1) { clearTimeout(this.zoomTimer); }
    this.zoomTimer = setTimeout(() => { this.scroller.scrollTo({ xOffset: 0, yOffset: offset }); }, duration);
  }
  private beginDrag(block: CalendarBlock, resize: boolean): void {
    if (!resize && block.continuesBefore) { this.dragLabel = '跨日安排请从开始当天移动'; return; }
    this.dragBlock = block; this.dragKey = block.key; this.dragResize = resize; this.dragMinutes = 0; this.dragDays = 0;
    this.dragX = 0; this.dragY = 0; this.edgeX = 0; this.edgeY = 0;
    this.dragStartScroll = this.scroller.currentOffset().yOffset; this.dragStartHorizontal = this.horizontal.currentOffset().xOffset;
    this.dragLabel = CalendarInteractionService.preview(block.item, 0, 0, resize);
  }
  private updateDrag(event: GestureEvent): void {
    if (!this.dragBlock || !this.dragKey) { return; }
    this.dragX = event.offsetX; this.dragY = event.offsetY;
    const finger = event.fingerList.find((item: FingerInfo) => item !== undefined);
    this.edgeY = finger ? finger.globalY < this.viewportTop + 48 ? -12 : finger.globalY > this.viewportTop + 392 ? 12 : 0 : 0;
    this.edgeX = finger && this.days.length > 1 && !this.dragResize ? finger.globalX < this.viewportLeft + 70 ? -10 : finger.globalX > this.viewportLeft + this.viewportWidth - 32 ? 10 : 0 : 0;
    this.updatePreview();
  }
  private updatePreview(): void {
    if (!this.dragBlock) { return; }
    this.dragMinutes = CalendarInteractionService.minutes(this.dragY + this.scroller.currentOffset().yOffset - this.dragStartScroll, this.hourHeight, this.snapMinutes);
    this.dragDays = this.dragResize || this.days.length === 1 ? 0 : Math.round((this.dragX + this.horizontal.currentOffset().xOffset - this.dragStartHorizontal) / this.columnWidth());
    this.dragLabel = CalendarInteractionService.preview(this.dragBlock.item, this.dragDays, this.dragMinutes, this.dragResize);
  }
  private endDrag(): void {
    this.ignoreClickUntil = Date.now() + 350;
    const block = this.dragBlock, minutes = this.dragMinutes, days = this.dragDays, resize = this.dragResize;
    this.cancelDrag(); if (block && (minutes || days)) { this.onAdjust(block.item, days, minutes, resize); }
  }
  private cancelDrag(): void { this.dragKey = ''; this.dragBlock = undefined; this.dragLabel = ''; this.edgeY = 0; this.edgeX = 0; }
  private ghostHeight(block: CalendarBlock): number { return this.px(this.dragResize ? Math.max(5, Math.min(1440, (block.item.task.durationMinutes ?? 30) + this.dragMinutes)) : block.end - block.start); }
  aboutToDisappear(): void {
    if (this.autoTimer !== -1) { clearInterval(this.autoTimer); }
    if (this.zoomTimer !== -1) { clearTimeout(this.zoomTimer); }
    if (this.appearTimer !== -1) { clearTimeout(this.appearTimer); }
    this.cancelDrag();
  }
  aboutToAppear(): void { this.autoTimer = setInterval(() => { if (this.dragKey) {
    if (this.edgeY) { this.scroller.scrollTo({ xOffset: 0, yOffset: Math.max(0, Math.min(24 * this.hourHeight - 440, this.scroller.currentOffset().yOffset + this.edgeY)) }); }
    if (this.edgeX) { this.horizontal.scrollTo({ xOffset: Math.max(0, Math.min(44 + this.columnWidth() * this.days.length - this.viewportWidth, this.horizontal.currentOffset().xOffset + this.edgeX)), yOffset: 0 }); }
    this.updatePreview(); } }, 80);
    this.appearTimer = setTimeout((): void => {
    this.scroller.scrollTo({ xOffset: 0, yOffset: 7 * 60 });
    this.horizontal.scrollTo({ xOffset: Math.max(0, this.days.indexOf(this.selected)) * this.columnWidth(), yOffset: 0 });
  }, 150); }
  build() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text('双指缩放 · 长按移动 · 点按详情').fontSize(12).fontColor($r('app.color.text_secondary')).layoutWeight(1)
        Button({ type: ButtonType.Normal }) { Image($r('app.media.glyph_zoom_out')).width(22).height(22).accessibilityLevel('no') }.width(40).height(44).fontSize(22).padding(0).accessibilityText('缩小时间刻度').backgroundColor(Color.Transparent).fontColor($r('app.color.text_primary')).onClick(() => this.zoom(this.hourHeight / 1.5))
        Button({ type: ButtonType.Normal }) { Image($r('app.media.glyph_zoom_in')).width(22).height(22).accessibilityLevel('no') }.width(40).height(44).fontSize(22).padding(0).accessibilityText('放大时间刻度').backgroundColor(Color.Transparent).fontColor($r('app.color.text_primary')).onClick(() => this.zoom(this.hourHeight * 1.5))
      }.width('100%')
      Text(this.dragLabel ? this.dragLabel + ' · 松手后确认' : '长按移动，拖底部改时长；松手后再保存。').height(36).maxLines(2).fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
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
                  Text(hour.toString().padStart(2, '0') + ':00').height(this.hourHeight).width(44).fontSize(10)
                    .fontColor($r('app.color.text_secondary')).textAlign(TextAlign.Start).align(Alignment.TopStart)
                })
              }.height(24 * this.hourHeight)
              ForEach(this.days, (day: string) => {
                Stack({ alignContent: Alignment.TopStart }) {
                  Column({ space: 0 }) {
                    ForEach(this.hours, (hour: number) => {
                      Row().height(this.hourHeight).width(this.columnWidth()).border({ width: { top: 0.5, left: 0.5 }, color: $r('app.color.chip_background') })
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
                      if (block.end - block.start >= 30 && !block.continuesBefore && !block.continuesAfter) {
                      Text('━').fontSize(10).width('100%').height(18).fontColor($r('app.color.text_secondary'))
                        .position({ x: 0, y: Math.max(0, this.px(block.end - block.start) - 22) })
                        .accessibilityText('拖动调整时长')
                        .gesture(PanGesture({ direction: PanDirection.Vertical }).onActionStart(() => this.beginDrag(block, true)).onActionUpdate((event: GestureEvent) => this.updateDrag(event)).onActionEnd(() => this.endDrag()).onActionCancel(() => this.cancelDrag()))
                      }
                    }.padding(5).width((this.columnWidth() - 6) / block.lanes - 2).height(Math.max(18, this.px(block.end - block.start) - 2))
                      .borderRadius(8).clip(true).backgroundColor($r('app.color.chip_background'))
                      .opacity(this.dragKey === block.key ? 0.25 : block.item.completed ? 0.55 : 1)
                      .position({ x: 3 + block.lane * (this.columnWidth() - 6) / block.lanes, y: this.px(block.start) })
                      .accessibilityText(block.item.task.title + ' ' + TaskService.timeLabel(block.item.task))
                      .onClick(() => { if (Date.now() > this.ignoreClickUntil) { this.onEdit(block.item); } })
                      .gesture(GestureGroup(GestureMode.Sequence, LongPressGesture({ duration: 400 }).onAction(() => { this.ignoreClickUntil = Date.now() + 2000; }).onActionEnd(() => { this.ignoreClickUntil = Date.now() + 350; }),
                        PanGesture().onActionStart(() => this.beginDrag(block, false)).onActionUpdate((event: GestureEvent) => this.updateDrag(event)).onActionEnd(() => this.endDrag()).onActionCancel(() => this.cancelDrag())))
                    if (this.dragKey === block.key) {
                      Column({ space: 4 }) { Text(block.item.task.title).fontSize(13).fontWeight(FontWeight.Bold).maxLines(1).fontColor($r('app.color.text_primary'))
                        Text(this.dragLabel).fontSize(11).fontColor($r('app.color.text_secondary')).maxLines(2)
                      }.padding(6).width(this.columnWidth() - 6).height(Math.max(30, this.ghostHeight(block))).borderRadius(8)
                        .backgroundColor($r('app.color.card_background')).border({ width: 1.5, color: $r('app.color.accent') }).shadow({ radius: 8, color: '#22000000', offsetY: 3 })
                        .position({ x: 3 + this.dragDays * this.columnWidth(), y: this.px(block.start + (this.dragResize ? 0 : this.dragMinutes)) }).animation({ duration: MotionService.reduced(this.reduceMotion) ? 0 : 90, curve: Curve.EaseOut }).zIndex(20).hitTestBehavior(HitTestMode.None)
                    }
                  }, (block: CalendarBlock) => JSON.stringify(block))
                  if (day === ScheduleService.key(this.now)) {
                    Row().height(1).width(this.columnWidth()).backgroundColor($r('app.color.danger'))
                      .position({ x: 0, y: this.px(new Date(this.now).getHours() * 60 + new Date(this.now).getMinutes()) })
                  }
                }.width(this.columnWidth()).height(24 * this.hourHeight)
              }, (day: string) => day)
            }.alignItems(VerticalAlign.Top)
          }.height(440).width(44 + this.columnWidth() * this.days.length).scrollBar(BarState.On)
            .enableScrollInteraction(this.dragKey === '').onDidScroll(() => { this.verticalOffset = this.scroller.currentOffset().yOffset; })
        }
      }.scrollable(ScrollDirection.Horizontal).width('100%').scrollBar(BarState.On)
      Column({ space: 0 }) {
        Text('时间').width(44).height(40).fontSize(11).fontColor($r('app.color.text_secondary'))
          .backgroundColor($r('app.color.card_background'))
        Stack({ alignContent: Alignment.TopStart }) {
          Column({ space: 0 }) {
            ForEach(this.hours, (hour: number) => {
              Text(hour.toString().padStart(2, '0') + ':00').height(this.hourHeight).width(44).fontSize(10)
                .fontColor($r('app.color.text_secondary')).align(Alignment.TopStart)
            })
          }.height(24 * this.hourHeight).position({ x: 0, y: -this.verticalOffset })
        }.height(440).width(44).clip(true).backgroundColor($r('app.color.card_background'))
      }.width(44).hitTestBehavior(HitTestMode.None)
      }.width('100%').onAreaChange((oldArea: Area, area: Area) => { this.viewportTop = Number(area.globalPosition.y) + 40; this.viewportLeft = Number(area.globalPosition.x); this.viewportWidth = Number(area.width); })
        .parallelGesture(PinchGesture().onActionStart(() => { this.pinchHeight = this.hourHeight; }).onActionUpdate((event: GestureEvent) => this.zoom(this.pinchHeight * event.scale, Math.max(0, event.pinchCenterY - 40), true)))
    }.padding(10).borderRadius(18).backgroundColor($r('app.color.card_background')).width('100%')
  }
}
