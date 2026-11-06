import 'package:file_picker_platform_interface/file_picker_platform_interface.dart';

import 'src/file_picker_ohos_platform.dart';

export 'src/file_picker_ohos_platform.dart';

/// 鸿蒙专用 Dart 插件入口。
///
/// `flutter_tools` 生成的 `dart_plugin_registrant` 会在 isolate 启动时调用
/// [registerWith]，把 OH 社区 fork（10.x 旧 API）注册成 `file_picker` 13.x
/// 的 `FilePickerPlatform` 实现。上游 `lib/` 不需要感知这个桥接。
class FilePickerOhosBridge {
  FilePickerOhosBridge._();

  static void registerWith() {
    FilePickerPlatform.instance = FilePickerOhosPlatform();
  }
}
