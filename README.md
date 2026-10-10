# TaiPlan Harmony

TaiPlan 的鸿蒙原生基础工程，使用 ArkTS、ArkUI 和 HarmonyOS API 26。

## 当前范围

- 任务新建、编辑、删除、完成与取消完成。
- 待办与已完成两个区域，按创建时间倒序。
- 本地 Preferences 保存，写入失败显示重试提示。
- 中文界面、空状态、深浅色资源。

当前为开发中的基础版本。已在 DevEco Studio 26.0.0.851 自带工具链上完成 assembleHap 编译，生成未签名 HAP；尚未完成模拟器或真机验收，不作为正式发布版。编译仍有异常处理提示，后续继续完善。

## 打开和运行

1. 安装 DevEco Studio 26.0.0 与自带的 API 26 SDK。
2. 在 IDE 中打开本仓库根目录，等待工程同步。
3. 在 Device Manager 中安装 API 26 镜像并启动设备，或连接兼容真机。
4. 根据 IDE 提示配置本地调试签名，选择 entry 后运行。

签名、证书、local.properties 和构建缓存不提交 Git。

## 代码结构

```text
AppScope/                         应用名称、图标与版本
entry/src/main/ets/
  entryability/EntryAbility.ets    应用启动
  pages/Index.ets                  列表与编辑界面
  model/Task.ets                   数据模型、校验、排序、完成切换
  data/TaskRepository.ets          本地持久化
entry/src/main/resources/         中文文案、深浅色资源
```

页面发起操作 → TaskService 生成新数据 → TaskRepository 写入并 flush → 成功后更新页面。
首次启动为空列表，不自动插入演示数据。数据格式带版本号，读取错误时禁止覆盖旧数据。

## 后续计划

先完成设备运行与增删改查、重启恢复验收，再增加搜索、优先级、标签和今日视图。
本工程由 Codex 辅助搭建；DevEco Code 的实际使用与验证尚未开展。
