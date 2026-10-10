import { http } from '@kit.NetworkKit';
import { DraftProposal, DraftService } from '../services/DraftService';
import { ScheduleService } from '../services/ScheduleService';
interface Message { role: string; content: string; }
interface CompletionRequest { model: string; messages: Message[]; temperature: number; stream: boolean; }
interface Choice { message: Message; }
interface CompletionResponse { choices: Choice[]; }
export class AiClient {
  private request: http.HttpRequest | undefined = undefined;
  cancel(): void { this.request?.destroy(); this.request = undefined; }
  async parse(endpoint: string, model: string, key: string, input: string, now: number): Promise<DraftProposal[]> {
    if (!/^https:\/\/[^\s@?#]+\/[^\s?#]*$/.test(endpoint) || !model.trim() || !key.trim() || key.includes('\n') || input.length > 4000 || !input.trim()) {
      throw new Error('填写 HTTPS 完整 chat/completions 地址、模型、密钥与输入内容');
    }
    const req = http.createHttp(); this.cancel(); this.request = req;
    const body: CompletionRequest = { model: model.trim(), temperature: 0, stream: false, messages: [
      { role: 'system', content: '你只生成待确认日程草稿，不执行任何操作。今天是' + ScheduleService.key(now) + '，本地时区' + Intl.DateTimeFormat().resolvedOptions().timeZone +
        '。返回JSON对象{drafts:[{title,date,time,duration,priority,location,note,explanation,kind,list,deadlineDate,deadlineTime,repeat,interval,weekdays,until,count,reminder,leadMinutes}]}。date/deadlineDate/until为YYYY-MM-DD或空串，time/deadlineTime为HH:mm或空串；duration为5到1440整数分钟，默认30；priority为0/1/2，未说明为1；kind为task或event，event必须有日期且无deadline；list为清单名或空串；repeat为none/daily/weekly/monthly/yearly，interval默认1，weekdays仅weekly可填ISO星期1到7数组，until和count不能同时设置，count默认0；reminder为none/start/deadline，leadMinutes为0到10080整数；没有明确提醒要求用none。没有时间的今天任务保留time空串。其他字段为字符串。不臆造时间地点优先级。模糊内容和无法表达规则保留在note与explanation，要求用户确认。最多20条。' },
      { role: 'user', content: input }
    ] };
    try {
      const response = await req.request(endpoint, { method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + key }, extraData: JSON.stringify(body),
        connectTimeout: 15000, readTimeout: 30000, expectDataType: http.HttpDataType.STRING, usingCache: false });
      if (this.request !== req) { throw new Error('已取消'); }
      if (response.responseCode !== 200) { throw new Error('AI 请求失败，HTTP ' + response.responseCode.toString() + '；请检查鉴权、模型和配额'); }
      const raw = response.result as string; if (raw.length > 100000) { throw new Error('AI 响应过长'); }
      const doc = JSON.parse(raw) as CompletionResponse;
      if (!doc.choices?.length || typeof doc.choices[0].message?.content !== 'string') { throw new Error('服务未返回兼容格式'); }
      return DraftService.decode(doc.choices[0].message.content, now);
    } finally { req.destroy(); if (this.request === req) { this.request = undefined; } }
  }
}
