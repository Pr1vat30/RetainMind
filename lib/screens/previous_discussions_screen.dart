import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants.dart';
import '../models/session_models.dart';
import '../providers/exam_provider.dart';
import '../widgets/new_discussion_modal.dart';
import '../widgets/transcript_bubble.dart';
import 'discussion_detail_screen.dart';
import 'exam_screen.dart';

class PreviousDiscussionsScreen extends StatefulWidget {
  final bool showBackButton;

  const PreviousDiscussionsScreen({
    super.key,
    this.showBackButton = true,
  });

  /// Static helper to display the full transcript and diagnostic metrics for any session
  static void showDetailsSheet(
    BuildContext context,
    SessionHistoryItem item, {
    VoidCallback? onResume,
  }) {
    final exam = context.read<ExamProvider>();

    showModalBottomSheet(
      context: context,
      backgroundColor: AppConstants.surfaceContainerHigh,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppConstants.radiusCard)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.82,
          minChildSize: 0.45,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, scrollController) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppConstants.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Header Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              style: const TextStyle(
                                color: AppConstants.textPrimary,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.3,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (item.timestamp.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                item.timestamp.contains('T')
                                    ? item.timestamp.split('T').first
                                    : item.timestamp,
                                style: const TextStyle(
                                  color: AppConstants.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: AppConstants.textSecondary, size: 20),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // Metric badges
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppConstants.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                          border: Border.all(color: AppConstants.outlineCard),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.chat_bubble_outline, size: 13, color: AppConstants.primaryContainer),
                            const SizedBox(width: 6),
                            Text(
                              '${item.turnsCompleted} Scambi',
                              style: const TextStyle(
                                color: AppConstants.textPrimary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (item.averageMastery != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: (item.averageMastery! >= 0.70 ? AppConstants.success : AppConstants.warning)
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                item.averageMastery! >= 0.70 ? Icons.check_circle_outline : Icons.speed,
                                size: 13,
                                color: item.averageMastery! >= 0.70 ? AppConstants.success : AppConstants.warning,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Padronanza ${(item.averageMastery! * 100).toInt()}%',
                                style: TextStyle(
                                  color: item.averageMastery! >= 0.70 ? AppConstants.success : AppConstants.warning,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      Builder(
                        builder: (_) {
                          final isItemCompleted = item.status == 'COMPLETED';
                          final isItemInPausa = item.status == 'PAUSED' || (item.isCurrent && exam.sessionStatus?.status == 'PAUSED');
                          final itemColor = isItemCompleted
                              ? AppConstants.success
                              : (isItemInPausa ? AppConstants.warning : AppConstants.primaryContainer);
                          final itemLabel = isItemCompleted
                              ? 'Completata'
                              : (isItemInPausa ? 'In Pausa' : 'In Corso');

                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: itemColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                            ),
                            child: Text(
                              itemLabel,
                              style: TextStyle(
                                color: itemColor,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),

                  // Mastered & Weak Chips
                  if (item.masteredConcepts.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: item.masteredConcepts.map((c) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppConstants.success.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                            border: Border.all(color: AppConstants.success.withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            '✓ ${c.replaceAll('_', ' ')}',
                            style: const TextStyle(color: AppConstants.success, fontSize: 11.5, fontWeight: FontWeight.w600),
                          ),
                        );
                      }).toList(),
                    ),
                  ],

                  if (item.weakConcepts.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: item.weakConcepts.map((c) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppConstants.warning.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                            border: Border.all(color: AppConstants.warning.withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            '⚠ ${c.replaceAll('_', ' ')}',
                            style: const TextStyle(color: AppConstants.warning, fontSize: 11.5, fontWeight: FontWeight.w600),
                          ),
                        );
                      }).toList(),
                    ),
                  ],

                  const SizedBox(height: 16),
                  const Divider(color: AppConstants.outline),
                  const SizedBox(height: 8),

                  const Text(
                    'Trascrizione Scambi',
                    style: TextStyle(
                      color: AppConstants.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Async transcript list
                  Expanded(
                    child: FutureBuilder<List<DialogueTurn>>(
                      future: exam.fetchTranscriptForIteration(item.iteration, courseId: item.id),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppConstants.primaryContainer),
                          );
                        }

                        final turns = snapshot.data ?? [];
                        if (turns.isEmpty) {
                          return const Center(
                            child: Text(
                              'Nessuno scambio registrato per questa sessione.',
                              style: TextStyle(color: AppConstants.textSecondary, fontSize: 13),
                            ),
                          );
                        }

                        return ListView.builder(
                          controller: scrollController,
                          itemCount: turns.length,
                          itemBuilder: (context, idx) {
                            return TranscriptBubble(turn: turns[idx]);
                          },
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        if (onResume != null) {
                          onResume();
                        } else {
                          exam.resumeExamAndConnect(courseId: item.id).then((_) {
                            if (context.mounted) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const ExamScreen()),
                              );
                            }
                          });
                        }
                      },
                      icon: const Icon(Icons.play_arrow_rounded, size: 22),
                      label: Text(
                        item.isCurrent
                            ? 'Riprendi Questa Conversazione'
                            : 'Attiva e Riprendi Questa Discussione',
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppConstants.primaryContainer,
                        foregroundColor: AppConstants.onPrimary,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                        ),
                      ),
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

  @override
  State<PreviousDiscussionsScreen> createState() => _PreviousDiscussionsScreenState();
}

