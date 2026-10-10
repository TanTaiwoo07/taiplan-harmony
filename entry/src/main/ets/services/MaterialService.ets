import { uiMaterial } from '@kit.ArkUI';

export class MaterialService {
  static supported(): boolean {
    try { return uiMaterial.isImmersiveMaterialSupported(); } catch { return false; }
  }
  static surface(enabled: boolean): uiMaterial.ImmersiveMaterial | undefined {
    if (!enabled || !MaterialService.supported()) { return undefined; }
    try { return new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.REGULAR, interactive: true }); }
    catch { return undefined; }
  }
}
