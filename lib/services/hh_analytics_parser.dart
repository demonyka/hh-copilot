import '../models/resume_analytics.dart';
import 'hh_profile_parser.dart';
import 'json_scan.dart';

/// Разбор аналитических данных hh.ru со страниц `/applicant/resumes`
/// (статистика резюме) и `/applicant/negotiations` (отклики).
///
/// Структуры подтверждены разведкой на живом hh.ru:
/// - `applicantResumesStatistics.resumes[<id>].statistics` — 7-дневная статистика;
/// - `applicantResumesStatistics.recommendationsForAllResumes.responsesCount` — всего откликов;
/// - `applicantNegotiations.topicList[]` — отклики с `lastState` и `creationTime`;
/// - `applicantNegotiations.paging.pages[]` — число страниц.
class HhAnalyticsParser {
  const HhAnalyticsParser._();

  /// 7-дневная статистика конкретного резюме (по его id) со страницы резюме.
  static ResumeStatistics? parseResumeStatistics(
    String resumesHtml,
    String resumeId,
  ) {
    final text = HhProfileParser.htmlUnescape(resumesHtml);
    final root = JsonScan.objectAfterKey(text, '"applicantResumesStatistics":');
    if (root == null) return null;
    final resumes = root['resumes'];
    if (resumes is! Map) return null;
    final entry = resumes[resumeId];
    final stats = entry is Map ? entry['statistics'] : null;
    if (stats is! Map) return null;

    int count(String key) {
      final v = stats[key];
      return v is Map ? JsonScan.asInt(v['count']) : 0;
    }

    int countNew(String key) {
      final v = stats[key];
      return v is Map ? JsonScan.asInt(v['countNew']) : 0;
    }

    return ResumeStatistics(
      periodDays: JsonScan.asInt(stats['periodDays']),
      searchShows: count('searchShows'),
      views: count('views'),
      viewsNew: countNew('views'),
      invitations: count('invitations'),
      invitationsNew: countNew('invitations'),
    );
  }

  /// Всего откликов за всё время (по данным hh.ru).
  static int parseTotalResponses(String resumesHtml) {
    final text = HhProfileParser.htmlUnescape(resumesHtml);
    final root = JsonScan.objectAfterKey(text, '"applicantResumesStatistics":');
    final rec = root?['recommendationsForAllResumes'];
    if (rec is Map) return JsonScan.asInt(rec['responsesCount']);
    return 0;
  }

  /// Отклики с одной страницы `/applicant/negotiations`.
  static List<Negotiation> parseNegotiationsPage(String html) {
    final text = HhProfileParser.htmlUnescape(html);
    final root = JsonScan.objectAfterKey(text, '"applicantNegotiations":');
    final list = root?['topicList'];
    if (list is! List) return const [];

    final result = <Negotiation>[];
    for (final item in list) {
      if (item is! Map) continue;
      final state = item['lastState']?.toString() ??
          item['initialState']?.toString() ??
          '';
      final created = _parseDate(item['creationTime']);
      if (created == null) continue;
      result.add(Negotiation(state: state, createdAt: created));
    }
    return result;
  }

  /// Число страниц откликов (из `paging.pages`).
  static int parseNegotiationPageCount(String html) {
    final text = HhProfileParser.htmlUnescape(html);
    final root = JsonScan.objectAfterKey(text, '"applicantNegotiations":');
    final paging = root?['paging'];
    if (paging is Map && paging['pages'] is List) {
      final pages = paging['pages'] as List;
      int maxPage = 0;
      for (final p in pages) {
        if (p is Map) {
          final pageNum = JsonScan.asInt(p['page']);
          if (pageNum > maxPage) maxPage = pageNum;
        }
      }
      return maxPage + 1; // страницы нумеруются с 0
    }
    return 1;
  }

  static DateTime? _parseDate(dynamic v) {
    if (v is String) return DateTime.tryParse(v)?.toLocal();
    if (v is int) {
      return DateTime.fromMillisecondsSinceEpoch(v).toLocal();
    }
    return null;
  }
}
