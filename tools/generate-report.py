"""Generate the 1.0 simulator delivery report from current validation evidence."""
from pathlib import Path
from reportlab.pdfgen import canvas
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.lib.colors import HexColor
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'delivery';OUT.mkdir(exist_ok=True)
pdfmetrics.registerFont(TTFont('CN','C:/Windows/Fonts/msyh.ttc',subfontIndex=0))
c=canvas.Canvas(str(OUT/'TaiPlan-Harmony-1.0-Report.pdf'),pagesize=(960,540))
c.setTitle('TaiPlan Harmony 1.0 - 本机模拟器交付汇报');c.setAuthor('TaiWoo_Chen')
INK='#202124';MUTED='#656D70';GREEN='#346B60';page=0

def text(x,y,value,size=18,color=INK,maxwidth=835,leading=None):
 c.setFillColor(HexColor(color));c.setFont('CN',size);line='';leading=leading or size*1.5
 for char in value:
  if char=='\n' or pdfmetrics.stringWidth(line+char,'CN',size)>maxwidth:
   c.drawString(x,y,line);y-=leading;line='' if char=='\n' else char
  else:line+=char
 if line:c.drawString(x,y,line)
 return y-leading

def base(title,sub=''):
 global page
 page+=1;c.setFillColor(HexColor('#F4F6F5'));c.rect(0,0,960,540,fill=1,stroke=0)
 text(48,490,'TAIPLAN / HARMONYOS',12,GREEN);text(48,436,title,30)
 if sub:text(48,400,sub,13,MUTED)
 text(48,24,'1.0.0  |  本机 API 26 模拟器交付  |  2026-10-11',10,MUTED);text(890,24,str(page).zfill(2),11,MUTED)

def bullets(items,y=350,width=850):
 for heading,body in items:
  y=text(52,y,heading,20,INK,width)
  y=text(52,y-2,body,15,MUTED,width)-20
 assert y>=35,('Page overflow',page,y)

def image(name,x,y,w,h):
 p=ROOT/'milestones'/name
 if p.exists():c.drawImage(str(p),x,y,w,h,preserveAspectRatio=True,anchor='c',mask='auto')

base('把「想到的事」变成「能完成的安排」','待办是核心，日历负责时间，工作台承载可选工具。')
text(52,331,'TaiPlan',54);text(52,253,'桌面产品经验，鸿蒙原生实现',22)
text(52,205,'ArkTS + ArkUI + SQLite + HarmonyOS API 26',18,MUTED,maxwidth=575)
text(52,155,'作者：TaiWoo_Chen',17,GREEN)
text(52,109,'交付范围：本机模拟器；真实设备能力单列验收。',14,MUTED,maxwidth=555)
image('10-home-live.png',678,66,195,360);c.showPage()
base('页面有层级，首屏有重点','低饱和绿辅助表达，红色只用于紧急和危险操作。')
bullets([('今天 / 待办 / 日历 / 工作台','完成概览与优先处理；无日期事项先进入收集箱。'),('入口归位','右上角单一齿轮；下拉搜索；统一工具卡片；分组设置。'),('动效与原生材质','非线性过渡、搜索展开、拖动影子；原生光感接口及回退；支持减少动态效果。')],width=555)
image('10-workbench-dark.png',697,56,173,333);c.showPage()
base('考核要求对应到可操作的入口')
rows=[('新建 / 编辑 / 删除 / 完成','记一件事；点任务编辑；更多菜单删除；勾选完成'),('待办 / 已完成 / 创建倒序','待办全部视图；展开已完成；默认创建倒序'),('深浅色与搜索','齿轮 - 外观；顶部下拉搜索标题、备注、地点、标签'),('拖拽 / 标签 / 优先级','筛选内排序；编辑器高、中、低；清单与标签管理'),('扩展体验','重复编辑、ICS、智能草稿、专注、习惯、倒数日')]
y=352
for a,b in rows:
 c.setFillColor(HexColor('#FFFFFF'));c.roundRect(48,y-48,864,64,10,fill=1,stroke=0)
 text(65,y-6,a,16,maxwidth=280);text(366,y-6,b,14,MUTED,maxwidth=520);y-=64
