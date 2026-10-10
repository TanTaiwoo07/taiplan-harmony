import { common } from '@kit.AbilityKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';

export class BackupFiles {
  static async exportFile(context: common.UIAbilityContext, content: string, extension: string = 'json'): Promise<boolean> {
    const bytes = util.TextEncoder.create('utf-8').encodeInto(content);
    if (bytes.byteLength > 4 * 1024 * 1024) { throw new Error('备份超过 4 MB，暂不支持导出'); }
    const view = new picker.DocumentViewPicker(context);
    const uris = await view.save({ newFileNames: [`TaiPlan-${Date.now()}.${extension}`], fileSuffixChoices: [`TaiPlan 文件|.${extension}`] });
    if (uris.length === 0) { return false; }
    const file = await fileIo.open(uris[0], fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
    try {
      const written = await fileIo.write(file.fd, bytes.buffer as ArrayBuffer);
      if (written !== bytes.byteLength) { throw new Error('备份未完整写入，请重新导出'); }
      await fileIo.fsync(file.fd);
    } finally { await fileIo.close(file); }
    return true;
  }
  static async importFile(context: common.UIAbilityContext, extension: string = 'json'): Promise<string | undefined> {
    const view = new picker.DocumentViewPicker(context);
    const uris = await view.select({ maxSelectNumber: 1, fileSuffixFilters: [`.${extension}`] });
    if (uris.length === 0) { return undefined; }
    const file = await fileIo.open(uris[0], fileIo.OpenMode.READ_ONLY);
    try {
      const stat = await fileIo.stat(file.fd);
      if (stat.size === 0 || stat.size > 4 * 1024 * 1024) { throw new Error('请选择 4 MB 以内的非空备份'); }
      const buffer = new ArrayBuffer(stat.size);
      const count = await fileIo.read(file.fd, buffer);
      if (count !== stat.size) { throw new Error('文件未完整读取，请重试'); }
      return util.TextDecoder.create('utf-8', { fatal: true }).decodeToString(new Uint8Array(buffer));
    } finally { await fileIo.close(file); }
  }
}
