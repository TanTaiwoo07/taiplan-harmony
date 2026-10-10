# TaiPlan Harmony 0.2.0

鸿蒙原生待办应用，使用 ArkTS、ArkUI、HarmonyOS API 26。当前工作目录为桌面测试副本。

## 已实现

- 新建、编辑、删除任务，完成 / 取消完成；待办与已完成分区，创建时间倒序。
- 搜索标题、备注和标签；搜索与标签筛选可组合。
- 高 / 中 / 低优先级；每任务最多 5 个自定义标签，每标签最多 12 字。
- 可选截止日期（本地日期当天 23:59:59.999），未完成且已过截止日期的任务显示逾期。
- 跟随系统 / 浅色 / 深色主题；点击右上角按钮循环切换。
- ArkData 关系型数据库保存任务和标签；Preferences 保存主题设置。
- 首次升级自动迁移旧版 Preferences 任务，保留旧记录原文。任务和迁移标记在同一事务提交，失败则回滚。

## 结构

```text
entry/src/main/ets/
  pages/Index.ets              页面、筛选与编辑状态
  components/TaskCard.ets      任务卡片
  model/Task.ets               任务与草稿类型
  services/TaskService.ets     校验、搜索、排序、日期和旧数据解析
  data/TaskRepository.ets      数据库 CRUD、迁移和主题持久化
  entryability/EntryAbility.ets 应用入口
tests/core.test.cjs            业务规则、SQL/事务和迁移测试
```

数据库包含 tasks、task_tags、metadata 三张表。SQL 使用绑定参数。保存任务和替换标签、删除任务及关联标签均使用事务。页面等待写入成功后再更新列表，保存失败保留编辑内容。重复启动根据迁移标记跳过旧数据导入，避免覆盖已经修改的任务。

## 运行

1. 在 DevEco Studio 中打开本项目，确认 SDK 为 HarmonyOS 26.0.0。
2. 执行 ohpm install，创建并启动 API 26 手机模拟器。
3. 使用 IDE 运行 entry，或使用以下 PowerShell 命令构建、安装、启动。

本机 DevEco Studio 安装在 D:\Program Files\Huawei\DevEco Studio：

```powershell
$env:DEVECO_SDK_HOME='D:\Program Files\Huawei\DevEco Studio\sdk'
$env:JAVA_HOME='D:\Program Files\Huawei\DevEco Studio\jbr'
$env:Path='D:\Program Files\Huawei\DevEco Studio\tools\node;'+$env:Path
& 'D:\Program Files\Huawei\DevEco Studio\tools\ohpm\bin\ohpm.bat' install
& 'D:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat' --mode module -p product=default -p module=entry@default assembleHap --no-daemon
& 'D:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe' install -r entry\build\default\outputs\default\entry-default-unsigned.hap
& 'D:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe' shell aa start -a EntryAbility -b com.taiwoo.taiplan
```

这是原生应用，从模拟器窗口交互，无 HTTP 访问地址。当前未签名 HAP 已在本地 API 26 模拟器安装；真机安装需要配置相应签名并验收。

## 测试

```powershell
& 'D:\Program Files\Huawei\DevEco Studio\tools\node\node.exe' --test tests/core.test.cjs
```

需要 Node 24（使用内置 SQLite）。测试默认使用上述 DevEco 目录中的 TypeScript；其他安装位置可通过 TAIPLAN_TYPESCRIPT 环境变量指定 TypeScript 模块路径。

12 项测试覆盖：
中文与 emoji 数据保留、编辑与完成状态、标签解析及边界、组合搜索与排序、截止日期、旧数据格式校验、迁移幂等性、迁移失败回滚、损坏数据保护、任务与标签更新原子性、CRUD 与关联标签清理、主题保存恢复。

这些测试执行实际业务代码和真实 SQLite SQL，模拟 Harmony 系统接口；不能代替模拟器或真机测试。

### 本轮模拟器验收（2026-10-10）

- API 26 Mate 90 Pro 模拟器构建、覆盖安装、启动通过。
- 从 0.1.0 升级，原有已完成任务的标题、备注和完成状态保留。
- 实测新增中文任务、两个标签、高优先级、2026/10/11 截止日期；保存后卡片正常显示。
- 实测标签筛选、关键词搜索、清除搜索、深色主题切换。
- 模拟器退出并重启后，原任务、新任务全部字段和深色主题恢复。
- 12 项自动化测试通过；本轮未做真机验收。编译器仍有系统接口可能抛出异常的告警，页面操作入口统一捕获错误并提示。

## 当前范围

尚未实现拖拽排序、月历、重复任务、AI 解析、后台提醒和桌面数据导入 / 云同步。截止日期仅用于展示与逾期判断，不会触发通知。
