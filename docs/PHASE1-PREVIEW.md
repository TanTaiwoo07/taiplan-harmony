# 0.6.0-preview.1：第一阶段检查点与接续说明

这是第一阶段的开发预览，不是 P1 11 验收完成或正式 0.6.0。后续继续第一阶段，不能据此推进语音、提醒和 AI 的发布验收。

## 来源与保护边界

- 稳定基线：GitHub `33da4f5a17a778364ba818a1b20b575403876665`（0.5.0）。
- 开发分支：`feature/phase1-foundation`。
- 工作目录：`C:/Users/Lenovo/Desktop/taiplan-harmony-test`。
- 原始保护目录：`C:/Users/Lenovo/Documents/Codex/2026-10-09/1-0-github-2-0/outputs/taiplan-harmony`，91 个记录文件 SHA-256 均与原保护清单相同。
- 本地 Git 原先没有提交。通过连接器读取远端提交，重建 blob/tree/commit，校验 tree `74c88890a02579a06f8af895464f3e13902daf4e` 和提交 SHA 一致后，仅接入索引和引用，保留工作文件；当前为以 0.5.0 为边界的浅历史。不要误认为已拉取全部祖先对象。
- 开发前源码和 Git 索引快照：`milestones/v0.5.0-before-phase1/`。设备数据库在首次新版本安装之前停止应用后复制；外观 Preferences 在变更外观前额外备份。

## 这次实际实现的行为

1. 今天、待办、日历底部固定“＋ 记一件事”，设置页不显示。打开原生半屏收集面板，只要求标题，默认保存到无日期收集箱。输入法打开时输入框旁的“收集”按钮仍可点击，键盘完成键也能提交。
2. 收集后提供“安排今天”，进入可确认的编辑器。计划日期、时间区间、截止日期／时刻分开保存；清除计划不隐式添加截止。新日期任务不会到夜里自动变成逾期。
3. 编辑器区分待办任务和日历事件，常用日期／时间在前，地点、清单、备注、优先级、标签、重复、子任务在“更多设置”。返回时提示未保存的修改。
4. 事件没有任务勾选框，批量完成忽略事件；今日完成比例只统计任务，事件在独立日程组展示。
5. 待办有收集箱、已安排、全部入口，已完成可展开；原有排序、标签筛选、多选和手动拖动排序保留。添加清单名称后自动出现清单筛选入口。
6. 顶部搜索进入全局搜索，覆盖标题、备注、标签、地点、清单，包括已完成内容。重复系列按系列显示一次。
7. 卡片去掉红色侧边，完成和菜单点击区扩大；红色用于真实逾期与高优先级小标记。计划日期与截止信息分开展示。
8. 系统沉浸材质用于收集面板。MaterialService 检测 `uiMaterial.isImmersiveMaterialSupported()`，创建 API 26 `ImmersiveMaterial(REGULAR)`；不可用时保留实色背景。模拟器支持并已观察到模糊、透光、描边效果。导航和普通卡片暂未扩展材质。
9. 设置增加默认启动页、默认日历尺度、每周起始日、默认展开已完成和材质开关；原有跟随系统／浅色／深色保留。偏好通过 Preferences 持久化。
10. 年视图是十二个月入口；月视图选日后可打开时间表；周视图可横向滑动查看七列，日视图纵向显示 00:00–24:00。长按空白小时格进入带预填日期时间的编辑器。日期任务／全天事件位于选中日的无时间区。
11. 时间块按真实分钟高度布局，重叠连通组分列，跨午夜在两天拆片；最小可点击视觉高度不改写真实时长。当前时间线只出现在今天，时间块可打开编辑器。
12. 重复增加间隔、每周多星期、每年、次数或日期结束，结束日期包含当天；月末和闰日使用月末补齐。周一到周五只是星期组合，没有调休服务。

## 数据契约（实际代码为准）

`Task.planning?: TaskPlanning` 是新增兼容扩展。旧 `dueAt/startMinute/durationMinutes` 暂时保留为日历投影字段，不再统一解释成截止时间。

- `kind`: task / event；`scheduleMode`: unscheduled / date / timed / allDay。
- `plannedDate` 为本地 YYYY-MM-DD；有时间安排保存 `startAt/endAt/timeZone`。
- `deadlineMode`: none / date / datetime；`deadlineAt` 为 0 或明确截止时刻。按日期截止使用当天结束。
- `location/listName/sourceType/legacyTimeSemantics` 独立保存。当前清单使用名称，尚未实现稳定 listId、categoryId、分类配色和来源管理表。
- `rule`: interval、weekdays（ISO 周一=1）、untilDate、count。频率暂沿用 `Task.repeat`。
- 没有 planning 的历史任务读取时由 `PlanningService.forTask` 解释；旧 dueAt 和时长仍生成原本的截止规则，不会因升级消除逾期。

数据库新增 `task_planning(task_id, document)`，JSON 保存经过业务校验的扩展。元数据键 `planning_schema=1` 与已有记录的扩展迁移在同一事务提交，失败回滚并可重试。旧表保留。这个 schema 版本与 app 版本、备份格式版本无关。

备份写入格式 5，继续读取格式 3、4；TaskPlanning 随任务备份。恢复同 ID 数据仍保留本机版本，不覆盖。设置和未来工具数据尚未加入备份。

