# 实施记录与开发环境

## 本轮目标

按项目规划落实第一批可运行工程：M1 的菜谱/厨房持久化、Flutter 工程和离线读取缓存，接入 M2 的 DeepSeek 文本/图片解析，并完成已保存菜谱到真实调度计划的链路。本轮继续实现账号密码认证、版本化会话、Flutter 执行页、离线编辑同步和系统本地通知；生产部署仍需单独验收。

## 代码结构

```text
backend/
  cook_scheduler/       # 纯调度引擎
  service/
    api/catalog.py      # 按账号隔离的菜谱、厨房与已保存菜谱排程
    auth.py             # Argon2、JWT、刷新令牌轮换
    api/sessions.py     # 版本化会话、幂等重试、冲突保护
    api/offline.py      # 离线菜谱/厨房编辑的条件同步
    api/ai.py           # DeepSeek 导入、任务查询、配额与用量
    database.py         # SQLAlchemy 2.0 异步模型
    schemas.py          # 版本化菜谱与厨房验证
    deepseek.py         # 服务端 JSON/多模态适配
    imports.py          # 本地持久化导入队列
    migrations/         # Alembic 迁移
frontend/
  mobile/               # 正式 Flutter 工程（Android / iOS / Web）
    lib/core/           # Riverpod 状态与缓存恢复
    lib/data/           # Dio、Drift、本地模型
    lib/features/       # 菜谱/编辑/厨房/导入/计划页面
  index.html            # 保留原交互原型，执行体验仍可使用
scripts/                # Flutter 启动包装、配置与联调脚本
.tools/                 # 项目本地 SDK 和缓存，不跟踪
.data/                  # 本地数据库，不跟踪
```

## 后端启动

```bash
uv sync --extra test
.venv/bin/alembic -c backend/service/migrations/alembic.ini upgrade head
.venv/bin/python -m service
```

默认数据库是 `.data/cook.db`，重启保留数据。开发模式可自动初始化表和默认厨房。正式环境应运行 Alembic 迁移；`COOK_DATABASE_URL` 可切换 `postgresql+asyncpg://...`。本轮未部署 PostgreSQL 实例。

支持邮箱密码注册与登录，Argon2 密码哈希、15 分钟 JWT、30 天一次性刷新令牌及退出撤销刷新令牌。匿名开发账号默认关闭，仅显式设置 `COOK_ALLOW_DEVELOPMENT_LOGIN=true` 启用。开发模式仅负责建表；正式环境需迁移并配置至少 32 字符的 `COOK_JWT_SECRET`，通过 HTTPS 提供 API。开发密钥保存在忽略的 `.data/jwt-secret`（0600），不进入 APK。

## DeepSeek

密钥只在根目录 `.env` 的 `COOK_DEEPSEEK_API_KEY` 中，权限 0600；`.env` 已忽略，`.env.example` 只含空值。替换密钥可运行：

```bash
.venv/bin/python scripts/configure_deepseek.py
```

本轮已验证官方模型列表，使用 `deepseek-flash`。一次真实短菜谱解析成功，产生 6 个带备注任务，结构验证通过，返回 `confirmed=false`。实际应用中必须用户确认并保存后才能排程。

文本和图片导入返回任务 ID，客户端轮询结果。图片每次 1–5 张，单张最多 4MB、单边最多 4096 像素；按真实文件内容验证格式。重复内容优先返回缓存任务。每用户默认每分钟 2 次、UTC 每日 10 次，全平台每日 100 次；事务内原子预留，配额不足仍允许手动菜谱和排程。

AI 结果先做数值食材用量及重复厨具声明归一化（只扣除已经由持续占用覆盖的需求，保留额外数量），若结构校验失败最多额外请求一次修正；两次都记录用量，仍不合法则失败，不跳过 DAG 或资源校验。导入任务和 token 用量持久化；当前统计输入/输出 token，不把固定示例价格当作实际费用。按金额核算和平台每日金额上限尚未实现。当前队列是单进程异步 Worker，不是 Celery/Redis；待生产任务部署阶段替换。重启后恢复 pending 任务，对已在请求中的任务标为中断，避免静默重复计费。

## 前端环境

工具保存在项目目录，不替换系统 Java：

