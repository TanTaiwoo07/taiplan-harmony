import { common } from '@kit.AbilityKit';
import { AiConfigStore } from '../data/AiConfigStore';
import { BusinessError } from '@kit.BasicServicesKit';
import { AiConfigService } from '../services/AiConfigService';
import { TaskDraft } from '../model/Task';
import { DraftProposal, DraftService } from '../services/DraftService';
import { TaskService } from '../services/TaskService';
import { AiClient } from '../platform/AiClient';
import { AiSecretStore } from '../platform/AiSecretStore';
import { SpeechService } from '../platform/SpeechService';

@Component
export struct SmartEntry {
  @Prop initialText: string = '';
  @Prop configOnly: boolean = false;
  onOpenConfig: () => void = () => {};
  @State private persistKey: boolean = true;
  @State private keyStatus: string = '正在检查密钥状态…';
  @State private configSaving: boolean = false;
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
  private configRevision: number = 0;
  private alive: boolean = true;
  onSave: (drafts: TaskDraft[]) => void = () => {};
  onEdit: (draft: TaskDraft) => void = () => {};
  onTextChange: (text: string) => void = () => {};
  aboutToAppear(): void { this.text = this.initialText; this.loadConfig(); }
  aboutToDisappear(): void { this.alive = false; this.cancel(); SpeechService.shared.cancel(); this.secret = ''; }
  private context(): common.UIAbilityContext { return this.getUIContext().getHostContext() as common.UIAbilityContext; }
  private async loadConfig(): Promise<void> {
    const revision = this.configRevision;
    try { const config = await AiConfigStore.load(this.context());
      if (!this.alive) { return; }
      if (revision === this.configRevision) { this.endpoint = config.endpoint; this.model = config.model; }
      const status = await AiSecretStore.status(); if (this.alive) { this.keyStatus = status; }
    } catch { this.status = 'AI 配置读取失败，可继续离线识别'; }
  }
  private async saveConfig(): Promise<void> {
    if (this.configSaving) { return; }
    this.configSaving = true; let stage = 'input'; let clean = '';
    try {
      const endpoint = AiConfigService.endpoint(this.endpoint);
      if (!this.model.trim()) { throw new Error('请填写模型名称'); }
      if (this.secret) { clean = AiConfigService.validateSecret(this.secret); }
      stage = 'config'; await AiConfigStore.save(this.context(), { endpoint: endpoint, model: this.model.trim() });
      this.endpoint = endpoint;
      stage = 'secret';
      if (clean) { if (this.persistKey) { await AiSecretStore.save(clean); } else { AiSecretStore.useSession(clean); } this.secret = ''; }
      this.keyStatus = await AiSecretStore.status();
      this.status = clean ? '服务配置与密钥已更新；' + this.keyStatus : '服务配置已保存；' + this.keyStatus;
    } catch (error) {
      this.status = stage === 'input' ? (error as Error).message : (stage === 'secret' ? '服务配置已保存；密钥保存或读回未通过。' : '') + AiConfigService.failure(stage, (error as BusinessError).code);
    } finally { this.configSaving = false; }
  }
  private async diagnose(): Promise<void> {
    if (this.configSaving) { return; } this.configSaving = true;
    try { await AiSecretStore.probe(); this.status = '安全存储诊断通过：独立测试条目已写入、读回并删除；未触碰你的密钥。'; }
    catch (error) { this.status = AiConfigService.failure('secret', (error as BusinessError).code); }
    finally { this.configSaving = false; }
  }
  private async removeKey(): Promise<void> {
    this.getUIContext().showAlertDialog({ title: '移除 AI 密钥？', message: '服务地址和模型保留，之后需要重新填写密钥。',
      primaryButton: { value: '取消', action: () => {} }, secondaryButton: { value: '移除', action: async () => {
        try { await AiSecretStore.clear(); this.secret = ''; this.keyStatus = await AiSecretStore.status(); this.status = '密钥已移除'; }
        catch (error) { this.status = AiConfigService.failure('secret', (error as BusinessError).code); }
      } } });
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
    } catch (error) { if (id === this.requestId) { this.status = cloud ? (error as Error).message + '。没有创建任务，可改用离线识别。' : '无法可靠识别，请检查日期时间，或减少每行内容后重试。'; } }
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
    } catch (error) { if (id === this.requestId) { this.status = (error as Error).message; } }
    finally { if (id === this.requestId) { this.working = false; } }
  }
  build() {
    Column({ space: 12 }) {
      if (!this.configOnly) {
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
      Button('AI 服务设置  ›').height(48).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).width('100%').onClick(() => this.onOpenConfig())
      } else {
        Text('AI 服务').fontSize(22).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).width('100%')
        Text('填写服务根地址或完整接口地址，保存时自动补齐 /chat/completions。').fontSize(13).fontColor($r('app.color.text_secondary')).width('100%')
        Button('使用 DeepSeek 官方预设').height(48).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).width('100%')
          .onClick(() => { this.configRevision++; this.cancel(); this.endpoint = 'https://api.deepseek.com'; this.model = 'deepseek-flash'; })
        Text('服务地址').fontSize(14).fontColor($r('app.color.text_secondary')).width('100%')
        TextInput({ text: this.endpoint, placeholder: 'https://api.deepseek.com' }).height(48).backgroundColor($r('app.color.card_background')).fontColor($r('app.color.text_primary')).onChange((v: string) => { this.configRevision++; this.cancel(); this.endpoint = v; })
        Text('模型').fontSize(14).fontColor($r('app.color.text_secondary')).width('100%')
        TextInput({ text: this.model, placeholder: 'deepseek-flash' }).height(48).backgroundColor($r('app.color.card_background')).fontColor($r('app.color.text_primary')).onChange((v: string) => { this.configRevision++; this.cancel(); this.model = v; })
        Text('API Key · ' + this.keyStatus).fontSize(14).fontColor($r('app.color.text_secondary')).width('100%')
        TextInput({ text: this.secret, placeholder: '留空沿用现有密钥' }).type(InputType.Password).height(48).backgroundColor($r('app.color.card_background')).fontColor($r('app.color.text_primary')).onChange((v: string) => { this.cancel(); this.secret = v; })
        Row({ space: 8 }) {
          Button('安全保存').height(48).layoutWeight(1).fontSize(14).backgroundColor(this.persistKey ? $r('app.color.accent') : $r('app.color.chip_background')).fontColor(this.persistKey ? $r('app.color.on_accent') : $r('app.color.text_primary')).onClick(() => { this.persistKey = true; })
          Button('仅本次运行').height(48).layoutWeight(1).fontSize(14).backgroundColor(!this.persistKey ? $r('app.color.accent') : $r('app.color.chip_background')).fontColor(!this.persistKey ? $r('app.color.on_accent') : $r('app.color.text_primary')).onClick(() => { this.persistKey = false; })
        }
        Text(this.persistKey ? '密钥进入系统安全存储，重启后保留，不随备份导出。' : '密钥只留在应用内存，进程结束后清除；不会覆盖之前安全保存的密钥。').fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
        Button(this.configSaving ? '正在保存…' : '保存服务配置与密钥').height(50).backgroundColor($r('app.color.accent')).fontColor($r('app.color.on_accent')).width('100%').enabled(!this.configSaving && !this.working).onClick(() => this.saveConfig())
        Button('测试连接与草稿响应').height(48).backgroundColor($r('app.color.chip_background')).fontColor($r('app.color.text_primary')).width('100%').enabled(!this.working && !this.configSaving).onClick(() => this.testConnection())
        Text('测试只发送固定的买牛奶句子，不创建任务。未保存的新密钥也可用于测试。').fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
        if (this.working) { Button('取消测试').height(48).onClick(() => this.cancel()) }
        if (this.status) { Text(this.status).fontSize(14).fontColor($r('app.color.text_primary')).width('100%') }
        Button('诊断安全存储').height(48).backgroundColor(Color.Transparent).fontColor($r('app.color.text_secondary')).width('100%').enabled(!this.configSaving && !this.working).onClick(() => this.diagnose())
        Button('移除已保存密钥').height(48).backgroundColor(Color.Transparent).fontColor($r('app.color.text_secondary')).width('100%').enabled(!this.configSaving && !this.working).onClick(() => this.removeKey())
      }
    }.width('100%')
  }
}
