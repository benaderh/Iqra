import 'dart:io';
import 'package:flutter/material.dart';
import '../core/app_state.dart';
import '../core/highlighting_controller.dart';
import 'mushaf_provider.dart';
import 'quran_image_service.dart';

/// High-performance full-screen reader for external Quran page JPG/PNG images
/// loaded directly from `/storage/emulated/0/QuranHW/` (Hafs / Warsh).
class ExternalMushafView extends StatefulWidget {
  final HighlightingController controller;
  final VoidCallback? onPageTap;
  final QuranRiwaya riwaya;

  const ExternalMushafView({
    super.key,
    required this.controller,
    this.onPageTap,
    this.riwaya = QuranRiwaya.hafs,
  });

  @override
  State<ExternalMushafView> createState() => _ExternalMushafViewState();
}

class _ExternalMushafViewState extends State<ExternalMushafView> {
  late PageController _pageController;
  late int _currentPage;
  bool _isProgrammaticScroll = false;

  @override
  void initState() {
    super.initState();
    _currentPage = AppState.instance.currentMushafPage.value.clamp(1, 604);
    _pageController = PageController(initialPage: _currentPage - 1);
    AppState.instance.currentMushafPage.addListener(_onExternalPageChanged);
  }

  @override
  void dispose() {
    AppState.instance.currentMushafPage.removeListener(_onExternalPageChanged);
    _pageController.dispose();
    super.dispose();
  }

  void _onExternalPageChanged() {
    if (!mounted) return;
    final targetPage = AppState.instance.currentMushafPage.value;
    if (targetPage > 0 && targetPage != _currentPage && targetPage <= 604) {
      _goToPage(targetPage);
    }
  }

  void _goToPage(int page) {
    if (_currentPage == page) return;
    _currentPage = page;
    if (_pageController.hasClients) {
      final targetIndex = page - 1;
      final currentIndex = _pageController.page?.round() ?? _pageController.initialPage;
      if (currentIndex != targetIndex) {
        _isProgrammaticScroll = true;
        _pageController.jumpToPage(targetIndex);
        _isProgrammaticScroll = false;
      }
    }
  }

  void _onPageChanged(int index) {
    if (_isProgrammaticScroll) return;
    final pageNum = index + 1;
    if (_currentPage != pageNum) {
      _currentPage = pageNum;
      if (AppState.instance.currentMushafPage.value != pageNum) {
        AppState.instance.currentMushafPage.value = pageNum;
        AppState.instance.saveMushafPage(pageNum);
      }
      // Sync target surah/ayah
      final first = MushafProvider.instance.getFirstAyahOnPage(pageNum);
      if (first != null) {
        widget.controller.setTargetSurah(
          first.$1,
          preserveOtherSurahStates: true,
          clearTargetSurah: false,
        );
        widget.controller.setManualAyah(first.$1, first.$2);
        AppState.instance.saveLastPosition(first.$1, first.$2);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    final isDark = app.isDarkMode;

    return Directionality(
      textDirection: TextDirection.rtl, // RTL Quran reading direction
      child: PageView.builder(
        controller: _pageController,
        physics: const BouncingScrollPhysics(),
        itemCount: 604,
        onPageChanged: _onPageChanged,
        itemBuilder: (context, index) {
          final pageNum = index + 1;
          final imageFile = QuranImageService.getPageImage(pageNum, riwaya: widget.riwaya);

          if (imageFile != null) {
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onPageTap,
              child: Container(
                color: isDark ? Colors.black : const Color(0xFFFFFDF9),
                alignment: Alignment.center,
                child: Image.file(
                  imageFile,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                  gaplessPlayback: true,
                  errorBuilder: (_, __, ___) => _buildFallback(pageNum, isDark),
                ),
              ),
            );
          }

          return _buildFallback(pageNum, isDark);
        },
      ),
    );
  }

  Widget _buildFallback(int pageNum, bool isDark) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onPageTap,
      child: Container(
        color: isDark ? Colors.black : const Color(0xFFFAF8F5),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.auto_stories_rounded,
              size: 48,
              color: isDark ? Colors.white24 : Colors.black26,
            ),
            const SizedBox(height: 12),
            Text(
              'صفحة $pageNum',
              style: TextStyle(
                fontFamily: 'cairo',
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white54 : Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
