# GitHub Actions 构建与下载

## 工作流

| 工作流 | 环境 | 检查与产物 |
| --- | --- | --- |
| `Android APK` | Ubuntu 24.04、JDK 17 | `flutter analyze`、`flutter test`、Debug APK 与 SHA-256 |
| `iOS Build` | macOS 26、Xcode | 未签名 Release `.app.zip` 与 SHA-256；可手动选择 Debug 模拟器产物 |

两者固定 Flutter **3.47.8**，使用已提交的 `pubspec.lock`，依赖解析时启用 `--enforce-lockfile`。GitHub Actions 固定到官方发布版本的提交号。Android 的 Gradle Wrapper、版本和分发包校验值随代码提交。

修改 `frontend/mobile/` 或相应工作流后，推送到 `main` 或提交 PR 会触发构建。修改后端和文档不会自动消耗移动端构建时间。两套工作流独立运行，每套最长 45 分钟，新运行会取消同一分支的旧运行。

## 手动构建与后端地址

1. 打开仓库的 **Actions** 页面。
2. 选择 **Android APK** 或 **iOS Build**，点击 **Run workflow**。
3. 可填写 `api_base_url`；iOS 可选择 `device-unsigned` 或 `simulator`。
4. 等待运行成功，在该次运行的 **Artifacts** 下载产物，保留期为 14 天。

也可以在 **Settings → Secrets and variables → Actions → Variables** 添加仓库变量 `API_BASE_URL`。地址选择顺序为：手动输入、仓库变量、平台默认地址。

Android 默认 `http://10.0.2.2:8000`，用于 Android Studio 模拟器访问宿主机。iOS 默认 `http://127.0.0.1:8000`，用于 Mac 模拟器本地开发。WSA 或真机需要填入设备可访问的后端地址，或者在 App 登录页修改服务器地址；填写服务器时包含协议与端口，不加 `/api/v1`。公网部署使用 HTTPS。

`API_BASE_URL` 会编译进客户端，可以公开。DeepSeek Key、JWT Secret 和数据库密码只放服务端环境中，不能设置为客户端编译参数。工作流不启动或部署后端，也不调用真实 AI 服务。

## Android 安装

解压 Actions 下载文件，安装 `kaifan-android-debug.apk`。构建包允许本地 HTTP 调试，适合开发测试，不用于应用商店发布。

CI 使用运行器临时生成的 Debug 签名，可能与之前本地安装或其他运行的签名不同。如果覆盖安装提示签名不一致，需要先备份数据，再卸载旧包；卸载会清除本地数据。正式持续分发前，应另行配置固定的签名密钥与发布构建，密钥存入 GitHub Secrets，不提交到仓库。

## iOS 产物与签名

默认生成 `kaifan-ios-device-unsigned.app.zip`，验证真机目标编译，但不能直接安装到 iPhone，也不是可上传 TestFlight 的 IPA。真机分发需要 Apple Developer 账号、匹配 `dev.kaifan.kaifan` 的证书与 provisioning profile，以及独立的签名和导出流程。

手动选择 `simulator`，可得到 `kaifan-ios-simulator.app.zip`。在 Mac 上解压，启动匹配架构的 iOS 模拟器，然后运行：

```bash
xcrun simctl install booted /path/to/Runner.app
xcrun simctl launch booted dev.kaifan.kaifan
```

项目最低支持 iOS 15。原生插件使用 Flutter 的 Swift Package Manager 集成，同时保留 CocoaPods 回退配置。`Runner.entitlements` 为安全存储声明 Keychain 配置。

## 本地验证

安装 Flutter 3.47.8 后，在 `frontend/mobile` 中运行：

```bash
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter build apk --debug
# 需要 macOS 与 Xcode
flutter build ios --release --no-codesign
```

Linux 运行数据库测试需要可加载的 SQLite 库，Ubuntu 可安装 `libsqlite3-dev`。当前 WSL 的项目本地 SDK 可通过 `../../scripts/flutter.sh` 替代 `flutter`。

后端和 HTML 原型测试在根目录运行：

```bash
uv sync --extra test
uv run pytest -q
node --test frontend/tests/execution.test.cjs
```

工作流失败时，打开失败步骤查看日志；构建成功仅代表编译与自动检查通过，通知权限、离线恢复和设备输入仍需真机验收。
