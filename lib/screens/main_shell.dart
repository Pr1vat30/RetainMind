import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants.dart';
import '../providers/exam_provider.dart';
import '../widgets/new_discussion_modal.dart';
import 'home_screen.dart';
import 'previous_discussions_screen.dart';
import 'report_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  void _showConnectionSettings(BuildContext context) {
    final provider = context.read<ExamProvider>();
    final controller = TextEditingController(text: provider.apiService.baseUrl);
    final colors = context.colors;

    showModalBottomSheet(
      context: context,
      backgroundColor: colors.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppConstants.radiusCard)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            final activeThemeMode = provider.themeMode;

            return Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 24,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Impostazioni & Tema',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: colors.textSecondary, size: 20),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Theme Selector: Scuro (default) / Chiaro / Sistema
                  Text(
                    'TEMA INTERFACCIA',
                    style: TextStyle(
                      color: colors.textTertiary,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                      border: Border.all(color: colors.outlineCard),
                    ),
                    child: Row(
                      children: [
                        _buildThemePill(
                          label: 'Scuro',
                          icon: Icons.dark_mode_rounded,
                          isSelected: activeThemeMode == ThemeMode.dark,
                          colors: colors,
                          onTap: () {
                            provider.setThemeMode(ThemeMode.dark);
                            setModalState(() {});
                          },
                        ),
                        _buildThemePill(
                          label: 'Chiaro',
                          icon: Icons.light_mode_rounded,
                          isSelected: activeThemeMode == ThemeMode.light,
                          colors: colors,
                          onTap: () {
                            provider.setThemeMode(ThemeMode.light);
                            setModalState(() {});
                          },
                        ),
                        _buildThemePill(
                          label: 'Sistema',
                          icon: Icons.brightness_auto_rounded,
                          isSelected: activeThemeMode == ThemeMode.system,
                          colors: colors,
                          onTap: () {
                            provider.setThemeMode(ThemeMode.system);
                            setModalState(() {});
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),
                  Text(
                    'CONNESSIONE SERVER',
                    style: TextStyle(
                      color: colors.textTertiary,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: controller,
                    style: TextStyle(color: colors.textPrimary, fontSize: 13),
                    decoration: InputDecoration(
                      labelText: 'URL API Backend',
                      labelStyle: TextStyle(color: colors.textSecondary, fontSize: 12),
                      filled: true,
                      fillColor: colors.surfaceContainer,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () {
                        provider.updateBackendUrl(controller.text.trim());
                        Navigator.pop(ctx);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.primaryContainer,
                        foregroundColor: colors.onPrimaryContainer,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                        ),
                      ),
                      child: const Text('Salva e Chiudi', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildThemePill({
    required String label,
    required IconData icon,
    required bool isSelected,
    required AppColors colors,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? colors.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(AppConstants.radiusPill),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: isSelected ? colors.onPrimaryContainer : colors.textSecondary,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? colors.onPrimaryContainer : colors.textSecondary,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onCentralPlusTap() {
    NewDiscussionModal.show(context);
  }

  void _onTabChange(int index) {
    setState(() => _currentIndex = index);
    if (index == 1) {
      context.read<ExamProvider>().fetchHistory();
    } else if (index == 2) {
      context.read<ExamProvider>().loadReport();
      context.read<ExamProvider>().fetchHistory();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = context.isDarkMode;

    final pages = [
      HomeScreen(
        onOpenCronologia: () {
          context.read<ExamProvider>().fetchHistory();
          setState(() => _currentIndex = 1);
        },
      ),
      const PreviousDiscussionsScreen(showBackButton: false),
      const ReportScreen(showBackButton: false),
    ];

    return PopScope(
      canPop: _currentIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_currentIndex != 0) {
          setState(() => _currentIndex = 0);
        }
      },
      child: Scaffold(
        backgroundColor: colors.background,
        body: Stack(
          children: [
            // Content pages
            IndexedStack(
              index: _currentIndex > 2 ? 0 : _currentIndex,
              children: pages,
            ),

            // Floating Navigation Capsule (DESIGN.md: detached floating bar)
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: Container(
                        height: 64,
                        constraints: const BoxConstraints(maxWidth: 390),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerHigh.withValues(alpha: isDark ? 0.90 : 0.94),
                          borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                          border: Border.all(color: colors.outlineCard),
                          boxShadow: [
                            BoxShadow(
                              color: colors.floatingNavShadow,
                              blurRadius: 32,
                              offset: const Offset(0, 16),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            // 1. Home
                            _buildNavItem(
                              index: 0,
                              icon: Icons.grid_view_rounded,
                              label: 'Home',
                              colors: colors,
                              onTap: () => _onTabChange(0),
                            ),

                            // 2. History
                            _buildNavItem(
                              index: 1,
                              icon: Icons.history_rounded,
                              label: 'History',
                              colors: colors,
                              onTap: () => _onTabChange(1),
                            ),

                            // 3. Central Raised Cyan Plus Button (Upload docs to start new discussion)
                            Tooltip(
                              message: 'Carica documenti & Nuova discussione',
                              child: GestureDetector(
                                onTap: _onCentralPlusTap,
                                child: Container(
                                  width: 50,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: colors.heroGradient,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: colors.primaryContainer.withValues(alpha: isDark ? 0.50 : 0.35),
                                        blurRadius: 20,
                                        offset: const Offset(0, 6),
                                      ),
                                    ],
                                  ),
                                  child: Icon(
                                    Icons.add_rounded,
                                    color: colors.surfaceContainerLowest,
                                    size: 32,
                                  ),
                                ),
                              ),
                            ),

                            // 4. Report
                            _buildNavItem(
                              index: 2,
                              icon: Icons.insights_rounded,
                              label: 'Report',
                              colors: colors,
                              onTap: () => _onTabChange(2),
                            ),

                            // 5. Config
                            _buildNavItem(
                              index: 3,
                              icon: Icons.tune_rounded,
                              label: 'Config',
                              colors: colors,
                              isSelectedOverride: false,
                              onTap: () => _showConnectionSettings(context),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required String label,
    required AppColors colors,
    required VoidCallback onTap,
    bool? isSelectedOverride,
  }) {
    final isSelected = isSelectedOverride ?? (_currentIndex == index);
    final activeColor = colors.primaryContainer;
    final inactiveColor = colors.textSecondary;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 56,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected ? activeColor.withValues(alpha: 0.15) : Colors.transparent,
                borderRadius: BorderRadius.circular(AppConstants.radiusPill),
              ),
              child: Icon(
                icon,
                size: 20,
                color: isSelected ? activeColor : inactiveColor,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? activeColor : inactiveColor,
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                letterSpacing: -0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
