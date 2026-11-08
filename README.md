# 开饭 · AI 智能烹饪助手

包含 OR-Tools 调度引擎、SQLAlchemy 持久化服务、DeepSeek 文本/图片导入和 uni-app 客户端（H5 / 微信小程序）。旧版 Flutter 客户端与 HTML 原型保留供参考。

## 正式客户端开发

当前前端位于 `frontend/uniapp/`，采用 Vue 3 与 uni-app，支持 H5 和微信小程序构建。需要 Node.js 22.12+。

先在根目录启动后端：

```bash
uv sync --extra test
.venv/bin/alembic -c backend/service/migrations/alembic.ini upgrade head
.venv/bin/python -m service --port 8002
```

再在 `frontend/uniapp` 目录安装依赖并启动 H5：

```bash
cd frontend/uniapp
npm ci
cp .env.example .env.local
npm run dev:h5
```

打开 http://localhost:8080 。若后端不是 8002，请调整 `frontend/uniapp/.env.local` 中的 `VITE_API_BASE_URL`。当前提供登录、菜谱导入和编辑、厨房配置、计划生成、烹饪执行和离线恢复；微信后台系统提醒需另外实现订阅消息。

[uni-app 操作与微信构建说明](frontend/uniapp/README.md) · [Flutter 旧版说明](frontend/mobile/README.md) · [本轮实施与环境](docs/IMPLEMENTATION.md)

服务端密钥保存在忽略文件 `.env` 中，不能放入前端。默认使用 SQLite 本地持久化，支持邮箱密码注册、JWT 登录与刷新令牌轮换；uni-app 客户端按账号隔离本地缓存。匿名开发账号默认关闭。

## 食材结构化与份量换算

在菜谱编辑页逐项填写食材原用量、单位与换算规则。在做饭页设置每道菜本餐份数，点击“预览本餐食材用量”。支持线性、指数、固定＋变量、固定、手动与分段曲线；默认调味/油量曲线只是可调整的参考。水量、火力、时长和锅具容量需按实际配方核对。换算不会覆盖原菜谱，计划与执行会话保存独立食材快照。

旧菜谱无需手动迁移，明确的数值、分数与区间会自动解析；“适量”和无法可靠解析的数量保留原文，不猜测密度或容器规格。后端预览接口为 `POST /api/v1/recipes/{id}/scale`，请求 `{"target_servings":4}`；原计划接口可选传 `servings_by_recipe`。

[本轮实施与默认决策](docs/IMPLEMENTATION_DECISIONS.md) · [食材编辑界面](docs/structured-ingredients-preview.png) · [本餐换算界面](docs/portion-scaling-preview.png)

## 今天吃什么

菜谱页的“今天吃什么”提供 10分钟快手菜、普通一顿、吃顿好的三种倾向，默认分别为 1/2/3 道、10/30/60 分钟，可自行调整人数、菜数和工作量。推荐先调用 DeepSeek 返回可编辑菜名列表，不直接生成完整菜谱；换一批会排除当前菜名。已确认且唯一匹配的库中菜谱可加入计划，其余可导入后确认。

需要配置已有 `COOK_DEEPSEEK_API_KEY`，推荐与导入共用现有 API 配额。估时是菜单建议，实际时间以完整步骤和厨房排程为准。接口：`POST /api/v1/recommendations/menu`。截图：[快手模式](docs/meal-menu-quick-preview.png)、[丰盛模式](docs/meal-menu-feast-preview.png)。

## GitHub 自动构建

`frontend/uniapp` 更新会触发 H5、微信小程序和 App 资源构建；手动运行可通过 HBuilderX runner 生成 Android APK 和 iOS IPA。Flutter 工作流已删除。

- **uni-app H5 / 微信小程序**：运行 Node 测试并编译两个目标；微信小程序产物需在微信开发者工具中导入，并配置 AppID 与 HTTPS 合法域名。
- **原生 App**：手动签名云打包 Android APK / iOS IPA，配置方法见 [CI 文档](docs/CI.md)。

在对应运行的 **Artifacts** 区域下载构建结果。后端服务需独立运行。

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
│   ├── uniapp/          # 当前 H5 / 微信小程序客户端
│   ├── mobile/          # 旧版 Flutter 客户端
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
