import 'dart:convert';

import '../models/hh_profile.dart';

/// Разбор HTML страницы `/applicant/resumes` hh.ru.
///
/// Логика портирована с Go-референса (`hh-ai-responder`, `LoadProfileData`):
/// hh.ru встраивает состояние страницы в HTML в экранированном виде
/// (`&#34;` вместо `"`), поэтому сначала декодируем HTML-энтити, затем
/// вытаскиваем JSON-блоки `redirectConfig` / `applicantResumes` /
/// `latestResumeHash` отдельными якорями и парсим их.
class HhProfileParser {
  const HhProfileParser._();

  /// Возвращает профиль, если на странице найдены данные аккаунта.
  /// Возвращает `null`, если это гостевая страница (пользователь не вошёл)
  /// или разметку распарсить не удалось.
  static HhProfile? parse(String rawHtml) {
    if (rawHtml.isEmpty) return null;
    final text = htmlUnescape(rawHtml);

    // Блок redirectConfig содержит account / userNotifications / config.
    final config = _decodeObjectAt(text, '{"redirectConfig":');

    HhAccount account = const HhAccount();
    if (config != null) {
      final accountJson = _asMap(config['account']) ??
          _asMap(config['hhidAccount']) ??
          const {};
      final userId = _extractUserId(config);
      account = HhAccount(
        firstName: _str(accountJson['firstName']),
        middleName: _str(accountJson['middleName']),
        lastName: _str(accountJson['lastName']),
        email: _str(accountJson['email']),
        userId: userId,
      );
    }

    // latestResumeHash вынесен в отдельный state-блок — берём якорем.
    final latestResumeHash = _extractStringValue(text, '"latestResumeHash":"');

    // applicantResumes hh.ru отдаёт отдельным блоком, поэтому ищем массив,
    // у элементов которого есть `_attributes` (это реальные резюме).
    final resumes = _extractResumes(text);

    if (!account.isAuthenticated && resumes.isEmpty) {
      // Ничего похожего на авторизованную сессию — считаем, что не вошли.
      return null;
    }

    return HhProfile(
      account: account,
      resumes: resumes,
      latestResumeHash: latestResumeHash ?? '',
    );
  }

  // --------------------------------------------------------------------------
  // Извлечение резюме
  // --------------------------------------------------------------------------

  static List<HhResume> _extractResumes(String text) {
    const anchor = '"applicantResumes":';
    int from = 0;
    while (true) {
      final k = text.indexOf(anchor, from);
      if (k < 0) break;
      int i = k + anchor.length;
      i = _skipWhitespace(text, i);
      if (i < text.length && text[i] == '[') {
        final raw = _balancedSlice(text, i);
        if (raw != null) {
          try {
            final decoded = jsonDecode(raw);
            if (decoded is List &&
                decoded.isNotEmpty &&
                decoded.first is Map &&
                (decoded.first as Map).containsKey('_attributes')) {
              return decoded
                  .whereType<Map>()
                  .map(_mapResume)
                  .toList(growable: false);
            }
          } catch (_) {
            // пробуем следующее вхождение
          }
        }
      }
      from = k + anchor.length;
    }
    return const [];
  }

  static HhResume _mapResume(Map item) {
    final attrs = _asMap(item['_attributes']) ?? const {};

    final title = _firstStringField(item['title']);
    final area = _firstTitleField(item['area']);

    int salaryAmount = 0;
    String salaryCurrency = '';
    final salaryList = item['salary'];
    if (salaryList is List && salaryList.isNotEmpty && salaryList.first is Map) {
      final s = salaryList.first as Map;
      salaryAmount = _int(s['amount']);
      salaryCurrency = _str(s['currency']);
    }

    final skills = <String>[];
    final keySkills = item['keySkills'];
    if (keySkills is List) {
      for (final k in keySkills) {
        if (k is Map) {
          final v = _str(k['string']);
          if (v.isNotEmpty) skills.add(v);
        }
      }
    }

    return HhResume(
      id: _str(attrs['id']),
      hash: _str(attrs['hash']),
      title: title,
      area: area,
      salaryAmount: salaryAmount,
      salaryCurrency: salaryCurrency,
      skills: skills,
      percent: _intOrNull(attrs['percent']),
      status: attrs['status'] == null ? null : _str(attrs['status']),
    );
  }

  static int _extractUserId(Map<String, dynamic> config) {
    final notifications = config['userNotifications'];
    if (notifications is List) {
      for (final n in notifications) {
        if (n is Map) {
          final id = _int(n['userId']);
          if (id > 0) return id;
        }
      }
    }
    return 0;
  }

