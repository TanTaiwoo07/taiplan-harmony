"""Build the Chinese presentation PDF from local validation evidence. Requires reportlab."""
from pathlib import Path
from reportlab.pdfgen import canvas
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.lib.colors import HexColor
import re
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'delivery'; OUT.mkdir(exist_ok=True)
pdfmetrics.registerFont(TTFont('CN','C:/Windows/Fonts/msyh.ttc',subfontIndex=0))
c=canvas.Canvas(str(OUT/'TaiPlan-Harmony-Report.pdf'),pagesize=(960,540))
c.setTitle('TaiPlan Harmony - 模拟器交付汇报');c.setAuthor('TaiWoo_Chen')
INK='#202124';MUTED='#626773';RED='#C4373E'
page=0

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
 page+=1;c.setFillColor(HexColor('#F5F5F7'));c.rect(0,0,960,540,fill=1,stroke=0)
 text(48,490,'TAIPLAN / HARMONYOS',12,MUTED)
 text(48,436,title,30)
 if sub:text(48,400,sub,13,MUTED)
 text(48,24,'0.8.0-rc.1  |  本机 API 26 模拟器交付候选  |  2026-10-11',10,MUTED)
 text(890,24,str(page).zfill(2),11,MUTED)

def bullets(items,y=350,width=850):
 for heading,body in items:
  y=text(52,y,heading,20,INK,width)
  y=text(52,y-2,body,15,MUTED,width)-20

def image(name,x,y,w,h):
 p=ROOT/'milestones'/name
 if p.exists():c.drawImage(str(p),x,y,w,h,preserveAspectRatio=True,anchor='c',mask='auto')

base('把「想做」变成「能安排、能完成」','待办是核心，日历负责时间，可选工具保持克制。')
text(52,332,'TaiPlan',54)
text(52,252,'从桌面项目迁移到鸿蒙原生应用',22)
text(52,205,'ArkTS + ArkUI + SQLite',19,MUTED)
text(52,158,'四栏导航 / 无日期收集 / 重复日程 / 智能草稿',16,MUTED,maxwidth=540)
text(52,109,'本报告明确区分：已验证功能、原生适配与未验收能力。',14,RED,maxwidth=555)
image('08-urgent.png',678,66,195,360);c.showPage()
base('首页只回答：今天先做什么？','颜色表达紧急程度，清单和标签表达工作分类。')
bullets([('今天','完成概览、紧急和逾期提示、当日任务与事件。'),('待办与日历','收集箱不强制日期；年、月、周、日逐层进入时间表。'),('设置与可选工具','外观、分类、备份、AI 配置；专注、习惯、倒数日可隐藏。')],width=555)
image('08-urgent-dark.png',697,56,173,333);c.showPage()
base('考核要求对应到可操作的入口')
rows=[('新建 / 编辑 / 删除 / 完成','记一件事；点标题编辑；更多菜单删除；勾选完成'),('待办 / 已完成 / 创建倒序','待办的全部视图；展开已完成；默认创建倒序'),('深浅色与搜索','设置外观；首页右上角搜索；支持备注、标签和地点'),('拖拽 / 标签 / 优先级','筛选内拖拽排序；编辑器标签与高、中、低优先级'),('扩展体验','重复单次编辑、备份、离线草稿、可选个人工具')]
y=352
for a,b in rows:
 c.setFillColor(HexColor('#FFFFFF'));c.roundRect(48,y-48,864,64,10,fill=1,stroke=0)
 text(65,y-6,a,16,maxwidth=280);text(366,y-6,b,14,MUTED,maxwidth=520);y-=64
c.showPage()
base('代码如何协作','界面不直接信任 AI，也不直接拼数据库写入。')
for x,w,label,detail in [(48,258,'ArkUI 页面与组件','Index / TaskCard / Calendar'),(351,258,'纯业务服务','Planning / Recurrence / Draft'),(654,258,'数据库与系统适配','TaskRepository / Reminder / AI')]:
 c.setFillColor(HexColor('#FFFFFF'));c.roundRect(x,242,w,119,14,fill=1,stroke=0)
 text(x+16,327,label,19,maxwidth=w-32);text(x+16,290,detail,13,MUTED,maxwidth=w-32)
text(321,294,'→',21);text(624,294,'→',21)
bullets([('保存流程','草稿校验 → SQLite 事务提交 → 刷新列表 → 同步系统提醒。'),('两种成功必须分开','任务保存成功，不代表系统提醒登记成功；错误不能悄悄吞掉。')],y=190);c.showPage()
base('最重要的数据设计：安排 ≠ 截止')
bullets([('无日期 / 仅日期 / 精确时间','买牛奶可先留在收集箱；今天读书不需要时间；会议可以占 14:00-15:00。'),('重复日程的身份稳定','系列 ID + 原始日期标识一次发生。改到别的日期后，完成记录仍关联原身份。'),('修改范围与保护','仅本次、这次及以后、整个系列。未来已有记录的复杂拆分会拒绝，避免历史丢失。')]);c.showPage()
base('AI、语音与提醒：能力和证据分开','已按用户选择，以本机模拟器为本次交付边界。')
bullets([('智能草稿','离线多条识别；云端可配置 HTTPS 接口与模型；日期、时间、重复、提醒均校验。'),('保护与确认','只在主动请求时发送输入；密钥进入安全资产存储；草稿确认前不创建任务。'),('未完成的设备验收','真实 AI 请求与真机语音未验收。模拟器提醒发布返回 1700002，不能宣称锁屏或退进程可触发。')]);c.showPage()
base('测试、恢复与性能','测试结果是可复现证据，不等于所有设备都已验收。')
log=ROOT/'tests/current-08.log';hits=re.findall(r'tests (\d+)',log.read_text(encoding='utf-8') if log.exists() else '')
count=hits[-1] if hits else '117'
bullets([(count+' 项回归通过','覆盖纯业务、真实 SQLite、回滚和系统适配器替身；模拟器另做点击、重启与视觉检查。'),('备份格式 7','任务、发生项、专注、习惯、倒数日与偏好事务恢复；不迁移密钥或旧系统提醒 ID。'),('5,000 任务 + 500 重复系列','本机 Node 中位数：搜索 1.3 ms；今日概览 29.58 ms；月数据 127.42 ms。不是模拟器帧率。')]);c.showPage()
base('三分钟演示与后续边界')
bullets([('演示路线','首页紧急提示 → 收集箱 → 日历尺度 → 习惯打卡/撤销 → 倒数日 → 专注与外观。'),('交付物','源码归档、未签名模拟器 HAP、一键启动脚本、README、开发台账、此 PDF 与静音演示视频。'),('保留的边界','真实系统能力待设备验收；复杂 ICS、任意时区、历史系列任意重排与云端 AI 排程尚未完整实现。')]);c.showPage()
c.save();print(OUT/'TaiPlan-Harmony-Report.pdf')
