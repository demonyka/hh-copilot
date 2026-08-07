import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/interview_lead.dart';
import '../services/ai_client.dart';
import '../services/chat_responder.dart';
import '../services/interview_detector.dart';
import 'autoresponder_controller.dart';
import 'settings_controller.dart';

/// Хранит найденные приглашения на собеседования и шлёт уведомления в Telegram.
/// Детект идёт ТЕМ ЖЕ проходом по чатам, что и авто-ответы: движок чатов отдаёт
/// сюда сообщения работодателей через [AutoresponderController.employerMessageSink].
class InterviewsController extends ChangeNotifier {
  InterviewsController({required this.bot, required this.settings}) {
    _load();
    bot.employerMessageSink = _onEmployerMessage;
  }

  final AutoresponderController bot;
  final SettingsController settings;

  static const _leadsKey = 'interviews_leads_v1';
  static const _seenKey = 'interviews_seen_v1';
  static const _notifyWindow = Duration(minutes: 45);

  final List<InterviewLead> _leads = [];
  List<InterviewLead> get leads => List.unmodifiable(_leads);

  final Set<String> _seen = {};

  bool _loaded = false;
  bool get loaded => _loaded;

  bool get hasAi => bot.config.aiModel.trim().isNotEmpty;

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final leadsRaw = prefs.getString(_leadsKey);
      if (leadsRaw != null) {
        final list = jsonDecode(leadsRaw) as List;
        _leads.addAll(list
            .whereType<Map>()
            .map((m) => InterviewLead.fromJson(m.cast<String, dynamic>())));
      }
      _seen.addAll(prefs.getStringList(_seenKey) ?? const []);
    } catch (_) {}
    _loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _leadsKey, jsonEncode(_leads.map((e) => e.toJson()).toList()));
      final seen = _seen.length > 1000
          ? _seen.toList().sublist(_seen.length - 1000)
          : _seen.toList();
      await prefs.setStringList(_seenKey, seen);
    } catch (_) {}
  }

  void clearLeads() {
    _leads.clear();
    notifyListeners();
    _save();
  }

  /// Пришло сообщение работодателя — классифицируем один раз и, если это
  /// приглашение, добавляем в список и (для свежих) шлём уведомление.
  Future<void> _onEmployerMessage(EmployerMessage msg) async {
    final key = '${msg.chatId}:${msg.messageId}';
    if (_seen.contains(key)) return;
    _seen.add(key);

    final ai = _buildAi();
    String kind = '';
    String summary = '';
    bool isInterview;
    if (ai != null) {
      try {
        final v = await ai.classifyInterview(msg.text,
            vacancy: msg.vacancy, company: msg.company);
        isInterview = v.interview;
        kind = v.kind;
        summary = v.summary;
      } catch (_) {
        isInterview = InterviewDetector.isInterview(msg.text);
      }
    } else {
      isInterview = InterviewDetector.isInterview(msg.text);
    }

    if (!isInterview) {
      _save();
      return;
    }

    final lead = InterviewLead(
      chatId: msg.chatId,
      vacancy: msg.vacancy,
      company: msg.company,
      message: msg.text,
      kind: kind,
      summary: summary,
      detectedAt: DateTime.now(),
      messageAt: msg.messageAt,
    );
    _addLead(lead);

    final recent = msg.messageAt == null ||
        DateTime.now().difference(msg.messageAt!) <= _notifyWindow;
    if (recent && settings.settings.notifyInterviews) {
      await _notify(lead);
    }
    _save();
  }

  void _addLead(InterviewLead lead) {
    _leads.removeWhere((l) => l.chatId == lead.chatId);
    _leads.insert(0, lead);
    if (_leads.length > 100) _leads.removeRange(100, _leads.length);
    notifyListeners();
  }

  Future<void> _notify(InterviewLead lead) async {
    if (!settings.settings.telegramConfigured) return;
    final parts = <String>[
      '🎯 Приглашение на собеседование',
      if (lead.vacancy.isNotEmpty) 'Вакансия: ${lead.vacancy}',
      if (lead.company.isNotEmpty) 'Компания: ${lead.company}',
      if (lead.kind.isNotEmpty) 'Тип: ${lead.kind}',
      '',
      'Сообщение: ${_short(lead.message, 400)}',
      lead.chatUrl,
    ];
    try {
      await settings.notify(parts.join('\n'));
    } catch (_) {}
  }

  AiClient? _buildAi() {
    final cfg = bot.config;
    if (cfg.aiModel.trim().isEmpty) return null;
    return AiClient(
      baseUrl: cfg.aiBaseUrl,
      model: cfg.aiModel,
      apiKey: cfg.aiApiKey,
    );
  }

  static String _short(String s, int n) =>
      s.length > n ? '${s.substring(0, n)}…' : s;
}
