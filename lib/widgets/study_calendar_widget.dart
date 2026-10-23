import 'dart:math';
import 'package:flutter/material.dart';
import '../constants.dart';
import '../models/session_models.dart';

/// Helper class to compute general macro-analytics, consistency, and calendar data
/// from the session history without duplicating individual discussion items.
class StudyAnalytics {
  final Set<DateTime> allSessionDates;
  final Map<DateTime, List<SessionHistoryItem>> sessionsByDate;
  final int activeDaysCount;
  final int totalSessions;
  final int totalTurns;
  final double averageTurnsPerSession;
  final double overallMastery;
  final int currentStreak;
  final int bestStreak;
  final String peakHourLabel;
  final IconData peakHourIcon;
  final Map<int, int> weekdayCounts; // 1 = Lun, 7 = Dom
  final int weekdayMax;
  final int totalSubjects;

  StudyAnalytics._({
    required this.allSessionDates,
    required this.sessionsByDate,
    required this.activeDaysCount,
    required this.totalSessions,
    required this.totalTurns,
    required this.averageTurnsPerSession,
    required this.overallMastery,
    required this.currentStreak,
    required this.bestStreak,
    required this.peakHourLabel,
    required this.peakHourIcon,
    required this.weekdayCounts,
    required this.weekdayMax,
    required this.totalSubjects,
  });

  factory StudyAnalytics.fromHistory(List<SessionHistoryItem> history) {
    final sessionDatesSet = <DateTime>{};
    final byDate = <DateTime, List<SessionHistoryItem>>{};
    int turnsSum = 0;
    double masterySum = 0.0;
    int masteryCount = 0;
    final subjectsSet = <String>{};

    // Hour distribution buckets
    // 0: Notte (00-06), 1: Mattina (06-12), 2: Pomeriggio (12-18), 3: Sera (18-24)
    final hourBuckets = [0, 0, 0, 0];

    // Weekday counts: 1 (Mon) to 7 (Sun)
    final wCounts = <int, int>{1: 0, 2: 0, 3: 0, 4: 0, 5: 0, 6: 0, 7: 0};

    for (final item in history) {
      if (item.title.isNotEmpty) {
        subjectsSet.add(item.title);
      }
      turnsSum += item.turnsCompleted;
      if (item.averageMastery != null && item.averageMastery! > 0) {
        masterySum += item.averageMastery!;
        masteryCount++;
      }

      // Extract hours from timestamps
      for (final tsStr in [item.timestamp, item.updatedAt, item.createdAt]) {
        if (tsStr.isNotEmpty) {
          final parsed = DateTime.tryParse(tsStr);
          if (parsed != null) {
            final h = parsed.hour;
            if (h >= 6 && h < 12) {
              hourBuckets[1]++;
            } else if (h >= 12 && h < 18) {
              hourBuckets[2]++;
            } else if (h >= 18 && h < 24) {
              hourBuckets[3]++;
            } else {
              hourBuckets[0]++;
            }
          }
        }
      }

      // Group by calendar dates
      final itemDates = item.parsedSessionDates;
      for (final d in itemDates) {
        final norm = DateTime(d.year, d.month, d.day);
        sessionDatesSet.add(norm);
        byDate.putIfAbsent(norm, () => []).add(item);
        wCounts[norm.weekday] = (wCounts[norm.weekday] ?? 0) + 1;
      }
    }

    // Determine peak study hour label and icon
    int maxHourBucketIdx = 1; // default morning
    int maxHourCount = -1;
    for (int i = 0; i < 4; i++) {
      if (hourBuckets[i] > maxHourCount) {
        maxHourCount = hourBuckets[i];
        maxHourBucketIdx = i;
      }
    }

    String pLabel;
    IconData pIcon;
    if (history.isEmpty || maxHourCount == 0) {
      pLabel = 'Inizia la prima sessione';
      pIcon = Icons.schedule_rounded;
    } else {
      switch (maxHourBucketIdx) {
        case 1:
          pLabel = 'Mattina (06:00 - 12:00)';
          pIcon = Icons.wb_sunny_rounded;
          break;
        case 2:
          pLabel = 'Pomeriggio (12:00 - 18:00)';
          pIcon = Icons.wb_twilight_rounded;
          break;
        case 3:
          pLabel = 'Sera (18:00 - 24:00)';
          pIcon = Icons.nights_stay_rounded;
          break;
        default:
          pLabel = 'Notte (00:00 - 06:00)';
          pIcon = Icons.bedtime_rounded;
          break;
      }
    }

    // Calculate current streak & best streak
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    int currentStreak = 0;
    if (sessionDatesSet.contains(today)) {
      DateTime check = today;
      while (sessionDatesSet.contains(check)) {
        currentStreak++;
        check = check.subtract(const Duration(days: 1));
      }
    } else if (sessionDatesSet.contains(yesterday)) {
      DateTime check = yesterday;
      while (sessionDatesSet.contains(check)) {
        currentStreak++;
        check = check.subtract(const Duration(days: 1));
      }
    }

    // Best streak
    final sortedDates = sessionDatesSet.toList()..sort();
    int bestStreak = 0;
    int tempStreak = 0;
    DateTime? prev;
    for (final d in sortedDates) {
      if (prev == null) {
        tempStreak = 1;
      } else {
        final diff = d.difference(prev).inDays;
        if (diff == 1) {
          tempStreak++;
        } else if (diff > 1) {
          tempStreak = 1;
        }
      }
      prev = d;
      if (tempStreak > bestStreak) {
        bestStreak = tempStreak;
      }
    }
    if (currentStreak > bestStreak) {
      bestStreak = currentStreak;
    }

    int wMax = 0;
    for (final val in wCounts.values) {
      if (val > wMax) wMax = val;
    }

    final avgMastery = masteryCount > 0 ? (masterySum / masteryCount) : 0.0;
    final totalSess = history.length;
    final avgTurns = totalSess > 0 ? (turnsSum / totalSess) : 0.0;

    return StudyAnalytics._(
      allSessionDates: sessionDatesSet,
      sessionsByDate: byDate,
      activeDaysCount: sessionDatesSet.length,
      totalSessions: totalSess,
      totalTurns: turnsSum,
      averageTurnsPerSession: avgTurns,
      overallMastery: avgMastery,
      currentStreak: currentStreak,
      bestStreak: bestStreak,
      peakHourLabel: pLabel,
      peakHourIcon: pIcon,
      weekdayCounts: wCounts,
      weekdayMax: wMax,
      totalSubjects: subjectsSet.length,
    );
  }
}

