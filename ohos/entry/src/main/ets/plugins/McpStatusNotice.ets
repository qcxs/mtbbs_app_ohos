import { FlutterEngine, Log, MethodCall, MethodChannel, MethodResult } from '@ohos/flutter_ohos';
import { notificationManager } from '@kit.NotificationKit';
import { common, Want, wantAgent } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';

const TAG = 'MTBBS_MCP';

/** 通道名 / 通知 id / 点击标记必须与 Dart 侧及 Android 实现保持一致 */
const CHANNEL = 'mtbbs/mcp_status';
const NOTIFICATION_ID = 8765;
const TAP_PARAM = 'mcp_tap';

/**
 * Want 目标：本应用主 Ability。
 *
 * bundleName 不在编译期写死 —— 正式 / beta / debug 三个变体的包名不同
 * （见 ohos/build-profile.json5 的 products），运行时从 ApplicationInfo 取，
 * 保证任一变体装的包都能被通知正确拉起。
 */
const ABILITY_NAME = 'EntryAbility';

/**
 * MCP 运行状态常驻通知（鸿蒙实现）。
 *
 * Dart 侧 `lib/mcp/mcp_status_notice.dart` 只维护通道契约，两端实现必须一致：
 * `show(endpoint)` / `hide` / `getPendingTap` / `onNotificationTap`。
 *
 * 点击通知 → Want 携带 `mcp_tap` 回到 EntryAbility → 本类把它转成
 * `onNotificationTap` 回调（Dart 侧据此弹「MCP 快捷开关」）。
 * 冷启动时 Dart 还没注册回调，先把这次点击暂存为 `pendingTap`，
 * Dart 首帧后调用 `getPendingTap` 取走——与链接入站的「暂存 + 补取」同一套模式。
 */
export class McpStatusNotice {
  private static channel: MethodChannel | null = null;
  private static context: common.UIAbilityContext | null = null;

  /** Dart 侧完成注册（首次调用 getPendingTap）后置 true */
  private static dartReady: boolean = false;

  /** 冷启动点击暂存 */
  private static pendingTap: boolean = false;

  /** 在 configureFlutterEngine 里注册通道（Dart 侧 init 之前完成） */
  static register(engine: FlutterEngine, context: common.UIAbilityContext): void {
    McpStatusNotice.context = context;
    const channel = new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), CHANNEL);
    McpStatusNotice.channel = channel;
    channel.setMethodCallHandler({
      onMethodCall(call: MethodCall, result: MethodResult): void {
        McpStatusNotice.onMethodCall(call, result);
      },
    });
  }

  private static onMethodCall(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case 'show': {
        const endpoint: string = call.argument('endpoint') as string;
        McpStatusNotice.show(endpoint ?? '');
        result.success(null);
        break;
      }
      case 'hide':
        McpStatusNotice.hide();
        result.success(null);
        break;
      case 'getPendingTap': {
        McpStatusNotice.dartReady = true;
        const pending = McpStatusNotice.pendingTap;
        McpStatusNotice.pendingTap = false;
        result.success(pending);
        break;
      }
      default:
        result.notImplemented();
        break;
    }
  }

  /**
   * 处理带 `mcp_tap` 的 Want。必须在 `super.onCreate` / `super.onNewWant` 之前调用：
   * 冷启动时引擎尚未 attach，只能先暂存。
   */
  static handleWant(want: Want): void {
    if (!McpStatusNotice.isTapWant(want)) return;
    const channel = McpStatusNotice.channel;
    if (!McpStatusNotice.dartReady || channel === null) {
      McpStatusNotice.pendingTap = true;
      return;
    }
    channel.invokeMethod('onNotificationTap', null);
  }

  /** 发布/更新常驻通知；通知权限未授予时先申请，被拒则静默跳过 */
  static show(endpoint: string): void {
    McpStatusNotice.publish(endpoint).catch((e: BusinessError) => {
      Log.w(TAG, '显示 MCP 状态通知失败: ' + JSON.stringify(e));
    });
  }

  /** 取消常驻通知 */
  static hide(): void {
    notificationManager.cancel(NOTIFICATION_ID).catch((e: BusinessError) => {
      Log.w(TAG, '取消 MCP 状态通知失败: ' + JSON.stringify(e));
    });
  }

  private static async publish(endpoint: string): Promise<void> {
    const context = McpStatusNotice.context;
    if (context === null) return;
    if (!await notificationManager.isNotificationEnabled()) {
      // 用户拒绝后此调用会抛错（系统不再重复弹窗），由外层 catch 静默处理
      await notificationManager.requestEnableNotification(context);
    }
    const agent = await wantAgent.getWantAgent(
      McpStatusNotice.wantAgentInfo(context.applicationInfo.name),
    );
    const request: notificationManager.NotificationRequest = {
      id: NOTIFICATION_ID,
      notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION,
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: {
          title: 'MCP 服务已开启',
          text: endpoint,
        },
      },
      wantAgent: agent,
      isOngoing: true,
      // 默认 true：点了带 wantAgent 的通知就自动清除。常驻状态通知必须保留，
      // 否则点一次通知就再也没有「MCP 服务已开启」了。
      tapDismissed: false,
    };
    await notificationManager.publish(request);
  }

  private static wantAgentInfo(bundleName: string): wantAgent.WantAgentInfo {
    return {
      wants: [{
        bundleName: bundleName,
        abilityName: ABILITY_NAME,
        parameters: { 'mcp_tap': true },
      }],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: NOTIFICATION_ID,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG],
    };
  }

  private static isTapWant(want: Want): boolean {
    const params = want.parameters;
    if (params === undefined) return false;
    const flag: Object | undefined = params[TAP_PARAM];
    return flag !== undefined && flag.toString() === 'true';
  }
}
