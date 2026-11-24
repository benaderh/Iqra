import 'dart:io';
import 'package:flutter/foundation.dart';

/// Supported Quran recitations for external images.
enum QuranRiwaya { hafs, warsh }

/// Service to locate and serve external Quran page images (Hafs / Warsh)
/// placed manually by the user in `/storage/emulated/0/QuranHW/`.
abstract final class QuranImageService {
  static const String basePath = '/storage/emulated/0/QuranHW';
  static const String altBasePath = '/sdcard/QuranHW';

  /// Returns the image [File] for [page] (1..604) for [riwaya], or null if not present.
  static File? getPageImage(int page, {QuranRiwaya riwaya = QuranRiwaya.hafs}) {
    if (kIsWeb) return null;

    final candidates = _buildCandidates(page, riwaya);
    for (final path in candidates) {
      try {
        final f = File(path);
        if (f.existsSync() && f.lengthSync() > 1024) {
          return f;
        }
      } catch (_) {}
    }
    return null;
  }

  /// Checks whether external images for [riwaya] are detected on this device.
  static bool hasExternalImages({QuranRiwaya riwaya = QuranRiwaya.hafs}) {
    if (kIsWeb) return false;
    return getPageImage(1, riwaya: riwaya) != null ||
        getPageImage(2, riwaya: riwaya) != null ||
        getPageImage(3, riwaya: riwaya) != null;
  }

  static List<String> _buildCandidates(int page, QuranRiwaya riwaya) {
    final List<String> list = [];
    final riwayaFolder = riwaya == QuranRiwaya.hafs ? 'HA' : 'WA';
    final altFolder = riwaya == QuranRiwaya.hafs ? 'HI' : 'WI';
    final padded3 = page.toString().padLeft(3, '0');

    for (final base in [basePath, altBasePath]) {
      // 1. Primary folder (e.g. /QuranHW/HA/p1.jpg)
      list.add('$base/$riwayaFolder/p$page.jpg');
      list.add('$base/$riwayaFolder/p$padded3.jpg');
      list.add('$base/$riwayaFolder/$page.jpg');
      list.add('$base/$riwayaFolder/p$page.png');
      list.add('$base/$riwayaFolder/p$padded3.png');

      // 2. Alternate folder (e.g. /QuranHW/HI/p1.jpg or /WI/p1.png)
      list.add('$base/$altFolder/p$page.jpg');
      list.add('$base/$altFolder/p$padded3.jpg');
      list.add('$base/$altFolder/p$page.png');
      list.add('$base/$altFolder/p$padded3.png');
      list.add('$base/$altFolder/$page.jpg');

      // 3. Root folder (e.g. /QuranHW/p1.jpg)
      list.add('$base/p$page.jpg');
      list.add('$base/$page.jpg');
    }
    return list;
  }
}
