# TaiPlan Harmony 1.0.1：图标与官方材质验收

日期：2026-10-11。工作目录为桌面的 taiplan-harmony-test；原始项目为受保护只读目录。本版基于 1.0.0 提交 2c70fbfad6fb1db12dc912c8c26f390363816f11，独立分支 feature/1.0.1-icons。此前 1.0.0 交付 ZIP 保留；本次源码、安装包及截图单独归档，不改写旧版报告/视频。

## 图标接入

收到 74 个 SVG，包含应用标志、导航普通/选中态及功能操作图标。design/icon-source 保留逐字节原稿和 SHA256；文件是设计素材，不作为指令，不执行用户附带的生成脚本。解析时检查了脚本、外链、外部实体和非 SVG 内容。

原稿使用 currentColor，原生 Image 并不以文字颜色完整重染 SVG 描边。因此资源分别生成浅色 #26332F、深色 #DBE8E2、选中态绿，以及主按钮反色版本；形状、线宽、圆角、透明度及应用标志渐变保持原稿。去除 Image.fillColor，防止填实原稿的空心区域。

|位置|使用方式|
|---|---|
|应用与关于页|app-icon 原稿，关于页 64vp|
|四个底部页签|today / todo / calendar / workbench，普通与 selected 状态，24vp|
|页首设置与导航|settings 齿轮、back/next、close；保留原点击区域及无障碍文字|
|工作台|schedule 主入口，smart_input 快速识别，focus/habit/countdown/list_manage 工具入口，28vp|
|分类设置|appearance/preferences/workbench/reminder_perm/ai_service/backup/about，统一容器及留白|
|任务编辑|plan_date/location/deadline/reminder/note/repeat/tag/time_range/duration 等字段与操作|
|任务列表|more/edit/copy/trash/undo/drag/multi_select；紧急事项使用 warning 红色图标|
|其他操作|search/filter/import/export/connection_test/mic/play/pause/stop/key/repo 等配合文字|
|输入与状态|搜索框及密码显隐使用原生组件图标接口；Checkbox、Switch 等交互仍由系统控件绘制|

导航 24vp、功能入口 28vp、按钮/字段图标 20–22vp；图标本身不抢占文字层级，触摸区域沿用现有按钮。并非每个图标都必须独立创建入口；部分图库用于未来功能或原生状态，资源接入不代表对应新功能上线。逐项资源及引用情况见 design/icon-inventory.csv。

## 官方沉浸光感：决定与边界

官方称为“沉浸光感”。核查来源：
- [华为 UI Design Kit](https://developer.huawei.com/consumer/cn/sdk/ui-design-kit)：标题栏与底部导航的沉浸材质及光场体验。
- [Navigation 官方 API](https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/ts-basic-components-navigation)。
- 本机 HarmonyOS API26 的 Tabs.barFloatingStyle、CommonAttribute.systemMaterial 及 @ohos.arkui.uiMaterial 定义。

本版不用 CSS 模拟苹果玻璃。底栏放入真正的系统 Tabs 底部页签，启用 barFloatingStyle、ULTRA_THIN ImmersiveMaterial、交互光感和系统阴影。上版自定义容器的材质调用不等同于受支持的系统底部页签，本次修正这个位置。收集 sheet 及现有系统弹窗/菜单在允许的组件上使用 REGULAR 系统材质。

“全局所有卡片都变成官方液态玻璃”不能当作已经实现：系统接口有应用场景限制，普通内容容器不等于标题栏/底部页签；正文继续保留上版实色卡片。界面统一来自同一套图标、颜色和留白。官方材质的实际表现由设备、系统设置及材质档位决定，不能保证所有手机与模拟器逐像素一致。

MaterialService 运行时检查支持性及禁用状态；不支持/禁用/用户关闭材质时显示上一版浮动栏。减少动画时关闭材质交互及光效参数，保留可用导航。模拟器报告的档位为“精致”；已在设置页实际读取，不仅是编译通过。

## 本轮验收

- API26 原生构建成功，覆盖安装成功，应用已启动。HAP 为未签名模拟器包，不等于真机上架包。
- 154 项业务回归通过，无失败。日志在交付包 evidence 中。
- 人工检查模拟器：首页、工作台、设置、日历、收集面板、编辑页及关于页；浅色/深色均检查。修正按钮反色、圆角及空心图标被填实的问题。
- 检查原生材质关闭后的上一版浮动栏回退；截图分别标记 native/fallback。
- 本轮没有发送真实 AI 请求，没有提交新任务或修改任务；原任务数据和保护目录完整性另见 integrity.json。
- 原有语音、锁屏/退出提醒、真机签名及全量无障碍/手势验收边界延续 1.0 的记录。本轮 UI 检查不扩大那些能力的验收结论。

## 交付与版本

1.0.1 的独立交付包含当前源码、模拟器 HAP、图标原稿、界面截图、回归/构建日志、SHA256 清单及本记录。源码不含用户数据库、密钥、缓存或签名材料。1.0.0 的历史包未覆盖。用户要求同步本版到 GitHub：首页 README 补充应用标志、功能入口、运行方法及能力边界。archive/v1.0.1-icons 保留图标版快照；main 在核对源码树与远端分支后更新。原本地包保持独立，远端最终提交另行记录。
