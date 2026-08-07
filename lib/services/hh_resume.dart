import 'dart:convert';

import '../state/app_state.dart';
import 'hh_profile_parser.dart';
import 'json_scan.dart';

/// Возвращает встроенный объект состояния `{"redirectConfig":...}` со страницы hh.
Map<String, dynamic>? redirectConfigRoot(String unescapedHtml) {
  final idx = unescapedHtml.indexOf('{"redirectConfig":');
  if (idx < 0) return null;
  final raw = JsonScan.balancedSlice(unescapedHtml, idx);
  if (raw == null) return null;
  try {
    final decoded = jsonDecode(raw);
    return decoded is Map ? decoded.cast<String, dynamic>() : null;
  } catch (_) {
    return null;
  }
}

/// Компактная выжимка опыта резюме (до 3 последних мест, ~900 символов) —
/// используется в промптах писем и ответов в чатах.
Future<String> loadResumeExperience(AppState appState, String resumeHash) async {
  final resp = await appState.hhRequest(
    method: 'GET',
    url: '${AppState.baseUrl}/resume/$resumeHash',
  );
  if (resp == null || !resp.ok) return '';
  final text = HhProfileParser.htmlUnescape(resp.body);
  final root = redirectConfigRoot(text);
  final resume = root?['applicantResume'];
  final experience = resume is Map ? resume['experience'] : null;
  if (experience is! List) return '';

  final buf = StringBuffer();
  var count = 0;
  for (final e in experience) {
    if (e is! Map) continue;
    if (count >= 3) break;
    if (count > 0) buf.write('\n\n');
    final end = e['endDate']?.toString() ?? 'по настоящее время';
    buf.writeln(e['position']?.toString() ?? '');
    buf.writeln(e['companyName']?.toString() ?? '');
    buf.writeln('${e['startDate'] ?? ''} - $end');
    buf.write(e['description']?.toString() ?? '');
    count++;
  }
  final full = HhProfileParser.htmlUnescape(buf.toString()).trim();
  return full.length <= 900 ? full : '${full.substring(0, 900).trim()}…';
}
