# Web 数据库依赖

- `drift_worker.js`：Drift 2.31.0 官方发布资源，MIT 许可证见 LICENSE.drift.txt。
  来源：https://github.com/simolus3/drift/releases/tag/drift-2.31.0
- `sqlite3.wasm`：sqlite3.dart 2.9.4 官方发布资源；Dart 包 MIT 许可证见 LICENSE.sqlite3.txt，SQLite 核心为公有领域。
  来源：https://github.com/simolus3/sqlite3.dart/releases/tag/sqlite3-2.9.4

两者与 pubspec.lock 中的版本对应。升级数据库依赖时需同时验证和更新 Web 文件。
