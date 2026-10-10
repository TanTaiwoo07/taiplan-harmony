import { common } from '@kit.AbilityKit';
import { AiConfigStore } from '../data/AiConfigStore';
import { preferences } from '@kit.ArkData';
import { TaskDraft } from '../model/Task';
import { DraftProposal, DraftService } from '../services/DraftService';
import { TaskService } from '../services/TaskService';
import { AiClient } from '../platform/AiClient';
import { AiSecretStore } from '../platform/AiSecretStore';
import { SpeechService } from '../platform/SpeechService';

@Component
export struct SmartEntry {
  @Prop initialText: string = '';
  @Prop saving: boolean = false;
  @State private text: string = '';
  @State private rows: DraftProposal[] = [];
  @State private status: string = '';
  @State private working: boolean = false;
  @State private config: boolean = false;
  @State private endpoint: string = '';
  @State private model: string = '';
  @State private secret: string = '';
  private client: AiClient = new AiClient();
  private requestId: number = 0;
  onSave: (drafts: TaskDraft[]) => void = () => {};
  onEdit: (draft: TaskDraft) => void = () => {};
  onTextChange: (text: string) => void = () => {};
  aboutToAppear(): void { this.text = this.initialText; this.loadConfig(); }
  aboutToDisappear(): void { this.cancel(); SpeechService.shared.cancel(); this.secret = ''; }
  private context(): common.UIAbilityContext { return this.getUIContext().getHostContext() as common.UIAbilityContext; }
  private async loadConfig(): Promise<void> {
    try { const config = await AiConfigStore.load(this.context());
      this.endpoint = config.endpoint; this.model = config.model;
    } catch { this.status = 'AI 配置读取失败，可继续离线识别'; }
  }
  private async saveConfig(): Promise<void> {
    try {
      if (!this.endpoint.startsWith('https://') || !this.model.trim()) { throw new Error('先填写 HTTPS 地址和模型'); }
      AiConfigStore.validate({ endpoint: this.endpoint.trim(), model: this.model.trim() });
      if (this.secret) { await AiSecretStore.save(this.secret); this.secret = ''; }
      await AiConfigStore.save(this.context(), { endpoint: this.endpoint.trim(), model: this.model.trim() });
      this.status = '配置已保存；密钥保存在系统安全资产存储，不进入任务备份。';
    } catch { this.status = '配置保存失败，请检查设备安全存储与输入；密钥不会降级写入普通文件。'; }
  }
  private cancel(): void { this.requestId++; this.client.cancel(); this.working = false; }
  private async parse(cloud: boolean): Promise<void> {
    this.getUIContext().getFocusController().clearFocus();
    this.cancel(); const id = this.requestId; this.working = true; this.rows = []; this.status = cloud ? 'AI 正在生成草稿…' : '正在离线识别…';
    try {
      const key = cloud ? (this.secret || await AiSecretStore.read()) : '';
      if (id !== this.requestId) { return; }
      const rows = cloud ? await this.client.parse(this.endpoint.trim(), this.model.trim(), key, this.text, Date.now()) : DraftService.local(this.text, Date.now());
      if (id !== this.requestId) { return; } this.rows = rows; this.status = '尚未保存。请逐项核对，不确定内容可打开编辑器修改。';
    } catch { if (id === this.requestId) { this.status = cloud ? 'AI 识别失败：检查配置、网络、授权或返回格式。没有创建任务，可改用离线识别。' : '无法可靠识别，请检查日期时间，或减少每行内容后重试。'; } }
    finally { if (id === this.requestId) { this.working = false; } }
  }
  private choose(index: number): void {
    this.rows = this.rows.map((row: DraftProposal, i: number): DraftProposal => { return { draft: row.draft, explanation: row.explanation, selected: i === index ? !row.selected : row.selected }; });
  }
  private async testConnection(): Promise<void> {
    this.cancel(); const id = this.requestId; this.working = true; this.status = '正在发送固定测试句，不上传你的任务…';
    try {
      const key = this.secret || await AiSecretStore.read(); if (id !== this.requestId) { return; }
      await this.client.parse(this.endpoint.trim(), this.model.trim(), key, '记得买牛奶，不安排日期。', Date.now());
      if (id === this.requestId) { this.status = '连接及结构化响应校验通过，没有保存测试任务。'; }
    } catch { if (id === this.requestId) { this.status = '连接或响应校验失败，请检查服务地址、模型和密钥。'; } }
    finally { if (id === this.requestId) { this.working = false; } }
  }
  build() {
    Column({ space: 12 }) {
      Text('先说出来，再核对安排').fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).width('100%')
      TextArea({ text: this.text, placeholder: '每行一件事，例如：明天下午三点讨论项目，一个小时' }).height(150).maxLength(4000)
        .fontColor($r('app.color.text_primary')).backgroundColor($r('app.color.card_background'))
        .onChange((value: string) => { if (value !== this.text) { this.cancel(); this.text = value; this.onTextChange(value); this.rows = []; } })
      Row({ space: 8 }) {
        Button('语音输入').height(44).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).fontSize(13).layoutWeight(1).onClick(() => SpeechService.shared.start(this.context(),
          (value: string) => { this.cancel(); this.text = value; this.onTextChange(value); this.rows = []; }, (value: string) => { this.status = value; }))
        Button('结束录音').height(44).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).fontSize(13).layoutWeight(1).onClick(() => SpeechService.shared.finish())
        Button('取消录音').height(44).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).fontSize(13).layoutWeight(1).onClick(() => { SpeechService.shared.cancel(); this.status = '录音已取消'; })
      }
      Row({ space: 8 }) {
        Button('离线识别').height(48).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).layoutWeight(1).enabled(!this.working).onClick(() => this.parse(false))
        Button('发送给 AI 识别').height(48).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).layoutWeight(1).enabled(!this.working).onClick(() => this.parse(true))
      }
      if (this.working) { Button('取消识别').height(44).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).onClick(() => { this.cancel(); this.status = '已取消，无任务写入'; }) }
      Text('云端识别仅发送上面的文字、当前日期和时区，不上传已有任务。使用你配置的兼容 Chat Completions 服务。')
        .fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
      if (this.status) { Text(this.status).fontSize(13).fontColor($r('app.color.text_secondary')).width('100%') }
      ForEach(this.rows, (row: DraftProposal, index: number) => {
        Column({ space: 8 }) {
          Row() {
            Checkbox().select(row.selected).onChange(() => this.choose(index))
            Text(row.draft.title).fontSize(16).layoutWeight(1).fontColor($r('app.color.text_primary'))
          }
          Text(TaskService.dateLabel(row.draft.dueAt) + ' · ' + TaskService.timeLabel(TaskService.create(row.draft, 'preview', 0)) + ' · ' + TaskService.priorityLabel(row.draft.priority) + '优先级').fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
          Text((row.draft.planning?.location || '地点未设置') + (row.draft.note ? '\n' + row.draft.note : '')).fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
          Text(row.explanation).fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
          Button('编辑这一条').height(44).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).fontSize(13).onClick(() => this.onEdit(row.draft))
        }.padding(14).borderRadius(16).backgroundColor($r('app.color.card_background')).width('100%')
      }, (row: DraftProposal) => JSON.stringify(row))
      if (this.rows.length > 0) {
        Button('确认保存选中草稿').height(50).backgroundColor($r('app.color.accent')).fontColor($r('app.color.on_accent')).width('100%').enabled(!this.saving && this.rows.some((row: DraftProposal) => row.selected))
          .onClick(() => this.onSave(this.rows.filter((row: DraftProposal) => row.selected).map((row: DraftProposal) => row.draft)))
      }
      Button(this.config ? '收起 AI 配置' : 'AI 服务配置').height(44).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).width('100%').onClick(() => { this.config = !this.config; })
      if (this.config) {
        TextInput({ text: this.endpoint, placeholder: 'https://服务地址/v1/chat/completions' }).height(48).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).onChange((v: string) => { this.endpoint = v; })
        TextInput({ text: this.model, placeholder: '模型名称' }).height(48).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).onChange((v: string) => { this.model = v; })
        TextInput({ text: this.secret, placeholder: 'API Key（留空沿用安全存储）' }).type(InputType.Password).height(48).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).onChange((v: string) => { this.secret = v; })
        Button('保存配置与密钥').height(44).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).onClick(() => this.saveConfig())
        Button('测试连接（发送固定测试句）').height(48).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).enabled(!this.working).onClick(() => this.testConnection())
        Button('移除已保存密钥').height(44).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).onClick(async () => { try { await AiSecretStore.clear(); this.secret = ''; this.status = '密钥已移除'; } catch { this.status = '移除失败或没有已保存密钥'; } })
      }
    }.width('100%')
  }
}
