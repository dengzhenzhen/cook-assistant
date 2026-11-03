# uni-app GitHub Actions

工作流：`.github/workflows/uniapp.yml`。原 Flutter Android/iOS 工作流已删除；旧客户端源码保留。

## 自动检查与资源产物

修改 `frontend/uniapp/**` 或工作流后，main push、PR 自动运行：

- `npm ci`、`npm test`、原生打包脚本的模拟测试
- H5、微信小程序、App 资源构建
- 上传 `kaifan-uniapp-<运行编号>`，保留 14 天

仓库 Variables：

| 名称 | 用途 |
| --- | --- |
| `UNIAPP_API_BASE_URL` | 设备可访问的后端 HTTPS 地址，不含 `/api/v1` |
| `WECHAT_APP_ID` | 微信小程序真实 AppID，构建时注入 |
| `DCLOUD_APP_ID` | DCloud 申请的 AppID，格式 `__UNI__...`，与微信 AppID 不同 |
| `HBUILDERX_CLI` | 原生 runner 上 CLI 的绝对路径，默认 `/Applications/HBuilderX.app/Contents/MacOS/cli` |

未设置后端地址时，自动检查使用占位域名，产物仅用于验证编译。微信产物在 `dist/build/mp-weixin`，用微信开发者工具导入；发布前配置 request/uploadFile 合法域名。工作流不上传微信审核或发布。

App 资源 `dist/build/app` 不是 APK/IPA，不能直接安装。Vue 3 使用 `uni build -p app`，APK/IPA 使用下面的 HBuilderX 云打包。

## Android / iOS 签名安装包

原生任务只允许在 main 分支手动触发，依赖自动检查成功；不在 PR 上运行。

1. 配置专用 macOS self-hosted runner，标签包含 `self-hosted`、`macOS`、`hbuilderx`；安装 Node.js 22.12+、Python 3 和 HBuilderX 5.11+（编译器须与项目 DCloud 依赖兼容）。用 runner 的同一系统账号登录 HBuilderX，安装 uni-app/Vue 3 编译插件，确认云打包可用。
2. 在 DCloud 创建真实应用，配置 `DCLOUD_APP_ID`。准备 Android 自有签名证书；iOS 准备匹配 bundle ID 的 p12 与 provisioning profile。将证书存于 runner 的工作区之外，限制为 runner 账号可读。
3. 创建 GitHub Environment `uniapp-native`，限制部署分支为 main；在此环境添加 Secret `NATIVE_PACK_CONFIG`，内容见下方。可按团队需要设置环境审批。
4. Actions → **uni-app builds** → **Run workflow** → 选择 `android`、`ios` 或 `both`，必要时填写 `api_base_url`。`none` 只运行资源构建。
5. 成功后下载 `kaifan-native-<目标>-<运行编号>`，内含 APK/IPA 和 SHA-256。iOS 能否安装取决于证书类型和描述文件授权设备，App Store 分发仍需单独上传。

`NATIVE_PACK_CONFIG` 示例（按选择的平台提供相应对象，路径为 runner 上真实绝对路径）：

```json
{
  "android": {
    "packagename": "com.example.kaifan",
    "androidpacktype": "0",
    "certfile": "/Users/runner/signing/kaifan.keystore",
    "certalias": "kaifan",
    "certpassword": "证书密码",
    "storePassword": "证书库密码"
  },
  "ios": {
    "bundle": "com.example.kaifan",
    "supporteddevice": "iPhone,iPad",
    "profile": "/Users/runner/signing/kaifan.mobileprovision",
    "certfile": "/Users/runner/signing/kaifan.p12",
    "certpassword": "p12密码"
  }
}
```

脚本强制使用自有 Android 证书和传统云打包，临时配置权限为 0600，结束后删除；不会上传证书或原始打包日志。传统云打包会把项目与签名材料发送至 DCloud，请按团队的 DCloud 使用约定配置。原生任务串行使用 HBuilderX；打包期间不要在同一应用上手动提交其他云打包。脚本排除已有下载地址，等待新结果并校验下载是 ZIP 包；失败或超时不会将“提交成功”当作“构建成功”。

云打包依赖 DCloud 登录状态、网络与服务额度，可能产生费用。取消 GitHub 任务不保证取消已提交的云端任务，需在 HBuilderX 查看并取消。临时原生 AppID 和后端配置在脚本退出时恢复。

## 本地验证

```bash
cd frontend/uniapp
npm ci
npm test
npm run build:h5
npm run build:mp-weixin
npm run build:app
```

签名打包需配置上述环境，在 macOS runner 上运行 `python3 scripts/native-build.py`。CI 不部署后端；DeepSeek Key、JWT Secret 和数据库密码只保存在后端，不能编译进客户端。

官方参考：[uni-app CLI](https://uniapp.dcloud.net.cn/worktile/CLI.html)、[HBuilderX 云打包](https://hx.dcloud.net.cn/cli/pack)。编译通过后仍需 Android/iOS 微信与原生 App 真机验证。
