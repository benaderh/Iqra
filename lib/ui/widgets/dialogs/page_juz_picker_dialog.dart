import 'package:flutter/material.dart';
import '../../../core/app_state.dart';
import 'dialog_base.dart';

/// Helper utilities for Quran page and Juz navigation.
abstract final class QuranPageUtils {
  static const List<int> juzStartPages = [
    1, 22, 42, 62, 82, 102, 122, 142, 162, 182,
    202, 222, 242, 262, 282, 302, 322, 342, 362, 382,
    402, 422, 442, 462, 482, 502, 522, 542, 562, 582,
  ];

  static const List<String> juzNames = [
    'الجزء الأول',
    'الجزء الثاني',
    'الجزء الثالث',
    'الجزء الرابع',
    'الجزء الخامس',
    'الجزء السادس',
    'الجزء السابع',
    'الجزء الثامن',
    'الجزء التاسع',
    'الجزء العاشر',
    'الجزء الحادي عشر',
    'الجزء الثاني عشر',
    'الجزء الثالث عشر',
    'الجزء الرابع عشر',
    'الجزء الخامس عشر',
    'الجزء السادس عشر',
    'الجزء السابع عشر',
    'الجزء الثامن عشر',
    'الجزء التاسع عشر',
    'الجزء العشرون',
    'الجزء الحادي والعشرون',
    'الجزء الثاني والعشرون',
    'الجزء الثالث والعشرون',
    'الجزء الرابع والعشرون',
    'الجزء الخامس والعشرون',
    'الجزء السادس والعشرون',
    'الجزء السابع والعشرون',
    'الجزء الثامن والعشرون',
    'الجزء التاسع والعشرون',
    'الجزء الثلاثون',
  ];

  /// Calculates the 1-based Juz number for a given Mushaf [page] (1..604).
  static int getJuzForPage(int page) {
    for (int i = juzStartPages.length - 1; i >= 0; i--) {
      if (page >= juzStartPages[i]) {
        return i + 1;
      }
    }
    return 1;
  }
}

/// Dialog allowing the user to quickly jump to any Mushaf page (1 to 604).
class PagePickerDialog extends StatefulWidget {
  final int currentPage;
  final ValueChanged<int> onPageSelected;

  const PagePickerDialog({
    super.key,
    required this.currentPage,
    required this.onPageSelected,
  });

  static Future<void> show(
    BuildContext context, {
    required int currentPage,
    required ValueChanged<int> onPageSelected,
  }) {
    return showDialog<void>(
      context: context,
      barrierColor: DialogTokens.barrierColor,
      builder: (ctx) => PagePickerDialog(
        currentPage: currentPage,
        onPageSelected: onPageSelected,
      ),
    );
  }

  @override
  State<PagePickerDialog> createState() => _PagePickerDialogState();
}

class _PagePickerDialogState extends State<PagePickerDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.currentPage}');
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    final page = int.tryParse(text);
    if (page == null || page < 1 || page > 604) {
      setState(() {
        _errorText = 'الرجاء إدخال رقم بين 1 و 604';
      });
      return;
    }
    widget.onPageSelected(page);
    if (Navigator.of(context).canPop()) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    final c = app.colors;
    final isDark = app.isDarkMode;

    return AppDialog(
      title: 'الانتقال إلى صفحة',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            keyboardType: TextInputType.number,
            autofocus: true,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: c.text,
            ),
            decoration: InputDecoration(
              hintText: '1 - 604',
              hintStyle: TextStyle(color: c.muted),
              errorText: _errorText,
              filled: true,
              fillColor: isDark ? const Color(0xFF1B2430) : const Color(0xFFF1F5F9),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: isDark ? Colors.white12 : Colors.black12,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(
                  color: Color(0xFF10B981),
                  width: 1.5,
                ),
              ),
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  text: 'إلغاء',
                  variant: AppButtonVariant.secondary,
                  onTap: () {
                    if (Navigator.of(context).canPop()) {
                      Navigator.pop(context);
                    }
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AppButton(
                  text: 'انتقال',
                  variant: AppButtonVariant.primary,
                  onTap: _submit,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet displaying the 30 Quranic Juz (الأجزاء) with their starting pages.
class JuzPickerSheet extends StatelessWidget {
  final int currentJuz;
  final ValueChanged<int> onPageSelected;

  const JuzPickerSheet({
    super.key,
    required this.currentJuz,
    required this.onPageSelected,
  });

  static Future<void> show(
    BuildContext context, {
    required int currentJuz,
    required ValueChanged<int> onPageSelected,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: DialogTokens.barrierColor,
      elevation: 0,
      builder: (ctx) => JuzPickerSheet(
        currentJuz: currentJuz,
        onPageSelected: onPageSelected,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    final c = app.colors;
    final isDark = app.isDarkMode;

    return AppBottomSheet(
      maxHeightFactor: 0.80,
      child: Column(
        children: [
          const AppDragHandle(),
          AppModalHeader(
            title: 'فهرس الأجزاء',
            subtitle: 'اختر الجزء للانتقال المباشر إليه',
            onClose: () {
              if (Navigator.of(context).canPop()) {
                Navigator.pop(context);
              }
            },
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              itemCount: 30,
              itemBuilder: (context, index) {
                final juzNum = index + 1;
                final startPage = QuranPageUtils.juzStartPages[index];
                final name = QuranPageUtils.juzNames[index];
                final isSelected = juzNum == currentJuz;

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      onPageSelected(startPage);
                      if (Navigator.of(context).canPop()) {
                        Navigator.pop(context);
                      }
                    },
                    child: Container(
                      height: 54,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF10B981).withValues(alpha: isDark ? 0.20 : 0.12)
                            : (isDark
                                ? Colors.white.withValues(alpha: 0.04)
                                : Colors.black.withValues(alpha: 0.03)),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFF10B981).withValues(alpha: isDark ? 0.50 : 0.40)
                              : (isDark
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : Colors.black.withValues(alpha: 0.06)),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF10B981)
                                  : (isDark
                                      ? Colors.white.withValues(alpha: 0.08)
                                      : Colors.black.withValues(alpha: 0.06)),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '$juzNum',
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.white
                                    : (isDark ? Colors.white70 : Colors.black87),
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              name,
                              style: TextStyle(
                                fontFamily: 'cairo',
                                fontSize: 14.5,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                color: isSelected
                                    ? (isDark ? const Color(0xFF10B981) : const Color(0xFF059669))
                                    : c.text,
                              ),
                            ),
                          ),
                          Text(
                            'ص $startPage',
                            style: TextStyle(
                              fontFamily: 'cairo',
                              fontSize: 12.5,
                              color: c.muted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
