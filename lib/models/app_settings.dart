/// Настройки приложения (уведомления в Telegram).
class AppSettings {
  const AppSettings({
    this.telegramToken = '',
    this.telegramChatId = '',
    this.notifyInterviews = true,
  });

  /// Токен Telegram-бота (от @BotFather).
  final String telegramToken;

  /// Chat id получателя (личный чат или группа).
  final String telegramChatId;

  /// Слать уведомления о собеседованиях.
  final bool notifyInterviews;

  bool get telegramConfigured =>
      telegramToken.trim().isNotEmpty && telegramChatId.trim().isNotEmpty;

  AppSettings copyWith({
    String? telegramToken,
    String? telegramChatId,
    bool? notifyInterviews,
  }) {
    return AppSettings(
      telegramToken: telegramToken ?? this.telegramToken,
      telegramChatId: telegramChatId ?? this.telegramChatId,
      notifyInterviews: notifyInterviews ?? this.notifyInterviews,
    );
  }

  Map<String, dynamic> toJson() => {
        'telegramToken': telegramToken,
        'telegramChatId': telegramChatId,
        'notifyInterviews': notifyInterviews,
      };

  factory AppSettings.fromJson(Map<String, dynamic> j) {
    const d = AppSettings();
    return AppSettings(
      telegramToken: (j['telegramToken'] ?? d.telegramToken) as String,
      telegramChatId: (j['telegramChatId'] ?? d.telegramChatId) as String,
      notifyInterviews: (j['notifyInterviews'] ?? d.notifyInterviews) as bool,
    );
  }
}
