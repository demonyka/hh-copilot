import 'package:flutter_test/flutter_test.dart';
import 'package:hh_copilot/models/resume_analytics.dart';
import 'package:hh_copilot/services/hh_analytics_parser.dart';

void main() {
  // JSON как его отдаёт hh.ru: встроенный в HTML с экранированными кавычками.
  const rawJson =
      '{"applicantResumesStatistics":{'
      '"recommendationsForAllResumes":{"responsesCount":349},'
      '"resumes":{"274880922":{"statistics":{"periodDays":7,'
      '"searchShows":{"count":220},"views":{"count":226,"countNew":12},'
      '"invitations":{"count":9,"countNew":1}}}}},'
      '"applicantNegotiations":{"topicList":['
      '{"id":1,"lastState":"DISCARD","creationTime":"2026-08-06T02:09:59"},'
      '{"id":2,"lastState":"INTERVIEW","creationTime":"2026-08-05T12:47:53"},'
      '{"id":3,"initialState":"RESPONSE","creationTime":"2026-08-04T10:00:00"}'
      '],"paging":{"pages":[{"page":0},{"page":1},{"page":2}]}}}';

  String asHhPage(String json) {
    final escaped = json.replaceAll('"', '&#34;');
    return '<html><body><template>$escaped</template></body></html>';
  }

  final html = asHhPage(rawJson);

  group('HhAnalyticsParser', () {
    test('парсит 7-дневную статистику резюме', () {
      final stats = HhAnalyticsParser.parseResumeStatistics(html, '274880922');
      expect(stats, isNotNull);
      expect(stats!.periodDays, 7);
      expect(stats.searchShows, 220);
      expect(stats.views, 226);
      expect(stats.viewsNew, 12);
      expect(stats.invitations, 9);
      expect(stats.invitationsNew, 1);
    });

    test('парсит общее число откликов', () {
      expect(HhAnalyticsParser.parseTotalResponses(html), 349);
    });

    test('парсит отклики страницы (lastState + дата, с фолбэком)', () {
      final items = HhAnalyticsParser.parseNegotiationsPage(html);
      expect(items, hasLength(3));
      expect(items[0].state, 'DISCARD');
      expect(items[0].category, NegotiationCategory.rejection);
      expect(items[1].category, NegotiationCategory.interview);
      // третий без lastState — берём initialState
      expect(items[2].state, 'RESPONSE');
      expect(items[2].category, NegotiationCategory.pending);
    });

    test('считает число страниц', () {
      expect(HhAnalyticsParser.parseNegotiationPageCount(html), 3);
    });
  });

  group('ResumeAnalytics', () {
    ResumeAnalytics build() => ResumeAnalytics(
          resumeHash: 'h',
          stats: null,
          negotiations: [
            Negotiation(state: 'DISCARD', createdAt: DateTime(2026, 8, 6)),
            Negotiation(state: 'INTERVIEW', createdAt: DateTime(2026, 8, 5)),
            Negotiation(state: 'RESPONSE', createdAt: DateTime(2026, 8, 4)),
          ],
          totalResponsesAllTime: 3,
          fetchedPages: 1,
          capped: false,
          now: DateTime(2026, 8, 7, 12),
        );

    test('считает отклики за период', () {
      final a = build();
      expect(a.responsesIn(AnalyticsPeriod.all), 3);
      expect(a.responsesIn(AnalyticsPeriod.week), 3);
      expect(a.responsesIn(AnalyticsPeriod.month), 3);
    });

    test('распределяет по категориям', () {
      final counts = build().categoryCounts(AnalyticsPeriod.all);
      expect(counts[NegotiationCategory.rejection], 1);
      expect(counts[NegotiationCategory.interview], 1);
      expect(counts[NegotiationCategory.pending], 1);
    });

    test('конверсия и доля отказов', () {
      final a = build();
      // 1 из 3 положительный (INTERVIEW), 1 из 3 отказ
      expect(a.invitationRate(AnalyticsPeriod.all), closeTo(33.3, 0.5));
      expect(a.rejectionRate(AnalyticsPeriod.all), closeTo(33.3, 0.5));
    });

    test('ряд по дням покрывает окно и суммирует отклики', () {
      final series = build().dailySeries(30);
      expect(series, hasLength(30));
      expect(series.fold<int>(0, (s, d) => s + d.count), 3);
    });
  });
}
