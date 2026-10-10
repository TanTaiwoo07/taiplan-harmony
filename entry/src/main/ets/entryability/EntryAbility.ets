import { SpeechService } from '../platform/SpeechService';
import { UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want): void { this.receive(want); }
  onNewWant(want: Want): void { this.receive(want); }
  private receive(want: Want): void {
    const id = want.parameters?.taskId; const day = want.parameters?.originalDate;
    if (typeof id === 'string' && typeof day === 'string') { AppStorage.setOrCreate('taiplanReminderTarget', JSON.stringify([id, day])); }
  }
  onBackground(): void { SpeechService.shared.cancel(); }
  onDestroy(): void { SpeechService.shared.cancel(); }
  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index');
  }
}