- Flutter 稳定版 3.47.8，Dart 3.13.7。
- JDK 17，Android API 35/36，Build Tools 36.0.0，Platform Tools 37.0.1，NDK 28.2.13676358，Gradle 9.3.1、CMake 3.22.1。
- `scripts/flutter.sh` 设置项目本地 Pub 缓存、官方中国镜像、Android SDK 与 JDK 路径；换机器可用 `COOK_FLUTTER_SDK` 指向自行安装的同版本 SDK。
- VS Code 已安装 Flutter/Dart 扩展，`.vscode/` 提供 SDK 路径和启动配置。

客户端通过 `API_BASE_URL` 指定后端，不包含任何 AI 密钥。后端默认 CORS 允许本地 8080 预览端口。Web 默认连接 `http://127.0.0.1:8000`；Android 模拟器默认 `http://10.0.2.2:8000`，真机需指定开发电脑可访问的地址。仅调试配置允许本地明文 HTTP，正式发布应使用 HTTPS。

Linux/WSL 可以生成和验证 Flutter Web/Android 工程；iOS 签名和实机构建仍需要 macOS/Xcode。

## 执行、离线与提醒

执行页显示手动/明火任务及自动设备任务，备注、独立计时器、确认按钮、设备自动确认等待（5/30/60/120/300/600 秒）。仅被动自动设备且没有明火/锅具占用的任务可以自动确认；倒计时结束之前仍保留资源。手动确认会尝试重新计算剩余计划，失败时保留原进度，可手动重试。暂停只停止安排新任务，物理运行继续计时。

Drift 按账号命名空间保存菜谱、厨房、计划、AI 草稿及执行状态。菜谱/厨房编辑先持久化到 outbox，再条件写入服务端；联网时每 20 秒重试，冲突保留本地内容并提供采用云端/本地选择和备份。执行页每 10 秒或手动尝试同步，会话版本冲突提供恢复云端或另存独立会话。离线可以执行已下载的计划，不能离线调用 AI 或 OR-Tools 生成新计划。

系统通知按正在运行任务的实际到期时间预先登记，Android 配置通知、精确闹钟和重启恢复权限；拒绝权限会显示提示。应用进程在后台停止时仍由系统提醒；回到前台再按墙上时间补算设备确认和下一步骤，不在后台启动人工操作。退出账号清除令牌并取消本机提醒。iOS 已接入通知授权与前台代理，仍需 macOS 实机构建验收。

## 当前阶段边界

尚未实现邮箱验证、密码找回、URL 抓取、系统分享、Celery/Redis、金额成本上限、WebSocket 推送及跨步骤资源占用编辑器。多设备会话依靠版本化拉取和显式冲突处理；后台不持续联网同步。用户启动正式登录后，旧开发账号的菜谱仍属于开发账号，不会自动转移给新注册用户。

## 参考

