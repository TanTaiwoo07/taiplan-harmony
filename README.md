# TaiPlan Harmony 0.9.0-preview.1

鸿蒙原生待办、日历与可选个人工具，ArkTS + ArkUI + HarmonyOS API 26 + SQLite。
本机模拟器交付候选；完整功能、验证证据及边界见 [当前交付记录](docs/DELIVERY-090.md)，[演示与答辩](docs/DEMO-AND-DEFENSE.md)，[总计划](docs/DEVELOPMENT_PLAN.md)。

本版新增工作台导航、下拉搜索、开关式编辑器、重复/提醒滚轮、日历详情与缩放拖动预览、AI地址规范化/分阶段保存/独立安全诊断。继承紧急徽标/具体截止/登记状态、模块开关、可恢复番茄钟、习惯打卡、倒数日与纪念日、分类管理、全工具与偏好备份7、AI复杂草稿与连接测试、自定义辅助排程和单条采用。保留四栏、CRUD、待办/完成分区、搜索、标签、优先级、拖排、年月周日和重复单次编辑。

本机 API 26 模拟器已运行。桌面副本中双击 Start-TaiPlan.cmd。新环境执行：

```powershell
./tools/run-emulator.ps1 -Build -DevEcoHome 'D:\Program Files\Huawei\DevEco Studio' -Device '127.0.0.1:5555'
```

先在 DevEco Device Manager 打开模拟器。项目依赖可由脚本 ohpm install 安装；使用 DevEco 自带 Node/JBR/SDK。原始 outputs/taiplan-harmony 为保护目录，不运行构建。原生应用没有 localhost 地址。

```powershell
& 'D:\Program Files\Huawei\DevEco Studio\tools\node\node.exe' --test tests/core.test.cjs
& 'D:\Program Files\Huawei\DevEco Studio\tools\node\node.exe' tools/performance.cjs
```

130 项回归通过。模拟器覆盖安装/原生交互和浅深色另行记录；测试替身不代表真实系统提醒成功。

交付目录 delivery 的 0.9 包含源码 ZIP、未签名 HAP、运行入口、交付记录与 SHA256 清单。0.8 的 PDF/视频保留在旧版包中，不作为本版新验证。HAP 仅在本机模拟器验收，真机需签名与设备测试。

真实 AI 请求、真机语音、锁屏/退出后的提醒未验收；模拟器提醒发布返回 1700002，界面明确失败。复杂 ICS/任意时区、历史系列任意重排、云端 AI 排程和完整无障碍仍有边界。详细清单见交付记录，不能把本版本称为全计划正式1.0。

密钥只在应用中填写，安全资产存储保管，不进源码、普通配置、备份和日志。云端识别需主动操作，仅发送本次输入。备份恢复在 SQLite 事务里，偏好恢复需在导入预览确认。

项目位置：model 定义任务与工具；services 处理纯业务；data 负责 SQLite/文件/配置；platform 对接语音/提醒/AI；components 实现页面块；Index 协调导航与编辑。旧版构建细节与历史说明见 docs/HISTORY-v0.7-preview.md。