现有日期完成记录仍使用 taskId + dateKey；**尚未实现单次改期的稳定原始发生项键**。为防止破坏历史，若新模型系列已有完成／跳过记录，修改规则或锚定日期会被拒绝，编辑内容保留，提示复制新系列。仅改标题、地点、时间等仍允许整系列编辑。这不是“仅这次／此后／全部”编辑范围的替代实现。

## 模块职责与下一位执行者入口

| 文件 | 职责 |
| --- | --- |
| model/Task.ets | TaskPlanning、RecurrenceRule、AppPreferences 类型与旧模型扩展 |
| services/PlanningService.ets | 时间契约、旧语义解释、校验、明确截止、设置默认值 |
| data/TaskRepository.ets | task_planning 表、事务迁移、读写、历史保护、设置持久化 |
| services/RecurrenceService.ets | 有限重复投影、间隔和星期；次数计算不按历史天数逐日累加 |
| services/CalendarService.ets | 跨午夜切片、重叠分列、周起始日、全局关键词搜索 |
| services/ScheduleService.ets | 收集箱／已安排／今日投影，跨午夜冲突检查，旧排序 |
| services/FocusService.ets | 今日任务比例、事件分组、截止事项去重 |
| services/MaterialService.ets | 系统材质支持检测、创建失败回退 |
| components/CalendarWorkspace.ets | 年月周日切换、日期导航、选中日无时间事项 |
| components/TimeTable.ets | 横纵滚动、小时格、时间块、当前时刻、长按创建 |
| components/PreferencePanel.ets | 偏好界面；通过回调让父级在持久化成功后更新 |
| pages/Index.ets | 导航、页面共享状态、编辑、收集、搜索与持久化协调，仍需继续拆分 |
| tests/core.test.cjs | 真实 SQLite 事务测试和纯业务回归，不是完整 UI 自动化 |

以上路径相对于 `entry/src/main/ets/`，tests 路径相对于根目录。

## 已执行验证

- 旧基线：60 项全部通过；本检查点：82 项全部通过。
- 新测试覆盖：无日期／无截止不逾期、期限独立、事件统计、跨午夜和相邻时段、重叠连通组、搜索 Unicode、有限重复终止、星期组合计数、月末闰年、备份 3/4/5、迁移失败回滚与幂等、偏好、历史保护、批量完成排除事件。
- API 26 原生构建通过；覆盖安装成功，无卸载清库。已有未签名 HAP 仅在当前允许安装的模拟器验证，不能保证直接装任意真机。
- 原生交互实测：收集、中文 emoji 保存、键盘打开时保存、收集箱、安排今天、删除与撤销、月年入口、日时间表纵向滚动、两个重叠区块并排、周入口、深浅色切换。
- 首次键盘测试发现保存按钮被遮挡；改成输入框旁固定按钮后截图及点击保存通过。
- 用户原数据比较：tasks 5、task_tags 5、task_options 5、task_details 2、task_occurrences 3、task_step_states 2；升级前后这六张旧表逐行一致。新增 task_planning 共 5 行。验收用的两条 P1 前缀任务已删除。
- 本地证据在 milestones：device-data-verification.json、phase1-keyboard-fixed.png、phase1-overlap.png、phase1-dark-settings.png；构建日志 build-test.log，测试日志 tests/latest-test.log。设备原始数据快照不上传源码仓库。

## 尚未完成，不能宣称支持

- P1 02/06：稳定发生项身份、单次 override、此后拆分、完整系列编辑范围；结构化分类／清单／来源表。
- P1 04：Today/Tasks/Editor/Capture/Search 尚未全部拆出 Index；大字体、无障碍、手势全量验收。
- P1 05：工作时段、默认时长、恢复默认、完整设置体系；材质关闭的设备级视觉回归。
- P1 07：跨时区旅行和 DST 重复／缺失时刻的统一转换策略、5000 项性能、周视图边界滚动细节。仅指定默认尺度，临时切换尺度不会自动改写默认值。
- P1 08：时间块拖动、边缘调整、吸附和撤销尚未接入；已有列表手动排序不是这项能力。
- P1 09：ICS 仍是 0.5 的有限单次导入；常见 RRULE、EXDATE、RDATE、RECURRENCE-ID、来源更新尚未实现。不要用预览版导入重复课表并承诺成功。
- P1 10：日期／来源搜索筛选、结果范围导航、清单管理与分类配色尚未实现。
- 语音、系统提醒、AI、番茄钟、习惯、倒数日属于后续阶段，未实现；输入法自带语音不等于应用已接语音 API。

## 继续开发的具体顺序

1. 保留本检查点源码和设备备份；运行 82 项回归，确认当前分支与设备任务数据。
2. 先补稳定 occurrence key 与 override 表及 v5 后续备份兼容，再接三种编辑范围。不移除历史保护条件，直到替代逻辑和迁移用例完成。
3. 用同一 override 服务实现时间块拖动／缩放，先事务成功再刷新，冲突预览和撤销必须共用已有备份／状态契约。
4. 升级 ICS 规则解析与来源标识，再补课表取消改期、幂等更新和桌面迁移。
5. 完成数据模型剩余字段与迁移、Index 拆分、清单分类管理、设置和性能／可访问性验收，方可标记整个第一阶段 verified。

主计划见 DEVELOPMENT_PLAN.md；工作包真实状态以外部实时 PROGRESS.md 为准。本检查点不把部分工作包标成完整完成。
