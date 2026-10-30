
import window from '@ohos.window';
import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import { AbilityConstant, Want } from '@kit.AbilityKit';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import { McpStatusNotice } from '../plugins/McpStatusNotice';
import { ContinuationBridge } from '../plugins/ContinuationBridge';

export default class EntryAbility extends FlutterAbility {
  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    McpStatusNotice.register(flutterEngine, this.context)
    ContinuationBridge.register(flutterEngine, this.context)
  }

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam) {
    // 冷启动点 MCP 通知时先暂存，Dart 首帧后用 getPendingTap 补取
    McpStatusNotice.handleWant(want)
    super.onCreate(want, launchParam)
    // 应用接续：默认不可接续，Dart 侧进入可接续页面后再置 ACTIVE，
    // 避免无内容时对端出现接续入口、点击却失败（见 docs/ohos/05 §4.4）
    ContinuationBridge.setMissionContinueState(false)
    if (ContinuationBridge.handleWant(want, launchParam, false)) {
      // 接续冷启动时系统在 onCreate 后触发 onWindowStageRestore 而非
      // onWindowStageCreate，必须调用 restoreWindowStage 才会加载窗口内容
      this.context.restoreWindowStage(new LocalStorage())
    }
  }

  onNewWant(want: Want, launchParams: AbilityConstant.LaunchParam): void {
    McpStatusNotice.handleWant(want)
    super.onNewWant(want, launchParams)
    // 热启动：窗口与引擎均已就绪，不走 restoreWindowStage，
    // 由 handleWant(notify=true) 推送通知 Dart 直接跳转
    ContinuationBridge.handleWant(want, launchParams, true)
  }

  /**
   * 接续冷启动的窗口恢复回调。FlutterAbility 未实现此回调（不使用 ArkUI
   * 页面栈），按正常创建流程初始化 Flutter 视图并加载页面，否则对端白屏。
   */
  onWindowStageRestore(windowStage: window.WindowStage): void {
    this.onWindowStageCreate(windowStage)
  }

  /**
   * 源端：系统发起接续时收集当前页面快照写入 wantParam。
   * 不在可接续页面（Dart 返回 null）或超时则拒绝本次接续。
   */
  async onContinue(wantParam: Record<string, Object>): Promise<AbilityConstant.OnContinueResult> {
    const state = await ContinuationBridge.getState()
    if (state === null) {
      return AbilityConstant.OnContinueResult.REJECT
    }
    wantParam['mtbbs_continuation'] = state
    return AbilityConstant.OnContinueResult.AGREE
  }

  onDestroy() {
    McpStatusNotice.hide()
    super.onDestroy()
  }
}
