import 'dart:async';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker_ohos/file_picker_ohos.dart' as legacy;
import 'package:file_picker_platform_interface/file_picker_platform_interface.dart';

/// 把 OH 社区 fork（`file_picker_ohos` 10.x，旧 `FilePicker.platform` API）
/// 适配成上游 file_picker 13.x 的 [FilePickerPlatform]。
///
/// 只有鸿蒙构建会通过 `FilePickerOhosBridge.registerWith()` 安装它；其他平台
/// 仍由 file_picker 自带实现接管。
final class FilePickerOhosPlatform extends FilePickerPlatform {
  FilePickerOhosPlatform();

  final legacy.FilePicker _legacy = legacy.FilePickerIO();

  static legacy.FileType _toLegacyType(FileType type) =>
      legacy.FileType.values.byName(type.name);

  static Function(legacy.FilePickerStatus)? _toLegacyStatus(
    Function(FilePickerStatus)? callback,
  ) {
    if (callback == null) return null;
    return (status) =>
        callback(FilePickerStatus.values.byName(status.name));
  }

  PlatformFile? _convert(legacy.PlatformFile file) {
    final path = file.path;
    if (path == null) return null;
    return _OhosPlatformFile(
      name: file.name,
      path: path,
      size: file.size,
    );
  }

  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    final result = await _legacy.pickFiles(
      dialogTitle: dialogTitle,
      initialDirectory: initialDirectory,
      type: _toLegacyType(type),
      allowedExtensions: allowedExtensions,
      onFileLoading: _toLegacyStatus(onFileLoading),
      allowMultiple: false,
      // 不请求旧版一次性读字节：新接口的 readAsBytes()/length() 按需读取
      withData: false,
      withReadStream: false,
      compressionQuality: compressionQuality,
    );
    if (result == null || result.files.isEmpty) return null;
    return _convert(result.files.first);

  }

  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    final result = await _legacy.pickFiles(
      dialogTitle: dialogTitle,
      initialDirectory: initialDirectory,
      type: _toLegacyType(type),
      allowedExtensions: allowedExtensions,
      onFileLoading: _toLegacyStatus(onFileLoading),
      allowMultiple: true,
      withData: false,
      withReadStream: false,
      compressionQuality: compressionQuality,
    );
    if (result == null) return const [];
    return [
      for (final file in result.files) ?_convert(file),
    ];
  }

  @override
  Future<List<String>> pickFileAndDirectoryPaths({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
  }) async {
    final paths = await _legacy.pickFileAndDirectoryPaths(
      type: _toLegacyType(type),
      allowedExtensions: allowedExtensions,
      initialDirectory: initialDirectory,
    );
    return paths ?? const [];
  }

  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    String? initialDirectory,
    AndroidOptions androidOptions = const AndroidOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) {
    return _legacy.getDirectoryPath(
      dialogTitle: dialogTitle,
      initialDirectory: initialDirectory,
    );
  }

  @override
  Future<void> clearTemporaryFiles() async {
    await _legacy.clearTemporaryFiles();
  }

  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    // OH fork 的 initialDirectory 是“源文件路径”（原生据此读取大文件/推导
    // 默认文件名），不是对话框初始目录；上游 13.x 的 OH 分支已按此语义写入
    // 临时文件（见 lib/platform/optional/file_save.dart）。
    final savedPath = await _legacy.saveFile(
      dialogTitle: dialogTitle,
      fileName: fileName,
      initialDirectory: initialDirectory,
      bytes: bytes,
    );
    if (savedPath == null) return null;
    return Uri.tryParse(savedPath) ?? Uri.file(savedPath);
  }

  @override
  Future<void> skipEntitlementsChecks() async {
    // OH 没有沙箱授权检查
  }
}

/// 新接口的 [PlatformFile] 实现：基于旧 fork 的沙箱文件路径。
final class _OhosPlatformFile extends PlatformFile {
  _OhosPlatformFile({
    required this.name,
    required String path,
    required int size,
    Uint8List? bytes,
  })  : uri = Uri.file(path),
        _size = size,
        _bytes = bytes;

  @override
  final String name;

  @override
  final Uri uri;

  final int _size;
  final Uint8List? _bytes;

  @override
  XFile get xFile => XFile(uri.toFilePath(), name: name);

  @override
  int? lengthSync() => _size;

  @override
  Future<int?> length() async => _size;

  @override
  Future<Uint8List> readAsBytes() async =>
      _bytes ?? await xFile.readAsBytes();

  @override
  Stream<Uint8List> readAsByteStream() => xFile.openRead();
}
