import 'package:flutter/widgets.dart';
import 'package:mtbbs/main.dart' as app;
import 'package:mtbbs/ohos/continuation_bridge.dart';

/// 鸿蒙专属启动入口（构建/运行须带 `--target lib/ohos/entry.dart`）。
///
/// 不改上游 `lib/main.dart`：这里只多做一件事——在 `app.main()` 之前挂上
/// 应用接续通道（见 docs/ohos/05）。`ensureInitialized()` 必须先调：
/// `setMethodCallHandler` 依赖 Binding；`main.dart` 自己也会调，重复调用幂等。
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  ContinuationBridge.install();
  app.main();
}