c.showPage()
base('代码如何协作','UI 发起动作，业务层校验，数据层用事务保存。')
for x,w,label,detail in [(48,258,'ArkUI 页面与组件','Index / TaskCard / Calendar'),(351,258,'纯业务服务','Planning / Recurrence / AI Plan'),(654,258,'数据库与系统适配','TaskRepository / Reminder / AI')]:
 c.setFillColor(HexColor('#FFFFFF'));c.roundRect(x,242,w,119,14,fill=1,stroke=0)
 text(x+16,327,label,19,maxwidth=w-32);text(x+16,290,detail,13,MUTED,maxwidth=w-32)
text(321,294,'→',21);text(624,294,'→',21)
bullets([('一次保存','草稿校验 → SQLite 事务 → 刷新投影 → 提醒对账。'),('成功必须分开','任务保存成功，不等于系统提醒登记和送达成功。')],y=190);c.showPage()
base('时间语义：安排 ≠ 截止')
bullets([('无日期 / 仅日期 / 精确时间','先收集灵感；今天读书不占小时格；会议可以覆盖 14:00-15:00。'),('重复发生项身份稳定','系列 ID + 原始日期。单次改期后完成记录仍关联原身份。'),('三种修改范围','仅本次、这次及以后、整个系列。未来已有历史的复杂拆分会拒绝，保护已有进度。')]);c.showPage()
base('AI 优化：评价、建议、预览、确认','既有日程不移动；候选标题和匿名忙碌段按确认发送。')
bullets([('明确当前时间和可用空档','程序先计算未来7天空档，再请求结构化建议；优先级名称明确。'),('校验后再采用','检查 ID、日期、网格、时长、截止和冲突；支持单项采用、全部采用与撤销。'),('本机真实验证','收到有效 AI 安排并采用/撤销；另一份冲突响应被拒绝。单次成功不代表所有模型都已验收。')],width=555)
image('10-ai-final.png',697,56,173,333);c.showPage()
base('日历互通与安全恢复')
bullets([('ICS 常见课表','常见 RRULE、EXDATE、单次调课及 RDATE；IANA 时区和跨夏令时系列可展开。'),('同来源更新需要确认','默认保留旧 UID；显式更新无进度的日历来源事项。有完成记录或例外则保护。'),('备份和边界','备份7覆盖任务、工具与偏好，不含密钥。ICS 是有报告的子集；无结束跨时区系列只展开到一年后。')]);c.showPage()
base('证据和能力边界','没有用模拟器结果替代真机能力验证。')
bullets([('154 项回归 + API 26 构建','真实 SQLite 事务/回滚、AI 校验、夏令时、ICS 来源更新；原生覆盖安装与交互另验。'),('5,000 任务 + 500 重复系列','Node 中位数：搜索1.33 ms；今日概览31.43 ms；月数据123.87 ms。不是原生帧率。'),('仍需真实设备','中文语音、锁屏/退进程提醒、签名安装、尺寸/读屏/连续双指矩阵。模拟器提醒失败1700002明确保留。')]);c.showPage()
base('交付与三分钟演示','每个版本独立归档，源码、运行包和验证记录对应。')
bullets([('演示路线','首页 → 工作台 AI 预览 → 采用 → 日历 → 设置外观 → 关于。临时任务测试后删除。'),('交付材料','源码 ZIP、模拟器 HAP、运行入口、README、交付记录、此 PDF、抽帧操作视频、SHA256。'),('项目与后续验收','github.com/TanTaiwoo07/taiplan-harmony（私有）。1.0 为本机交付范围，后续补真机验收，不宣称完整 RFC 或全设备认证。')]);c.showPage()
c.save();print(OUT/'TaiPlan-Harmony-1.0-Report.pdf')
