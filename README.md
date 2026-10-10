# TaiPlan Harmony 0.6.0-preview.1

鸿蒙原生待办与日历应用，ArkTS + ArkUI + HarmonyOS API 26。

这是第一阶段的可运行检查点，尚不是完整 0.6.0。实际范围、验证证据和下一步见 [开发交接](docs/PHASE1-PREVIEW.md)，总需求见 [三阶段开发计划](docs/DEVELOPMENT_PLAN.md)。[0.5.0 文档](docs/HISTORY-v0.5.0.md) 仅供历史参考。

## 本版本可用功能

- 今天、待办、日历、设置四个栏目；今日任务完成概览和日程分组。
- 底部“记一件事”与原生收集面板，默认无日期收集箱；输入框旁直接保存，键盘完成键可提交。
- 新建、编辑、删除撤销、完成／取消完成；事件不勾选完成，也不计入任务完成比例。
- 计划日期、起止区间和截止期限分开，支持无日期、仅日期、有时间、全天事件和跨午夜安排。
- 地点、清单名称、优先级、标签、子任务；全局搜索包括标题、备注、标签、地点和清单。
- 年份下十二个月入口，月视图选日，周／日时间表、重叠并排、跨午夜切片、当前时间线和长按小时格创建。
- 每日／每周／每月／每年，重复间隔、每周多个星期、截止日期或重复次数；月末不足日期自动补齐。
- 黑白灰界面；跟随系统／浅色／深色；支持设备的原生沉浸材质收集面板，可关闭。
- 启动页、默认日历尺度、每周起始日和默认展开已完成等持久偏好。
- 原有标签筛选、多选、四种排序、列表长按拖拽排序、本地一句话解析、有限 ICS 导入和桌面数据转换继续保留。
- SQLite 事务迁移；JSON 备份格式 5，兼容导入格式 3、4。

## 使用规则与当前边界

快速收集不强制日期。需要今天完成时点“安排今天”，需要提醒自己某日必须交付时另设“截止期限”。只有明确截止的任务才会逾期；历史 0.5 任务保留原来的截止含义。

点击任务标题编辑，“更多设置”显示地点、清单、备注、重复等字段。返回编辑器会提示未保存的更改。无时间事项放在日期区域，不挤占 00:00。周视图可以横向滑动查看七列。

全局搜索通过右上角“搜索”进入，包含已完成事项，重复系列只显示一次。默认创建倒序；已有用户选择的其他排序会被保留。

**尚未完成**：单次／此后／全部的系列编辑范围，时间块拖动与拉伸，完整重复课表 ICS、来源更新、分类配色、完整设置体系及真机全量验收。有历史的系列修改起始日期或规则暂时会拒绝保存，提示复制为新系列，原记录不会清空。改变子任务模板沿用旧版本的确认重置子任务进度行为。

ICS 仍是旧版单次事件子集，未知时区、跨日和重复规则逐项报告；不能宣传为已支持学期课表。导出为今天起 30 天快照，不是完整备份。JSON 恢复同 ID 保留本机数据，设置暂未包含在备份中。跨时区旅行与 DST 特殊时刻尚未验收。

语音、系统提醒、AI、番茄钟、习惯和倒数日仍在后续计划中。输入法语音可用不代表已接原生语音服务。

## 项目结构

```text
entry/src/main/ets/
  model/Task.ets             任务、计划、重复和偏好类型
  data/                     SQLite、迁移、Preferences、文件选择器
  services/                 校验、投影、重复、时间布局、搜索、材质、备份、ICS
  components/               任务卡、月历、日历工作区、时间表、设置面板
  pages/Index.ets            导航、共享状态、收集／编辑／搜索协调
  entryability/             原生应用入口
tests/core.test.cjs          Node + 真实 SQLite 回归
tools/desktop-transfer.cjs   桌面备份转换
docs/                       总计划、当前交接、历史说明
```

## 本机构建与运行

只使用桌面开发副本：`C:\Users\Lenovo\Desktop\taiplan-harmony-test`。原始 outputs/taiplan-harmony 是保护目录，不安装依赖、不编译。

已经安装 DevEco Studio 和 API 26 SDK 的本机 PowerShell：

```powershell
Set-Location 'C:\Users\Lenovo\Desktop\taiplan-harmony-test'
$env:DEVECO_SDK_HOME='D:\Program Files\Huawei\DevEco Studio\sdk'
$env:JAVA_HOME='D:\Program Files\Huawei\DevEco Studio\jbr'
$env:Path='D:\Program Files\Huawei\DevEco Studio\tools\node;'+$env:Path
& 'D:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat' --mode module -p product=default -p module=entry@default assembleHap --no-daemon
```

产物：`entry/build/default/outputs/default/entry-default-unsigned.hap`。在本机 API 26 模拟器覆盖安装，不卸载清库。先用 hdc 查询实际设备 ID：

```powershell
& 'D:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe' list targets
& 'D:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe' -t 127.0.0.1:5555 install -r entry/build/default/outputs/default/entry-default-unsigned.hap
& 'D:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe' -t 127.0.0.1:5555 shell aa start -a EntryAbility -b com.taiwoo.taiplan
```

这是原生应用，没有 localhost 地址。模拟器设备 ID 若不同需替换。真机需配置合适签名，未签名 HAP 不能保证直接装任意手机。

## 测试

```powershell
& 'D:\Program Files\Huawei\DevEco Studio\tools\node\node.exe' --test tests/core.test.cjs
```

本轮 82 项通过，涵盖旧 60 项与新增时间语义、有限重复、跨午夜、真实 SQLite 迁移回滚和备份兼容等。平台接口在 Node 中使用测试替身，原生 UI 另在模拟器验收。

升级前后六张旧表逐行一致：原有 5 个任务和 3 条日期状态完整保留；新增 task_planning 迁移成功，两条临时验收任务已清理。模拟器实测收集、emoji、安排今天、删除撤销、时间表滚动和深浅色。尚未完成完整 Design、大字体、真机及全部第一阶段验收。
