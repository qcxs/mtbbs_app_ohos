import 'dart:developer' as developer;

/// 本包独立于 app，无法使用 app 的 `AppLogger`（会形成循环依赖），
/// 统一走 `dart:developer` 日志（不会出现在 release 的 stdout）。
void logBridge(String message) => developer.log(message, name: 'MtbbsOhosBridge');
