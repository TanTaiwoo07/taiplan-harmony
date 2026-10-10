# TaiPlan Harmony 0.3.0

鸿蒙原生待办应用，使用 ArkTS、ArkUI、HarmonyOS API 26。开发与测试均在桌面 `taiplan-harmony-test` 副本中完成。

## 功能

- 任务新建、编辑、删除、完成与取消完成；待办和已完成分区，默认按创建时间倒序。
- 标题、备注、标签组合搜索；高 / 中 / 低优先级；最多 5 个标签，每个最多 12 字。
- 截止日期、逾期提示；系统 / 浅色 / 深色主题持久化。
- 全部、今天、未来 30 天、月历四种视图。月历点击日期看当天事项，支持切换月份与回到今天。
- 每天、每周、每月重复；完成记录按日期独立保存。可以跳过单次，在工具页恢复，或确认后删除整组。
- 工具页长按任务拖动排序，也可使用上下箭头；保存后启用手动顺序，列表可随时切回创建倒序。
- 一句话录入：本地规则识别日期、重复规则、标签、优先级，先预览草稿，再由用户保存。
- 系统文件选择器导出 / 导入 JSON 备份；校验后预览合并数量，已有同 ID 任务保持现状。
- ArkData 关系型数据库保存任务、标签、排序及重复完成记录；自动保留并迁移旧版数据。

## 使用约定

**日期与重复**：日期精确到本地当天 23:59:59.999。今天视图包含今天的重复事项和已逾期的普通未完成任务；没有截止日期的任务在全部视图中查看。未来视图展示明天起 30 天内的事项。全部视图每个重复系列只展示今天或下一次，过往完成记录可到月历查看。每周按起始日的星期重复，每月按起始日重复；不足该日的月份取最后一天，下月仍沿用原始日期。

编辑重复任务会修改整个系列；仅修改标题、备注等保留完成记录。改变起始日期或重复规则时，如果已有完成 / 跳过记录，会先提示确认重置。

**一句话示例**：

```text
明天 交报告 #学习 高优先级
每周一 复习英语 #学习
2026-10-11 准备演示 #项目
```

支持今天、明天、后天、下周几、明确日期、每天 / 每周 / 每月、#标签和高 / 中 / 低优先级。它是离线规则解析，不调用 AI API；不能识别的文字保留在标题中，保存前请核对草稿。

**备份**：当前格式为 `TaiPlanHarmony` version 3，包含任务、标签、顺序和重复完成 / 跳过记录，不包含主题设置。单文件最多 4 MB、5,000 个任务、50,000 条日期状态。导入只新增不存在的任务 ID；相同 ID 的任务及其日期状态均保留本机版本。多次导入不会产生重复任务。导入使用事务，失败整体回滚。该格式不能直接读取桌面 Python 版的 SQLite / 备份。

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
  data/TaskRepository.ets       数据库事务、迁移和设置
  data/BackupFiles.ets          系统文件选择器与 UTF-8 文件读写
  entryability/EntryAbility.ets 应用入口
tests/core.test.cjs             业务规则、真实 SQLite SQL 与事务测试
```

数据库包含 `tasks`、`task_tags`、`metadata`、`task_options`、`task_occurrences` 五张表。重复任务只保存规则及发生变化的日期状态，不提前生成无限任务。0.2 升级通过新增关联表兼容旧数据；更早的 Preferences 数据在首次启动时事务迁移，迁移失败保留原文，成功后不重复导入。SQL 使用绑定参数。页面等待持久化成功后更新列表，保存失败保留编辑内容。

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

不要复用从其他目录复制来的 `.hvigor` 或 `entry/build` 缓存，它们可能带有原目录的绝对路径。本副本使用独立生成的缓存。`milestones/v0.2.0` 保留上一版源码和 HAP 快照，不参与编译或 Git 提交。

## 验证

```powershell
& 'D:\Program Files\Huawei\DevEco Studio\tools\node\node.exe' --test tests/core.test.cjs
```

需要 Node 24（内置 SQLite）。测试默认使用上述 DevEco 中的 TypeScript；其他安装路径可通过 `TAIPLAN_TYPESCRIPT` 指定 TypeScript 模块目录。

32 项测试覆盖：中文和 emoji、字段边界、组合搜索、CRUD、升级保留、事务回滚、主题恢复、重复日期隔离、闰年与月末、夏令时、长期跳过后的下次日期、月历投影、未来视图范围、离线解析、手动排序、备份校验与幂等合并。这些测试运行实际业务代码和 SQLite SQL，模拟 Harmony 系统接口，不能替代设备测试。

2026-10-10：API 26 模拟器构建、覆盖安装、启动通过；旧任务保留；中文一句话录入、每日任务预览与保存、单次完成隔离、未来视图、月历选日与滑动、长按拖动保存已通过原生交互检查。文件选择器导出、重复导入不覆盖、删除测试系列后从备份恢复及日期完成记录保留、跳过与恢复单次事项、进程重启后数据和手动顺序恢复均通过。排序按钮与工具按钮的内边距问题已修复。本轮未做真机验收。系统接口可能抛出异常的编译告警仍存在，页面操作入口捕获并显示错误。

## 尚未移植

后台系统通知、云同步、云端 AI、ICS、Python 桌面数据库直接导入及桌面日历的拖拽改期。当前截止日期用于展示与逾期判断，不触发系统通知。