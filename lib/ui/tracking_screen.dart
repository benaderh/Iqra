import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../core/highlighting_controller.dart';
import '../audio/quran_timing_service.dart';
import '../audio/quran_audio_service.dart';
import '../core/platform_utils.dart';
import 'widgets/dialogs/dialog_service.dart';
import '../core/app_state.dart';
import 'widgets/mic_bar.dart';
import '../mushaf/mushaf_view.dart';
import '../mushaf/external_mushaf_view.dart';
import '../mushaf/quran_image_service.dart';
import '../verse_list/verse_list_view.dart';

/// Main interactive screen for real-time recitation tracking and reading.
/// Supports high-performance vector Mushaf and dedicated Verse List modes.
class TrackingScreen extends StatefulWidget {
  final HighlightingController controller;
  final bool isRecording;
  final bool isVoiceSearching;
  final String voiceSearchText;
  final ValueListenable<String>? voiceSearchTextNotifier;
  final VoidCallback onToggleRecord;
  final VoidCallback onVoiceSearchToggle;
  final bool isLoadingEngine;
  final ValueNotifier<bool>? isVoiceSearchLoading;
  final VoiceSearchController? voiceSearchController;
  final void Function(int surah, int ayah)? onSelectVoiceCandidate;
  final ValueChanged<bool>? onVoiceSearchHoldChanged;
  final VoidCallback onClearBuffer;

  const TrackingScreen({
    super.key,
    required this.controller,
    required this.isRecording,
    required this.isVoiceSearching,
    this.voiceSearchText = '',
    this.voiceSearchTextNotifier,
    this.voiceSearchController,
    this.onSelectVoiceCandidate,
    this.onVoiceSearchHoldChanged,
    required this.onToggleRecord,
    required this.onVoiceSearchToggle,
    this.isLoadingEngine = false,
    this.isVoiceSearchLoading,
    required this.onClearBuffer,
  });

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const MethodChannel _lifecycleChannel =
      MethodChannel('com.recitequran.app/audio_lifecycle');

  final ValueNotifier<String> _voiceSearchNotifier = ValueNotifier('');
  final GlobalKey<VerseListViewState> _verseListKey =
      GlobalKey<VerseListViewState>();
  final ValueNotifier<bool> _isAutoScrolling = ValueNotifier<bool>(false);
  late final ValueNotifier<int> _surahNotifier;
  bool _showBars = true;
  QuranRiwaya _riwaya = QuranRiwaya.hafs;

  AppBannerInfo? _lastBanner;
  int? _lastAyah;
  int? _lastSurah;
  late final Listenable _screenThemeLanguageListenable;
  late final Listenable _bottomBarListenable;

