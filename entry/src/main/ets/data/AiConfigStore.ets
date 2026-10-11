import { common } from '@kit.AbilityKit';
import { preferences, relationalStore } from '@kit.ArkData';
import { AiConfigService } from '../services/AiConfigService';
export interface AiConfig { endpoint: string; model: string; }
export class AiConfigStore {
  static validate(config: AiConfig): void {
    if (!config || typeof config.endpoint !== 'string' || typeof config.model !== 'string' || config.endpoint.length > 2048 || config.model.length > 128 ||
      (config.endpoint && AiConfigService.endpoint(config.endpoint).length > 2048)) { throw new Error('AI 配置无效'); }
  }
  static async load(context: common.UIAbilityContext): Promise<AiConfig> {
    const db = await relationalStore.getRdbStore(context, { name: 'taiplan.db', securityLevel: relationalStore.SecurityLevel.S1 });
    const rows = await db.querySql("SELECT value FROM metadata WHERE key='setting:ai_config'");
    try { if (rows.goToNextRow()) { const config = JSON.parse(rows.getString(0)) as AiConfig; AiConfigStore.validate(config); return config; } }
    finally { rows.close(); }
    const old = await preferences.getPreferences(context, { name: 'taiplan_ai' });
    const config: AiConfig = { endpoint: await old.get('endpoint', '') as string, model: await old.get('model', '') as string };
    AiConfigStore.validate(config); return config;
  }
  static async save(context: common.UIAbilityContext, config: AiConfig): Promise<void> {
    AiConfigStore.validate(config);
    const db = await relationalStore.getRdbStore(context, { name: 'taiplan.db', securityLevel: relationalStore.SecurityLevel.S1 });
    const normalized: AiConfig = { endpoint: config.endpoint ? AiConfigService.endpoint(config.endpoint) : '', model: config.model.trim() };
    await db.executeSql('INSERT OR REPLACE INTO metadata(key,value) VALUES (?,?)', ['setting:ai_config', JSON.stringify(normalized)]);
  }
}
