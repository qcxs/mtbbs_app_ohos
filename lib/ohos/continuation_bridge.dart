import 'dart:async';

import 'package:flutter/services.dart';
import 'package:mtbbs/core/utils/logger.dart';
import 'package:mtbbs/ohos/continuation.dart';

/// 应用接续通道契约（通道名 `mtbbs/continuation`）。
///
/// ArkTS 实现见 `ohos/entry/src/main/ets/plugins/ContinuationBridge.ets`，
/// 设计见 `docs/ohos/05-应用流转可行性调研.md` §4.5。两端方法必须一致：
///
/// | 方向 | 方法 |
/// |------|------|
/// | ArkTS→Dart | `getContinuationState`（源端 onContinue 拉快照） |
/// | ArkTS→Dart | `onContinuationRestore`（对端热启动推送） |
/// | Dart→ArkTS | `getPendingContinuation`（取走暂存数据） |
/// | Dart→ArkTS | `setContinuationActive`（切换可接续态） |
abstract class ContinuationBridge {
  static const String _tag = 'Continuation';

  static const MethodChannel _channel = MethodChannel('mtbbs/continuation');

  static bool _installed = false;

  /// 自定义入口 `lib/ohos/entry.dart` 在 `app.main()` 之前调用一次。
  ///
  /// 注册 handler 必须先于 `runApp`：`onContinue` 可能在引擎启动后的任意时刻
  /// 到达，handler 缺失会直接判为 `notImplemented` → 接续失败。
  static void install() {
    if (_installed) return;
    _installed = true;
    _channel.setMethodCallHandler(_onMethodCall);
    Continuation.start();
  }

  static Future<Object?> _onMethodCall(MethodCall call) async {
    switch (call.method) {
      // 源端：原生 onContinue 向 Dart 拉当前快照（无快照返回 null → REJECT）
      case 'getContinuationState':
        return Continuation.currentState();
      // 对端热启动（onNewWant）：原生已暂存，通知 Dart 立即取走并跳转
      case 'onContinuationRestore':
        unawaited(Continuation.restorePending());
        return null;
      default:
        throw MissingPluginException('未实现的接续回调: ${call.method}');
    }
  }

  /// 取走原生暂存的对端接续数据（原生侧取走即清空，不会重复跳转）。
  static Future<String?> takePending() async {
    try {
      return await _channel.invokeMethod<String>('getPendingContinuation');
    } on PlatformException catch (e) {
      AppLogger.w(_tag, 'getPendingContinuation failed: $e');
      return null;
    } on MissingPluginException catch (_) {
      // 原生侧未实现（旧包），静默降级
      return null;
    }
  }

  /// 切换本机在对端设备的「可接续」入口显隐。
  static void setActive(bool active) {
    unawaited(
      _channel
          .invokeMethod<void>('setContinuationActive', {'active': active})
          .catchError(
            (Object e) => AppLogger.w(_tag, 'setContinuationActive failed: $e'),
          ),
    );
  }
}
