import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'app_state.dart';

/// Manages downloading and verifying the Sherpa-ONNX speech recognition model
/// at runtime on native platforms (Android, iOS, Windows, macOS).
class AsrModelManager {
  AsrModelManager._();
  static final AsrModelManager instance = AsrModelManager._();

  static const String modelUrl =
      'https://huggingface.co/Tidzo/darten-zipformer-quran/resolve/main/zipformer_p_arabic_v3.int8.onnx';

  static const String modelFileName =
      'v2_zipformer_zipformer_p_arabic_v3.int8.onnx';

  static const int minValidBytes = 50 * 1024 * 1024; // 50 MB
  static const int expectedTotalBytes = 72705392; // ~72.7 MB

  static const List<String> externalModelPaths = [
    '/storage/emulated/0/QuranHW/zipformer_p_arabic_v3.int8.onnx',
    '/storage/emulated/0/QuranHW/v2_zipformer_zipformer_p_arabic_v3.int8.onnx',
    '/storage/emulated/0/QuranHB/zipformer_p_arabic_v3.int8.onnx',
    '/storage/emulated/0/QuranHB/v2_zipformer_zipformer_p_arabic_v3.int8.onnx',
    '/sdcard/QuranHW/zipformer_p_arabic_v3.int8.onnx',
    '/sdcard/QuranHW/v2_zipformer_zipformer_p_arabic_v3.int8.onnx',
    '/sdcard/QuranHB/zipformer_p_arabic_v3.int8.onnx',
    '/sdcard/QuranHB/v2_zipformer_zipformer_p_arabic_v3.int8.onnx',
  ];

  /// Checks whether the model is in external storage or internal app storage.
  Future<bool> isModelReady() async {
    if (kIsWeb) return false;
    try {
      // 1. Check external folder (/storage/emulated/0/QuranHW/)
      for (final extPath in externalModelPaths) {
        final extFile = File(extPath);
        if (await extFile.exists()) {
          final len = await extFile.length();
          if (len >= minValidBytes) {
            await _ensureCopiedFromExternal(extFile);
            return true;
          }
        }
      }

      // 2. Check internal application support directory
      final docDir = await getApplicationSupportDirectory();
      final file = File('${docDir.path}/$modelFileName');
      if (await file.exists()) {
        final len = await file.length();
        if (len >= minValidBytes) {
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  Future<void> _ensureCopiedFromExternal(File extFile) async {
    try {
      final docDir = await getApplicationSupportDirectory();
      final targetFile = File('${docDir.path}/$modelFileName');
      if (!await targetFile.exists() || (await targetFile.length()) < minValidBytes) {
        await extFile.copy(targetFile.path);
      }
      final alt1 = File('${docDir.path}/zipformer_p_arabic_v3.int8.onnx');
      if (!await alt1.exists()) {
        await extFile.copy(alt1.path);
      }
      final docsDir = await getApplicationDocumentsDirectory();
      final alt2 = File('${docsDir.path}/$modelFileName');
      if (!await alt2.exists()) {
        await extFile.copy(alt2.path);
      }
      final alt3 = File('${docsDir.path}/zipformer_p_arabic_v3.int8.onnx');
      if (!await alt3.exists()) {
        await extFile.copy(alt3.path);
      }
    } catch (_) {}
  }

  /// Downloads the ONNX model from Hugging Face with progress streaming and
  /// atomic write (.tmp -> rename) to prevent corruption.
  Future<bool> downloadModel() async {
    if (kIsWeb) return false;
    http.Client? client;
    IOSink? sink;
    File? tmpFile;

    try {
      final docDir = await getApplicationSupportDirectory();
      final targetFile = File('${docDir.path}/$modelFileName');
      tmpFile = File('${docDir.path}/$modelFileName.tmp');

      if (await tmpFile.exists()) {
        try {
          await tmpFile.delete();
        } catch (_) {}
      }

      client = http.Client();
      final uri = Uri.parse(modelUrl);
      final request = http.Request('GET', uri);
      final response = await client.send(request);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return false;
      }

      final totalBytes = response.contentLength ?? expectedTotalBytes;
      int receivedBytes = 0;

      sink = tmpFile.openWrite();
      await for (final chunk in response.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        AppState.instance.updateModelDownloadProgress(
          loaded: receivedBytes,
          total: totalBytes,
          fraction: totalBytes > 0 ? (receivedBytes / totalBytes) : 0.0,
        );
      }
      await sink.flush();
      await sink.close();
      sink = null;

      final len = await tmpFile.length();
      if (len < minValidBytes) {
        try {
          await tmpFile.delete();
        } catch (_) {}
        return false;
      }

      if (await targetFile.exists()) {
        try {
          await targetFile.delete();
        } catch (_) {}
      }
      await tmpFile.rename(targetFile.path);

      // Copy fallback names and locations for complete engine compatibility
      try {
        final alt1 = File('${docDir.path}/zipformer_p_arabic_v3.int8.onnx');
        if (!await alt1.exists()) {
          await targetFile.copy(alt1.path);
        }
        final docsDir = await getApplicationDocumentsDirectory();
        final alt2 = File('${docsDir.path}/$modelFileName');
        if (!await alt2.exists()) {
          await targetFile.copy(alt2.path);
        }
        final alt3 = File('${docsDir.path}/zipformer_p_arabic_v3.int8.onnx');
        if (!await alt3.exists()) {
          await targetFile.copy(alt3.path);
        }
      } catch (_) {}

      AppState.instance.completeModelDownload();
      return true;
    } catch (_) {
      AppState.instance.resetModelDownload();
      return false;
    } finally {
      try {
        await sink?.close();
      } catch (_) {}
      client?.close();
    }
  }
}
