import { uiMaterial } from '@kit.ArkUI';

export class MaterialService {
  static supported(): boolean {
    try { return uiMaterial.isImmersiveMaterialSupported(); } catch { return false; }
  }
  static nativeDock(enabled: boolean): boolean {
    if (!enabled || !MaterialService.supported()) { return false; }
    try { return uiMaterial.getMaterialInfo().state !== uiMaterial.MaterialState.DISABLE; } catch { return false; }
  }
  static description(): string {
    if (!MaterialService.supported()) { return '当前设备使用上一版材质回退'; }
    try {
      const level = uiMaterial.getGlobalMaterialLevel();
      const name = level === uiMaterial.MaterialLevel.EXQUISITE ? '精致' : level === uiMaterial.MaterialLevel.GENTLE ? '柔和' : '流畅';
      return '系统材质档位：' + name + '；视觉效果由设备与系统沉浸光感设置决定';
    } catch { return '当前设备支持系统沉浸光感，效果由系统控制'; }
  }
  static surface(enabled: boolean): uiMaterial.ImmersiveMaterial | undefined {
    if (!MaterialService.nativeDock(enabled)) { return undefined; }
    try { return new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.REGULAR }); }
    catch { return undefined; }
  }
  static dock(enabled: boolean, reduced: boolean): uiMaterial.ImmersiveMaterial | undefined {
    if (!MaterialService.nativeDock(enabled)) { return undefined; }
    try { return new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
      interactive: !reduced, lightEffect: reduced ? null : {}, applyShadow: true }); }
    catch { return undefined; }
  }
}
