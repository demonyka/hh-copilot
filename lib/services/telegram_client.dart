import 'dart:convert';

import 'package:http/http.dart' as http;

/// Отправка уведомлений в Telegram через Bot API.
class TelegramClient {
  TelegramClient(this.token);

  final String token;

  bool get configured => token.trim().isNotEmpty;

  Future<void> sendMessage(String chatId, String text) async {
    if (!configured) throw Exception('Не указан токен бота');
    if (chatId.trim().isEmpty) throw Exception('Не указан chat id');
    final uri =
        Uri.parse('https://api.telegram.org/bot${token.trim()}/sendMessage');
    final resp = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'chat_id': chatId.trim(),
            'text': text,
            'disable_web_page_preview': true,
          }),
        )
        .timeout(const Duration(seconds: 30));
    Map<String, dynamic>? data;
    try {
      final decoded = jsonDecode(resp.body);
      if (decoded is Map) data = decoded.cast<String, dynamic>();
    } catch (_) {}
    if (resp.statusCode != 200 || data?['ok'] != true) {
      final desc = data?['description'] ?? resp.body;
      throw Exception('Telegram ${resp.statusCode}: $desc');
    }
  }
}
