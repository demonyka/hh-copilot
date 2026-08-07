import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';
import '../services/telegram_client.dart';

/// Настройки приложения (Telegram-уведомления). Персистятся.
class SettingsController extends ChangeNotifier {
  SettingsController() {
    _load();
  }

  static const _prefsKey = 'app_settings_v1';

  AppSettings _settings = const AppSettings();
  AppSettings get settings => _settings;

  bool _loaded = false;
  bool get loaded => _loaded;

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null) {
        _settings =
            AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (_) {}
    _loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(_settings.toJson()));
    } catch (_) {}
  }

  void update(AppSettings settings) {
    _settings = settings;
    notifyListeners();
    _save();
  }

  TelegramClient get telegram => TelegramClient(_settings.telegramToken);

  /// Отправить пробное сообщение.
  Future<void> sendTest() async {
    await telegram.sendMessage(
      _settings.telegramChatId,
      '🤖 hh·copilot: тестовое уведомление. Всё работает!',
    );
  }

  /// Отправить уведомление, если Telegram настроен.
  Future<void> notify(String text) async {
    if (!_settings.telegramConfigured) return;
    await telegram.sendMessage(_settings.telegramChatId, text);
  }
}