  // --------------------------------------------------------------------------
  // Низкоуровневые помощники разбора
  // --------------------------------------------------------------------------

  /// Находит якорь [anchor] (начинающийся с `{`) и декодирует сбалансированный
  /// JSON-объект от него.
  static Map<String, dynamic>? _decodeObjectAt(String text, String anchor) {
    final idx = text.indexOf(anchor);
    if (idx < 0) return null;
    // anchor вида `{"redirectConfig":` — объект начинается с первого `{`.
    final start = text.indexOf('{', idx);
    if (start < 0) return null;
    final raw = _balancedSlice(text, start);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? decoded.cast<String, dynamic>() : null;
    } catch (_) {
      return null;
    }
  }

  /// Извлекает строковое значение сразу после якоря вида `"key":"`.
  static String? _extractStringValue(String text, String anchor) {
    final k = text.indexOf(anchor);
    if (k < 0) return null;
    final start = k + anchor.length;
    final end = text.indexOf('"', start);
    if (end < 0) return null;
    return text.substring(start, end);
  }

  /// Возвращает подстроку сбалансированного JSON-объекта или массива,
  /// начинающегося на позиции [start] (символ `{` или `[`).
  /// Корректно учитывает строки и экранирование.
  static String? _balancedSlice(String s, int start) {
    if (start < 0 || start >= s.length) return null;
    final open = s[start];
    final close = open == '{' ? '}' : (open == '[' ? ']' : '');
    if (close.isEmpty) return null;

    int depth = 0;
    bool inString = false;
    bool escaped = false;

    for (int i = start; i < s.length; i++) {
      final ch = s[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (ch == '\\') {
          escaped = true;
        } else if (ch == '"') {
          inString = false;
        }
        continue;
      }
      if (ch == '"') {
        inString = true;
      } else if (ch == open) {
        depth++;
      } else if (ch == close) {
        depth--;
        if (depth == 0) return s.substring(start, i + 1);
      }
    }
    return null;
  }

  static int _skipWhitespace(String s, int i) {
    while (i < s.length) {
      final ch = s[i];
      if (ch == ' ' || ch == '\n' || ch == '\t' || ch == '\r') {
        i++;
      } else {
        break;
      }
    }
    return i;
  }

  static String _firstStringField(dynamic list) {
    if (list is List && list.isNotEmpty && list.first is Map) {
      return _str((list.first as Map)['string']);
    }
    return '';
  }

  static String _firstTitleField(dynamic list) {
    if (list is List && list.isNotEmpty && list.first is Map) {
      return _str((list.first as Map)['title']);
    }
    return '';
  }

  static Map<String, dynamic>? _asMap(dynamic v) =>
      v is Map ? v.cast<String, dynamic>() : null;

  static String _str(dynamic v) => v == null ? '' : v.toString();

  static int _int(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  static int? _intOrNull(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  // --------------------------------------------------------------------------
  // Декодирование HTML-энтити (аналог Go `html.UnescapeString`)
  // --------------------------------------------------------------------------

  static final RegExp _entityPattern =
      RegExp(r'&(#[xX][0-9a-fA-F]+|#[0-9]+|[a-zA-Z][a-zA-Z0-9]*);');

  static const Map<String, String> _namedEntities = {
    'quot': '"',
    'amp': '&',
    'apos': "'",
    'lt': '<',
    'gt': '>',
    'nbsp': ' ',
    'laquo': '«',
    'raquo': '»',
    'mdash': '—',
    'ndash': '–',
    'hellip': '…',
    'rsquo': '’',
    'lsquo': '‘',
    'ldquo': '“',
    'rdquo': '”',
    'copy': '©',
    'reg': '®',
    'trade': '™',
    'deg': '°',
    'euro': '€',
    'ruble': '₽',
  };

  static String htmlUnescape(String input) {
    if (!input.contains('&')) return input;
    return input.replaceAllMapped(_entityPattern, (m) {
      final e = m.group(1)!;
      if (e.startsWith('#x') || e.startsWith('#X')) {
        final code = int.tryParse(e.substring(2), radix: 16);
        return _fromCode(code) ?? m.group(0)!;
      }
      if (e.startsWith('#')) {
        final code = int.tryParse(e.substring(1));
        return _fromCode(code) ?? m.group(0)!;
      }
      return _namedEntities[e] ?? m.group(0)!;
    });
  }

  static String? _fromCode(int? code) {
    if (code == null || code < 0 || code > 0x10FFFF) return null;
    try {
      return String.fromCharCode(code);
    } catch (_) {
      return null;
    }
  }
}
