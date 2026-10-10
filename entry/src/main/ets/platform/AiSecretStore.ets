import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
export class AiSecretStore {
  private static queryMap(): asset.AssetMap {
    const map: asset.AssetMap = new Map(); map.set(asset.Tag.ALIAS, new util.TextEncoder().encodeInto('taiplan_ai_v1')); return map;
  }
  static async save(key: string): Promise<void> {
    if (!key.trim() || key.length > 4096) { throw new Error('密钥长度无效'); }
    const attrs = AiSecretStore.queryMap(); attrs.set(asset.Tag.SECRET, new util.TextEncoder().encodeInto(key));
    attrs.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
    attrs.set(asset.Tag.CONFLICT_RESOLUTION, asset.ConflictResolution.OVERWRITE);
    await asset.add(attrs);
  }
  static async read(): Promise<string> {
    const query = AiSecretStore.queryMap(); query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    const result = await asset.query(query); if (!result.length) { return ''; }
    return util.TextDecoder.create('utf-8').decodeToString(result[0].get(asset.Tag.SECRET) as Uint8Array);
  }
  static async clear(): Promise<void> { await asset.remove(AiSecretStore.queryMap()); }
}
