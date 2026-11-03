# 开饭 · uni-app 客户端

Vue 3 + uni-app，构建 H5 与微信小程序，共用现有 FastAPI 菜谱、DeepSeek、调度和会话接口。Flutter 客户端保留在 `../mobile/` 作为旧版客户端。

## 本地运行

需要 Node.js 22.12+、npm，以及 Python 后端。先在仓库根目录启动后端；此仓库当前默认端口由 `backend/service/__main__.py` 决定，可显式指定：

```bash
.venv/bin/python -m service --port 8002
```

在本目录执行：

```bash
npm ci
cp .env.example .env.local
npm run dev:h5
```

打开 `http://localhost:8080`。若更换 H5 地址，须同步配置后端 `COOK_CORS_ORIGINS`。服务端密钥只保存在后端 `.env`，不要写入本项目环境变量。
启动命令是 `npm run dev:h5`；`npm uni --port 8080` 不会启动项目的 uni-app 开发服务。

## 微信小程序

将 `src/manifest.json` 中 `mp-weixin.appid` 改为自己的小程序 AppID。在本目录创建 `.env.production.local`，设置 `VITE_API_BASE_URL=https://你的后端域名`，然后运行：

```bash
npm ci
npm run build:mp-weixin
```

用微信开发者工具导入 `dist/build/mp-weixin`。在微信小程序后台把同一个 HTTPS 域名配置为 **request 合法域名** 和 **uploadFile 合法域名**；正式环境后端也应通过 HTTPS 提供服务。账号目前沿用邮箱密码登录，暂未接入微信身份登录。图片导入每次一张；文本可直接输入菜名。微信小程序退到后台时不保证定时提醒，返回执行页后会按真实时间恢复计时。正式发布前请在微信开发者工具和 Android/iOS 微信真机完成登录、导入、排程、执行与恢复验收。

GitHub Actions 的 uni-app 构建使用仓库变量 `UNIAPP_API_BASE_URL`。未设置时只验证编译，产物指向占位域名，不能直接联机使用。发布前请设置实际 HTTPS 地址并重新构建。

## 验证

```bash
npm test
npm run build:h5
npm run build:mp-weixin
```

`src/lib/` 包含 API、账号隔离缓存、离线编辑队列和烹饪状态机；`src/pages/` 包含登录、菜谱、导入、编辑、厨房、计划、时间线与执行页面。离线编辑会保存在本机，联网后可在“我的”重试同步或处理冲突；计划生成会先要求所有本机编辑同步完成。云端会话冲突会保留本机进度，由用户选择恢复云端或保存为独立会话。

## 依赖审计

2026-11-03 的完整 `npm audit` 结果为 **0 项**。项目使用 Vue 3.5.44、Vue I18n 11.4.17 和 Vite 7.3.7，并通过 `overrides` 统一 DCloud 依赖树中的修复版本。`vite.config.js` 将 DCloud 默认使用的内嵌 Vue I18n 9 运行时替换为项目安装的 Vue I18n 11 运行时。

这些版本覆盖由本项目维护，升级 DCloud 编译器时应重新核对覆盖规则及运行时 alias。更新依赖后运行 `npm ci`、`npm audit`、`npm test` 和两个目标的构建命令；微信开发者工具与真机运行仍需单独验收。无需使用 `--legacy-peer-deps` 或关闭审计。

## Android / iOS 构建

`npm run build:app` 生成 App 资源。GitHub Actions 可手动选择 Android、iOS 或两者，通过已配置的 HBuilderX runner 云打包签名 APK/IPA。所需 Variables、Secrets、证书和 runner 配置见 [CI 文档](../../docs/CI.md)。原 Flutter 构建工作流已移除。
