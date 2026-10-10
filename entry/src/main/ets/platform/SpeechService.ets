import { speechRecognizer } from '@kit.CoreSpeechKit';
import { audio } from '@kit.AudioKit';
import { abilityAccessCtrl, common } from '@kit.AbilityKit';
export class SpeechService {
  static shared: SpeechService = new SpeechService();
  private engine: speechRecognizer.SpeechRecognitionEngine | undefined = undefined;
  private capturer: audio.AudioCapturer | undefined = undefined;
  private session: string = '';
  private timer: number = -1;
  private status: (value: string) => void = () => {};
  async start(context: common.UIAbilityContext, onText: (text: string) => void, onStatus: (text: string) => void): Promise<void> {
    await this.cancel(); const session = 'taiplan_' + Date.now().toString(); this.session = session; this.status = onStatus;
    try {
      if (!canIUse('SystemCapability.AI.SpeechRecognizer')) { throw new Error('设备不支持原生语音识别'); }
      onStatus('正在请求麦克风权限');
      const permission = await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(context, ['ohos.permission.MICROPHONE']);
      if (this.session !== session) { return; }
      if (permission.authResults.some((result: number) => result !== 0)) { throw new Error('麦克风未授权，可继续文字输入'); }
      onStatus('正在准备中文识别模型');
      const engine = await speechRecognizer.createEngine({ language: 'zh-CN', online: 1 });
      if (this.session !== session) { engine.shutdown(); return; } this.engine = engine;
      engine.setListener({
        onStart: () => { if (this.session === session) { onStatus('正在聆听，最多 60 秒'); } },
        onEvent: () => {},
        onResult: (_id: string, result: speechRecognizer.SpeechRecognitionResult) => { if (this.session === session) { onText(result.result); } },
        onComplete: () => { if (this.session === session) { this.cancel(); onStatus('识别完成，请核对文字'); } },
        onError: (_id: string, code: number) => { if (this.session === session) { this.cancel(); onStatus('语音服务不可用（' + code.toString() + '），可改用文字输入'); } }
      });
      const capturer = await audio.createAudioCapturer({ streamInfo: { samplingRate: audio.AudioSamplingRate.SAMPLE_RATE_16000,
        channels: audio.AudioChannel.CHANNEL_1, sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE, encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW },
        capturerInfo: { source: audio.SourceType.SOURCE_TYPE_MIC, capturerFlags: 0 } });
      if (this.session !== session) { await capturer.release(); return; } this.capturer = capturer;
      let pending = new Uint8Array(0);
      capturer.on('readData', (data: ArrayBuffer) => {
        if (this.session !== session) { return; }
        const bytes = new Uint8Array(pending.length + data.byteLength); bytes.set(pending); bytes.set(new Uint8Array(data), pending.length);
        let offset = 0;
        try { while (offset + 640 <= bytes.length) { engine.writeAudio(session, bytes.slice(offset, offset + 640)); offset += 640; } }
        catch { this.cancel(); onStatus('音频传输失败，请重试'); }
        pending = bytes.slice(offset);
      });
      engine.startListening({ sessionId: session, audioInfo: { audioType: 'pcm', sampleRate: 16000, soundChannel: 1, sampleBit: 16 } });
      await capturer.start();
      if (this.session !== session) { return; }
      this.timer = setTimeout(() => { this.finish(); }, 59000);
    } catch (error) { if (this.session === session) { await this.cancel(); onStatus('语音未启动：' + (error as Error).message); } }
  }
  async finish(): Promise<void> {
    if (this.timer !== -1) { clearTimeout(this.timer); this.timer = -1; }
    const capturer = this.capturer; this.capturer = undefined;
    if (capturer) { try { await capturer.stop(); } catch {} try { await capturer.release(); } catch {} }
    try { this.engine?.finish(this.session); this.status('正在整理识别结果'); this.timer = setTimeout(() => { this.cancel(); }, 10000); }
    catch { await this.cancel(); }
  }
  async cancel(): Promise<void> {
    const session = this.session; this.session = '';
    if (this.timer !== -1) { clearTimeout(this.timer); this.timer = -1; }
    const engine = this.engine; this.engine = undefined;
    try { if (engine) { engine.cancel(session); engine.shutdown(); } } catch { try { engine?.shutdown(); } catch {} }
    const capturer = this.capturer; this.capturer = undefined;
    if (capturer) { try { await capturer.stop(); } catch {} try { await capturer.release(); } catch {} }
  }
}
