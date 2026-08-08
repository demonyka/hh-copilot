import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/settings_controller.dart';
import '../state/update_controller.dart';
import '../theme/hh_theme.dart';
import '../widgets/bot_widgets.dart';

/// Настройки приложения: Telegram-уведомления.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    if (!controller.loaded) {
      return const Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2.6),
        ),
      );
    }
    return const _Body();
  }
}

class _Body extends StatefulWidget {
  const _Body();

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  late final TextEditingController _token;
  late final TextEditingController _chatId;

  SettingsController get _c => context.read<SettingsController>();

  @override
  void initState() {
    super.initState();
    _token = TextEditingController(text: _c.settings.telegramToken);
    _chatId = TextEditingController(text: _c.settings.telegramChatId);
  }

  @override
  void dispose() {
    _token.dispose();
    _chatId.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final s = controller.settings;

    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BotSection(
                  title: 'Уведомления в Telegram',
                  subtitle:
                      'Создайте бота у @BotFather → получите токен. Chat id можно узнать у @userinfobot (напишите ему). Затем напишите своему боту любое сообщение — и проверьте кнопкой ниже.',
                  children: [
                    BotTextField(
                      controller: _token,
                      label: 'Токен бота',
                      hint: '123456:ABC-DEF…',
                      obscure: true,
                      onChanged: (v) =>
                          _c.update(s.copyWith(telegramToken: v)),
                    ),
                    const SizedBox(height: 14),
                    BotTextField(
                      controller: _chatId,
                      label: 'Chat id',
                      hint: 'например 123456789',
                      onChanged: (v) =>
                          _c.update(s.copyWith(telegramChatId: v)),
                    ),
                    const SizedBox(height: 14),
                    BotSwitch(
                      label: 'Уведомлять о собеседованиях',
                      value: s.notifyInterviews,
                      onChanged: (v) =>
                          _c.update(s.copyWith(notifyInterviews: v)),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: _sendTest,
                          icon: const Icon(Icons.send, size: 18),
                          label: const Text('Отправить тест'),
                        ),
                        const SizedBox(width: 12),
                        if (s.telegramConfigured)
                          const Row(
                            children: [
                              Icon(Icons.check_circle,
                                  size: 18, color: HhColors.green),
                              SizedBox(width: 6),
                              Text('Настроено',
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: HhColors.textSecondary)),
                            ],
                          )
                        else
                          const Text('Заполните токен и chat id',
                              style: TextStyle(
                                  fontSize: 13, color: HhColors.textMuted)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const _UpdatesSection(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _sendTest() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger
        .showSnackBar(const SnackBar(content: Text('Отправляю тест в Telegram…')));
    try {
      await _c.sendTest();
      messenger.showSnackBar(const SnackBar(
          backgroundColor: HhColors.green,
          content: Text('Отправлено — проверьте Telegram')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          backgroundColor: HhColors.red, content: Text('Ошибка: $e')));
    }
  }
}

class _UpdatesSection extends StatelessWidget {
  const _UpdatesSection();

  @override
  Widget build(BuildContext context) {
    final u = context.watch<UpdateController>();
    final info = u.available;

    return BotSection(
      title: 'Обновления',
      subtitle: u.currentVersion.isEmpty
          ? null
          : 'Текущая версия: ${u.currentVersion}',
      children: [
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: u.checking ? null : () => u.check(manual: true),
              icon: u.checking
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh, size: 18),
              label: const Text('Проверить обновления'),
            ),
            const SizedBox(width: 12),
            if (u.lastCheckMessage != null && info == null)
              Text(u.lastCheckMessage!,
                  style: const TextStyle(
                      fontSize: 13, color: HhColors.textSecondary)),
          ],
        ),
        if (info != null) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.system_update_alt,
                  size: 18, color: HhColors.red),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  u.installing
                      ? '${u.installStage} ${(u.installProgress * 100).round()}%'
                      : 'Доступна версия ${info.version}',
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: HhColors.textPrimary),
                ),
              ),
              if (u.installing)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              else
                ElevatedButton(
                  onPressed: u.installUpdate,
                  child: Text(u.canInstall ? 'Обновить' : 'Скачать'),
                ),
            ],
          ),
          if (u.canInstall && !u.installing)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Приложение скачает и установит обновление само, затем '
                'перезапустится.',
                style: TextStyle(fontSize: 12, color: HhColors.textMuted),
              ),
            ),
        ],
      ],
    );
  }
}