class _PreviousDiscussionsScreenState extends State<PreviousDiscussionsScreen> {
  String _searchQuery = '';
  int _selectedFilterIndex = 0; // 0: Tutte, 1: In corso, 2: Completate

  final List<String> _filters = ['Tutte', 'In corso', 'Completate'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ExamProvider>().fetchHistory();
    });
  }

  Future<void> _confirmClearAllHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppConstants.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusCard),
          side: const BorderSide(color: AppConstants.outlineCard),
        ),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppConstants.error, size: 24),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Cancella cronologia',
                style: TextStyle(
                  color: AppConstants.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: const Text(
          'Sei sicuro di voler cancellare tutte le discussioni registrate? Tutti i dati di studio, le sessioni e le trascrizioni verranno rimossi.',
          style: TextStyle(color: AppConstants.textSecondary, fontSize: 13.5, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla', style: TextStyle(color: AppConstants.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppConstants.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppConstants.radiusPill),
              ),
            ),
            child: const Text('Cancella tutto', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final exam = context.read<ExamProvider>();
    await exam.resetAllSessionData(deletePlan: true);
    await exam.fetchPlan();
    await exam.fetchHistory();
    await exam.fetchStatus();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Tutte le discussioni sono state cancellate dal server.'),
        backgroundColor: AppConstants.surfaceContainerHighest,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppConstants.radiusSm)),
      ),
    );
  }

  Future<void> _confirmDeleteDiscussion(dynamic identifier, {String? title}) async {
    final displayTitle = title ?? '#$identifier';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppConstants.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusCard),
          side: const BorderSide(color: AppConstants.outlineCard),
        ),
        title: const Row(
          children: [
            Icon(Icons.delete_outline_rounded, color: AppConstants.error, size: 22),
            SizedBox(width: 8),
            Text(
              'Elimina discussione',
              style: TextStyle(
                color: AppConstants.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Text(
          'Sei sicuro di voler eliminare la discussione "$displayTitle"? Verrà rimossa definitivamente dal server.',
          style: const TextStyle(color: AppConstants.textSecondary, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla', style: TextStyle(color: AppConstants.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppConstants.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppConstants.radiusPill),
              ),
            ),
            child: const Text('Elimina dal server', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final exam = context.read<ExamProvider>();
    await exam.deleteDiscussion(identifier);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Discussione "$displayTitle" eliminata dal server.'),
        backgroundColor: AppConstants.surfaceContainerHighest,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppConstants.radiusSm)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final exam = context.watch<ExamProvider>();
    final history = exam.historyItems;
    final isPaused = exam.sessionStatus?.status == 'PAUSED';

    // Apply filtering
    final filteredItems = history.reversed.where((item) {
      final isCompleted = item.status == 'COMPLETED';
      if (_selectedFilterIndex == 1 && isCompleted) return false;
      if (_selectedFilterIndex == 2 && !isCompleted) return false;

      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchTitle = item.title.toLowerCase().contains(q);
        final matchConcepts = item.masteredConcepts.any((c) => c.toLowerCase().contains(q)) ||
            item.weakConcepts.any((c) => c.toLowerCase().contains(q));
        final matchIteration = 'iterazione #${item.iteration}'.contains(q) ||
            'conversazione #${item.iteration}'.contains(q) ||
            '${item.iteration}'.contains(q);
        return matchTitle || matchConcepts || matchIteration;
      }
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: AppConstants.background,
      appBar: AppBar(
        backgroundColor: AppConstants.background,
        elevation: 0,
        automaticallyImplyLeading: widget.showBackButton,
        leading: widget.showBackButton
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppConstants.textPrimary),
                onPressed: () => Navigator.pop(context),
              )
            : null,
        title: const Text(
          'Cronologia Discussioni',
          style: TextStyle(
            color: AppConstants.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.3,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_rounded, color: AppConstants.error, size: 22),
            tooltip: 'Cancella tutte le discussioni',
            onPressed: _confirmClearAllHistory,
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline, color: AppConstants.primary, size: 22),
            tooltip: 'Nuova discussione',
            onPressed: () => NewDiscussionModal.show(context),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => exam.fetchHistory(),
          color: AppConstants.primaryContainer,
          backgroundColor: AppConstants.surfaceContainerHigh,
          child: Column(
            children: [
              // Search & Filter Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Column(
                  children: [
                    // Search Bar
                    TextField(
                      onChanged: (val) => setState(() => _searchQuery = val.trim()),
                      style: const TextStyle(color: AppConstants.textPrimary, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Cerca per titolo, argomento o iterazione...',
                        hintStyle: const TextStyle(color: AppConstants.textSecondary, fontSize: 12.5),
                        prefixIcon: const Icon(Icons.search, size: 20, color: AppConstants.textSecondary),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18, color: AppConstants.textSecondary),
                                onPressed: () => setState(() => _searchQuery = ''),
                              )
                            : null,
                        filled: true,
                        fillColor: AppConstants.surfaceContainerLow,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                          borderSide: const BorderSide(color: AppConstants.outlineCard),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                          borderSide: const BorderSide(color: AppConstants.outlineCard),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                          borderSide: const BorderSide(color: AppConstants.primaryContainer),
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Filter Pills
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: List.generate(_filters.length, (idx) {
                        final isSel = _selectedFilterIndex == idx;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: () => setState(() => _selectedFilterIndex = idx),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                              decoration: BoxDecoration(
                                color: isSel ? AppConstants.primaryContainer : AppConstants.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                                border: Border.all(
                                  color: isSel ? AppConstants.primaryContainer : AppConstants.outlineCard,
                                ),
                              ),
                              child: Text(
                                _filters[idx],
                                style: TextStyle(
                                  color: isSel ? AppConstants.onPrimaryContainer : AppConstants.textSecondary,
                                  fontSize: 12,
                                  fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                  ],
                ),
              ),

              const SizedBox(height: 6),

              // Discussions List or Empty State
              Expanded(
                child: filteredItems.isEmpty
                    ? Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppConstants.surfaceContainerHigh,
                                  border: Border.all(color: AppConstants.outlineCard),
                                ),
                                child: Icon(
                                  _searchQuery.isNotEmpty
                                      ? Icons.search_off_rounded
                                      : Icons.upload_file_rounded,
                                  size: 34,
                                  color: _searchQuery.isNotEmpty
                                      ? AppConstants.textSecondary
                                      : AppConstants.primary,
                                ),
                              ),
                              const SizedBox(height: 18),
                              Text(
                                _searchQuery.isNotEmpty
                                    ? 'Nessuna discussione trovata'
                                    : 'Inizia la tua Prima Discussione',
                                style: const TextStyle(
                                  color: AppConstants.textPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _searchQuery.isNotEmpty
                                    ? 'Nessun risultato corrisponde alla ricerca "$_searchQuery".'
                                    : 'Non hai ancora registrato sessioni di studio precedenti.\nCarica il tuo primo file PDF o appunti per iniziare l\'interrogazione vocale.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: AppConstants.textSecondary,
                                  fontSize: 13,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 22),
                              if (_searchQuery.isNotEmpty)
                                OutlinedButton.icon(
                                  onPressed: () => setState(() => _searchQuery = ''),
                                  icon: const Icon(Icons.clear_rounded, size: 18),
                                  label: const Text('Reimposta ricerca'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppConstants.textPrimary,
                                    side: const BorderSide(color: AppConstants.outlineCard),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                                    ),
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                  ),
                                )
                              else
                                ElevatedButton.icon(
                                  onPressed: () {
                                    NewDiscussionModal.show(context);
                                  },
                                  icon: const Icon(Icons.upload_file_rounded, size: 18),
                                  label: const Text('Carica File & Inizia'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppConstants.primaryContainer,
                                    foregroundColor: AppConstants.onPrimary,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                                    ),
                                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                        itemCount: filteredItems.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, idx) {
                          final item = filteredItems[idx];
                          final isCur = item.isCurrent;
                          final isItemPaused = isCur && isPaused;

                          return Container(
                            decoration: BoxDecoration(
                              color: AppConstants.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(AppConstants.radiusCard),
                              border: Border.all(
                                color: isCur
                                    ? AppConstants.primaryContainer.withValues(alpha: 0.5)
                                    : AppConstants.outlineCard,
                                width: isCur ? 1.5 : 1,
                              ),
                            ),
                            child: InkWell(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => DiscussionDetailScreen(item: item)),
                                );
                              },
                              borderRadius: BorderRadius.circular(AppConstants.radiusCard),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Row 1: Iteration badge + Status badge + Date + Delete Button
                                    Wrap(
                                      alignment: WrapAlignment.spaceBetween,
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      spacing: 8,
                                      runSpacing: 6,
                                      children: [
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 4,
                                          crossAxisAlignment: WrapCrossAlignment.center,
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: AppConstants.surfaceContainerHigh,
                                                borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Icon(Icons.description_outlined, size: 12, color: AppConstants.primary),
                                                  const SizedBox(width: 4),
                                                  ConstrainedBox(
                                                    constraints: const BoxConstraints(maxWidth: 160),
                                                    child: Text(
                                                      item.filename.isNotEmpty ? item.filename : 'Documento #${item.iteration}',
                                                      style: const TextStyle(
                                                        color: AppConstants.primary,
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.w700,
                                                      ),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Builder(
                                              builder: (_) {
                                                final isItemCompleted = item.status == 'COMPLETED';
                                                final isItemInPausa = item.status == 'PAUSED' || (isCur && isItemPaused);
                                                final itemBadgeColor = isItemCompleted
                                                    ? AppConstants.success
                                                    : (isItemInPausa ? AppConstants.warning : AppConstants.primaryContainer);
                                                final itemBadgeLabel = isItemCompleted
                                                    ? 'Completata'
                                                    : (isItemInPausa ? 'In Pausa' : (isCur ? 'In Corso (Attiva)' : 'In Corso'));

                                                return Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: itemBadgeColor.withValues(alpha: 0.15),
                                                    borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                                                  ),
                                                  child: Text(
                                                    itemBadgeLabel,
                                                    style: TextStyle(
                                                      color: itemBadgeColor,
                                                      fontSize: 10.5,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                          ],
                                        ),
                                        Wrap(
                                          crossAxisAlignment: WrapCrossAlignment.center,
                                          spacing: 6,
                                          children: [
                                            if (item.timestamp.isNotEmpty)
                                              Text(
                                                item.timestamp.contains('T')
                                                    ? item.timestamp.split('T').first
                                                    : item.timestamp,
                                                style: const TextStyle(
                                                  color: AppConstants.textTertiary,
                                                  fontSize: 11.5,
                                                ),
                                              ),
                                            GestureDetector(
                                              onTap: () => _confirmDeleteDiscussion(item.id.isNotEmpty ? item.id : item.iteration, title: item.title),
                                              child: const Padding(
                                                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                                child: Icon(
                                                  Icons.delete_outline_rounded,
                                                  size: 18,
                                                  color: AppConstants.textTertiary,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),

                                    const SizedBox(height: 12),

                                    // Title
                                    Text(
                                      item.title,
                                      style: const TextStyle(
                                        color: AppConstants.textPrimary,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: -0.2,
                                      ),
                                    ),

                                    const SizedBox(height: 8),

                                    // Key Metrics (Turns & Mastery)
                                    Wrap(
                                      spacing: 12,
                                      runSpacing: 4,
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      children: [
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.chat_bubble_outline_rounded,
                                              size: 14,
                                              color: AppConstants.textSecondary,
                                            ),
                                            const SizedBox(width: 5),
                                            Text(
                                              '${item.turnsCompleted} scambi',
                                              style: const TextStyle(
                                                color: AppConstants.textSecondary,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (item.averageMastery != null)
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                item.averageMastery! >= 0.70
                                                    ? Icons.check_circle_outline
                                                    : Icons.speed_rounded,
                                                size: 14,
                                                color: item.averageMastery! >= 0.70
                                                    ? AppConstants.success
                                                    : AppConstants.warning,
                                              ),
                                              const SizedBox(width: 5),
                                              Text(
                                                '${(item.averageMastery! * 100).toInt()}% assimilato',
                                                style: TextStyle(
                                                  color: item.averageMastery! >= 0.70
                                                      ? AppConstants.success
                                                      : AppConstants.warning,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                      ],
                                    ),

                                    // Weak Concepts preview
                                    if (item.weakConcepts.isNotEmpty) ...[
                                      const SizedBox(height: 10),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 6,
                                        children: item.weakConcepts.take(3).map((c) {
                                          return Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: AppConstants.warning.withValues(alpha: 0.10),
                                              borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                                              border: Border.all(color: AppConstants.warning.withValues(alpha: 0.25)),
                                            ),
                                            child: Text(
                                              '⚠ ${c.replaceAll('_', ' ')}',
                                              style: const TextStyle(
                                                color: AppConstants.warning,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                    ],

                                    const SizedBox(height: 14),

                                    // Action bar inside card - using Wrap to eliminate RenderFlex overflows
                                    Wrap(
                                      alignment: WrapAlignment.end,
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      spacing: 8,
                                      runSpacing: 6,
                                      children: [
                                        TextButton.icon(
                                          onPressed: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(builder: (_) => DiscussionDetailScreen(item: item)),
                                            );
                                          },
                                          icon: const Icon(Icons.menu_book_rounded, size: 15, color: AppConstants.primary),
                                          label: const Text(
                                            'Sillabo & Trascrizione',
                                            style: TextStyle(color: AppConstants.primary, fontSize: 12, fontWeight: FontWeight.bold),
                                          ),
                                          style: TextButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            minimumSize: Size.zero,
                                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          ),
                                        ),
                                        Builder(
                                          builder: (_) {
                                            final isItemCompleted = item.status == 'COMPLETED';
                                            if (!isItemCompleted) {
                                              return ElevatedButton.icon(
                                                onPressed: () async {
                                                  final nav = Navigator.of(context);
                                                  await context.read<ExamProvider>().resumeExamAndConnect(courseId: item.id);
                                                  if (mounted) {
                                                    nav.push(
                                                      MaterialPageRoute(builder: (_) => const ExamScreen()),
                                                    );
                                                  }
                                                },
                                                icon: const Icon(Icons.play_arrow_rounded, size: 16),
                                                label: const Text('Riprendi'),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: AppConstants.primaryContainer,
                                                  foregroundColor: AppConstants.onPrimary,
                                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                                  minimumSize: Size.zero,
                                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                                                  ),
                                                ),
                                              );
                                            } else {
                                              return OutlinedButton.icon(
                                                onPressed: () async {
                                                  final nav = Navigator.of(context);
                                                  await context.read<ExamProvider>().startNewExam(adapt: true, courseId: item.id);
                                                  if (mounted) {
                                                    nav.push(
                                                      MaterialPageRoute(builder: (_) => const ExamScreen()),
                                                    );
                                                  }
                                                },
                                                icon: const Icon(Icons.replay_rounded, size: 15, color: AppConstants.secondary),
                                                label: const Text(
                                                  'Ripeti con adattamento',
                                                  style: TextStyle(color: AppConstants.secondary, fontSize: 12),
                                                ),
                                                style: OutlinedButton.styleFrom(
                                                  side: const BorderSide(color: AppConstants.secondaryContainer),
                                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                  minimumSize: Size.zero,
                                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                                                  ),
                                                ),
                                              );
                                            }
                                          },
                                        ),
                                      ],
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
        ),
      ),
    );
  }
}