/// Interactive monthly calendar widget highlighting session days and displaying daily summary
class StudyCalendarCard extends StatefulWidget {
  final StudyAnalytics analytics;
  final DateTime? initialSelectedDay;
  final ValueChanged<DateTime>? onDaySelected;

  const StudyCalendarCard({
    super.key,
    required this.analytics,
    this.initialSelectedDay,
    this.onDaySelected,
  });

  @override
  State<StudyCalendarCard> createState() => _StudyCalendarCardState();
}

class _StudyCalendarCardState extends State<StudyCalendarCard> {
  AppColors get colors => context.colors;
  late DateTime _viewMonth;
  late DateTime _selectedDay;

  static const List<String> _monthNames = [
    'Gennaio',
    'Febbraio',
    'Marzo',
    'Aprile',
    'Maggio',
    'Giugno',
    'Luglio',
    'Agosto',
    'Settembre',
    'Ottobre',
    'Novembre',
    'Dicembre',
  ];

  static const List<String> _weekDayLabels = [
    'LUN',
    'MAR',
    'MER',
    'GIO',
    'VEN',
    'SAB',
    'DOM',
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    _selectedDay = widget.initialSelectedDay ?? today;

    // If there are recorded sessions, default view to the month of the most recent session or current month
    if (widget.analytics.allSessionDates.isNotEmpty) {
      final latestDate = widget.analytics.allSessionDates.reduce((a, b) => a.isAfter(b) ? a : b);
      _viewMonth = DateTime(latestDate.year, latestDate.month, 1);
      _selectedDay = latestDate;
    } else {
      _viewMonth = DateTime(now.year, now.month, 1);
    }
  }

  void _previousMonth() {
    setState(() {
      _viewMonth = DateTime(_viewMonth.year, _viewMonth.month - 1, 1);
    });
  }

  void _nextMonth() {
    setState(() {
      _viewMonth = DateTime(_viewMonth.year, _viewMonth.month + 1, 1);
    });
  }

