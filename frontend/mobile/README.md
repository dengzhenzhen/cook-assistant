# 开饭 · Flutter 客户端

Flutter + Riverpod + go_router + Dio + Drift，Android / iOS / Web 共用业务代码。HTML 原型仍保留在上级目录。

## 当前实现

- 真实菜谱列表、手动创建/编辑、收藏、选菜。
- 步骤备注、时长、关注方式、非线性依赖和厨具需求。
- 默认厨房与设备数量持久化。
- DeepSeek 文本/图片异步导入、结果确认再保存、用量查看。
- 从已保存菜谱和厨房生成真实调度时间线。
- Drift/SQLite 缓存菜谱、厨房、选菜和上次计划；断网可查看缓存。

正式客户端已接入登录、并行烹饪执行、离线编辑与会话同步、系统计时通知。上级 HTML 原型保留用于交互参考。

## 本机环境

已配置项目内 `.tools/flutter`、JDK 17、Android SDK 36 与 VS Code Flutter/Dart 扩展。工具与缓存均被忽略，不提交 SDK。详细实施和服务端配置见 [IMPLEMENTATION.md](../../docs/IMPLEMENTATION.md)。

### 安装依赖与代码生成

在本目录执行：

```bash
../../scripts/flutter.sh pub get
../../scripts/dart.sh run build_runner build
```

`pubspec.lock` 和 `lib/data/database.g.dart` 保留在仓库，便于重复构建。Web SQLite/Worker 按锁定版本提供，来源和许可证见 `web/THIRD_PARTY_NOTICES.md`。

### 本地 Web 调试

先在仓库根目录启动后端：

```bash
.venv/bin/python -m service
```

再在本目录运行：

```bash
../../scripts/flutter.sh run -d web-server --web-port 8080 \
  --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

打开终端显示的 http://localhost:8080。VS Code 中也可选择「开饭 · Flutter Web」启动配置。

### Android

连接 Android 真机或启动模拟器后，在本目录运行：

```bash
../../scripts/flutter.sh devices
../../scripts/flutter.sh run --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

`10.0.2.2` 只适用于 Android 模拟器；真机需改为电脑局域网地址，并在受控开发网络内让服务监听可访问地址。发布版本需使用 HTTPS；当前仅 Debug 允许本地 HTTP。

iOS 平台文件已生成，选图用途说明已配置；iOS 编译、签名和实机调试仍需要 macOS/Xcode，不能在当前 Linux/WSL 上验收。

## 验证与构建

```bash
../../scripts/flutter.sh analyze
../../scripts/flutter.sh test
../../scripts/flutter.sh build web --no-web-resources-cdn \
  --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

Web 构建结果位于 `build/web`。服务端 `.env` 中的 DeepSeek 密钥不会进入 Flutter 配置或构建产物。

邮箱密码注册/登录使用 JWT 和轮换刷新令牌，令牌保存于系统安全存储。本地 Drift 数据按账号隔离。离线菜谱/厨房编辑进入持久队列，冲突需选择采用本地或云端；执行进度按版本同步，可以恢复云端会话。后台使用系统本地通知；Android 安装和权限说明见 [安装指南](../../docs/ANDROID.md)。

0.1.2 增加 WSA 清空重输兼容处理、保留目标时间的休息等待模式、后续开工系统提醒与显式提前开始。自动设备运行期间可等待后续操作；明火仍需看管。

0.1.3：WSA 的菜谱字段点击后使用系统编辑框，点「完成」回填、点「取消」保留原文，支持「清空」。普通 Android 手机和 Web 保持原有内联编辑。

0.1.3：WSA 的菜谱字段点击后使用系统编辑框，点「完成」回填，点「取消」保留原文，支持「清空」。普通 Android 手机和 Web 保持内联编辑。
