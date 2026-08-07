import 'dart:convert';

/// Утилиты для вытаскивания встроенного JSON из HTML-состояния hh.ru.
/// Находят по «якорю»-ключу сбалансированный объект/массив и парсят его.
class JsonScan {
  const JsonScan._();

  /// Возвращает подстроку сбалансированного `{...}`/`[...]`, начиная с позиции
  /// [start] (символ `{` или `[`). Учитывает строки и экранирование.
  static String? balancedSlice(String s, int start) {
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

  /// Декодирует объект/массив, идущий сразу после ключа [key] (например,
  /// `"applicantNegotiations":`). Ищет первый `{` или `[` после ключа.
  static dynamic decodeAfterKey(String text, String key, {int from = 0}) {
    final k = text.indexOf(key, from);
    if (k < 0) return null;
    int i = k + key.length;
    while (i < text.length) {
      final ch = text[i];
      if (ch == '{' || ch == '[') break;
      if (ch == ' ' || ch == '\n' || ch == '\t' || ch == '\r') {
        i++;
        continue;
      }
      // после ключа не структура (например, null/число) — не наш случай
      return null;
    }
    final raw = balancedSlice(text, i);
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? objectAfterKey(String text, String key,
      {int from = 0}) {
    final v = decodeAfterKey(text, key, from: from);
    return v is Map ? v.cast<String, dynamic>() : null;
  }

  static List<dynamic>? arrayAfterKey(String text, String key, {int from = 0}) {
    final v = decodeAfterKey(text, key, from: from);
    return v is List ? v : null;
  }

  static int asInt(dynamic v, [int fallback = 0]) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }
}
