import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'bridge.dart';
import 'log.dart';

/// 鸿蒙应用接续（流转）的 Dart 侧：可接续态、快照生成、对端恢复。
///
/// 与 PiliPlus 在页面里 `hold/release` 的侵入写法不同，这里**零侵入**上游页面：
/// 只监听 `GoRouter` 的 `routerDelegate`，按当前 location 是否命中可接续路由
/// 切换系统侧的 `ACTIVE / INACTIVE`；快照也是"用时按当前 location 生成"，天然
/// 是最新值（见 docs/ohos/05 §4.4）。
abstract class Continuation {
  /// P0 可接续路由：首页、帖子详情、版块。
  ///
  /// 快照只存路由 location，对端 `router.go(location)` 即可原样落回同一页面，
  /// 新增可接续页面时只需在这里放开判断，无需改数据结构。
  static bool _isContinuable(String location) {
    // 首页：允许从首页发起流转（对端落回首页）
    if (location == '/') return true;
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
  static bool _started = false;
  static bool _syncScheduled = false;

  /// 由 [ContinuationBridge.install] 调用（此时 binding 已就绪）。
  static void start() {
    if (_started) return;
    _started = true;
    _attach();
  }

  /// 等 GoRouter 挂载后再绑定。
  ///
  /// **不能只按帧重试 3 次**：上游 `main()` 在 `runApp()` 之前有大量 `await`
  /// （设置/站点/登录态/网络初始化），此时帧已经被引擎预跑了好几帧，按帧计数会
  /// 在 `runApp()` 之前就用光重试，导致 [_active] 永远不置 ACTIVE、对端不显示
  /// 接续入口。改为按时间轮询（250 ms，上限 60 s），`runApp()` 挂载路由后立即绑定。
  static void _attach() {
    if (_bind() != null) {
      _onBound();
      return;
    }
    var ticks = 0;
    Timer.periodic(const Duration(milliseconds: 250), (timer) {
      ticks++;
      if (_bind() != null) {
        timer.cancel();
        _onBound();
        return;
      }
      if (ticks >= 240) {
        timer.cancel();
        logBridge('等待 GoRouter 超时（60s），应用接续不可用');
      }
    });
  }

  /// 路由可用后：同步可接续态，并补取冷启动暂存的快照。
  static void _onBound() {
    _syncActive();
    // 冷启动接续：原生只暂存不推送（此时推送会在首帧前回放而丢失），
    // 由这里在路由就绪后主动补取（见 docs/ohos/05 §4.3）。
    unawaited(restorePending(coldStart: true));
  }

  /// 绑定 GoRouter；未就绪返回 null。成功后常驻监听路由变化。
  ///
  /// app 的 `rootNavigatorKey` 属于上游代码，本包不能依赖；从根元素向下找
  /// 最近的 `InheritedGoRouter`（`GoRouter.maybeOf` 是非依赖查询，可在帧外调用）。
  static GoRouter? _bind() {
    final bound = _router;
    if (bound != null) return bound;
    final router = _findRouter(WidgetsBinding.instance.rootElement);
    if (router == null) return null;
    _router = router;
    router.routerDelegate.addListener(_syncActive);
    return router;
  }

  static GoRouter? _findRouter(Element? element) {
    if (element == null) return null;
    final router = GoRouter.maybeOf(element);
    if (router != null) return router;
    GoRouter? found;
    element.visitChildElements((child) {
      found ??= _findRouter(child);
    });
    return found;
  }

  static String? _currentLocation() {
    return _bind()?.routerDelegate.currentConfiguration.uri.toString();
  }

  /// 路由变化：按当前 location 命中与否切换可接续态（无需用户设置开关）。
  ///
  /// `routerDelegate` 的通知可能早于 `currentConfiguration` 更新（此时读到的是
  /// 旧 location，会被 [_lastLocation] 判成"没变化"而丢掉这次切换），因此统一
  /// 推迟到帧后再读，保证拿到的是本次导航落地后的 location。
  static void _syncActive() {
    if (_syncScheduled) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      _applyActive();
    });
  }

  static void _applyActive() {
    final location = _currentLocation();
    if (location == null || location == _lastLocation) return;
    _lastLocation = location;
    final active = _isContinuable(location);
    if (active == _active) return;
    _active = active;
    ContinuationBridge.setActive(active);
    logBridge(
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
  ///
  /// [coldStart] 为 true（冷启动补取）时先让启动期请求落地再跳转；
  /// 热启动由原生推送触发，窗口与初始化都已完成，直接跳。
  static Future<void> restorePending({bool coldStart = false}) async {
    // 取走即清空，路由未就绪时不能消费，否则数据白白丢失
    final router = _bind();
    if (router == null || _restoring) return;
    _restoring = true;
    String? location;
    try {
      final data = await ContinuationBridge.takePending();
      if (data == null || data.isEmpty) return;
      final decoded = jsonDecode(data);
      location = (decoded is Map ? decoded['location'] : null) as String?;
      if (location == null || location.isEmpty) {
        logBridge('continuation decode failed: $data');
        _showRestoreDialog(router, null);
        return;
      }
      logBridge('restore continuation: $location');
      if (coldStart) await _settleStartup();
      router.go(location);
    } catch (e) {
      // 不再静默失败：弹窗让用户手动前往，避免"点了流转却停在原地"
      logBridge('continuation restore failed: $e');
      _showRestoreDialog(router, location);
    } finally {
      _restoring = false;
    }
  }

  /// 冷启动时让出一点时间：目标页的请求若与启动期（站点/会话/Cookie 罐/
  /// 导航守卫）的请求同时发出，偶发首屏 "Failed to load cookies" 类失败。
  /// 等首帧 + 300 ms 后再跳，正常用户感知不到，但能显著降低抢跑概率。
  static Future<void> _settleStartup() async {
    try {
      await WidgetsBinding.instance.endOfFrame;
    } catch (_) {
      // 没有可等待的帧（例如后台挂起），直接进入延时
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  /// 恢复失败的可见反馈：弹窗提示可手动前往，而不是只在日志里静默失败。
  static void _showRestoreDialog(GoRouter router, String? location) {
    final context = router.routerDelegate.navigatorKey.currentContext;
    if (context == null) {
      logBridge('无法弹窗（Navigator 未就绪），接续目标：$location');
      return;
    }
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('应用接续'),
        content: Text(
          location == null
              ? '收到了另一台设备的接续内容，但无法解析。'
              : '收到了另一台设备的接续内容，但自动跳转失败：\n$location',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('关闭'),
          ),
          if (location != null)
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                router.go(location);
              },
              child: const Text('前往'),
            ),
        ],
      ),
    );
  }
}
