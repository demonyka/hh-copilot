import 'dart:convert';
import 'dart:math';

import '../models/autoresponder_config.dart';
import '../state/app_state.dart';
import 'ai_client.dart';

/// Сообщение работодателя, замеченное при проходе по чатам.
class EmployerMessage {
  const EmployerMessage({
    required this.chatId,
    required this.messageId,
    required this.text,
    required this.vacancy,
    required this.company,
    this.messageAt,
  });

  final int chatId;
  final String messageId;
  final String text;
  final String vacancy;
  final String company;
  final DateTime? messageAt;
}

/// Авто-ответы в чатах hh.ru. Портировано с Go-референса (`AutoRespondChats`),
/// но ходит на чат-API chatik.hh.ru через веб-вью раздела «Чаты» (same-origin).
class ChatResponder {
  ChatResponder({
    required this.appState,
    required this.ai,
    required this.config,
    required this.userId,
    required this.resumeId,
    required this.fullName,
    required this.resumeTitle,
    required this.resumeSalary,
    required this.resumeSkills,
    required this.experience,
    required this.onStatus,
    required this.onLog,
    required this.onReplied,
    this.onEmployerMessage,
  });

  static const String _base = 'https://chatik.hh.ru';
  static const String _referer = '$_base/?platform=xhh&dest=iframe';
  static const String _botAnswer =
      'Спасибо!\nВаши ответы отправлены работодателю. Если ваш отклик его заинтересует, он напишет в этом же чате или позвонит по номеру, который вы указали.';

  final AppState appState;
  final AiClient ai;
  final AutoresponderConfig config;
  final int userId;
  final String resumeId;
  final String fullName;
  final String resumeTitle;
  final String resumeSalary;
  final String resumeSkills;
  final String experience;

  final void Function(String status) onStatus;
  final void Function(String message, {bool error}) onLog;
  final void Function(int replied) onReplied;

  /// Вызывается для каждого нового сообщения работодателя — используется для
  /// определения приглашений на собеседование (тем же проходом по чатам).
  final void Function(EmployerMessage msg)? onEmployerMessage;

  bool _cancelled = false;
  void cancel() => _cancelled = true;

  int _replied = 0;
  final _rng = Random();

