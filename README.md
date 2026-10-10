# TaiPlan Harmony 0.4.0

鸿蒙原生待办应用，使用 ArkTS、ArkUI、HarmonyOS API 26。开发与测试均在桌面 `taiplan-harmony-test` 副本中完成。

## 功能

- 任务新建、编辑、删除、完成与取消完成；待办和已完成分区，默认按创建时间倒序。
- 标题、备注、标签组合搜索；高 / 中 / 低优先级；最多 5 个标签，每个最多 12 字。
- 截止日期、开始时间、预计用时、逾期提示；系统 / 浅色 / 深色主题持久化。
- 每个任务最多 20 个子任务；重复事项的子任务进度按日期独立保存。
- 任务复制、按当前视图和筛选结果批量完成 / 恢复待办；今天与逾期数量摘要。
- 全部、今天、未来 30 天、月历四种视图。月历点击日期看当天事项，支持切换月份与回到今天。
- 每天、每周、每月重复；完成记录按日期独立保存。可以跳过单次，在工具页恢复，或确认后删除整组。
- 创建倒序、日程时间、优先级、手动顺序四种排序；工具页支持长按拖动与上下箭头。
- 一句话录入：本地规则识别日期、重复规则、标签、优先级，先预览草稿，再由用户保存。
- 系统文件选择器导出 / 导入 JSON 备份；校验后预览合并数量，已有同 ID 任务保持现状。
- ICS 日历导入、今天起 30 天日历快照导出；不支持的事件逐项报告。
- 桌面版 SQLite 备份转换工具，生成鸿蒙 JSON 备份及迁移报告。
- ArkData 关系型数据库保存任务、标签、排序及重复完成记录；自动保留并迁移旧版数据。

## 使用约定

**日期与重复**：全天任务以本地当天 23:59:59.999 判断逾期；有时间的任务以开始时间加预计用时判断。今天视图包含今天的重复事项和已逾期的普通未完成任务；没有截止日期的任务在全部视图中查看。未来视图展示明天起 30 天内的事项。全部视图每个重复系列只展示今天或下一次，过往完成记录可到月历查看。每周按起始日的星期重复，每月按起始日重复；不足该日的月份取最后一天，下月仍沿用原始日期。

编辑重复任务会修改整个系列；仅修改标题、备注等保留完成记录。改变起始日期或重复规则时，如果已有完成 / 跳过记录，会先提示确认重置。

**时间与冲突**：使用原生时间选择器，预计用时 5～1440 分钟，时间段不能跨过当天 24:00。全天任务不参加冲突判断。保存时检查从今天或较晚起始日开始的 30 天，最多列出 5 个冲突；可确认后继续保存。已完成、已跳过事项不算冲突。这不是无限日期范围的排程保证，也不触发系统通知。

**子任务与批量操作**：子任务每行一个，最多 20 项、每项 100 字。勾选子任务与整个任务的完成状态独立。修改子任务内容会重置子任务进度，保留系列日期的整体完成记录。复制任务生成新草稿，清空完成和子任务进度。批量操作只处理进入面板时当前视图和筛选结果中的项目，重复任务只影响选中日期；整个批次在同一数据库事务内保存。

**一句话示例**：

```text
明天 交报告 #学习 高优先级
每周一 复习英语 #学习
2026-10-11 准备演示 #项目
每天 14:30 准备演示 用时60分钟 #验收 高优先级
```

支持今天、明天、后天、下周几、明确日期、每天 / 每周 / 每月、HH:mm 时间、用时 / 持续若干分钟、#标签和高 / 中 / 低优先级。它是离线规则解析，不调用 AI API；不能识别的文字保留在标题中，保存前请核对草稿。

**备份**：当前格式为 `TaiPlanHarmony` version 4，兼容导入 version 3；包含任务、时间、子任务、标签、顺序和重复完成 / 跳过 / 子任务进度，不包含主题设置。单文件最多 4 MB、5,000 个任务、50,000 条日期状态。导入只新增不存在的任务 ID；相同 ID 的任务及其日期状态均保留本机版本。多次导入不会产生重复任务，也不会更新同 ID 的旧数据。导入使用事务，失败整体回滚。桌面版 SQLite 备份须先使用下方工具转换。

## 日历互通

