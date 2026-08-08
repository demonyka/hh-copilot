import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/hh_profile.dart';
import '../models/resume_analytics.dart';
import '../state/app_state.dart';
import '../theme/hh_theme.dart';

/// Экран аналитики по одному резюме: KPI, круговая диаграмма состояний,
/// график откликов по дням.
class ResumeAnalyticsScreen extends StatefulWidget {
  const ResumeAnalyticsScreen({super.key});

  @override
  State<ResumeAnalyticsScreen> createState() => _ResumeAnalyticsScreenState();
}

class _ResumeAnalyticsScreenState extends State<ResumeAnalyticsScreen> {
  AnalyticsPeriod _period = AnalyticsPeriod.month;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final resume = appState.selectedResume;

    if (resume == null) {
      return const Center(
        child: Text(
          'Нет резюме для аналитики',
          style: TextStyle(color: HhColors.textSecondary),
        ),
      );
    }

    final analytics = appState.analyticsFor(resume.hash);

    return Column(
      children: [
        if (appState.isRefreshing || appState.analyticsLoading)
          const LinearProgressIndicator(minHeight: 2.5)
        else
          const SizedBox(height: 2.5),
        Expanded(
          child: _buildBody(context, appState, resume, analytics),
        ),
      ],
    );
  }

  Widget _buildBody(
    BuildContext context,
    AppState appState,
    HhResume resume,
    ResumeAnalytics? analytics,
  ) {
    if (analytics == null) {
      if (appState.analyticsError != null) {
        return _ErrorState(
          message: appState.analyticsError!,
          onRetry: () => appState.loadAnalytics(resume, force: true),
        );
      }
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2.6),
            ),
            SizedBox(height: 16),
            Text('Загружаем аналитику…',
                style: TextStyle(color: HhColors.textSecondary)),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _PeriodSelector(
                        period: _period,
                        onChanged: (p) => setState(() => _period = p),
                      ),
                    ),
                    _HhLink(resume: resume),
                  ],
                ),
                const SizedBox(height: 20),
                _KpiRow(analytics: analytics, period: _period),
                const SizedBox(height: 16),
                if (analytics.stats != null) ...[
                  _ResumeStatsCard(stats: analytics.stats!),
                  const SizedBox(height: 16),
                ],
                _ChartsRow(analytics: analytics, period: _period),
                const SizedBox(height: 16),
                _ResponsesChartCard(analytics: analytics),
                if (analytics.capped) ...[
                  const SizedBox(height: 16),
                  _CappedNote(count: analytics.negotiations.length),
                ],
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HhLink extends StatelessWidget {
  const _HhLink({required this.resume});

  final HhResume resume;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: resume.hash.isEmpty
          ? null
          : () => launchUrl(
                Uri.parse('${AppState.baseUrl}/resume/${resume.hash}'),
                mode: LaunchMode.externalApplication,
              ),
      icon: const Icon(Icons.open_in_new, size: 16),
      label: const Text('Открыть на hh.ru'),
    );
  }
}

class _PeriodSelector extends StatelessWidget {
  const _PeriodSelector({required this.period, required this.onChanged});

  final AnalyticsPeriod period;
  final ValueChanged<AnalyticsPeriod> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: AnalyticsPeriod.values.map((p) {
        final selected = p == period;
        return ChoiceChip(
          label: Text(p.label),
          selected: selected,
          showCheckmark: false,
          onSelected: (_) => onChanged(p),
          backgroundColor: HhColors.surface,
          selectedColor: HhColors.red,
          side: BorderSide(
            color: selected ? HhColors.red : HhColors.border,
          ),
          labelStyle: TextStyle(
            color: selected ? Colors.white : HhColors.textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        );
      }).toList(),
    );
  }
}

class _KpiRow extends StatelessWidget {
  const _KpiRow({required this.analytics, required this.period});

  final ResumeAnalytics analytics;
  final AnalyticsPeriod period;

