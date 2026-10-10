import { CalendarDay } from '../model/Task';

@Component
export struct MonthCalendar {
  @Prop days: CalendarDay[] = [];
  @Prop selected: string = '';
  @Prop month: string = '';
  onSelect: (key: string) => void = () => {};
  onMonth: (delta: number) => void = () => {};
  onToday: () => void = () => {};
  build() {
    Column({ space: 8 }) {
      Row() {
        Button('‹').height(36).width(38).fontSize(24).backgroundColor(Color.Transparent)
          .fontColor($r('app.color.accent')).accessibilityText('上个月').onClick(() => this.onMonth(-1))
        Text(this.month.slice(0, 7)).fontSize(18).fontWeight(FontWeight.Bold).layoutWeight(1)
          .fontColor($r('app.color.text_primary')).textAlign(TextAlign.Center)
        Button('今天').height(32).fontSize(12).backgroundColor(Color.Transparent)
          .fontColor($r('app.color.accent')).onClick(() => this.onToday())
        Button('›').height(36).width(38).fontSize(24).backgroundColor(Color.Transparent)
          .fontColor($r('app.color.accent')).accessibilityText('下个月').onClick(() => this.onMonth(1))
      }.width('100%')
      Row() {
        ForEach(['一', '二', '三', '四', '五', '六', '日'], (day: string) => {
          Text(day).layoutWeight(1).textAlign(TextAlign.Center).fontSize(12).fontColor($r('app.color.text_secondary'))
        })
      }
      Grid() {
        ForEach(this.days, (day: CalendarDay) => {
          GridItem() {
            Column({ space: 2 }) {
              Text(day.day.toString()).fontSize(14)
                .fontColor(day.key === this.selected ? $r('app.color.on_accent') : day.inMonth ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
              Text(day.count > 0 ? `${day.count}件` : ' ').fontSize(9)
                .fontColor(day.key === this.selected ? $r('app.color.on_accent') : $r('app.color.accent'))
            }.width('100%').height(40).justifyContent(FlexAlign.Center).borderRadius(10)
              .opacity(day.inMonth ? 1 : 0.5)
              .backgroundColor(day.key === this.selected ? $r('app.color.accent') : Color.Transparent)
          }.accessibilityText(`${day.key}，${day.count}件任务`).onClick(() => this.onSelect(day.key))
        }, (day: CalendarDay) => `${day.key}:${day.count}`)
      }.columnsTemplate('1fr 1fr 1fr 1fr 1fr 1fr 1fr').rowsGap(2).height(250)
    }.padding(10).width('100%').borderRadius(18).backgroundColor($r('app.color.card_background'))
  }
}