  void _goToToday() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    setState(() {
      _viewMonth = DateTime(today.year, today.month, 1);
      _selectedDay = today;
    });
    widget.onDaySelected?.call(today);
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _formatDateItalian(DateTime d) {
    const weekdays = [
      'Lunedì',
      'Martedì',
      'Mercoledì',
      'Giovedì',
      'Venerdì',
      'Sabato',
      'Domenica',
    ];
    final wName = weekdays[d.weekday - 1];
    final mName = _monthNames[d.month - 1];
    return '$wName ${d.day} $mName ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monthLabel = '${_monthNames[_viewMonth.month - 1]} ${_viewMonth.year}';
    final isCurrentMonth = _viewMonth.year == now.year && _viewMonth.month == now.month;

    // Number of days in view month
    final daysInMonth = DateTime(_viewMonth.year, _viewMonth.month + 1, 0).day;
    // 1 = Monday, 7 = Sunday
    final firstWeekday = DateTime(_viewMonth.year, _viewMonth.month, 1).weekday;
    final leadingSpaces = firstWeekday - 1; // 0 for Monday

    // Sessions for currently selected day
    final normalizedSelected = DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day);
    final daySessions = widget.analytics.sessionsByDate[normalizedSelected] ?? [];

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppConstants.radiusCard),
        border: Border.all(color: colors.outlineCard),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Title + Month Switcher + Oggi Button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colors.primaryContainer.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.calendar_month_rounded,
                        color: colors.primaryContainer,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Calendario Sessioni',
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                            ),
                          ),
                          Text(
                            monthLabel,
                            style: TextStyle(
                              color: colors.primary,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!isCurrentMonth)
                    InkWell(
                      onTap: _goToToday,
                      borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                          border: Border.all(color: colors.outlineCard),
                        ),
                        child: Text(
                          'Oggi',
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  IconButton(
                    icon: Icon(Icons.chevron_left_rounded, color: colors.textSecondary, size: 22),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    onPressed: _previousMonth,
                    tooltip: 'Mese precedente',
                  ),
                  IconButton(
                    icon: Icon(Icons.chevron_right_rounded, color: colors.textSecondary, size: 22),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    onPressed: _nextMonth,
                    tooltip: 'Mese successivo',
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Weekday Labels
          Row(
            children: _weekDayLabels.map((lbl) {
              final isWeekend = lbl == 'SAB' || lbl == 'DOM';
              return Expanded(
                child: Center(
                  child: Text(
                    lbl,
                    style: TextStyle(
                      color: isWeekend
                          ? colors.textSecondary.withValues(alpha: 0.6)
                          : colors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 8),
          Divider(color: colors.outline, height: 1),
          const SizedBox(height: 8),

          // Days Grid
          LayoutBuilder(
            builder: (context, constraints) {
              final cellWidth = constraints.maxWidth / 7;
              final totalCells = leadingSpaces + daysInMonth;
              final rowCount = (totalCells / 7).ceil();

              return Column(
                children: List.generate(rowCount, (rowIdx) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: List.generate(7, (colIdx) {
                        final cellIdx = rowIdx * 7 + colIdx;
                        final dayNumber = cellIdx - leadingSpaces + 1;

                        if (cellIdx < leadingSpaces || dayNumber > daysInMonth) {
                          return SizedBox(width: cellWidth, height: 38);
                        }

                        final dayDate = DateTime(_viewMonth.year, _viewMonth.month, dayNumber);
                        final hasSession = widget.analytics.allSessionDates.contains(dayDate);
                        final isSelected = _isSameDay(dayDate, _selectedDay);
                        final isTodayDay = _isSameDay(dayDate, today);
                        final sessionsCount = widget.analytics.sessionsByDate[dayDate]?.length ?? 0;

                        return SizedBox(
                          width: cellWidth,
                          height: 38,
                          child: InkWell(
                            onTap: () {
                              setState(() => _selectedDay = dayDate);
                              widget.onDaySelected?.call(dayDate);
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              margin: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? colors.primaryContainer
                                    : (hasSession
                                        ? colors.primaryContainer.withValues(alpha: 0.20)
                                        : Colors.transparent),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isSelected
                                      ? colors.primaryGlow
                                      : (isTodayDay
                                          ? colors.primary.withValues(alpha: 0.6)
                                          : (hasSession
                                              ? colors.primaryContainer.withValues(alpha: 0.45)
                                              : Colors.transparent)),
                                  width: isSelected || isTodayDay ? 1.5 : 1,
                                ),
                              ),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Text(
                                    '$dayNumber',
                                    style: TextStyle(
                                      color: isSelected
                                          ? colors.onPrimaryContainer
                                          : (hasSession
                                              ? colors.primaryGlow
                                              : (isTodayDay
                                                  ? colors.textPrimary
                                                  : colors.textSecondary)),
                                      fontSize: 12.5,
                                      fontWeight: isSelected || hasSession || isTodayDay
                                          ? FontWeight.w700
                                          : FontWeight.normal,
                                    ),
                                  ),
                                  if (hasSession && !isSelected)
                                    Positioned(
                                      bottom: 3,
                                      child: Container(
                                        width: sessionsCount > 1 ? 12 : 4.5,
                                        height: 4.5,
                                        decoration: BoxDecoration(
                                          color: colors.primaryContainer,
                                          borderRadius: BorderRadius.circular(3),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  );
                }),
              );
            },
          ),

          const SizedBox(height: 14),

          // Legend
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildLegendDot(
                color: colors.primaryContainer,
                label: 'Sessione svolta',
              ),
              const SizedBox(width: 16),
              _buildLegendOutline(
                borderColor: colors.primary.withValues(alpha: 0.8),
                label: 'Oggi',
              ),
            ],
          ),

          const SizedBox(height: 14),
          Divider(color: colors.outline, height: 1),
          const SizedBox(height: 14),

          // Daily Detail Card for Selected Date
          _buildDailySummaryCard(
            selectedDate: normalizedSelected,
            sessions: daySessions,
            formattedDate: _formatDateItalian(normalizedSelected),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendDot({required Color color, required String label}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(color: colors.textSecondary, fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildLegendOutline({required Color borderColor, required String label}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: borderColor, width: 1.5),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(color: colors.textSecondary, fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildDailySummaryCard({
    required DateTime selectedDate,
    required List<SessionHistoryItem> sessions,
    required String formattedDate,
  }) {
    final hasActivity = sessions.isNotEmpty;
    final totalTurnsDay = sessions.fold<int>(0, (sum, item) => sum + item.turnsCompleted);

    final subjects = sessions
        .map((s) => s.title.replaceAll(RegExp(r'\(.*\)'), '').trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();

    double avgMasteryDay = 0.0;
    int masteryCount = 0;
    for (final s in sessions) {
      if (s.averageMastery != null && s.averageMastery! > 0) {
        avgMasteryDay += s.averageMastery!;
        masteryCount++;
      }
    }
    if (masteryCount > 0) {
      avgMasteryDay /= masteryCount;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: hasActivity
            ? colors.surfaceContainerHigh.withValues(alpha: 0.7)
            : colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppConstants.radiusSm),
        border: Border.all(
          color: hasActivity
              ? colors.primaryContainer.withValues(alpha: 0.3)
              : colors.outlineCard,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  formattedDate,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: hasActivity
                      ? colors.success.withValues(alpha: 0.16)
                      : colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                ),
                child: Text(
                  hasActivity ? '${sessions.length} sessioni' : 'Nessuna attività',
                  style: TextStyle(
                    color: hasActivity ? colors.success : colors.textTertiary,
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (hasActivity) ...[
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                _buildMiniMetric(
                  icon: Icons.chat_bubble_outline_rounded,
                  label: '$totalTurnsDay scambi',
                ),
                if (avgMasteryDay > 0)
                  _buildMiniMetric(
                    icon: Icons.speed_rounded,
                    label: '${(avgMasteryDay * 100).toInt()}% padronanza',
                  ),
                _buildMiniMetric(
                  icon: Icons.folder_open_rounded,
                  label: '${subjects.length} ${subjects.length == 1 ? 'materia' : 'materie'}',
                ),
              ],
            ),
            if (subjects.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Argomenti affrontati: ${subjects.join(', ')}',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 11.5,
                  height: 1.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ] else ...[
            Text(
              'Nessuna simulazione vocale completata in questa giornata.\nConsulta gli altri giorni evidenziati sul calendario per analizzare il ritmo di studio.',
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 11.5,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMiniMetric({required IconData icon, required String label}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: colors.primary),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Study streak and consistency hero card
class StudyStreakCard extends StatelessWidget {
  final StudyAnalytics analytics;

  const StudyStreakCard({super.key, required this.analytics});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppConstants.radiusCard),
        border: Border.all(color: colors.outlineCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFFF97316).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.local_fire_department_rounded,
                  color: Color(0xFFFB923C),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Costanza di Studio',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      analytics.currentStreak > 0
                          ? 'Ottimo ritmo di preparazione!'
                          : 'Fai una sessione per avviare la serie',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: (analytics.currentStreak > 0 ? const Color(0xFFF97316) : colors.surfaceContainerHighest)
                        .withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                  ),
                  child: Text(
                    'Record: ${analytics.bestStreak} ${analytics.bestStreak == 1 ? 'giorno' : 'giorni'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: analytics.currentStreak > 0 ? const Color(0xFFFB923C) : colors.textTertiary,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Big Streak display + Active days
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            '${analytics.currentStreak}',
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'giorni di fila',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colors.textSecondary,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Serie attiva attuale',
                        style: TextStyle(color: colors.textTertiary, fontSize: 10.5),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            '${analytics.activeDaysCount}',
                            style: TextStyle(
                              color: colors.primary,
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'giorni totali',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colors.textSecondary,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Giorni di studio registrati',
                        style: TextStyle(color: colors.textTertiary, fontSize: 10.5),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Learning volume and peak study hours overview grid
class StudyHabitsGrid extends StatelessWidget {
  final StudyAnalytics analytics;

  const StudyHabitsGrid({super.key, required this.analytics});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Abitudini & Volume di Apprendimento',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildMetricTile(
                colors: colors,
                icon: Icons.forum_rounded,
                iconColor: colors.primaryContainer,
                title: '${analytics.totalTurns}',
                subtitle: 'Scambi vocali totali',
                caption: 'Volume dialogo AI',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildMetricTile(
                colors: colors,
                icon: Icons.psychology_rounded,
                iconColor: colors.secondary,
                title: analytics.averageTurnsPerSession.toStringAsFixed(1),
                subtitle: 'Scambi medi / sessione',
                caption: 'Profondità media',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildMetricTile(
                colors: colors,
                icon: Icons.school_rounded,
                iconColor: colors.success,
                title: '${analytics.totalSessions}',
                subtitle: 'Sessioni complessive',
                caption: 'Totale simulazioni',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildMetricTile(
                colors: colors,
                icon: analytics.peakHourIcon,
                iconColor: const Color(0xFFFBBF24),
                title: analytics.peakHourLabel.split('(').first.trim(),
                subtitle: 'Fascia più produttiva',
                caption: analytics.peakHourLabel.contains('(')
                    ? '(${analytics.peakHourLabel.split('(').last}'
                    : 'Orario preferito',
                isCompactTitle: true,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricTile({
    required AppColors colors,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String caption,
    bool isCompactTitle = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppConstants.radiusSm),
        border: Border.all(color: colors.outlineCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: iconColor, size: 18),
              ),
              Flexible(
                child: Text(
                  caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textTertiary,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: isCompactTitle ? 15 : 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Visual distribution of study activity across days of the week (Lun - Dom)
class WeeklyStudyRhythmCard extends StatelessWidget {
  final StudyAnalytics analytics;

  const WeeklyStudyRhythmCard({super.key, required this.analytics});

  static const List<String> _labels = ['LUN', 'MAR', 'MER', 'GIO', 'VEN', 'SAB', 'DOM'];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final maxCount = max(analytics.weekdayMax, 1);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppConstants.radiusCard),
        border: Border.all(color: colors.outlineCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bar_chart_rounded, color: colors.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: Text(
                  'Ritmo Settimanale di Studio',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                flex: 2,
                child: Text(
                  'Distribuzione sessioni',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    color: colors.textSecondary.withValues(alpha: 0.8),
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          // 7 Bars for Monday through Sunday
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(7, (idx) {
              final dayIndex = idx + 1; // 1 to 7
              final count = analytics.weekdayCounts[dayIndex] ?? 0;
              final ratio = count / maxCount;
              final isMax = count > 0 && count == analytics.weekdayMax;

              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        count > 0 ? '$count' : '',
                        style: TextStyle(
                          color: isMax ? colors.primaryGlow : colors.textSecondary,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        height: 70,
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          width: double.infinity,
                          height: max(70 * ratio, 6.0),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: isMax
                                  ? [colors.primaryContainer, colors.primaryGlow]
                                  : (count > 0
                                      ? [
                                          colors.surfaceContainerHigh,
                                          colors.primaryContainer.withValues(alpha: 0.6)
                                        ]
                                      : [
                                          colors.surfaceContainerLowest,
                                          colors.surfaceContainerHigh.withValues(alpha: 0.5)
                                        ]),
                            ),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _labels[idx],
                        style: TextStyle(
                          color: isMax ? colors.primary : colors.textSecondary,
                          fontSize: 10.5,
                          fontWeight: isMax ? FontWeight.bold : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}
