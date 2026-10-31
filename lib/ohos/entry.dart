import 'package:flutter/widgets.dart';
import 'package:mtbbs/main.dart' as app;
import 'package:mtbbs_ohos_bridge/mtbbs_ohos_bridge.dart';

/// 鸿蒙专属启动入口 —— **可选**，已不再是构建必带项。
///
/// 接续通道由 Dart 插件 `packages/mtbbs_ohos_bridge` 在 isolate 启动时自动注册
/// （见该包 `lib/mtbbs_ohos_bridge.dart`），默认 `lib/main.dart` 构建即生效。
/// 这里保留显式兜底：`--target lib/ohos/entry.dart` 时手动装一次（幂等），
/// 便于排查"自动注册是否生效"（见 docs/ohos/05 §5.1）。
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  ContinuationBridge.install();
  app.main();
}