工具页可导入 `.ics` 文件，先查看可合并数量与跳过原因，再确认导入。当前支持单次 `VEVENT`、单日全天事项、整分钟的同日时间段；支持本地浮动时间、UTC 和 `Asia/Shanghai` 时区。UID 必填且最多 120 字，文件内重复 UID 会报告，已导入的 UID 不覆盖本机任务。日期范围为 2000～2100 年。

`RRULE`、`RDATE`、`EXDATE`、`RECURRENCE-ID`、`DURATION`、跨日事件、其他时区和 `VTODO` 暂不支持，会提示跳过。带重复规则的外部日历应先展开为单次事件。描述、地点、链接会合并到备注；字段超限的事件会报告，不截断内容。

导出包含今天起 30 天有日期的事项，重复事项展开为单次事件，跳过的日期不导出；子任务作为备注文本保存。它是日程交换快照，不能替代完整 JSON 备份。导出后再导入本应用会生成日历来源的新任务，而不是更新原任务。

## 桌面版数据迁移

转换器按 [TaiPlan-desktop 源码](https://github.com/TanTaiwoo07/TaiPlan-desktop/tree/7e6a83212d4014234a3b15ab3353abbecfb74844) 的数据库结构实现。已用真实 SQLite 测试库验证，尚未读取或迁移你的个人任务数据库。

1. 在桌面版导出一致性数据库备份，将备份复制到本测试项目的 `migration/desktop-backup.db`。不要直接传入正在使用的数据库。
2. 在本项目目录运行以下命令，需要 Node 24。最后的 `my-desktop` 是数据源名称：同一数据源重复转换应沿用它，不同来源应使用不同名称（1～32 个英文字母、数字、下划线或短横线）。
3. 查看生成的 `.report.json`，确认跳过内容，然后把 JSON 文件传到设备，在「日程工具 → 从文件恢复任务」中预览并导入。

```powershell
& 'D:\Program Files\Huawei\DevEco Studio\tools\node\node.exe' tools/desktop-transfer.cjs migration/desktop-backup.db migration/harmony-import.json my-desktop
```

工具输出 `harmony-import.json` 与 `harmony-import.json.report.json`，拒绝覆盖现有文件。源备份先复制到临时目录，以只读方式打开临时副本；原文件不会通过 SQLite 打开。检测到源文件旁的 WAL 文件会停止并要求导出备份。报告含源文件 SHA-256、转换数量和跳过原因，不读取 API Key 或桌面配置。

支持普通任务的标题、备注、链接、日期时间、时长、优先级与完成状态；支持间隔为 1、无截止条件的每天 / 每周 / 每月规则，以及单次完成、取消和改期。改期会转换为独立任务，并跳过原日期。小时、工作日、周末、季度、年度、自定义间隔与有结束条件等复杂规则暂不转换；无法完整保留日期状态的系列整体跳过并报告。转换是单向导入，不是双向同步。

## 结构

```text
entry/src/main/ets/
  pages/Index.ets               页面与交互状态
  components/TaskCard.ets       任务卡片
  components/MonthCalendar.ets  月历
  model/Task.ets                任务、日期状态与备份类型
  services/TaskService.ets      校验、搜索、编辑、旧数据解析
  services/ScheduleService.ets  日期投影、重复规则、月历、排序
  services/QuickEntryService.ets 本地一句话解析
  services/BackupService.ets    备份格式与校验
  services/IcsService.ets       ICS 解析、兼容性报告与日历快照
  data/TaskRepository.ets       数据库事务、迁移和设置
  data/BackupFiles.ets          系统文件选择器与 UTF-8 文件读写
  entryability/EntryAbility.ets 应用入口
tests/core.test.cjs             业务规则、真实 SQLite SQL 与事务测试
tools/desktop-transfer.cjs      桌面 SQLite 备份 → 鸿蒙 JSON
```

数据库包含 `tasks`、`task_tags`、`metadata`、`task_options`、`task_occurrences`、`task_details`、`task_step_states` 七张表。重复任务只保存规则及发生变化的日期状态，不提前生成无限任务。升级通过新增关联表兼容旧数据；更早的 Preferences 数据在首次启动时事务迁移，迁移失败保留原文，成功后不重复导入。SQL 使用绑定参数。页面等待持久化成功后更新列表，保存失败保留编辑内容。

## 运行

1. 在 DevEco Studio 中打开本目录，安装 HarmonyOS 26.0.0 SDK。
2. 执行 `ohpm install`，创建并启动 API 26 手机模拟器。
3. 使用 IDE 运行 entry，或在项目目录执行以下 PowerShell 命令。

本机 DevEco Studio 安装位置为 `D:\Program Files\Huawei\DevEco Studio`：

```powershell
$env:DEVECO_SDK_HOME='D:\Program Files\Huawei\DevEco Studio\sdk'
$env:JAVA_HOME='D:\Program Files\Huawei\DevEco Studio\jbr'
$env:Path='D:\Program Files\Huawei\DevEco Studio\tools\node;'+$env:Path
& 'D:\Program Files\Huawei\DevEco Studio\tools\ohpm\bin\ohpm.bat' install
& 'D:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat' --mode module -p product=default -p module=entry@default assembleHap --no-daemon
$hdc='D:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
& $hdc list targets
& $hdc -t 127.0.0.1:5555 install -r entry\build\default\outputs\default\entry-default-unsigned.hap
& $hdc -t 127.0.0.1:5555 shell aa start -a EntryAbility -b com.taiwoo.taiplan
```

设备地址以 `hdc list targets` 结果为准。这是原生应用，从模拟器窗口交互，无 HTTP 地址。当前未签名 HAP 可在本地 API 26 模拟器安装；真机需配置签名，并单独验收。

不要复用从其他目录复制来的 `.hvigor` 或 `entry/build` 缓存，它们可能带有原目录的绝对路径。本副本使用独立生成的缓存。`milestones/v0.2.0`、`milestones/v0.3.0` 保留历史源码和 HAP 快照，不参与编译或 Git 提交。

## 验证

```powershell
& 'D:\Program Files\Huawei\DevEco Studio\tools\node\node.exe' --test tests/core.test.cjs
```

需要 Node 24（内置 SQLite）。测试默认使用上述 DevEco 中的 TypeScript；其他安装路径可通过 `TAIPLAN_TYPESCRIPT` 指定 TypeScript 模块目录。

57 项测试覆盖：中文和 emoji、字段边界、组合搜索、CRUD、升级保留、事务回滚、主题恢复、重复日期隔离、闰年与月末、夏令时、长期跳过后的下次日期、月历投影、未来视图范围、离线解析、四种排序、时间冲突、子任务、批量完成与回滚、备份 v3/v4 兼容与幂等合并、ICS 时区 / 折行 / 拒绝报告 / 导出、桌面 SQLite 转换及源文件哈希不变。这些测试运行实际业务代码和 SQLite SQL，模拟 Harmony 系统接口，不能替代设备测试。

2026-10-10：API 26 模拟器构建、覆盖安装、启动通过；旧任务保留；中文一句话录入、每日任务预览与保存、单次完成隔离、未来视图、月历选日与滑动、长按拖动保存已通过原生交互检查。文件选择器导出、重复导入不覆盖、删除测试系列后从备份恢复及日期完成记录保留、跳过与恢复单次事项、进程重启后数据和手动顺序恢复均通过。排序按钮与工具按钮的内边距问题已修复。本轮未做真机验收。系统接口可能抛出异常的编译告警仍存在，页面操作入口捕获并显示错误。

0.4.0 本轮验收：57 项自动测试通过，API 26 构建与覆盖安装通过。模拟器中验证了中文一句话时间解析、原生时间选择器、两项子任务连续勾选及次日进度隔离、复制任务与冲突确认、按标签批量完成和恢复待办、同一任务连续箭头排序。修复了 ArkUI 列表复用导致卡片内容不及时刷新和排序操作引用旧位置的问题。ICS 系统文件选择器成功导出 30 天快照，重新选取后 91 条事件全部识别并进入预览；验收取消了合并，避免向现有列表添加重复日程。桌面迁移使用测试库验证，未操作个人数据库。原始项目的 91 个文件哈希与开发前一致。

## 尚未移植

后台系统通知、云同步、云端 AI、更丰富的重复间隔与结束条件、原生单次改期编辑、日历拖拽改期。当前时间用于展示与逾期判断，不触发系统通知。鸿蒙版已接通桌面备份的部分数据迁移，但尚未达到桌面版全部功能。
