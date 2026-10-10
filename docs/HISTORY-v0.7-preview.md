# TaiPlan Harmony 0.7.0-preview.1

鸿蒙原生待办与日历应用，ArkTS + ArkUI + HarmonyOS API 26。

这是 0.6/0.7 联合开发预览，两个正式阶段都尚未全面验收。实际范围、设备限制、验证证据与接续入口见 [联合开发交接](docs/INTEGRATED-0607.md)；[上次 0.6 检查点](docs/PHASE1-PREVIEW.md) 仅供历史参考，总需求见 [三阶段开发计划](docs/DEVELOPMENT_PLAN.md)。[0.5.0 文档](docs/HISTORY-v0.5.0.md) 仅供历史参考。

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
- SQLite 事务迁移；JSON 备份格式 6，兼容导入格式 3、4、5，包含重复单次例外和逻辑提醒。

## 使用规则与当前边界

快速收集不强制日期。需要今天完成时点“安排今天”，需要提醒自己某日必须交付时另设“截止期限”。只有明确截止的任务才会逾期；历史 0.5 任务保留原来的截止含义。

点击任务标题编辑，“更多设置”显示地点、清单、备注、重复等字段。返回编辑器会提示未保存的更改。无时间事项放在日期区域，不挤占 00:00。周视图可以横向滑动查看七列。

全局搜索通过右上角“搜索”进入，包含已完成事项，重复系列只显示一次。默认创建倒序；已有用户选择的其他排序会被保留。

本轮新增：重复单次改期、受保护的此后拆分、时间块拖动/时长调整与撤销、常见重复 ICS/排除日期/调课、多条自然语言草稿、原生语音适配、云端 AI 与安全密钥存储、系统提醒登记对账、本地辅助排程。

**系统能力状态**：原生构建通过；模拟器已验证麦克风拒绝后文字可用、无密钥安全失败、时间块缩放与撤销。通知授权成功，但真实提醒发布返回 1700002；不能宣称后台提醒可用。语音中文真机识别、真实云端请求及锁屏/重启提醒尚待验收。

**仍有边界**：未来已有进度或例外的系列拆分会保护性拒绝；历史系列更改锚点/规则仍受限制。ICS 不支持 RDATE/复杂 RRULE/任意时区和同 UID 更新；重复课表只支持交接文档列出的子集。分类管理、完整设置、跨时区/DST 和全面设计/性能验收仍待补齐。

系统提醒只预约未来 7 天、应用侧最多 50 条，真实系统配额可能更少。每次打开或编辑补齐，长期不打开不会续约。云端 AI 需要在应用内填写自己的 HTTPS 服务地址、模型与密钥，只有主动点击才发送当前输入。密钥由 AssetStoreKit 保存，不进入任务备份。

本地辅助排程位于设置，保留已有安排，提出未来 7 天 09:00–21:00 的建议，确认后采用并可撤销；目前不是云端 AI 自动调度。番茄钟、习惯和倒数日仍属后续阶段。

## 项目结构

```text
entry/src/main/ets/
  model/Task.ets             任务、计划、重复和偏好类型
  data/                     SQLite、迁移、Preferences、文件选择器
  services/                 校验、投影、重复、时间布局、搜索、材质、备份、ICS
  components/               任务卡、月历、日历工作区、时间表、设置面板、智能输入
  platform/                 原生语音、代理提醒、AI 网络和安全资产存储
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

本轮 98 项通过，涵盖旧 60 项与新增时间语义、有限重复、跨午夜、真实 SQLite 迁移回滚和备份兼容等。平台接口在 Node 中使用测试替身，原生 UI 另在模拟器验收。

本轮升级前后七张原表逐行一致，原有 5 个任务和 3 条日期状态完整保留；单条临时验收任务已清理。模拟器实测草稿、麦克风拒绝、AI 无密钥失败、时长拖动与撤销、提醒失败反馈。完整验收与未完成项见联合开发交接。
