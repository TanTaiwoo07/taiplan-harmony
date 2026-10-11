export class AiConfigService {
  static endpoint(value: string): string {
    const text = value.trim().replace(/\/+$/, '');
    if (text.length > 2048 || !/^https:\/\/[a-zA-Z0-9.-]+(?::\d+)?(?:\/[^\s@?#]*)?$/.test(text)) {
      throw new Error('地址须为 HTTPS 服务地址，不能包含凭据或查询参数');
    }
    if (text.endsWith('/chat/completions')) { return text; }
    const endpoint = text + '/chat/completions';
    if (endpoint.length > 2048) { throw new Error('服务地址过长'); }
    return endpoint;
  }
  static validateSecret(value: string): string {
    const key = value.trim();
    if (!key || key.length > 4096 || /[\x00-\x20\x7f]/.test(key)) { throw new Error('密钥为空、过长或含空白字符，请重新粘贴'); }
    return key;
  }
  static failure(stage: string, code: number = 0, http: number = 0): string {
    if (stage === 'network') {
      if (http === 401 || http === 403) { return '鉴权失败，请检查密钥及服务访问权限（HTTP ' + http.toString() + '）'; }
      if (http === 404) { return '接口不存在，请检查服务地址（HTTP 404）'; }
      if (http === 429) { return '服务限流或配额不足，请稍后重试（HTTP 429）'; }
      if (http >= 500) { return 'AI 服务暂时异常，请稍后重试（HTTP ' + http.toString() + '）'; }
      if (http) { return '请求参数或模型不被服务接受（HTTP ' + http.toString() + '）'; }
      return '网络请求失败或超时，请检查网络后重试';
    }
    if (stage === 'secret') {
      if (code === 24000001) { return '设备安全存储服务不可用，可主动选择仅本次运行'; }
      if (code === 24000005) { return '设备解锁状态不满足安全存储要求，请解锁后重试'; }
      return '安全存储操作失败' + (code ? '（错误码 ' + code.toString() + '）' : '') + '；没有写入普通文件';
    }
    return '服务配置保存失败，请重试';
  }
}
