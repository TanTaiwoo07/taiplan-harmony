import { IconLabel } from './IconLabel';
import { ProductState } from '../model/Product';
import { ProductService } from '../services/ProductService';
@Component
export struct ProductSettings {
  @Prop state: ProductState = ProductService.defaults();
  onSave: (state: ProductState) => Promise<void> = async () => {};
  onOpen: () => void = () => {};
  @State private error: string = '';
  @State private busy: boolean = false;
  private async change(name: string): Promise<void> {
    if (this.busy) { return; } this.busy = true; this.error = '';
    const next = ProductService.clone(this.state);
    if (name === 'simple' || name === 'full') { next.features = { focus: name === 'full', habits: name === 'full', countdowns: name === 'full', ai: name === 'full' }; }
    else if (name === 'focus') { next.features.focus = !next.features.focus; }
    else if (name === 'habits') { next.features.habits = !next.features.habits; }
    else if (name === 'countdowns') { next.features.countdowns = !next.features.countdowns; }
    else if (name === 'ai') { next.features.ai = !next.features.ai; }
    else if (name === 'work') { next.focusOptions.work = next.focusOptions.work === 25 ? 45 : next.focusOptions.work === 45 ? 60 : 25; }
    else if (name === 'short') { next.focusOptions.shortBreak = next.focusOptions.shortBreak === 5 ? 10 : 5; }
    else if (name === 'long') { next.focusOptions.longBreak = next.focusOptions.longBreak === 15 ? 30 : 15; }
    else if (name === 'cycles') { next.focusOptions.cycles = next.focusOptions.cycles === 4 ? 2 : 4; }
    else if (name === 'start') { next.workStart = (next.workStart ?? 9) === 8 ? 9 : (next.workStart ?? 9) === 9 ? 10 : 8; }
    else if (name === 'end') { next.workEnd = (next.workEnd ?? 21) === 18 ? 21 : (next.workEnd ?? 21) === 21 ? 23 : 18; }
    try { await this.onSave(next); } catch (error) { this.error = (error as Error).message; }
    finally { this.busy = false; }
  }
  build() {
    Column({ space: 10 }) {
      Text('功能与工具').fontSize(18).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).width('100%')
      Text('辅助排程可用时段').fontSize(13).fontColor($r('app.color.text_secondary')).width('100%')
      Row({ space: 8 }) {
        Button('开始 ' + (this.state.workStart ?? 9).toString() + ':00').height(48).fontSize(14).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).layoutWeight(1).onClick(() => this.change('start'))
        Button('结束 ' + (this.state.workEnd ?? 21).toString() + ':00').height(48).fontSize(14).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).layoutWeight(1).onClick(() => this.change('end'))
      }
      Row({ space: 8 }) {
        Button('简洁预设').height(48).fontSize(14).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).layoutWeight(1).onClick(() => this.change('simple'))
        Button('完整预设').height(48).fontSize(14).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).layoutWeight(1).onClick(() => this.change('full'))
      }
      Flex({ wrap: FlexWrap.Wrap }) {
        Button((this.state.features.focus ? '✓ ' : '') + '专注').height(48).fontSize(14).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).margin(3).onClick(() => this.change('focus'))
        Button((this.state.features.habits ? '✓ ' : '') + '习惯').height(48).fontSize(14).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).margin(3).onClick(() => this.change('habits'))
        Button((this.state.features.countdowns ? '✓ ' : '') + '倒数日').height(48).fontSize(14).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).margin(3).onClick(() => this.change('countdowns'))
        Button((this.state.features.ai ? '✓ ' : '') + '智能输入').height(48).fontSize(14).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).margin(3).onClick(() => this.change('ai'))
      }
      Text('关闭只隐藏入口，数据保留，已有计时或提醒不会自动取消。请在工具内结束计时，或在系统提醒设置取消登记。').fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
      if (this.state.features.focus) {
        Flex({ wrap: FlexWrap.Wrap }) {
          Button('专注 ' + this.state.focusOptions.work.toString() + ' 分').height(48).fontSize(14).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).margin(3).onClick(() => this.change('work'))
          Button('短休 ' + this.state.focusOptions.shortBreak.toString() + ' 分').height(48).fontSize(14).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).margin(3).onClick(() => this.change('short'))
          Button('长休 ' + this.state.focusOptions.longBreak.toString() + ' 分').height(48).fontSize(14).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).margin(3).onClick(() => this.change('long'))
          Button(this.state.focusOptions.cycles.toString() + ' 轮后长休').height(48).fontSize(14).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).margin(3).onClick(() => this.change('cycles'))
        }
      }
      if (this.state.features.focus || this.state.features.habits || this.state.features.countdowns) {
        Button({ type: ButtonType.Capsule }) { IconLabel('打开我的工具', $r('app.media.glyph_workbench_on_accent'), $r('app.color.on_accent')) }.height(52).width('100%').onClick(() => this.onOpen())
      }
      if (this.error) { Text(this.error).fontSize(13).fontColor($r('app.color.danger')) }
    }.padding(16).width('100%').borderRadius(18).backgroundColor($r('app.color.card_background')).enabled(!this.busy)
  }
}
