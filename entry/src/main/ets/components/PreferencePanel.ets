import { AppPreferences } from '../model/Task';
import { PlanningService } from '../services/PlanningService';
import { MaterialService } from '../services/MaterialService';

@Component
export struct PreferencePanel {
  @Prop settings: AppPreferences = PlanningService.defaults();
  onChange: (value: AppPreferences) => void = () => {};
  private change(key: string, value: number | string | boolean): void {
    const next = JSON.parse(JSON.stringify(this.settings)) as AppPreferences;
    if (key === 'start') { next.startPage = value as number; }
    else if (key === 'view') { next.calendarView = value as string; }
    else if (key === 'week') { next.weekStart = value as number; }
    else if (key === 'done') { next.showCompleted = value as boolean; }
    else if (key === 'material') { next.useMaterial = value as boolean; }
    else if (key === 'snap') { next.snapMinutes = value as number; }
    this.onChange(next);
  }
  build() {
    Column({ space: 12 }) {
      Text('显示与操作偏好').fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).width('100%')
      Text('启动时打开').fontSize(13).fontColor($r('app.color.text_secondary')).width('100%')
      Row({ space: 6 }) {
        ForEach([0, 1, 2], (page: number) => {
          Button(['今天', '收集箱', '日历'][page]).height(44).layoutWeight(1).fontSize(13)
            .backgroundColor(this.settings.startPage === page ? $r('app.color.accent') : $r('app.color.chip_background'))
            .fontColor(this.settings.startPage === page ? $r('app.color.on_accent') : $r('app.color.text_primary')).onClick(() => this.change('start', page))
        })
      }
      Text('默认日历视图').fontSize(13).fontColor($r('app.color.text_secondary')).width('100%')
      Row({ space: 6 }) {
        ForEach(['year', 'month', 'week', 'day'], (view: string) => {
          Button(view === 'year' ? '年' : view === 'month' ? '月' : view === 'week' ? '周' : '日').height(44).layoutWeight(1)
            .backgroundColor(this.settings.calendarView === view ? $r('app.color.accent') : $r('app.color.chip_background'))
            .fontColor(this.settings.calendarView === view ? $r('app.color.on_accent') : $r('app.color.text_primary')).onClick(() => this.change('view', view))
        })
      }
      Button('每周开始于：' + (this.settings.weekStart === 1 ? '星期一' : '星期日')).height(48).width('100%').fontSize(13)
        .backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).onClick(() => this.change('week', this.settings.weekStart === 1 ? 0 : 1))
      Button('日历拖动吸附：' + this.settings.snapMinutes.toString() + ' 分钟').height(48).width('100%').fontSize(13)
        .backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary'))
        .onClick(() => this.change('snap', this.settings.snapMinutes === 5 ? 15 : this.settings.snapMinutes === 15 ? 30 : 5))
      Row() {
        Text('默认展开已完成').layoutWeight(1).fontSize(14).fontColor($r('app.color.text_primary'))
        Toggle({ type: ToggleType.Switch, isOn: this.settings.showCompleted }).selectedColor($r('app.color.accent')).onChange((value: boolean) => this.change('done', value))
      }.constraintSize({ minHeight: 48 })
      Row() {
        Text('原生沉浸材质').layoutWeight(1).fontSize(14).fontColor($r('app.color.text_primary'))
        Toggle({ type: ToggleType.Switch, isOn: this.settings.useMaterial }).selectedColor($r('app.color.accent')).onChange((value: boolean) => this.change('material', value))
      }.constraintSize({ minHeight: 48 })
      Text(MaterialService.supported() ? '用于快速收集面板，效果跟随设备策略。' : '当前设备使用清晰的实色面板；支持材质的设备自动适配。')
        .fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
    }.width('100%').padding(16).borderRadius(18).backgroundColor($r('app.color.card_background'))
  }
}
