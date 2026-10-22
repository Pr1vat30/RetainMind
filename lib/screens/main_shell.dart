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

    showModalBottomSheet(
      context: context,
      backgroundColor: AppConstants.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppConstants.radiusCard)),
      ),
      builder: (ctx) {
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
                  const Text(
                    'Impostazioni Server & Connessione',
                    style: TextStyle(
                      color: AppConstants.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppConstants.textSecondary, size: 20),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                style: const TextStyle(color: AppConstants.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'URL API Backend',
                  labelStyle: const TextStyle(color: AppConstants.textSecondary, fontSize: 12),
                  filled: true,
                  fillColor: AppConstants.surfaceContainer,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () {
                    provider.updateBackendUrl(controller.text.trim());
                    Navigator.pop(ctx);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppConstants.primaryContainer,
                    foregroundColor: AppConstants.onPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                    ),
                  ),
                  child: const Text('Salva e Riconnetti', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        );
      },
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
        backgroundColor: AppConstants.background,
        body: Stack(
        children: [
          // Content pages
          IndexedStack(
            index: _currentIndex > 2 ? 0 : _currentIndex,
            children: pages,
          ),

          // Floating Navigation Capsule (HTML: max-w-sm h-16 bg-surface-container-high/90 backdrop-blur-2xl rounded-full)
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
                        color: AppConstants.surfaceContainerHigh.withValues(alpha: 0.90),
                        borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                        border: Border.all(color: AppConstants.outlineCard),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.5),
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
                            onTap: () => _onTabChange(0),
                          ),

                          // 2. History
                          _buildNavItem(
                            index: 1,
                            icon: Icons.history_rounded,
                            label: 'History',
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
                                  gradient: const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Color(0xFF70D6FF),
                                      Color(0xFF38BDF8),
                                      Color(0xFF00A7C0),
                                    ],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppConstants.primaryContainer.withValues(alpha: 0.50),
                                      blurRadius: 20,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.add_rounded,
                                  color: AppConstants.surfaceContainerLowest,
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
                            onTap: () => _onTabChange(2),
                          ),

                          // 5. Config
                          _buildNavItem(
                            index: 3,
                            icon: Icons.tune_rounded,
                            label: 'Config',
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
    required VoidCallback onTap,
    bool? isSelectedOverride,
  }) {
    final isSelected = isSelectedOverride ?? (_currentIndex == index);
    final activeColor = AppConstants.primaryContainer;
    final inactiveColor = AppConstants.textSecondary;

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
