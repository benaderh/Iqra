import 'dart:io';
import 'package:flutter/material.dart';
import '../core/app_state.dart';
import '../core/highlighting_controller.dart';
import 'mushaf_provider.dart';
import 'quran_image_service.dart';

/// High-performance full-screen reader for external Quran page JPG/PNG images
/// loaded directly from `/storage/emulated/0/QuranHW/` (Hafs / Warsh).
/// In portrait: horizontal PageView (right to left).
/// In landscape: full-width vertical continuous scroll (top to bottom like ContinuousPageView).
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
  late ScrollController _verticalScrollController;
  late int _currentPage;
  bool _isProgrammaticScroll = false;
  double _lastTotalItemHeight = 0;
  bool _hasInitialScrolledLandscape = false;
  bool? _lastWasLandscape;

  @override
  void initState() {
    super.initState();
    _currentPage = AppState.instance.currentMushafPage.value.clamp(1, 604);
    _pageController = PageController(initialPage: _currentPage - 1);
    _verticalScrollController = ScrollController();
    AppState.instance.currentMushafPage.addListener(_onExternalPageChanged);
  }

  @override
  void dispose() {
    AppState.instance.currentMushafPage.removeListener(_onExternalPageChanged);
    _pageController.dispose();
    _verticalScrollController.dispose();
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
    _isProgrammaticScroll = true;
    if (_pageController.hasClients) {
      final targetIndex = page - 1;
      final currentIndex = _pageController.page?.round() ?? _pageController.initialPage;
      if (currentIndex != targetIndex) {
        _pageController.jumpToPage(targetIndex);
      }
    }
    if (_verticalScrollController.hasClients && _lastTotalItemHeight > 0) {
      final targetOffset = (page - 1) * _lastTotalItemHeight;
      _verticalScrollController.jumpTo(targetOffset);
    }
    _isProgrammaticScroll = false;
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

  void _onVerticalScroll() {
    if (_isProgrammaticScroll || !_verticalScrollController.hasClients || _lastTotalItemHeight <= 0) return;
    final offset = _verticalScrollController.offset;
    if (offset < 0) return;
    final pageNum = (offset / _lastTotalItemHeight).floor() + 1;
    final clamped = pageNum.clamp(1, 604);
    if (clamped != _currentPage) {
      _currentPage = clamped;
      if (AppState.instance.currentMushafPage.value != clamped) {
        AppState.instance.currentMushafPage.value = clamped;
        AppState.instance.saveMushafPage(clamped);
      }
      final first = MushafProvider.instance.getFirstAyahOnPage(clamped);
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
    final bool isLandscape = MediaQuery.orientationOf(context) == Orientation.landscape;

    if (_lastWasLandscape != isLandscape) {
      _lastWasLandscape = isLandscape;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (isLandscape) {
          if (_verticalScrollController.hasClients && _lastTotalItemHeight > 0) {
            _verticalScrollController.jumpTo((_currentPage - 1) * _lastTotalItemHeight);
          }
        } else {
          if (_pageController.hasClients) {
            _pageController.jumpToPage(_currentPage - 1);
          }
        }
      });
    }

    if (isLandscape) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final screenWidth = constraints.maxWidth;
          final pageHeight = screenWidth * 1.4142; // Quran ratio A4 (height / width)
          const separatorHeight = 6.0;
          _lastTotalItemHeight = pageHeight + separatorHeight;

          if (!_hasInitialScrolledLandscape && _currentPage > 1) {
            _hasInitialScrolledLandscape = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _verticalScrollController.hasClients) {
                _verticalScrollController.jumpTo((_currentPage - 1) * _lastTotalItemHeight);
              }
            });
          }

          return NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              _onVerticalScroll();
              return false;
            },
            child: ListView.builder(
              controller: _verticalScrollController,
              physics: const ClampingScrollPhysics(),
              itemCount: 604,
              itemExtent: _lastTotalItemHeight,
              itemBuilder: (context, index) {
                final pageNum = index + 1;
                final imageFile = QuranImageService.getPageImage(pageNum, riwaya: widget.riwaya);

                Widget content;
                if (imageFile != null) {
                  content = Image.file(
                    imageFile,
                    width: screenWidth,
                    height: pageHeight,
                    fit: BoxFit.fill,
                    filterQuality: FilterQuality.medium,
                    gaplessPlayback: true,
                    errorBuilder: (_, __, ___) => _buildFallback(pageNum, isDark),
                  );
                } else {
                  content = SizedBox(
                    width: screenWidth,
                    height: pageHeight,
                    child: _buildFallback(pageNum, isDark),
                  );
                }

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onPageTap,
                  child: Column(
                    children: [
                      content,
                      Container(
                        height: separatorHeight,
                        color: const Color(0xFF1A1A1A),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      );
    }

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
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.auto_stories_rounded,
              size: 56,
              color: isDark ? Colors.white24 : Colors.black26,
            ),
            const SizedBox(height: 14),
            Text(
              'صفحة $pageNum',
              style: TextStyle(
                fontFamily: 'cairo',
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'لم يتم العثور على صورة الصفحة في\n/storage/emulated/0/QuranHW/',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'cairo',
                fontSize: 13,
                color: isDark ? Colors.white38 : Colors.black45,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                final granted = await QuranImageService.ensurePermission();
                if (granted) {
                  QuranImageService.scanFolders();
                  if (mounted) setState(() {});
                }
              },
              icon: const Icon(Icons.folder_open_rounded, size: 18),
              label: const Text(
                'منح إذن قراءة الذاكرة',
                style: TextStyle(fontFamily: 'cairo', fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
