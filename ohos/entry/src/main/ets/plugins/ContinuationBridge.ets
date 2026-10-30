import { AbilityConstant, common, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Any, FlutterEngine, Log, MethodCall, MethodChannel, MethodResult } from '@ohos/flutter_ohos';

const TAG = 'MTBBS_CONTINUATION';

/** 通道名与方法名必须与 Dart 侧 lib/ohos/continuation_bridge.dart 一致 */
const CHANNEL = 'mtbbs/continuation';

/** 接续数据在 want.parameters 中的键，须避开系统预置 key（version/targetDevice 等） */
const CONTINUATION_KEY = 'mtbbs_continuation';

/** 源端向 Dart 拉快照的超时：onContinue 受系统时限约束，超时即 REJECT，不能卡死 */
const STATE_TIMEOUT_MS = 1500;

/**
 * 应用接续（流转）的 ArkTS 侧通道，设计见 docs/ohos/05-应用流转可行性调研.md。
 *
 * 与 McpStatusNotice 同一套「暂存 + 补取」模式：
 * - 源端 `onContinue` → `getState()` 向 Dart 拉当前路由快照；
 * - 对端冷启动 `onCreate` → `handleWant(..., notify=false)` 只暂存，Dart 首帧后
 *   调 `getPendingContinuation` 取走（冷启动时推送会被引擎 channel buffer 回放，
 *   在根路由挂载前被取走而丢失，见文档 §4.3）；
 * - 对端热启动 `onNewWant` → `handleWant(..., notify=true)` 推送
 *   `onContinuationRestore` 让 Dart 立即取走。
 */
export class ContinuationBridge {
  private static channel: MethodChannel | null = null;
  private static context: common.UIAbilityContext | null = null;

  /** 对端收到的接续快照，Dart 取走即清空（只放内存，不持久化） */
  private static pending: string | null = null;

  /** 在 configureFlutterEngine 里注册通道（与 McpStatusNotice 同一时机） */
  static register(engine: FlutterEngine, context: common.UIAbilityContext): void {
    ContinuationBridge.context = context;
    const channel = new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), CHANNEL);
    ContinuationBridge.channel = channel;
    channel.setMethodCallHandler({
      onMethodCall(call: MethodCall, result: MethodResult): void {
        ContinuationBridge.onMethodCall(call, result);
      },
    });
  }

  private static onMethodCall(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case 'getPendingContinuation': {
        // 取走即清空：Dart 侧已判路由就绪，不会重复跳转
        const data = ContinuationBridge.pending;
        ContinuationBridge.pending = null;
        result.success(data);
        break;
      }
      case 'setContinuationActive': {
        const active: boolean = call.argument('active') ?? false;
        ContinuationBridge.setMissionContinueState(active);
        result.success(null);
        break;
      }
      default:
        result.notImplemented();
        break;
    }
  }

  /**
   * 源端 onContinue 时向 Dart 拉当前路由快照（JSON 字符串）；
   * 不在可接续页面（Dart 返回 null）、超时、通道异常都 resolve null。
   */
  static getState(): Promise<string | null> {
    const channel = ContinuationBridge.channel;
    if (channel === null) {
      return Promise.resolve(null);
    }
    return new Promise<string | null>((resolve) => {
      const timer = setTimeout(() => resolve(null), STATE_TIMEOUT_MS);
      const callback: MethodResult = {
        success: (result: Any) => {
          clearTimeout(timer);
          resolve(typeof result === 'string' ? result as string : null);
        },
        error: (_code: string, _msg: string, _details: Any) => {
          clearTimeout(timer);
          resolve(null);
        },
        notImplemented: () => {
          clearTimeout(timer);
          resolve(null);
        },
      };
      channel.invokeMethod('getContinuationState', null, callback);
    });
  }

  /**
   * 对端：从接续 Want 取源端快照并暂存。返回是否为接续启动。
   *
   * notify 仅热启动为 true；冷启动必须 false（原因见类注释）。
   */
  static handleWant(want: Want, launchParam: AbilityConstant.LaunchParam, notify: boolean): boolean {
    if (launchParam.launchReason !== AbilityConstant.LaunchReason.CONTINUATION) {
      return false;
    }
    const data: Object | undefined = want.parameters?.[CONTINUATION_KEY];
    if (typeof data === 'string' && data.length > 0) {
      ContinuationBridge.setPending(data as string, notify);
    }
    return true;
  }

  private static setPending(data: string, notify: boolean): void {
    ContinuationBridge.pending = data;
    if (notify) {
      ContinuationBridge.channel?.invokeMethod('onContinuationRestore', null);
    }
  }

  /**
   * 切换本机在对端设备是否显示「可接续」入口。默认 INACTIVE（onCreate 里下发），
   * Dart 侧按当前路由命中可接续页面时置 ACTIVE，避免用户点了却失败。
   */
  static setMissionContinueState(active: boolean): void {
    const context = ContinuationBridge.context;
    if (context === null) return;
    const state = active
      ? AbilityConstant.ContinueState.ACTIVE
      : AbilityConstant.ContinueState.INACTIVE;
    context.setMissionContinueState(state).catch((err: BusinessError) => {
      Log.w(TAG, `setMissionContinueState failed: ${err.code} ${err.message}`);
    });
  }
}
