/// MTBBS 鸿蒙应用接续（应用流转）的 Dart 侧入口。
///
/// 本包以 **Dart 插件**（`flutter.plugin.platforms.ohos.dartPluginClass`）声明：
/// 构建时 flutter_tools 生成 `.dart_tool/flutter_build/dart_plugin_registrant.dart`，
/// 引擎在 isolate 启动时自动调用 [MtbbsOhosBridge.registerWith]，因此默认的
/// `lib/main.dart` 构建/运行也会带上接续能力（不再需要 `--target`）。
///
/// 原生侧（通道实现、系统回调）仍在 app 的 `ohos/`，设计见
/// `docs/ohos/05-应用流转可行性调研.md`。
library;

import 'src/bridge.dart';

export 'src/bridge.dart' show ContinuationBridge;
export 'src/continuation.dart' show Continuation;

/// 插件注册入口（由生成的 dart_plugin_registrant 调用，**早于** `main()`）。
abstract final class MtbbsOhosBridge {
  /// 注册器执行时 `WidgetsBinding` 尚未初始化、`setMethodCallHandler` 不可用，
  /// 交给 [ContinuationBridge.installWhenBindingReady] 等 binding 就绪后再装。
  static void registerWith() => ContinuationBridge.installWhenBindingReady();
}
