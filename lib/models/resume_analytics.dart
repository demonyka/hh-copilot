import 'package:flutter/material.dart';

import '../theme/hh_theme.dart';

/// Категория отклика по МЕТКЕ hh.ru (`lastState`).
///
/// ВНИМАНИЕ: «Приглашения» здесь — это метка hh.ru (работодатель нажал
/// «Пригласить»/назначил статус). Это НЕ то же, что раздел «Собеседования» —
/// там мы сами определяем реальные приглашения через ИИ по тексту сообщений.
enum NegotiationCategory { invitation, rejection, pending }

extension NegotiationCategoryX on NegotiationCategory {
  String get label {
    switch (this) {
      case NegotiationCategory.invitation:
        return 'Приглашения';
      case NegotiationCategory.rejection:
        return 'Отказы';
      case NegotiationCategory.pending:
        return 'Ожидание';
    }
  }

  Color get color {
    switch (this) {
      case NegotiationCategory.invitation:
        return HhColors.green;
      case NegotiationCategory.rejection:
        return HhColors.red;
      case NegotiationCategory.pending:
        return HhColors.textMuted;
    }
  }

  /// Положительный исход (для конверсии).
  bool get isPositive => this == NegotiationCategory.invitation;
}

/// Категоризация метки hh.ru (`lastState`). Всё, что hh отметил как
/// приглашение/интервью/оффер/приём, считаем «Приглашением» (метка hh).
NegotiationCategory categorizeState(String state) {
  final s = state.toUpperCase();
  if (s.startsWith('DISCARD')) return NegotiationCategory.rejection;
  if (s == 'INVITATION' ||
      s.contains('INTERVIEW') ||
      s == 'ASSESSMENT' ||
      s == 'OFFER' ||
      s == 'HIRED') {
    return NegotiationCategory.invitation;
  }
  // RESPONSE, CONSIDERATION, RESUME_VIEWED и прочее — ждём ответа.
  return NegotiationCategory.pending;
}

/// Один отклик (переговор) на вакансию.
class Negotiation {
  const Negotiation({required this.state, required this.createdAt});

  final String state;
  final DateTime createdAt;

  NegotiationCategory get category => categorizeState(state);
}

/// 7-дневная статистика резюме (данные самого hh.ru).
class ResumeStatistics {
  const ResumeStatistics({
    required this.periodDays,
    required this.searchShows,
    required this.views,
    required this.viewsNew,
    required this.invitations,
    required this.invitationsNew,
  });

  final int periodDays;
  final int searchShows;
  final int views;
  final int viewsNew;
  final int invitations;
  final int invitationsNew;
}

/// Окно, за которое считаем отклики.
enum AnalyticsPeriod { day, week, month, all }

extension AnalyticsPeriodX on AnalyticsPeriod {
  String get label {
    switch (this) {
      case AnalyticsPeriod.day:
        return 'День';
      case AnalyticsPeriod.week:
        return 'Неделя';
      case AnalyticsPeriod.month:
        return 'Месяц';
      case AnalyticsPeriod.all:
        return 'Всё время';
    }
  }

  /// Число дней окна; null — всё время.
  int? get days {
    switch (this) {
      case AnalyticsPeriod.day:
        return 1;
      case AnalyticsPeriod.week:
        return 7;
      case AnalyticsPeriod.month:
        return 30;
      case AnalyticsPeriod.all:
        return null;
    }
  }
}

/// Счётчик откликов за один день (для графика по времени).
class DailyCount {
  const DailyCount(this.day, this.count);
  final DateTime day;
  final int count;
}

/// Готовая аналитика по одному резюме.
class ResumeAnalytics {
  ResumeAnalytics({
    required this.resumeHash,
    required this.stats,
    required this.negotiations,
    required this.totalResponsesAllTime,
    required this.fetchedPages,
    required this.capped,
    required this.now,
  });

  final String resumeHash;

  /// 7-дневная статистика hh.ru (может отсутствовать).
  final ResumeStatistics? stats;

  /// Загруженные отклики (по убыванию даты), возможно, только за недавний период.
  final List<Negotiation> negotiations;

  /// Всего откликов за всё время (по данным hh.ru).
  final int totalResponsesAllTime;

  final int fetchedPages;

  /// true — загружены не все отклики (обрезано по лимиту страниц).
  final bool capped;

  /// Момент расчёта (передаётся снаружи, т.к. в UI нельзя дергать now напрямую).
  final DateTime now;

  bool get isEmpty => negotiations.isEmpty && stats == null;

  /// Отклики за период (null days — все загруженные).
  List<Negotiation> inPeriod(AnalyticsPeriod period) {
    final days = period.days;
    if (days == null) return negotiations;
    final cutoff = now.subtract(Duration(days: days));
    return negotiations.where((n) => n.createdAt.isAfter(cutoff)).toList();
  }

  /// Сколько откликов за период. Для «всё время» берём точное число hh.ru.
  int responsesIn(AnalyticsPeriod period) {
    if (period == AnalyticsPeriod.all) {
      return totalResponsesAllTime > 0
          ? totalResponsesAllTime
          : negotiations.length;
    }
    return inPeriod(period).length;
  }

  Map<NegotiationCategory, int> categoryCounts(AnalyticsPeriod period) {
    final counts = <NegotiationCategory, int>{
      for (final c in NegotiationCategory.values) c: 0,
    };
    for (final n in inPeriod(period)) {
      counts[n.category] = (counts[n.category] ?? 0) + 1;
    }
    return counts;
  }

  int categoryCount(AnalyticsPeriod period, NegotiationCategory category) =>
      categoryCounts(period)[category] ?? 0;

  int positiveCount(AnalyticsPeriod period) => inPeriod(period)
      .where((n) => n.category.isPositive)
      .length;

  /// Конверсия «отклик → приглашение/собеседование/оффер», %.
  double invitationRate(AnalyticsPeriod period) {
    final list = inPeriod(period);
    if (list.isEmpty) return 0;
    return positiveCount(period) / list.length * 100;
  }

  /// Доля отказов, %.
  double rejectionRate(AnalyticsPeriod period) {
    final list = inPeriod(period);
    if (list.isEmpty) return 0;
    final rejected =
        list.where((n) => n.category == NegotiationCategory.rejection).length;
    return rejected / list.length * 100;
  }

  /// Ряд «откликов по дням» за последние [days] дней.
  List<DailyCount> dailySeries(int days) {
    final today = DateTime(now.year, now.month, now.day);
    final buckets = <DateTime, int>{};
    for (int i = days - 1; i >= 0; i--) {
      buckets[today.subtract(Duration(days: i))] = 0;
    }
    for (final n in negotiations) {
      final d = DateTime(n.createdAt.year, n.createdAt.month, n.createdAt.day);
      if (buckets.containsKey(d)) buckets[d] = buckets[d]! + 1;
    }
    final entries = buckets.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return entries.map((e) => DailyCount(e.key, e.value)).toList();
  }
}
