import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// Supported Quran recitations for external images.
enum QuranRiwaya { hafs, warsh }

/// Service to locate and serve external Quran page images (Hafs / Warsh)
/// placed manually by the user in `/storage/emulated/0/QuranHB/` or `/storage/emulated/0/QuranHW/`.
abstract final class QuranImageService {
  static const List<String> basePaths = [
    '/storage/emulated/0/QuranHW',
    '/storage/emulated/0/QuranHB',
    '/sdcard/QuranHW',
    '/sdcard/QuranHB',
  ];

  static final Map<int, File> _hafsCache = {};
  static final Map<int, File> _warshCache = {};
  static bool _hasScanned = false;

  /// Ensures Android storage permissions are requested and granted at runtime.
  static Future<bool> ensurePermission() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    try {
      if (await Permission.manageExternalStorage.isGranted) return true;
      if (await Permission.storage.isGranted) return true;

      final resManage = await Permission.manageExternalStorage.request();
      if (resManage.isGranted) {
        _hasScanned = false; // Re-scan with new permissions
        return true;
      }

      final resStorage = await Permission.storage.request();
      if (resStorage.isGranted) {
        _hasScanned = false;
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// Scans all candidate folders and populates image caches.
  static void scanFolders() {
    if (kIsWeb) return;
    _hafsCache.clear();
    _warshCache.clear();

    for (final base in basePaths) {
      final baseDir = Directory(base);
      if (!baseDir.existsSync()) continue;

      // Scan Hafs subdirectories: HI, HA, H, hafs, or base itself
      for (final sub in ['HI', 'HA', 'H', 'hafs', '']) {
        final dir = sub.isEmpty ? baseDir : Directory('$base/$sub');
        if (dir.existsSync()) {
          _scanDirectoryInto(dir, _hafsCache);
        }
      }

      // Scan Warsh subdirectories: WI, WA, W, warsh
      for (final sub in ['WI', 'WA', 'W', 'warsh']) {
        final dir = Directory('$base/$sub');
        if (dir.existsSync()) {
          _scanDirectoryInto(dir, _warshCache);
        }
      }
    }
    _hasScanned = true;
  }

  static void _scanDirectoryInto(Directory dir, Map<int, File> targetMap) {
    try {
      final files = dir.listSync();
      final pageRegex = RegExp(r'(?:p|page|)?0*(\d{1,3})\.(?:jpg|jpeg|png|webp)', caseSensitive: false);
      for (final entity in files) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.isNotEmpty
            ? entity.uri.pathSegments.last
            : entity.path.split(Platform.pathSeparator).last;
        final match = pageRegex.firstMatch(name);
        if (match != null) {
          final pageNum = int.tryParse(match.group(1)!);
          if (pageNum != null && pageNum >= 1 && pageNum <= 608) {
            // Do not overwrite if already mapped
            targetMap.putIfAbsent(pageNum, () => entity);
          }
        }
      }
    } catch (_) {}
  }

  /// Returns the image [File] for [page] (1..604) for [riwaya], or null if not present.
  static File? getPageImage(int page, {QuranRiwaya riwaya = QuranRiwaya.hafs}) {
    if (kIsWeb) return null;

    if (!_hasScanned) {
      scanFolders();
    }

    final cache = riwaya == QuranRiwaya.hafs ? _hafsCache : _warshCache;
    final cached = cache[page];
    if (cached != null && cached.existsSync()) {
      return cached;
    }

    // Direct fallback check if not yet discovered
    final candidates = _buildDirectCandidates(page, riwaya);
    for (final path in candidates) {
      try {
        final f = File(path);
        if (f.existsSync() && f.lengthSync() > 1024) {
          cache[page] = f;
          return f;
        }
      } catch (_) {}
    }
    return null;
  }

  /// Checks whether external images for [riwaya] are detected on this device.
  static bool hasExternalImages({QuranRiwaya riwaya = QuranRiwaya.hafs}) {
    if (kIsWeb) return false;
    if (!_hasScanned) {
      scanFolders();
    }
    final cache = riwaya == QuranRiwaya.hafs ? _hafsCache : _warshCache;
    if (cache.isNotEmpty) return true;

    return getPageImage(1, riwaya: riwaya) != null ||
        getPageImage(2, riwaya: riwaya) != null ||
        getPageImage(3, riwaya: riwaya) != null;
  }

  static List<String> _buildDirectCandidates(int page, QuranRiwaya riwaya) {
    final List<String> list = [];
    final folders = riwaya == QuranRiwaya.hafs
        ? const ['HI', 'HA', 'H', 'hafs', '']
        : const ['WI', 'WA', 'W', 'warsh', ''];
    final padded3 = page.toString().padLeft(3, '0');

    for (final base in basePaths) {
      for (final f in folders) {
        final dir = f.isEmpty ? base : '$base/$f';
        list.add('$dir/p$page.jpg');
        list.add('$dir/p$page.png');
        list.add('$dir/p$padded3.jpg');
        list.add('$dir/p$padded3.png');
        list.add('$dir/$page.jpg');
        list.add('$dir/$page.png');
        list.add('$dir/p$page.jpeg');
      }
    }
    return list;
  }
}