  Future<int> run() async {
    onStatus('Загружаю чаты…');
    final chats = await _getChats(0);
    if (chats == null) {
      onLog('Не удалось загрузить чаты', error: true);
      return _replied;
    }
    final items = ((chats['chats'] as Map?)?['items']) as List? ?? const [];
    final resources = (chats['resources'] as Map?) ?? const {};
    final vacancies = (resources['vacancies'] as Map?) ?? const {};

    if (items.isEmpty) {
      onLog('Новых чатов для ответа нет');
      return _replied;
    }

    final system = _renderPrompt(
      config.chatPrompt.trim().isEmpty ? kDefaultChatPrompt : config.chatPrompt,
      {
        '{name}': fullName,
        '{title}': resumeTitle,
        '{salary}': resumeSalary,
        '{skills}': resumeSkills,
        '{experience}': experience,
      },
    );

    for (final item in items) {
      if (_cancelled) break;
      if (item is! Map) continue;
      final last = item['lastMessage'];
      if (last is! Map) continue;

      // Слишком старые чаты не трогаем.
      final created = DateTime.tryParse(last['creationTime']?.toString() ?? '');
      if (created != null &&
          DateTime.now().difference(created) > const Duration(hours: 72)) {
        continue;
      }
      // Последним писали мы.
      if (_toInt(last['participantId']) == userId) continue;
      final text = last['text']?.toString() ?? '';
      if (text.trim().isEmpty || text == _botAnswer) continue;

      final res = (item['resources'] as Map?) ?? const {};
      final vacancyIds = (res['VACANCY'] as List?) ?? const [];
      final resumeIds = (res['RESUME'] as List?) ?? const [];
      if (vacancyIds.isEmpty) continue;

      final vacancy = vacancies[vacancyIds.first.toString()];
      final vacancyName =
          vacancy is Map ? (vacancy['name']?.toString() ?? '') : '';
      final companyName = vacancy is Map && vacancy['company'] is Map
          ? ((vacancy['company'] as Map)['name']?.toString() ?? '')
          : '';
      final chatId = _toInt(item['id']);

      // Детект собеседований — по всем чатам, независимо от резюме и того,
      // можем ли мы ответить (уведомления не зависят от тестового режима).
      onEmployerMessage?.call(EmployerMessage(
        chatId: chatId,
        messageId: '${last['id'] ?? last['creationTime'] ?? ''}',
        text: text,
        vacancy: vacancyName,
        company: companyName,
        messageAt: created,
      ));

      // Дальше — только авто-ответы по выбранному резюме.
      if (resumeIds.isEmpty) continue;
      if (!resumeIds.map((e) => e.toString()).contains(resumeId)) continue;

      // Отказ — не отвечаем; при включённой очистке выходим из чата.
      final wf = last['workflowTransition'];
      if (wf is Map && wf['applicantState']?.toString() == 'DISCARD') {
        if (config.leaveDiscardChats) {
          if (config.dryRun) {
            onLog('[тест] вышел бы из чата (отказ): «$vacancyName»');
          } else {
            final ok = await _leaveChat(chatId);
            onLog(
              ok
                  ? 'Вышел из чата (отказ): «$vacancyName»'
                  : 'Не смог выйти из чата «$vacancyName»',
              error: !ok,
            );
            await _wait();
          }
        }
        continue;
      }

      // Варианты-кнопки.
      final options = <String>[];
      final actions = last['actions'];
      final buttons = actions is Map ? actions['text_buttons'] : null;
      if (buttons is List) {
        for (final b in buttons) {
          if (b is Map && b['text'] != null) options.add(b['text'].toString());
        }
      }

      String userPrompt;
      int maxTokens;
      double temperature;
      if (options.isNotEmpty) {
        temperature = 0.1;
        maxTokens = 120;
        userPrompt = 'Сообщение работодателя:\n$text\n\n'
            'Ответь СТРОГО одним из вариантов, дословно, без лишних символов:\n'
            '${options.map((o) => '- $o').join('\n')}';
      } else {
        final data = await _getChatData(chatId);
        if (data == null) {
          onLog('Не смог открыть чат «$vacancyName»', error: true);
          continue;
        }
        final writeAllowed = (((data['chatStates'] as Map?)?['writeMessageState']
                as Map?)?['allowed']) ==
            true;
        final messages =
            ((data['chat'] as Map?)?['messages'] as Map?)?['items'] as List?;
        if (!writeAllowed || (messages != null && messages.length >= 20)) {
          continue;
        }
        temperature = 0.5;
        maxTokens = 700;
        userPrompt = 'Название вакансии: $vacancyName\nКомпания: $companyName\n'
            'Сообщение работодателя:\n$text\n\nИстория переписки:\n'
            '${_joinMessages(messages)}';
        if (config.contacts.trim().isNotEmpty) {
          userPrompt += '\n\nТвои контакты: ${config.contacts.trim()}';
        }
      }

      onStatus('Отвечаю в чате «$vacancyName»…');
      String reply;
      try {
        reply = await ai.chat(system, userPrompt,
            maxTokens: maxTokens, temperature: temperature);
      } catch (e) {
        onLog('Ошибка ИИ (чат): $e', error: true);
        await _wait();
        continue;
      }
      if (reply.trim().isEmpty) continue;

      if (config.dryRun) {
        _replied++;
        onReplied(_replied);
        onLog('[тест] ответил бы «$vacancyName»: ${_short(reply)}');
        await _wait();
        continue;
      }

      final ok = await _sendMessage(chatId, reply);
      if (ok) {
        _replied++;
        onReplied(_replied);
        onLog('Ответил в чате «$vacancyName»');
      } else {
        onLog('Не удалось ответить в чате «$vacancyName»', error: true);
      }
      await _wait();
    }

    return _replied;
  }

  // --- chatik API ---

  Map<String, String> get _headers => {
        'Accept': 'application/json',
        'X-Requested-With': 'XMLHttpRequest',
        'Referer': _referer,
      };

