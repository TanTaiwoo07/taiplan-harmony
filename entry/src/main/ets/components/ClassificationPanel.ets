import { MaterialService } from '../services/MaterialService';
import { Task } from '../model/Task';
@Component
export struct ClassificationPanel {
  @Prop useMaterial: boolean = true;
  @Prop tasks: Task[] = [];
  onRename: (kind: string, from: string, to: string) => Promise<void> = async () => {};
  @State private kind: string = 'list';
  @State private from: string = '';
  @State private to: string = '';
  @State private busy: boolean = false;
  @State private message: string = '';
  private names(): string[] {
    const names: string[] = [];
    for (const task of this.tasks) {
      if (this.kind === 'list') { names.push(task.planning?.listName ?? ''); for (const entry of task.overrides ?? []) { names.push(entry.draft.planning?.listName ?? ''); } }
      else { names.push(...task.tags); for (const entry of task.overrides ?? []) { names.push(...entry.draft.tagsText.split(/[,，、\n]/)); } }
    }
    return Array.from(new Set<string>(names.filter((name: string) => name.length > 0))).sort();
  }
  private confirm(remove: boolean): void {
    this.getUIContext().showAlertDialog({ systemMaterial: MaterialService.surface(this.useMaterial), title: remove ? '移除分类？' : '重命名或合并分类？',
      message: '影响全部关联任务及单次例外，任务本身和完成记录保留。目标名称已存在时会合并归类。',
      primaryButton: { value: '取消', action: () => {} }, secondaryButton: { value: '确认', action: async () => {
        if (this.busy) { return; } this.busy = true;
        try { await this.onRename(this.kind, this.from, remove ? '' : this.to.trim()); this.message = '分类已更新'; this.from = ''; this.to = ''; }
        catch (error) { this.message = (error as Error).message; } finally { this.busy = false; }
      } } });
  }
  build() {
    Column({ space: 12 }) {
      Text('分类在添加或编辑任务时创建，这里统一重命名、合并或移除。').fontSize(13).fontColor($r('app.color.text_secondary'))
      Row({ space: 8 }) {
        Button('清单').height(48).fontSize(14).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).onClick(() => { this.kind = 'list'; this.from = ''; })
        Button('标签').height(48).fontSize(14).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).onClick(() => { this.kind = 'tag'; this.from = ''; })
      }
      ForEach(this.names(), (name: string) => {
        Button((name === this.from ? '✓ ' : '') + name).height(48).fontSize(14).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).width('100%').onClick(() => { this.from = name; this.to = name; })
      }, (name: string) => name)
      if (this.from) {
        TextInput({ text: this.to, placeholder: '新名称' }).height(48).fontSize(14).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).maxLength(this.kind === 'tag' ? 12 : 30).onChange((value: string) => { this.to = value; })
        Button('重命名 / 合并').height(48).fontSize(14).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).enabled(this.to.trim().length > 0).onClick(() => this.confirm(false))
        Button('从任务中移除此分类').height(48).fontSize(14).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).onClick(() => this.confirm(true))
      }
      if (this.message) { Text(this.message).fontSize(13).fontColor($r('app.color.text_secondary')) }
    }.width('100%').enabled(!this.busy)
  }
}
