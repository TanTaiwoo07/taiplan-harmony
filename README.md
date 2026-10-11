<p align="center"><img src="AppScope/resources/base/media/app_icon.svg" width="88" alt="TaiPlan 图标"></p>

# TaiPlan Harmony

把想到的事记下来，把重要的事安排好。鸿蒙原生待办、日历与可选个人工具。

**当前版本：1.0.1 · HarmonyOS API 26 · 本机模拟器交付版**  
作者：**TaiWoo_Chen** · 技术：**ArkTS / ArkUI / SQLite**

## 1.0.1 更新

- 接入整套 74 个自绘 SVG 资源，统一导航、工具、设置、任务表单和常用操作图标，适配浅深色与选中态。
- 底栏使用 API 26 官方浮动页签和沉浸光感；收集面板、系统弹窗使用原生材质。不支持时回退上一版，普通内容卡片保持实色。
- 修复空心图标被填实、深色按钮图标对比度和图文按钮圆角问题。
- 154 项回归通过；本机原生构建、覆盖安装和 UI 检查通过。真机效果仍需验收。

详细记录：[图标与材质验收](docs/ICONS-101.md) · [版本记录](CHANGELOG.md)

## 功能入口

| 页面 | 主要能力 |
| --- | --- |
| 今天 | 完成概览、优先处理、紧急与逾期提示、快速收集 |
| 待办 | 新建、编辑、删除、完成/取消，待办与完成分区、创建倒序、搜索、标签、优先级与手动排序 |
| 日历 | 年/月/周/日视图、时间块、拖动与缩放、常见重复日程、单次修改、ICS 导入导出 |
| 工作台 | 离线自然语言草稿、云端 AI 草稿与排程建议、预览/确认/撤销、专注、习惯、倒数日 |
| 设置 | 跟随系统/浅色/深色、减少动画、模块开关、清单与标签、备份、AI 配置及提醒状态 |

事项可以先放进无日期收集箱，再安排日期或精确时间；安排时间与截止期限分别保存。工具可按个人偏好隐藏。

## 在本机运行

1. 安装 DevEco Studio 与 API 26 手机模拟器镜像，在 Device Manager 启动模拟器。
2. 克隆本私有仓库（需要访问权限），或解压源码归档。
3. 在项目根目录执行，按实际安装路径和设备编号调整参数：

```powershell
./tools/run-emulator.ps1 -Build -DevEcoHome 'D:\Program Files\Huawei\DevEco Studio' -Device '127.0.0.1:5555'
```

脚本使用 DevEco 自带 Node、JBR 和 SDK，缺少依赖时安装 ohpm 依赖；覆盖安装保留应用数据。也可使用 DevEco Studio 打开工程后运行 EntryAbility。

这是原生应用，通过模拟器窗口操作，没有 localhost 网页地址。未签名 HAP 只用于本机模拟器；真机安装与上架需签名和另行验收。

## 验证

```powershell
& 'D:\Program Files\Huawei\DevEco Studio\tools\node\node.exe' --test tests/core.test.cjs
& 'D:\Program Files\Huawei\DevEco Studio\tools\node\node.exe' tools/performance.cjs
```

当前 154 项回归覆盖业务、SQLite 事务及系统适配器替身，不能代替真机语音、后台提醒和全部手势验收。性能脚本测量纯业务处理时间，不是原生帧率。

## 项目结构

```text
AppScope/                     应用信息与应用图标
entry/src/main/ets/
  model/                      任务、重复与工具模型
  services/                   时间、校验、排程、导入与材质能力
  data/                       SQLite 事务、文件与配置
  platform/                   AI、系统提醒与语音适配
  components/                 ArkUI 页面组件
  pages/Index.ets             页面导航与编辑协调
entry/src/main/resources/     浅深色资源与图标
design/                      图标原稿、哈希与引用清单
tests/                       回归测试
tools/                       构建运行、迁移与性能工具
docs/                        开发、验收与历史记录
```

## 数据与 AI

任务保存在本机 SQLite；备份格式 7 覆盖任务、发生项、工具与偏好，兼容旧备份。重复使用系列 ID、原发生日期及单次覆盖，保护已有进度。

AI 服务地址、模型与密钥在应用设置中填写。密钥使用安全资产存储，不进入普通文件、源码、日志或备份。只有主动确认才向云端发送请求，草稿和排程建议经校验、预览及确认后保存。没有 AI 服务时仍可使用手动输入和离线解析。

## 验收范围与版本归档

- `main`：当前 1.0.1 源码与首页说明。
- `archive/v1.0.1-icons`：已验证图标版的固定源码快照。
- `archive/v1.0.0` 及更早归档：独立保留旧版，不覆盖历史记录。
- 安装包、源码 ZIP、截图、报告和视频按版本存放于本机交付归档；被忽略的 `delivery/` 不会自动出现在 GitHub，不将其误写为已上传附件。

中文语音、锁屏/退出后的通知、真机签名以及全量屏幕/字体/无障碍/手势矩阵仍待验收。高级搜索、复杂重复历史迁移、完整 RFC 5545、调休与农历也有明确缺口。当前版本代表本机模拟器交付范围。

进一步了解：[1.0 交付记录](docs/DELIVERY-100.md) · [功能核查与后续开发](docs/FEATURE-AUDIT-100.md) · [开发计划](docs/DEVELOPMENT_PLAN.md) · [演示与答辩](docs/DEMO-AND-DEFENSE.md)