[Flutter 安装](https://docs.flutter.dev/install/manual)、[Drift 配置](https://drift.simonbinder.eu/setup/)、[DeepSeek JSON 输出](https://api-docs.deepseek.com/guides/json_mode/)、[DeepSeek 图片输入](https://api-docs.deepseek.com/guides/vision/)。

## 本轮验证记录

- Flutter doctor：Flutter、Android 工具链、Chrome、连接设备及网络检查全部通过。
- Flutter 代码分析无问题；27 项测试覆盖模型、SQLite 重启恢复、路由数据、初始化竞态、离线 AI 草稿、执行状态机和 outbox。
- 37 项后端测试通过，覆盖调度、CRUD、持久化恢复、配额、AI 修正和资源归一化。
- Flutter Web 正式构建成功，本地打包中文字体与数据库 WASM，无外部渲染 CDN 依赖。
- 浏览器实际联通 DeepSeek 导入、确认编辑、编辑页刷新恢复、数据库保存、选菜、真实排程与后端不可用时的缓存恢复。联调菜谱已清理，AI 用量和任务记录保留。
- [Flutter 菜谱页](flutter-client-preview.png)、[Flutter 计划页](flutter-plan-preview.png)。

浏览器新增验收通过：注册登录、实际计划开始、手动与设备并行、断网确认衔接、刷新恢复与联网同步。

尚未执行 Android/iOS 实机发布验收。iOS 构建需要 macOS/Xcode。

认证实现参考 [FastAPI 安全文档](https://fastapi.tiangolo.com/tutorial/security/oauth2-jwt/)，系统提醒配置参考 [flutter_local_notifications 官方文档](https://pub.dev/documentation/flutter_local_notifications/latest/index.html)。首次构建的官方引擎包通过分段下载并校验存储 MD5，写入项目本地 Maven 缓存；Gradle 分发包通过官方 SHA-256 校验。以上缓存均在忽略目录 `.tools/` 中。APK 运行和验收边界见 [Android 安装说明](ANDROID.md)。

## Android 构建交付

`build apk --debug` 成功，产物为 `dist/kaifan-android-debug.apk`（183,832,450 字节）。APK 签名校验通过，包含 ARM32、ARM64、x86_64；通知图标与字体许可证已打包，AI 密钥未进入 APK。后台通知的锁屏、省电和重启恢复仍需真机验收。

## 0.1.1 交互修正

- `target_finish_time` 可以省略或设为 `null`；客户端默认不指定目标时间，预览和重新规划兼容无目标计划。
- 设备不足等调度错误显示中文弹窗和持续错误卡片；自动重新规划收到服务端冲突也会显示原因。
- 被动/间歇步骤计时未结束时，提前完成需弹窗确认；取消不推进，倒计时正常继续。
- 完成页增加「完成并返回菜谱」，保存历史及未同步进度后返回；新计划不会要求继续已完成的旧会话。
- APK 版本号更新为 0.1.1（versionCode 2），可以覆盖安装。覆盖安装后重启后端以加载可选时间接口。

## 0.1.2：输入兼容与按时回厨房

- WSA 专用输入桥在文本清空后同步空编辑状态并重启输入连接，不改写正文、光标或中文组成区；普通 Android 保持原输入路径。隔离 WSA 中清空重输验证通过，用户原始偶发回填仍需原键盘操作复验。
- 指定目标时不再平移计划起点。完成设备启动操作可直接衔接同道菜的被动运行，其他菜的未来手动任务保留计划时间。无目标计划仍可立即开始。
- 增加休息状态、后续开工时间、到点开始按钮和提前开始确认；离开前登记未来任务的系统提醒，回到前台不虚构人工开始事实。
- 旧会话通过恢复目标的相对坐标纠正原定开饭时刻，实际开始/完成值保持原样；联网后重新安排剩余任务。
- WSA 隔离测试包最小化后，系统实际投递 30 秒后的开工通知。测试包已卸载，未改正式应用数据；手机实机与系统重启场景尚未验收。
- 原生实现参考 [Android restartInput](https://developer.android.com/reference/android/view/inputmethod/InputMethodManager#restartInput(android.view.View)) 与 [Flutter textInput 通道](https://api.flutter.dev/flutter/services/SystemChannels/textInput-constant.html)。

## 0.1.3：导入及手动编辑的 WSA 原生输入

此前清空后重置 Flutter 输入缓存的处理不足以解决完整菜谱页面的问题。本版本为这些字段提供 WSA 专用的 Android EditText 对话框，直接使用系统输入连接；完成时回填控制器及草稿，取消时保留旧值。编辑期间保持列表字段存活，防止滚动或窗口尺寸变化丢失输入。只读预览不再触发旧的 Flutter 输入连接重置。

普通 Android 和 Web 仍使用原有内联 TextFormField。原生输入包含数值键盘、长度限制、清空和多行配置；Android 手机尚未实测。新增 3 项回归覆盖真实导入页提交文本、编辑页保存替换后的菜名、取消编辑及普通 Android 路径。

0.1.3（versionCode 4）与旧版签名一致，已通过覆盖安装保留数据。Windows 键盘自动化使用明确的前台窗口校验；测试内容不提交给 AI，也不保存为正式菜谱。

## 0.1.3：WSA 正式菜谱页面输入修复

为导入和编辑页增加 WSA 专用 Android EditText 系统编辑框，完成时回填控制器及草稿，取消时保留旧值。字段在原生编辑期间保持存活，避免列表回收丢失修改；只读预览不触发旧的 Flutter 输入缓存重置。支持数值、长度限制、清空和多行配置；普通 Android/Web 仍内联编辑。

新增 3 项测试覆盖实际导入内容提交、手动编辑保存替换后的菜名、取消保持及普通 Android 输入；全套 27 项 Flutter 测试和静态检查通过。正式包已覆盖安装到 WSA，未清理账号和菜谱数据。对正式应用的输入、中文拼音、六类字段、回填及取消做了实际验证；所有测试文字均未提交或保存。

实现参考 [Android 系统对话框](https://developer.android.com/develop/ui/views/components/dialogs) 与 [Flutter 平台通道](https://docs.flutter.dev/platform-integration/platform-channels)。

WSA 最终验收还覆盖原问题：输入 ABCD、四次实际退格删除、输入 Z，结果仅保留 Z。完成后返回菜谱首页，测试输入均未保存。
