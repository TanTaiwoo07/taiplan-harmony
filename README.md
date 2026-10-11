# TaiPlan Harmony 1.0.0

鸿蒙原生待办与日历，ArkTS + ArkUI + HarmonyOS API26 + SQLite。作者 TaiWoo_Chen。
这是本机模拟器交付版；支持范围和未验收能力见[交付记录](docs/DELIVERY-100.md)、[功能核查](docs/FEATURE-AUDIT-100.md)、[演示答辩](docs/DEMO-AND-DEFENSE.md)。

四栏：今天、待办、日历、工作台。支持CRUD、完成分区、创建倒序、搜索、标签、优先级、拖排、年月周日历、重复和ICS；扩展收集箱、语音适配、自然语言草稿、AI辅助排程、番茄钟、习惯、倒数日和备份。设置控制简洁/完整模块、跟随系统/深浅色与减少动画。
1.0新增浮动原生材质导航、非线性过渡、齿轮与分类设置、作者项目页、云端排程评价/预览/确认/撤销、RDATE/IANA时区和保护性来源更新。

## 安装运行

安装DevEco Studio和API26手机镜像，在Device Manager启动模拟器。已有桌面副本双击Start-TaiPlan.cmd；新源码解压目录运行：

```powershell
./tools/run-emulator.ps1 -Build -DevEcoHome 'D:\Program Files\Huawei\DevEco Studio' -Device '127.0.0.1:5555'
```

脚本使用DevEco的Node/JBR/SDK，缺少依赖时安装ohpm依赖，覆盖安装保留数据；拒绝原保护目录构建。原生模拟器没有localhost地址。未签名HAP仅用于本机模拟器，真机需要签名和另行验收。

## 验证

```powershell
& 'D:\Program Files\Huawei\DevEco Studio\tools\node\node.exe' --test tests/core.test.cjs
& 'D:\Program Files\Huawei\DevEco Studio\tools\node\node.exe' tools/performance.cjs
```

154项回归通过、API26构建成功。原生AI方案采用/撤销及冲突拒绝、日历移动确认/撤销有本轮记录。测试使用系统替身，不代表语音/后台提醒真机通过。纯业务5000任务测量不是原生帧率。

## 代码结构与数据

entry/src/main/ets/model定义模型；services负责时间、重复、校验、排程与导入；data负责SQLite事务与安全配置；platform对接AI、提醒、语音；components与pages实现ArkUI。
AI需在应用里配置HTTPS服务和密钥，密钥只进安全资产存储，不进普通文件、源码、日志或备份。云端需主动确认发送，建议经程序校验与用户确认才写入。
备份7覆盖任务、工具和偏好，兼容旧备份；重复使用系列+原发生日期+单次覆盖。计划与截止分开，无日期收集不会产生虚假逾期。

## 交付与边界

delivery中的1.0独立包包含源码、HAP、报告PDF、约三分钟静音抽帧视频、运行说明、测试/构建/完整性记录与SHA256。旧包独立保留。GitHub为私有仓库，archive/v1.0.0保留本版源码。
中文语音、锁屏/退出提醒、真机签名与完整无障碍/拖动矩阵仍待验收。复杂重复历史迁移、高级搜索、完整RFC5545、调休/农历未完整实现；详细缺口不隐藏。1.0表示本机交付范围，不表示整个长期路线全部完成。
