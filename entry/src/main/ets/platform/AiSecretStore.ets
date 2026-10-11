import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { AiConfigService } from '../services/AiConfigService';
class AiStorageError extends Error {
  code: number;
  constructor(code: number) { super(AiConfigService.failure('secret', code)); this.code = code; }
}
export class AiSecretStore {
  private static sessionKey: string = '';
  private static queryMap(): asset.AssetMap {
    const map: asset.AssetMap = new Map(); map.set(asset.Tag.ALIAS, new util.TextEncoder().encodeInto('taiplan_ai_v1')); return map;
  }
  static async save(key: string): Promise<void> {
    const clean = AiConfigService.validateSecret(key);
    const attrs = AiSecretStore.queryMap(); attrs.set(asset.Tag.SECRET, new util.TextEncoder().encodeInto(clean));
    attrs.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
    attrs.set(asset.Tag.CONFLICT_RESOLUTION, asset.ConflictResolution.OVERWRITE);
    await asset.add(attrs);
    AiSecretStore.sessionKey = '';
    if ((await AiSecretStore.read()) !== clean) { throw new Error('密钥写入后读回不一致'); }
  }
  static useSession(key: string): void { AiSecretStore.sessionKey = AiConfigService.validateSecret(key); }
  static async status(): Promise<string> {
    if (AiSecretStore.sessionKey) { return '仅本次运行，重启应用后需重新填写'; }
    try { return (await AiSecretStore.read()) ? '已安全保存' : '未配置密钥'; }
    catch (error) { return AiConfigService.failure('secret', (error as BusinessError).code); }
  }
  static async read(): Promise<string> {
    if (AiSecretStore.sessionKey) { return AiSecretStore.sessionKey; }
    const query = AiSecretStore.queryMap(); query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    try {
      const result = await asset.query(query); if (!result.length) { return ''; }
      return util.TextDecoder.create('utf-8').decodeToString(result[0].get(asset.Tag.SECRET) as Uint8Array);
    } catch (error) { if ((error as BusinessError).code === 24000002) { return ''; } throw new AiStorageError((error as BusinessError).code); }
  }
  static async clear(): Promise<void> {
    AiSecretStore.sessionKey = '';
    try { await asset.remove(AiSecretStore.queryMap()); } catch (error) { if ((error as BusinessError).code !== 24000002) { throw error as Error; } }
  }
  static async probe(): Promise<void> {
    const attrs: asset.AssetMap = new Map();
    attrs.set(asset.Tag.ALIAS, new util.TextEncoder().encodeInto('taiplan_probe_' + util.generateRandomUUID()));
    attrs.set(asset.Tag.SECRET, new util.TextEncoder().encodeInto('TaiPlan-storage-probe'));
    attrs.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
    const query: asset.AssetMap = new Map(); query.set(asset.Tag.ALIAS, attrs.get(asset.Tag.ALIAS)!);
    await asset.add(attrs);
    try {
      const read: asset.AssetMap = new Map(); read.set(asset.Tag.ALIAS, attrs.get(asset.Tag.ALIAS)!); read.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
      const result = await asset.query(read);
      if (!result.length || util.TextDecoder.create('utf-8').decodeToString(result[0].get(asset.Tag.SECRET) as Uint8Array) !== 'TaiPlan-storage-probe') { throw new Error('安全存储读回不一致'); }
    } finally { await asset.remove(query); }
  }
}