  Future<Map<String, dynamic>?> _getChats(int page) async {
    final token = await appState.xsrfToken();
    var url =
        '$_base/chatik/api/chats?filterUnread=false&filterHasTextMessage=false&do_not_track_session_events=true';
    if (page > 0) url += '&page=$page';
    final resp = await appState.chatikRequest(
      method: 'GET',
      url: url,
      headers: {..._headers, 'X-Xsrftoken': token},
    );
    return _decode(resp?.body);
  }

  Future<Map<String, dynamic>?> _getChatData(int chatId) async {
    final token = await appState.xsrfToken();
    final resp = await appState.chatikRequest(
      method: 'GET',
      url:
          '$_base/chatik/api/chat_data?chatId=$chatId&applicantId=$userId&do_not_track_session_events=true',
      headers: {
        ..._headers,
        'X-Xsrftoken': token,
        'Referer': '$_base/chat/$chatId',
      },
    );
    return _decode(resp?.body);
  }

  Future<bool> _sendMessage(int chatId, String text) async {
    final token = await appState.xsrfToken();
    final payload = jsonEncode({
      'chatId': chatId,
      'text': text,
      'idempotencyKey': _uuidV4(),
    });
    final resp = await appState.chatikRequest(
      method: 'POST',
      url: '$_base/chatik/api/send',
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'X-Requested-With': 'XMLHttpRequest',
        'X-Xsrftoken': token,
        'Referer': _referer,
      },
      body: payload,
    );
    if (resp == null) return false;
    final data = _decode(resp.body);
    if (data == null) return resp.ok;
    return data['error'] == null;
  }

  Future<bool> _leaveChat(int chatId) async {
    final token = await appState.xsrfToken();
    final resp = await appState.chatikRequest(
      method: 'POST',
      url: '$_base/chatik/api/leave',
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'X-Requested-With': 'XMLHttpRequest',
        'X-Xsrftoken': token,
        'Referer': '$_base/chat/$chatId',
        'X-hhtmFrom': 'resume',
        'X-hhtmFromLabel': 'resume',
        'X-hhtmSource': 'app',
        'X-hhtmSourceLabel': 'resume',
      },
      body: jsonEncode({'chatId': chatId}),
    );
    if (resp == null) return false;
    final data = _decode(resp.body);
    if (data == null) return resp.ok;
    return data['error'] == null;
  }

  // --- helpers ---

  Map<String, dynamic>? _decode(String? body) {
    if (body == null || body.isEmpty) return null;
    try {
      final d = jsonDecode(body);
      return d is Map ? d.cast<String, dynamic>() : null;
    } catch (_) {
      return null;
    }
  }

  String _joinMessages(List? messages) {
    if (messages == null) return '';
    final buf = StringBuffer();
    for (final m in messages) {
      if (m is! Map) continue;
      final author = (m['participantDisplay'] is Map)
          ? ((m['participantDisplay'] as Map)['name']?.toString() ?? '')
          : '';
      final t = m['creationTime']?.toString() ?? '';
      buf.writeln('[$t] $author');
      final text = m['text']?.toString() ?? '';
      if (text.trim().isNotEmpty) buf.writeln(text.trim());
      buf.writeln('---');
    }
    return buf.toString();
  }

  Future<void> _wait() async {
    var remaining = config.intervalSec;
    while (remaining > 0 && !_cancelled) {
      onStatus('Жду $remaining сек…');
      await Future<void>.delayed(const Duration(seconds: 1));
      remaining--;
    }
  }

  String _uuidV4() {
    final b = List<int>.generate(16, (_) => _rng.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    String hex(int i) => b[i].toRadixString(16).padLeft(2, '0');
    final s = List.generate(16, hex).join();
    return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
  }

  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  static String _renderPrompt(String tmpl, Map<String, String> vars) {
    var out = tmpl;
    vars.forEach((k, v) => out = out.replaceAll(k, v));
    return out;
  }

  static String _short(String s) =>
      s.length > 80 ? '${s.substring(0, 80)}…' : s;
}
