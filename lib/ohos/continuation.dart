import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:mtbbs/core/utils/logger.dart';
import 'package:mtbbs/ohos/continuation_bridge.dart';
import 'package:mtbbs/widgets/common/toast_utils.dart' show rootNavigatorKey;

/// 鸿蒙应用接续（流转）的 Dart 侧：可接续态、快照生成、对端恢复。
///
/// 与 PiliPlus 在页面里 `hold/release` 的侵入写法不同，这里**零侵入**上游页面：
/// 只监听 `GoRouter` 的 `routerDelegate`，按当前 location 是否命中可接续路由
/// 切换系统侧的 `ACTIVE / INACTIVE`；快照也是"用时按当前 location 生成"，天然
/// 是最新值（见 docs/ohos/05 §4.4）。
abstract class Continuation {
  static const String _tag = 'Continuation';

  /// P0 可接续路由：帖子详情、版块。
  ///
  /// 快照只存路由 location，对端 `router.go(location)` 即可原样落回同一页面，
  /// 新增可接续页面时只需在这里放开判断，无需改数据结构。
  static bool _isContinuable(String location) {
    if (location.startsWith('/thread/')) {
      // `/thread/cache` 是本地缓存的只读页，不指向真实帖子，不可接续
      return !location.startsWith('/thread/cache');
    }
    return location == '/forum' || location.startsWith('/forum?');
  }

  static GoRouter? _router;
  static String? _lastLocation;
  static bool _active = false;
  static bool _restoring = false;

  /// 在 `ContinuationBridge.install()` 里调用（早于 `app.main()`）。
  static void start() {
    // 首帧后根导航才挂载，此时才能从 rootNavigatorKey 拿到 GoRouter
    WidgetsBinding.instance.addPostFrameCallback((_) => _attach(0));
  }

  static void _attach(int attempt) {
    if (_bind() == null) {
      // 首帧时路由仍未就绪：逐帧重试几次；之后还有 onContinuationRestore /
      // getContinuationState 两条按需绑定的兜底路径。
      if (attempt < 3) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _attach(attempt + 1));
      }
      return;
    }
    _syncActive();
    // 冷启动接续：原生只暂存不推送（此时推送会在首帧前回放而丢失），
    // 由这里在路由就绪后主动补取（见 docs/ohos/05 §4.3）。
    unawaited(restorePending());
  }

  /// 绑定 GoRouter；未就绪返回 null。成功后常驻监听路由变化。
  static GoRouter? _bind() {
    final bound = _router;
    if (bound != null) return bound;
    final context = rootNavigatorKey.currentContext;
    if (context == null) return null;
    final router = GoRouter.maybeOf(context);
    if (router == null) return null;
    _router = router;
    router.routerDelegate.addListener(_syncActive);
    return router;
  }

  static String? _currentLocation() {
    return _bind()?.routerDelegate.currentConfiguration.uri.toString();
  }

  /// 路由变化：按当前 location 命中与否切换可接续态（无需用户设置开关）。
  static void _syncActive() {
    final location = _currentLocation();
    if (location == null || location == _lastLocation) return;
    _lastLocation = location;
    final active = _isContinuable(location);
    if (active == _active) return;
    _active = active;
    ContinuationBridge.setActive(active);
    AppLogger.d(
      _tag,
      'mission continue state -> ${active ? 'ACTIVE' : 'INACTIVE'} ($location)',
    );
  }

  /// 源端快照（由原生 onContinue 拉取）。不在可接续页面时返回 null → REJECT。
  static String? currentState() {
    final location = _currentLocation();
    if (location == null || !_isContinuable(location)) return null;
    return jsonEncode(<String, String>{'location': location});
  }

  /// 对端：路由就绪后取走原生暂存的快照并跳转。
  static Future<void> restorePending() async {
    // 取走即清空，路由未就绪时不能消费，否则数据白白丢失
    final router = _bind();
    if (router == null || _restoring) return;
    _restoring = true;
    try {
      final data = await ContinuationBridge.takePending();
      if (data == null || data.isEmpty) return;
      final decoded = jsonDecode(data);
      final location = decoded is Map ? decoded['location'] : null;
      if (location is! String || location.isEmpty) return;
      AppLogger.i(_tag, 'restore continuation: $location');
      router.go(location);
    } on FormatException catch (e) {
      AppLogger.w(_tag, 'continuation decode failed: $e');
    } finally {
      _restoring = false;
    }
  }
}