  @override
  Widget build(BuildContext context) {
    final responses = analytics.responsesIn(period);
    final invitations =
        analytics.categoryCount(period, NegotiationCategory.invitation);
    final rejections =
        analytics.categoryCount(period, NegotiationCategory.rejection);

    final cards = <Widget>[
      _KpiCard(
        label: 'Отклики',
        value: '$responses',
        icon: Icons.send_outlined,
        color: HhColors.textPrimary,
        hint: period == AnalyticsPeriod.all ? 'за всё время' : period.label.toLowerCase(),
      ),
      _KpiCard(
        label: 'Приглашения',
        value: '$invitations',
        icon: Icons.check_circle_outline,
        color: HhColors.green,
        hint: 'метка hh',
      ),
      _KpiCard(
        label: 'Отказы',
        value: '$rejections',
        icon: Icons.cancel_outlined,
        color: HhColors.red,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns =
            constraints.maxWidth > 720 ? cards.length : 2;
        final spacing = 16.0;
        final itemWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children:
              cards.map((c) => SizedBox(width: itemWidth, child: c)).toList(),
        );
      },
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.hint,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: HhColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: HhColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 19, color: color),
              ),
              if (hint != null) ...[
                const Spacer(),
                Text(
                  hint!,
                  style: const TextStyle(
                      fontSize: 11, color: HhColors.textMuted),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          Text(
            value,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: HhColors.textPrimary,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 13, color: HhColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _ResumeStatsCard extends StatelessWidget {
  const _ResumeStatsCard({required this.stats});

  final ResumeStatistics stats;

  @override
  Widget build(BuildContext context) {
    Widget metric(String label, int value, {int? delta}) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('$value',
                  style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: HhColors.textPrimary)),
              if (delta != null && delta > 0) ...[
                const SizedBox(width: 6),
                Text('+$delta',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: HhColors.green)),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text(label,
              style:
                  const TextStyle(fontSize: 13, color: HhColors.textSecondary)),
        ],
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: HhColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: HhColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.visibility_outlined,
                  size: 18, color: HhColors.textSecondary),
              const SizedBox(width: 8),
              Text(
                'Статистика hh.ru за ${stats.periodDays} дней',
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: HhColors.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 48,
            runSpacing: 16,
            children: [
              metric('Показы в поиске', stats.searchShows),
              metric('Просмотры', stats.views, delta: stats.viewsNew),
              metric('Приглашения', stats.invitations,
                  delta: stats.invitationsNew),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChartsRow extends StatelessWidget {
  const _ChartsRow({required this.analytics, required this.period});

  final ResumeAnalytics analytics;
  final AnalyticsPeriod period;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > 720;
        final pie = _StatePieCard(analytics: analytics, period: period);
        final kpi = _ConversionCard(analytics: analytics, period: period);
        if (wide) {
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 3, child: pie),
                const SizedBox(width: 16),
                Expanded(flex: 2, child: kpi),
              ],
            ),
          );
        }
        return Column(children: [pie, const SizedBox(height: 16), kpi]);
      },
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: HhColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: HhColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: HhColors.textPrimary)),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _StatePieCard extends StatelessWidget {
  const _StatePieCard({required this.analytics, required this.period});

  final ResumeAnalytics analytics;
  final AnalyticsPeriod period;

  @override
  Widget build(BuildContext context) {
    final counts = analytics.categoryCounts(period);
    final total = counts.values.fold<int>(0, (a, b) => a + b);
    final present = NegotiationCategory.values
        .where((c) => (counts[c] ?? 0) > 0)
        .toList();

    return _ChartCard(
      title: 'Соотношение исходов',
      child: total == 0
          ? const _EmptyChart(text: 'Нет откликов за период')
          : Row(
              children: [
                SizedBox(
                  width: 160,
                  height: 160,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      PieChart(
                        PieChartData(
                          sectionsSpace: 2,
                          centerSpaceRadius: 52,
                          sections: present.map((c) {
                            final v = counts[c]!;
                            return PieChartSectionData(
                              value: v.toDouble(),
                              color: c.color,
                              radius: 22,
                              showTitle: false,
                            );
                          }).toList(),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('$total',
                              style: const TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
                                  color: HhColors.textPrimary)),
                          const Text('откликов',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: HhColors.textSecondary)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: present.map((c) {
                      final v = counts[c]!;
                      final pct = total == 0 ? 0 : (v / total * 100).round();
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                  color: c.color, shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(c.label,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      color: HhColors.textPrimary)),
                            ),
                            Text('$v · $pct%',
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: HhColors.textSecondary)),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
    );
  }
}

class _ConversionCard extends StatelessWidget {
  const _ConversionCard({required this.analytics, required this.period});

  final ResumeAnalytics analytics;
  final AnalyticsPeriod period;

  @override
  Widget build(BuildContext context) {
    final invRate = analytics.invitationRate(period);
    final rejRate = analytics.rejectionRate(period);

    Widget gauge(String label, double pct, Color color) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 13, color: HhColors.textSecondary)),
              Text('${pct.toStringAsFixed(0)}%',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: color)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: (pct / 100).clamp(0, 1),
              minHeight: 8,
              backgroundColor: HhColors.surfaceMuted,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      );
    }

    return _ChartCard(
      title: 'Конверсия',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          gauge('Отклик → приглашение', invRate, HhColors.green),
          const SizedBox(height: 18),
          gauge('Доля отказов', rejRate, HhColors.red),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _ResponsesChartCard extends StatelessWidget {
  const _ResponsesChartCard({required this.analytics});

  final ResumeAnalytics analytics;

  @override
  Widget build(BuildContext context) {
    const days = 30;
    final series = analytics.dailySeries(days);
    final maxCount = series.fold<int>(0, (m, d) => d.count > m ? d.count : m);
    final maxY = (maxCount == 0 ? 1 : maxCount).toDouble();

    return _ChartCard(
      title: 'Отклики по дням (30 дней)',
      child: SizedBox(
        height: 200,
        child: maxCount == 0
            ? const _EmptyChart(text: 'Нет откликов за 30 дней')
            : BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceBetween,
                  maxY: maxY * 1.15,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: (maxY / 3).ceilToDouble(),
                    getDrawingHorizontalLine: (_) => const FlLine(
                        color: HhColors.border, strokeWidth: 1),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        interval: (maxY / 3).ceilToDouble(),
                        getTitlesWidget: (value, meta) => Text(
                          value.toInt().toString(),
                          style: const TextStyle(
                              fontSize: 10, color: HhColors.textMuted),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 22,
                        interval: 1,
                        getTitlesWidget: (value, meta) {
                          final i = value.toInt();
                          if (i < 0 || i >= series.length) {
                            return const SizedBox.shrink();
                          }
                          // подписываем примерно каждый 5-й день
                          if (i % 5 != 0) return const SizedBox.shrink();
                          final d = series[i].day;
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text('${d.day}.${d.month}',
                                style: const TextStyle(
                                    fontSize: 10, color: HhColors.textMuted)),
                          );
                        },
                      ),
                    ),
                  ),
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (group, gi, rod, ri) {
                        final d = series[group.x].day;
                        return BarTooltipItem(
                          '${d.day}.${d.month}\n${rod.toY.toInt()} откл.',
                          const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600),
                        );
                      },
                    ),
                  ),
                  barGroups: [
                    for (int i = 0; i < series.length; i++)
                      BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: series[i].count.toDouble(),
                            color: HhColors.red,
                            width: 6,
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(3)),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _EmptyChart extends StatelessWidget {
  const _EmptyChart({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 140,
      child: Center(
        child: Text(text,
            style: const TextStyle(color: HhColors.textMuted, fontSize: 13)),
      ),
    );
  }
}

class _CappedNote extends StatelessWidget {
  const _CappedNote({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.info_outline, size: 16, color: HhColors.textMuted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Загружены последние $count откликов. Данные по состояниям и графику '
            'основаны на них; всего откликов показано отдельной цифрой.',
            style: const TextStyle(fontSize: 12, color: HhColors.textMuted),
          ),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 40, color: HhColors.textMuted),
          const SizedBox(height: 12),
          Text(message,
              style: const TextStyle(color: HhColors.textSecondary)),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: onRetry, child: const Text('Повторить')),
        ],
      ),
    );
  }
}
