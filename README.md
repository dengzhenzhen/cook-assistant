# 开饭 · AI 智能烹饪助手

包含 OR-Tools 调度引擎、SQLAlchemy 持久化服务、DeepSeek 文本/图片导入和 Flutter 客户端。原有 HTML 原型保留完整烹饪执行演示。

## 正式客户端开发

前端环境已配置为项目本地 Flutter 3.47.8 / Dart 3.13.7、JDK 17 和 Android SDK 36，并配置了 VS Code Flutter/Dart 扩展。

先在根目录启动后端：

```bash
uv sync --extra test
.venv/bin/alembic -c backend/service/migrations/alembic.ini upgrade head
.venv/bin/python -m service
```

再在 `frontend/mobile` 目录启动 Flutter Web：

```bash
../../scripts/flutter.sh run -d web-server --web-port 8080 \
  --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

打开 http://localhost:8080 。当前提供登录、菜谱导入和编辑、厨房配置、计划生成、烹饪执行、离线同步与系统提醒。

[Flutter 操作说明](frontend/mobile/README.md) · [本轮实施与环境](docs/IMPLEMENTATION.md) · [项目规划](docs/PROJECT_PLAN.md)

服务端密钥保存在忽略文件 `.env` 中，不能放入前端。默认使用 SQLite 本地持久化，支持邮箱密码注册、JWT 登录与刷新令牌轮换；客户端令牌使用系统安全存储。匿名开发账号默认关闭。

## GitHub 自动构建

移动端代码推送到 `main` 或提交 PR 后，GitHub Actions 分别构建 Android 和 iOS，也可以在 Actions 页面点击 **Run workflow** 手动执行。

- **Android APK**：静态检查、Flutter 测试、生成可安装的 Debug APK。
- **iOS Build**：在 macOS 上生成未签名的真机应用；手动运行时也可选择模拟器应用。

在对应运行的 **Artifacts** 区域下载构建结果。iOS 真机安装和 TestFlight 发布需要另行配置 Apple 开发者证书与描述文件。后端服务需独立运行，详见 [CI 构建与下载说明](docs/CI.md)。

## 体验 HTML 原型

在仓库根目录运行：

```bash
uv sync --extra test
.venv/bin/python -m service
```

打开 http://127.0.0.1:8000 ，即可体验菜谱导入确认、厨房配置、真实排程和烹饪执行。端口可用 `--port 8001` 调整；Ctrl+C 停止服务。

[原型操作说明](frontend/README.md) · [项目规划](docs/PROJECT_PLAN.md)


## 安装与运行

需要 Python 3.10+：

```bash
uv venv .venv
uv pip install --python .venv/bin/python -e '.[test]'
.venv/bin/python -m cook_scheduler examples/dinner.json
.venv/bin/python -m pytest -q
```

Python 调用：

```python
from cook_scheduler import Request, generate_plan
request = Request.model_validate_json(open('examples/dinner.json').read())
plan = generate_plan(request)
print(plan.model_dump_json(indent=2))
```

## 目录结构

```text
.
├── backend/
│   ├── cook_scheduler/  # 调度模型、CP-SAT 引擎和命令行入口
│   ├── service/         # FastAPI、持久化、DeepSeek 导入与调度
│   └── tests/           # 后端回归测试
├── frontend/
│   ├── mobile/          # Flutter 正式客户端
│   └── index.html       # HTML 交互原型
├── scripts/             # 本地 SDK 包装和联调脚本
├── docs/                # 规划与实施记录
├── examples/            # 调度输入示例
├── pyproject.toml       # Python 依赖、打包和测试配置
└── uv.lock              # Python 依赖锁文件
```

安装和运行命令均在仓库根目录执行。Python 包仍通过 `from cook_scheduler import ...` 导入。移动目录后需重新执行可编辑安装，以更新包路径。

示例包含米饭和番茄炒蛋，两条备料分支不会被强制串行依赖。

## 输入约定

所有时间均为相对同一会话起点的整数秒。调用方把目标开饭时间转换为 `target_finish_seconds`；不传则尽早完成。任务 ID 在整个请求中唯一，依赖通过 ID 引用；环、未知依赖、重复 ID 和矛盾执行记录会被拒绝。跨菜谱依赖也可表达。

- `capacities`：厨具类型到可用数量的映射，未登记视为 0；`cook_count` 为厨师数。
- `tasks[].resources`：仅在该任务执行期间占用的资源及数量。
- `holds`：从 `start_task` 开始到 `end_task` 结束持续占用；省略结束任务则持有到开饭时刻。可表达锅中盛物、餐盘待用。相同占用不要同时写入任务资源，否则会重复计数。跨任务的结束事件应通过 DAG 保证在开始事件之后。
- `attention_type`：active 和 intermittent 全程占用一名厨师，passive 不占用。间歇检查的精细时间窗后续实现；需要操作的启动、检查、收尾应拆为独立 active 任务。
- `max_holding_seconds`：各菜允许的完成后等待时长；是软目标，无法满足时返回超出秒数。

资源按类型累计数量分配，尚不分配具体锅具 ID，也不处理能力替代、清洗或容量。

## 目标与重排

硬约束为 DAG、资源容量、人员容量及执行事实。依次优化：迟于目标的时间、菜品等待超限总量、首任务到末任务的跨度、完成时间。逐层固定已证明最优的目标，避免权重掩盖优先级；超时得到可行解时 `optimal=false`，不继续优化低优先级。每层默认限时 10 秒，总计最多约 40 秒。无可行方案时抛出 `SchedulingError`，不会静默忽略资源约束。

重排再次调用同一函数，提供 `now_seconds` 和 `execution`：完成任务填写 `actual_start/actual_end`，运行任务填写 `actual_start/remaining_seconds`。保留实际时间和占用，未启动任务只能安排在当前时刻之后。历史状态必须包含已启动任务的已完成前置任务。已完成任务保留在输出中以便审计。执行状态应由上层持久化；原型不负责暂停、跳过或状态事件幂等。

`finish_seconds` 是所有烹饪任务结束时刻；开饭时刻为它和目标时间的较大值。餐具占用延续到该时刻，饭后清洗及释放需后续扩展。

## 验证范围

测试覆盖 DAG 并行、循环检测、厨师与被动任务并行、缺少厨具、跨任务持锅、餐盘持有、目标时间与保鲜、执行延误后重排、历史资源冲突。固定时长是估计值，结果不替代用户对食物熟度和明火安全的判断。

建模参考：[OR-Tools 官方调度文档](https://github.com/google/or-tools/blob/stable/ortools/sat/docs/scheduling.md)。

烹饪执行支持同时显示手动和自动设备任务、步骤备注、确认后衔接与真实重排。离线编辑进入持久队列，进度按版本同步；冲突保留双方备份。APK 使用方法见 [Android 安装说明](docs/ANDROID.md)。