  @override
  void initState() {
    super.initState();
    final app = AppState.instance;
    _surahNotifier = ValueNotifier<int>(_effectiveSurah);
    _screenThemeLanguageListenable = Listenable.merge([
      app.themeNotifier,
      app.languageNotifier,
      app.mushafModeNotifier,
    ]);
    _bottomBarListenable = Listenable.merge([
      app.themeNotifier,
      app.blurModeNotifier,
      app.currentMushafPage,
      _surahNotifier,
    ]);
    if (!PlatformCapabilities.isWeb) {
      WidgetsBinding.instance.addObserver(this);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      unawaited(QuranImageService.ensurePermission().then((granted) {
        if (granted && mounted) {
          setState(() {});
        }
      }));
    }
    widget.controller.addListener(_onControllerUpdate);
    widget.controller.activeAyah.addListener(_onActiveAyahChanged);
    AppState.instance.mushafModeNotifier.addListener(_onMushafModeChanged);
    AppState.instance.currentMushafPage.addListener(_onMushafPageChanged);

    // Warm up Surah timings and Ayah 1 audio in memory/disk in the background for zero-latency instant play
    unawaited(QuranTimingService.instance
        .ensureSurahLoaded(widget.controller.targetSurah));
    if (!PlatformCapabilities.isWeb) {
      unawaited(QuranAudioService.ensureAyahDownloaded(
          widget.controller.targetSurah, 1));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (PlatformCapabilities.isWeb) return;

    final bool isDesktop = PlatformCapabilities.isDesktop;

    if (state == AppLifecycleState.detached) {
      QuranAudioService.instance.stop();
      if (widget.isRecording) widget.onToggleRecord();
      if (widget.isVoiceSearching) widget.onVoiceSearchToggle();
      return;
    }

    if (!isDesktop) {
      if (state == AppLifecycleState.resumed) {
        // Re-assert immersive sticky fullscreen mode whenever app regains focus or is resumed
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      } else if (state == AppLifecycleState.paused ||
          state == AppLifecycleState.inactive ||
          state == AppLifecycleState.hidden) {
        if (widget.isRecording || QuranAudioService.instance.isSingleWordMode) {
          QuranAudioService.instance.stop();
        } else if (state == AppLifecycleState.paused) {
          // TODO(playstore-fgs): While FOREGROUND_SERVICE_MEDIA_PLAYBACK is disabled,
          // allow audio on screen-off/lock (like v1.2.0+22) and stop if user minimized app.
          if (defaultTargetPlatform == TargetPlatform.android) {
            unawaited(_checkAndStopAudioIfMinimized());
          } else if (defaultTargetPlatform != TargetPlatform.iOS) {
            QuranAudioService.instance.stop();
          }
        }
        // Microphone recording and voice search are suspended.
        if (widget.isRecording) {
          widget.onToggleRecord();
        }
        if (widget.isVoiceSearching) {
          widget.onVoiceSearchToggle();
        }
      }
    }
  }

  Future<void> _checkAndStopAudioIfMinimized() async {
    try {
      final isOffOrLocked =
          await _lifecycleChannel.invokeMethod<bool>('isScreenOffOrLocked') ??
              false;
      if (!isOffOrLocked) {
        await QuranAudioService.instance.stop();
      }
    } catch (_) {
      await QuranAudioService.instance.stop();
    }
  }

  @override
  void dispose() {
    AppState.instance.stopVerseAudio();
    if (!PlatformCapabilities.isWeb) {
      WidgetsBinding.instance.removeObserver(this);
    }
    widget.controller.removeListener(_onControllerUpdate);
    widget.controller.activeAyah.removeListener(_onActiveAyahChanged);
    AppState.instance.mushafModeNotifier.removeListener(_onMushafModeChanged);
    AppState.instance.currentMushafPage.removeListener(_onMushafPageChanged);
    _voiceSearchNotifier.dispose();
    _isAutoScrolling.dispose();
    _surahNotifier.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(TrackingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      _surahNotifier.value = widget.controller.targetSurah;
    }
    if (widget.isRecording && !oldWidget.isRecording) {
      AppState.instance.dismissBanner();
      final int targetAyah =
          widget.controller.currentMatchedVerse?.verse.ayah ??
              widget.controller.activeAyah.value ??
              1;
      _lastAyah = targetAyah;
    }

    if (widget.isVoiceSearching && !oldWidget.isVoiceSearching) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          DialogService.showVoiceSearch(
            context,
            onStop: widget.onVoiceSearchToggle,
            isLoading: widget.isVoiceSearchLoading,
            asrTextNotifier:
                widget.voiceSearchTextNotifier ?? _voiceSearchNotifier,
            searchResultNotifier: widget.voiceSearchController?.currentResult,
            onSelectCandidate: widget.onSelectVoiceCandidate,
            onHoldChanged: widget.onVoiceSearchHoldChanged,
          );
        }
      });
    } else if (!widget.isVoiceSearching && oldWidget.isVoiceSearching) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      });
    }
  }

  void _onControllerUpdate() {
    if (widget.controller.targetSurah != _lastSurah) {
      final newSurah = widget.controller.targetSurah;
      _surahNotifier.value = newSurah;
      void applyUpdate() {
        if (!mounted) return;
        setState(() {
          _lastSurah = newSurah;
          _lastAyah = null;
        });
      }

      if (SchedulerBinding.instance.schedulerPhase ==
          SchedulerPhase.persistentCallbacks) {
        SchedulerBinding.instance.addPostFrameCallback((_) => applyUpdate());
      } else {
        applyUpdate();
      }
    }
  }

  void _onActiveAyahChanged() {
    if (QuranAudioService.instance.isSingleWordMode) return;

    final active = widget.controller.activeAyah.value;
    if (active != null && active != _lastAyah) {
      _lastAyah = active;
      AppState.instance.saveLastPosition(widget.controller.targetSurah, active);
    }
  }

  void _onMushafModeChanged() {
    _isAutoScrolling.value = false;
    final bool isMushaf = AppState.instance.isMushafMode;
    if (isMushaf) {
      final int currentSurah = widget.controller.targetSurah;
      final int currentAyah =
          widget.controller.activeAyah.value ?? AppState.instance.lastAyah;
      final mappedPage =
          MushafView.getPageForAyah(currentSurah, currentAyah) ??
              MushafView.getPageForAyah(currentSurah, 1);
      if (mappedPage != null) {
        AppState.instance.saveMushafPage(mappedPage);
      }
    } else {
      final int targetSurah = _effectiveSurah;
      if (widget.controller.targetSurah != targetSurah) {
        widget.controller.setTargetSurah(
          targetSurah,
          preserveOtherSurahStates: true,
          clearTargetSurah: false,
        );
      }
    }
    _surahNotifier.value = _effectiveSurah;
  }

  void _onMushafPageChanged() {
    if (AppState.instance.isMushafMode) {
      final newSurah = _effectiveSurah;
      if (_surahNotifier.value != newSurah) {
        _surahNotifier.value = newSurah;
      }
    }
  }

  int get _effectiveSurah {
    if (AppState.instance.isMushafMode) {
      final page = AppState.instance.currentMushafPage.value;
      final activeAyah = widget.controller.activeAyah.value;
      final activeSurah = widget.controller.targetSurah;
      if (activeAyah != null &&
          MushafView.isAyahOnPage(
            pageNumber: page,
            surah: activeSurah,
            ayah: activeAyah,
          )) {
        return activeSurah;
      }
      final dominant = MushafView.getDominantSurahOnPage(page);
      if (dominant != null) {
        return dominant;
      }
      final first = MushafView.getFirstAyahOnPage(page);
      if (first != null) {
        return first.$1;
      }
    }
    return widget.controller.targetSurah;
  }

  void _showSurahPicker() {
    DialogService.showSurahPicker(
      context,
      current: _effectiveSurah,
      controller: widget.controller,
      isRecording: widget.isRecording,
      isVoiceSearching: widget.isVoiceSearching,
      onToggleRecord: widget.onToggleRecord,
      onVoiceSearchToggle: widget.onVoiceSearchToggle,
      onPick: (n, {ayah}) async {
          QuranAudioService.instance.stop();
          if (widget.isRecording) {
            widget.onToggleRecord();
          }
          if (Navigator.of(context).canPop()) {
            Navigator.pop(context);
          }
          if (!mounted) return;

          final targetAyah = ayah ?? 1;
          await widget.controller.setTargetSurah(
            n,
            preserveOtherSurahStates: true,
            clearTargetSurah: false,
          );
          widget.controller.setManualAyah(n, targetAyah);
          AppState.instance.saveLastPosition(n, targetAyah);
          final mappedPage =
              MushafView.getPageForAyah(n, targetAyah);
          if (mappedPage != null) {
            AppState.instance.saveMushafPage(mappedPage);
          }
          unawaited(QuranTimingService.instance.ensureSurahLoaded(n));
          unawaited(QuranAudioService.ensureAyahDownloaded(n, 1));

          setState(() {
            _lastAyah = null;
          });
        },
    );
  }

  void _goToPage(int page) {
    final targetPage = page.clamp(1, 604);
    AppState.instance.saveMushafPage(targetPage);
    AppState.instance.currentMushafPage.value = targetPage;
    final first = MushafView.getFirstAyahOnPage(targetPage);
    if (first != null) {
      widget.controller.setTargetSurah(
        first.$1,
        preserveOtherSurahStates: true,
        clearTargetSurah: false,
      );
      widget.controller.setManualAyah(first.$1, first.$2);
      AppState.instance.saveLastPosition(first.$1, first.$2);
      unawaited(QuranTimingService.instance.ensureSurahLoaded(first.$1));
    }
    setState(() {
      _lastAyah = null;
    });
  }

  void _showPagePicker() {
    final curPage = AppState.instance.currentMushafPage.value.clamp(1, 604);
    DialogService.showPagePicker(
      context,
      currentPage: curPage,
      onPick: _goToPage,
    );
  }

  void _showJuzPicker() {
    final curPage = AppState.instance.currentMushafPage.value.clamp(1, 604);
    final curJuz = QuranPageUtils.getJuzForPage(curPage);
    DialogService.showJuzPicker(
      context,
      currentJuz: curJuz,
      onPick: _goToPage,
    );
  }

  void _showTafsirDialog() {
    final surah = _effectiveSurah;
    final ayah = widget.controller.activeAyah.value ?? 1;
    final surahName = _getSurahName(surah, true);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: DialogTokens.barrierColor,
      builder: (ctx) {
        final app = AppState.instance;
        final isDark = app.isDarkMode;

        return AppBottomSheet(
          maxHeightFactor: 0.65,
          child: Column(
            children: [
              const AppDragHandle(),
              AppModalHeader(
                title: 'تفسير سورة $surahName (الآية $ayah)',
                onClose: () => Navigator.pop(ctx),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1B2430) : const Color(0xFFFFF4CB),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isDark ? Colors.white12 : const Color(0xFFE2C988),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'سورة $surahName - الآية $ayah',
                          style: const TextStyle(
                            fontFamily: 'cairo',
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF227E08),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'يمكنك قراءة وتفسير الآيات ومتابعة التلاوة بالضغط على تلاوة أو استخدام الميكروفون للتحقق من الحفظ الذكي.',
                          style: TextStyle(
                            fontFamily: 'cairo',
                            fontSize: 14.5,
                            height: 1.6,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                          textAlign: TextAlign.right,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTopBar(ThemeColors c, AppState app, double topSafe) {
    final bool isDark = app.isDarkMode;
    final bool isPlayingAudio = QuranAudioService.instance.isPlaying;

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      top: (_showBars || widget.isRecording) ? topSafe : -70.0,
      left: 0,
      right: 0,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 220),
        opacity: (_showBars || widget.isRecording) ? 1.0 : 0.0,
        child: IgnorePointer(
          ignoring: !_showBars && !widget.isRecording,
          child: Container(
            height: 38.0,
            margin: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
            decoration: BoxDecoration(
              color: const Color(0xFF1D0606).withValues(alpha: isDark ? 0.95 : 0.90),
              borderRadius: BorderRadius.circular(10.0),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.15),
                width: 0.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Row(
                children: [
                  // 1. Search (btnF)
                  _buildTopBarItem(
                    flex: 1,
                    child: const Icon(Icons.search_rounded, color: Colors.white, size: 19),
                    tooltip: 'بحث صوتي',
                    onTap: () {
                      if (widget.isRecording) widget.onToggleRecord();
                      widget.onVoiceSearchToggle();
                    },
                  ),
                  _buildTopBarDivider(),
                  // 2. Warsh (btnW)
                  _buildTopBarItem(
                    flex: 2,
                    label: 'ورش',
                    isSelected: _riwaya == QuranRiwaya.warsh,
                    onTap: () {
                      setState(() {
                        _riwaya = QuranRiwaya.warsh;
                      });
                    },
                  ),
                  _buildTopBarDivider(),
                  // 3. Hafs (btnH)
                  _buildTopBarItem(
                    flex: 2,
                    label: 'حفص',
                    isSelected: _riwaya == QuranRiwaya.hafs,
                    onTap: () {
                      setState(() {
                        _riwaya = QuranRiwaya.hafs;
                      });
                    },
                  ),
                  _buildTopBarDivider(),
                  // 4. Tafsir (btnT)
                  _buildTopBarItem(
                    flex: 2,
                    label: 'تفسير',
                    onTap: _showTafsirDialog,
                  ),
                  _buildTopBarDivider(),
                  // 5. Tilawa (btnA) - green background like QIqra
                  _buildTopBarItem(
                    flex: 2,
                    label: isPlayingAudio ? 'إيقاف' : 'تلاوة',
                    bgColor: const Color(0xFF227E08),
                    isSelected: true,
                    onTap: () async {
                      if (isPlayingAudio) {
                        await QuranAudioService.instance.stop();
                      } else {
                        final surah = _effectiveSurah;
                        final targetAyah = widget.controller.activeAyah.value ?? 1;
                        await QuranAudioService.instance.playAyah(surah, targetAyah);
                      }
                      setState(() {});
                    },
                  ),
                  _buildTopBarDivider(),
                  // 6. Menu (btnM)
                  _buildTopBarItem(
                    flex: 2,
                    label: 'القائمة',
                    onTap: () {
                      DialogService.showSettings(context);
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBarItem({
    required int flex,
    String? label,
    Widget? child,
    bool isSelected = false,
    Color? bgColor,
    required VoidCallback onTap,
    String? tooltip,
  }) {
    return Expanded(
      flex: flex,
      child: Tooltip(
        message: tooltip ?? label ?? '',
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8.0),
          child: Container(
            height: double.infinity,
            decoration: BoxDecoration(
              color: bgColor ?? Colors.transparent,
              borderRadius: BorderRadius.circular(8.0),
            ),
            alignment: Alignment.center,
            child: child ??
                Text(
                  label ?? '',
                  style: TextStyle(
                    fontFamily: 'cairo',
                    fontSize: 12.5,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected ? Colors.white : const Color(0xFFAEA7A7),
                  ),
                ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBarDivider() {
    return Container(
      width: 0.8,
      height: 18.0,
      color: Colors.white.withValues(alpha: 0.15),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final top = MediaQuery.paddingOf(context).top;
    final safeLeft = MediaQuery.paddingOf(context).left;
    final double pageLabelLeft = safeLeft + 16.0;
    final app = AppState.instance;

    return ListenableBuilder(
      listenable: _screenThemeLanguageListenable,
      builder: (context, child) {
        final c = app.colors;

        return Directionality(
          textDirection: app.isArabic ? TextDirection.rtl : TextDirection.ltr,
          child: Scaffold(
            resizeToAvoidBottomInset: false,
            backgroundColor: c.bg,
            body: ValueListenableBuilder<bool>(
              valueListenable: _isAutoScrolling,
              child: Positioned.fill(child: _buildVerseContent(c, app)),
              builder: (context, isAutoScrolling, verseContentChild) {
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    // Main Verse Content (Mushaf View or Verse List View - preserved across auto-scroll toggles)
                    if (verseContentChild != null) verseContentChild,

                    // Top Action Bar (Exact QIqra Bar: Search | Warsh | Hafs | Tafsir | Tilawa | Menu)
                    _buildTopBar(c, app, top),

                    // Bottom Action Bar (Unified Glassmorphic Command Dock)
                    // Disappears during auto-scroll or on page tap for zero-distraction reading!
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                      bottom: (!app.isMushafMode && isAutoScrolling)
                          ? -90.0
                          : ((_showBars || widget.isRecording) ? 0 : -90.0),
                      left: 0,
                      right: 0,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 220),
                        opacity: (!app.isMushafMode && isAutoScrolling)
                            ? 0.0
                            : ((_showBars || widget.isRecording) ? 1.0 : 0.0),
                        child: IgnorePointer(
                          ignoring: (!app.isMushafMode && isAutoScrolling) ||
                              (!_showBars && !widget.isRecording),
                          child: AnimatedBuilder(
                            animation: _bottomBarListenable,
                            builder: (context, _) {
                              final effectiveSurah = _effectiveSurah;
                              final surahName =
                                  _getSurahName(effectiveSurah, app.isArabic);
                              final currentPage =
                                  app.currentMushafPage.value.clamp(1, 604);
                              final currentJuz =
                                  QuranPageUtils.getJuzForPage(currentPage);
                              return BottomActionBar(
                                key: const ValueKey('unified_dock_bar'),
                                isRecording: widget.isRecording,
                                isVoiceSearching: widget.isVoiceSearching,
                                isLoadingEngine: widget.isLoadingEngine,
                                c: c,
                                onMic: () {
                                  app.dismissBanner();
                                  if (widget.isVoiceSearching) {
                                    widget.onVoiceSearchToggle();
                                  } else {
                                    widget.onToggleRecord();
                                  }
                                },
                                isBlur: app.isBlurMode,
                                onToggleBlur: () {
                                  app.toggleBlurMode();
                                  if (app.isBlurMode) {
                                    app.showBlurBanner(true);
                                  } else {
                                    app.dismissBanner();
                                  }
                                },
                                onVoiceSearch: () {
                                  app.dismissBanner();
                                  if (widget.isRecording) {
                                    widget.onToggleRecord();
                                  }
                                  widget.onVoiceSearchToggle();
                                },
                                surahName: surahName,
                                onSurahTap: _showSurahPicker,
                                pageNumber: currentPage,
                                juzNumber: currentJuz,
                                onPageTap: _showPagePicker,
                                onJuzTap: _showJuzPicker,
                              );
                            },
                          ),
                        ),
                      ),
                    ),

                    // Modern Floating Slide-Up Banner (Scoped listener prevents full screen rebuilds)
                    ValueListenableBuilder<AppBannerInfo?>(
                      valueListenable: app.bannerNotifier,
                      builder: (context, activeBanner, _) =>
                          _buildModernBottomBanner(c, app, bottom, activeBanner),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  String _getSurahName(int surahNum, bool isArabic) {
    final metadata = widget.controller.repository.surahMetadata;
    if (surahNum >= 1 && surahNum <= metadata.length) {
      final s = metadata[surahNum - 1];
      return isArabic ? s.surahName : s.surahNameEn;
    }
    final verse1 = widget.controller.repository.getVerse(surahNum, 1);
    return isArabic ? (verse1?.surahName ?? '') : (verse1?.surahNameEn ?? '');
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Modern Floating Slide-Up Banner (Slides UP from bottom toolbar for all notices)
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildModernBottomBanner(
      ThemeColors c, AppState app, double bottom, AppBannerInfo? activeBanner) {
    final bool isDark = app.isDarkMode;
    final bool isAr = app.isArabic;
    final bool isVisible = activeBanner != null;

    if (activeBanner != null) {
      _lastBanner = activeBanner;
    }
    final banner = activeBanner ?? _lastBanner;
    if (banner == null) {
      return const SizedBox.shrink();
    }

    final Color accentColor;
    if (banner.customColor != null) {
      accentColor = banner.customColor!(c, isDark);
    } else if (banner.isWarning) {
      accentColor = isDark ? const Color(0xFFF59E0B) : const Color(0xFFD97706);
    } else {
      accentColor = c.primary;
    }

    final Color iconColor =
        (banner.isWarning && isDark) ? const Color(0xFFFBBF24) : accentColor;
    final String message = isAr ? banner.messageAr : banner.messageEn;

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      bottom: isVisible ? (bottom + 78) : (bottom + 16),
      left: 16,
      right: 16,
      child: IgnorePointer(
        ignoring: !isVisible,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 240),
          opacity: isVisible ? 1.0 : 0.0,
          child: RepaintBoundary(
            child: Center(
              child: GestureDetector(
                onTap: () {
                  app.dismissBanner();
                },
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 460),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isDark ? c.surfaceHigh : c.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: accentColor.withValues(alpha: isDark ? 0.38 : 0.30),
                      width: 1.1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color:
                            Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
                        blurRadius: 14,
                        offset: const Offset(0, -3),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color:
                              accentColor.withValues(alpha: isDark ? 0.20 : 0.12),
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(
                            color: accentColor.withValues(
                                alpha: isDark ? 0.42 : 0.32),
                            width: 0.8,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          banner.icon,
                          color: iconColor,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          message,
                          style: TextStyle(
                            color: c.text,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                            fontSize: 12.5,
                          ),
                          textAlign: isAr ? TextAlign.right : TextAlign.left,
                          textDirection:
                              isAr ? TextDirection.rtl : TextDirection.ltr,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVerseContent(ThemeColors c, AppState app) {
    if (app.isMushafMode) {
      if (!widget.isRecording &&
          (QuranImageService.hasExternalImages(riwaya: _riwaya) ||
              QuranImageService.hasExternalImages(riwaya: QuranRiwaya.hafs) ||
              QuranImageService.hasExternalImages(riwaya: QuranRiwaya.warsh))) {
        return ExternalMushafView(
          key: ValueKey('external_mushaf_${_riwaya.name}'),
          controller: widget.controller,
          riwaya: _riwaya,
          onPageTap: () {
            setState(() {
              _showBars = !_showBars;
            });
          },
        );
      }
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          setState(() {
            _showBars = !_showBars;
          });
        },
        child: MushafView(
          key: const ValueKey('mushaf_view_main'),
          controller: widget.controller,
          isRecording: widget.isRecording,
          showBottomPageNumber: true,
        ),
      );
    }

    return RepaintBoundary(
      key: const ValueKey('verse_list_boundary'),
      child: VerseListView(
        key: _verseListKey,
        controller: widget.controller,
        isRecording: widget.isRecording,
        onToggleRecord: widget.onToggleRecord,
        onAutoScrollChanged: (scrolling) {
          _isAutoScrolling.value = scrolling;
        },
      ),
    );
  }
}
